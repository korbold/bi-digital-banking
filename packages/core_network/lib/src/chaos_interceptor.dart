import 'package:core_network/src/api_client.dart' show serviceOf;
import 'package:core_network/src/chaos.dart';
import 'package:dio/dio.dart';

/// Transport-level fault injection driven by [ChaosController].
///
/// It sits at the bottom of the Dio pipeline so the rest of the stack
/// (retries, circuit breaker, cache fallback, UI states) reacts exactly as
/// it would to a real network problem.
class ChaosInterceptor extends Interceptor {
  ChaosInterceptor(this._chaos);

  final ChaosController _chaos;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final config = _chaos.value;
    if (!config.isActive) return handler.next(options);

    if (config.extraLatency > Duration.zero) {
      await Future<void>.delayed(config.extraLatency);
    }
    if (config.forceOffline) {
      return handler.reject(
        DioException.connectionError(
          requestOptions: options,
          reason: 'chaos: forced offline',
        ),
      );
    }
    final service = serviceOf(options.path);
    if (config.downServices.contains(service) || _chaos.rollFailure()) {
      return handler.reject(
        DioException.badResponse(
          statusCode: 503,
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 503,
            data: {
              'error': {
                'code': 'chaos_unavailable',
                'message': 'chaos: $service down',
              },
            },
          ),
        ),
      );
    }
    handler.next(options);
  }
}
