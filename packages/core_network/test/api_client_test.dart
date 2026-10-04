import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted transport: each call pops the next (status, body) pair.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<(int, Object?)> script;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = script.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _ScriptedAdapter adapter;
  late MemoryCacheStore cache;
  late ChaosController chaos;

  ApiClient build({
    List<(int, Object?)> script = const [],
    bool online = true,
  }) {
    adapter = _ScriptedAdapter([...script]);
    final dio = Dio(BaseOptions(baseUrl: 'https://bff.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(ChaosInterceptor(chaos));
    return ApiClient(
      dio: dio,
      cache: cache,
      tokenProvider: ({forceRefresh = false}) async => 'token',
      isOnline: () async => online,
      breakers: CircuitBreakerRegistry(failureThreshold: 2),
      random: Random(1),
      sleep: (_) async {},
    );
  }

  setUp(() {
    cache = MemoryCacheStore();
    chaos = ChaosController(random: Random(1));
  });

  test('serviceOf extracts the first segment after /api', () {
    expect(serviceOf('/api/accounts/1/movements'), 'accounts');
    expect(serviceOf('/api/home'), 'home');
  });

  test('successful GET returns network data and writes it to cache', () async {
    final client = build(
      script: [
        (200, {'balance': 10}),
      ],
    );
    final result = await client.get('/api/accounts', decode: (j) => j! as Map);

    final fetched = result.valueOrNull!;
    expect(fetched.source, DataSource.network);
    expect(fetched.data['balance'], 10);
    expect(adapter.requests.single.headers['Authorization'], 'Bearer token');
  });

  test('retries transient 5xx and succeeds', () async {
    final client = build(
      script: [
        (503, null),
        (200, {'ok': true}),
      ],
    );
    final result = await client.get('/api/accounts', decode: (j) => j! as Map);

    expect(result.valueOrNull?.data['ok'], isTrue);
    expect(adapter.requests, hasLength(2));
  });

  test('falls back to cache when the service keeps failing', () async {
    final client = build(
      script: [
        (200, {'balance': 10}),
        (500, null),
        (500, null),
        (500, null),
      ],
    );
    await client.get('/api/accounts', decode: (j) => j! as Map);

    final result = await client.get('/api/accounts', decode: (j) => j! as Map);
    expect(result.valueOrNull?.source, DataSource.cache);
    expect(result.valueOrNull?.data['balance'], 10);
  });

  test('open circuit fails fast without hitting the network', () async {
    final client = build(script: [(500, null), (500, null)]);
    await client.get('/api/accounts', decode: (j) => j, useCache: false);
    final before = adapter.requests.length;

    final result = await client.get(
      '/api/accounts',
      decode: (j) => j,
      useCache: false,
    );
    expect(result.failureOrNull, isA<ServiceUnavailableFailure>());
    expect(adapter.requests.length, before);
  });

  test('offline short-circuits to OfflineFailure', () async {
    final client = build(online: false);
    final result = await client.get(
      '/api/accounts',
      decode: (j) => j,
      useCache: false,
    );
    expect(result.failureOrNull, isA<OfflineFailure>());
    expect(adapter.requests, isEmpty);
  });

  test('POST without idempotency key is never retried', () async {
    final client = build(script: [(503, null), (200, {})]);
    final result = await client.post('/api/transfers', decode: (j) => j);
    expect(result.failureOrNull, isA<ServerFailure>());
    expect(adapter.requests, hasLength(1));
  });

  test('POST with idempotency key is retried and sends the header', () async {
    final client = build(
      script: [
        (503, null),
        (200, {'id': 't1'}),
      ],
    );
    final result = await client.post(
      '/api/transfers',
      decode: (j) => j! as Map,
      idempotencyKey: 'k-1',
    );
    expect(result.valueOrNull?['id'], 't1');
    expect(
      adapter.requests.map((r) => r.headers['Idempotency-Key']),
      everyElement('k-1'),
    );
  });

  test('4xx business errors map to ValidationFailure with code', () async {
    final client = build(
      script: [
        (
          422,
          {
            'error': {
              'code': 'insufficient_funds',
              'message': 'Saldo insuficiente',
            },
          },
        ),
      ],
    );
    final result = await client.post(
      '/api/transfers',
      decode: (j) => j,
      idempotencyKey: 'k',
    );
    final failure = result.failureOrNull! as ValidationFailure;
    expect(failure.code, 'insufficient_funds');
    expect(adapter.requests, hasLength(1));
  });

  test(
    'chaos: a down service is reported without reaching the transport',
    () async {
      chaos.toggleService('accounts');
      final client = build();
      final result = await client.get(
        '/api/accounts',
        decode: (j) => j,
        useCache: false,
      );
      expect(result.failureOrNull, isA<ServiceUnavailableFailure>());
      expect(adapter.requests, isEmpty);
    },
  );

  test('watch emits cache first, then fresh network data', () async {
    final client = build(
      script: [
        (200, {'v': 1}),
        (200, {'v': 2}),
      ],
    );
    await client.get('/api/home', decode: (j) => j! as Map);

    final emissions = await client
        .watch('/api/home', decode: (j) => j! as Map)
        .toList();
    expect(emissions.map((r) => r.valueOrNull?.source), [
      DataSource.cache,
      DataSource.network,
    ]);
    expect(emissions.last.valueOrNull?.data['v'], 2);
  });
}
