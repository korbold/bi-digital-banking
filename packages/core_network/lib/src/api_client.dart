import 'dart:async';
import 'dart:math';

import 'package:core/core.dart';
import 'package:core_network/src/cache_store.dart';
import 'package:core_network/src/circuit_breaker.dart';
import 'package:core_network/src/retry_policy.dart';
import 'package:dio/dio.dart';

/// Returns the current session token. [forceRefresh] is used once after a 401.
typedef TokenProvider = Future<String?> Function({bool forceRefresh});

/// Service name used for circuit breaking and chaos: the first path segment
/// after `/api/`. `/api/accounts/123/movements` -> `accounts`.
String serviceOf(String path) {
  final segments = Uri.parse(
    path,
  ).pathSegments.where((s) => s.isNotEmpty).toList();
  final apiIndex = segments.indexOf('api');
  if (apiIndex >= 0 && apiIndex + 1 < segments.length) {
    return segments[apiIndex + 1];
  }
  return segments.isEmpty ? 'root' : segments.first;
}

/// Single entry point to the backend (BFF).
///
/// Order of defences for a read:
///   1. connectivity check -> fail fast as [OfflineFailure]
///   2. per-service circuit breaker -> fail fast as [ServiceUnavailableFailure]
///   3. request with timeout, retried with jittered backoff on transient errors
///   4. on success: write-through to cache; on failure: serve last known good
///      copy from cache, tagged [DataSource.cache]
///
/// Writes are only retried when the caller supplies an idempotency key, so a
/// retried transfer can never be applied twice.
class ApiClient {
  ApiClient({
    required Dio dio,
    required CacheStore cache,
    required TokenProvider tokenProvider,
    CircuitBreakerRegistry? breakers,
    RetryPolicy retryPolicy = const RetryPolicy(),
    Future<bool> Function()? isOnline,
    String Function()? cacheScope,
    AppLogger logger = const ConsoleLogger(),
    PerformanceTracer tracer = const NoopTracer(),
    Random? random,
    Future<void> Function(Duration)? sleep,
  }) : _dio = dio,
       _cache = cache,
       _tokenProvider = tokenProvider,
       breakers = breakers ?? CircuitBreakerRegistry(),
       _retryPolicy = retryPolicy,
       _isOnline = isOnline ?? (() async => true),
       _cacheScope = cacheScope ?? (() => 'anon'),
       _logger = logger,
       _tracer = tracer,
       _random = random ?? Random(),
       _sleep = sleep ?? Future<void>.delayed;

  final Dio _dio;
  final CacheStore _cache;
  final TokenProvider _tokenProvider;
  final CircuitBreakerRegistry breakers;
  final RetryPolicy _retryPolicy;
  final Future<bool> Function() _isOnline;
  final String Function() _cacheScope;
  final AppLogger _logger;
  final PerformanceTracer _tracer;
  final Random _random;
  final Future<void> Function(Duration) _sleep;

  String _cacheKey(String path, Map<String, dynamic>? query) {
    final q = query == null || query.isEmpty
        ? ''
        : '?${Uri(queryParameters: query.map((k, v) => MapEntry(k, '$v'))).query}';
    return '${_cacheScope()}::$path$q';
  }

  /// Network-first read with cache fallback.
  Future<Result<Fetched<T>>> get<T>(
    String path, {
    required T Function(Object? json) decode,
    Map<String, dynamic>? query,
    bool useCache = true,
  }) async {
    final key = _cacheKey(path, query);
    final network = await _send<Object?>(
      'GET',
      path,
      query: query,
      retryable: true,
    );
    switch (network) {
      case Success(:final value):
        if (useCache) await _cache.write(key, value);
        return _decode(value, decode, DataSource.network, DateTime.now());
      case Failure(:final failure):
        if (!useCache || !failure.isRetryable) return Result.failure(failure);
        final cached = await _cache.read(key);
        if (cached == null) return Result.failure(failure);
        _logger.warning(
          'Serving cache for $path',
          context: {'cause': failure.toString()},
        );
        return _decode(cached.body, decode, DataSource.cache, cached.storedAt);
    }
  }

  /// Stale-while-revalidate: emits the cached copy immediately (if any) and
  /// then the network result. If the network fails after a cache hit, the
  /// failure is still emitted so the UI can show a "could not refresh" hint
  /// on top of the cached data.
  Stream<Result<Fetched<T>>> watch<T>(
    String path, {
    required T Function(Object? json) decode,
    Map<String, dynamic>? query,
  }) async* {
    final key = _cacheKey(path, query);
    final cached = await _cache.read(key);
    if (cached != null) {
      yield _decode(cached.body, decode, DataSource.cache, cached.storedAt);
    }

    final network = await _send<Object?>(
      'GET',
      path,
      query: query,
      retryable: true,
    );
    switch (network) {
      case Success(:final value):
        await _cache.write(key, value);
        yield _decode(value, decode, DataSource.network, DateTime.now());
      case Failure(:final failure):
        yield Result.failure(failure);
    }
  }

  /// Write. Retried only when [idempotencyKey] is provided.
  Future<Result<T>> post<T>(
    String path, {
    required T Function(Object? json) decode,
    Object? body,
    String? idempotencyKey,
  }) async {
    final result = await _send<Object?>(
      'POST',
      path,
      body: body,
      retryable: idempotencyKey != null,
      headers: {if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey},
    );
    return switch (result) {
      Success(:final value) => _safeDecode(() => decode(value)),
      Failure(:final failure) => Result.failure(failure),
    };
  }

  Future<void> clearCache() => _cache.clear();

  Result<Fetched<T>> _decode<T>(
    Object? json,
    T Function(Object?) decode,
    DataSource source,
    DateTime at,
  ) => _safeDecode(() => Fetched(decode(json), source: source, fetchedAt: at));

  Result<R> _safeDecode<R>(R Function() body) {
    try {
      return Result.success(body());
    } on Object catch (e, st) {
      _logger.error('Decode error', error: e, stackTrace: st);
      return const Result.failure(ServerFailure('Malformed response'));
    }
  }

  Future<Result<R>> _send<R>(
    String method,
    String path, {
    required bool retryable,
    Map<String, dynamic>? query,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    if (!await _isOnline()) return const Result.failure(OfflineFailure());

    final service = serviceOf(path);
    final breaker = breakers.of(service);
    final attempts = retryable ? _retryPolicy.maxAttempts : 1;
    var forceRefreshToken = false;
    AppFailure? last;

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (!breaker.allowsRequest) {
        return Result.failure(
          ServiceUnavailableFailure(service, retryAfter: breaker.retryAfter),
        );
      }
      if (attempt > 0) {
        await _sleep(_retryPolicy.delayFor(attempt - 1, _random));
      }

      try {
        final token = await _tokenProvider(forceRefresh: forceRefreshToken);
        final response = await _tracer.trace(
          'api_$service',
          () => _dio.request<R>(
            path,
            queryParameters: query,
            data: body,
            options: Options(
              method: method,
              headers: {
                ...headers,
                if (token != null) 'Authorization': 'Bearer $token',
                'X-Request-Id': _requestId(),
              },
            ),
          ),
          attributes: {'method': method},
        );
        breaker.recordSuccess();
        return Result.success(response.data as R);
      } on DioException catch (e) {
        last = mapDioException(e);
        if (last is UnauthorizedFailure && !forceRefreshToken) {
          // Token may simply be expired: refresh once and retry immediately.
          forceRefreshToken = true;
          attempt--;
          continue;
        }
        if (_countsAgainstBreaker(last)) breaker.recordFailure();
        _logger.warning(
          '$method $path failed (attempt ${attempt + 1}/$attempts)',
          context: {'failure': last.toString(), 'breaker': breaker.state.name},
        );
        if (!last.isRetryable) break;
      }
    }
    return Result.failure(last ?? const UnknownFailure());
  }

  bool _countsAgainstBreaker(AppFailure f) =>
      f is ServerFailure || f is TimeoutFailure;

  String _requestId() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
}

/// Maps transport errors to domain failures. Business errors from the BFF
/// come as `{ "error": { "code": "...", "message": "..." } }`.
AppFailure mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const TimeoutFailure();
    case DioExceptionType.connectionError:
      return const OfflineFailure();
    case DioExceptionType.badResponse:
      final status = e.response?.statusCode ?? 500;
      final data = e.response?.data;
      final error = data is Map ? data['error'] : null;
      final message = error is Map ? '${error['message']}' : 'HTTP $status';
      final code = error is Map ? error['code'] as String? : null;
      if (status == 401) return const UnauthorizedFailure();
      if (status >= 400 && status < 500) {
        return ValidationFailure(message, code: code);
      }
      return ServerFailure(message, statusCode: status);
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return UnknownFailure(e.message ?? 'Unknown network error');
  }
}
