import 'package:bi_digital_banking/src/config/env.dart';
import 'package:bi_digital_banking/src/config/remote_flags.dart';
import 'package:bi_digital_banking/src/observability/firebase_observability.dart';
import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_home/feature_home.dart';
import 'package:feature_notifications/feature_notifications.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:get_it/get_it.dart';

final GetIt sl = GetIt.instance;

/// Composition root. The only place that knows concrete implementations;
/// feature packages receive abstractions through constructors (ADR 0008).
Future<void> configureDependencies() async {
  // Observability
  final logger = CrashlyticsLogger(FirebaseCrashlytics.instance);
  final analytics = FirebaseAnalyticsTracker(FirebaseAnalytics.instance);
  sl
    ..registerSingleton<AppLogger>(logger)
    ..registerSingleton<AnalyticsTracker>(analytics)
    ..registerSingleton<PerformanceTracer>(
      FirebasePerformanceTracer(FirebasePerformance.instance),
    );

  // Flags (never blocks startup for more than 3 s)
  final flags = RemoteFlags(FirebaseRemoteConfig.instance, logger: logger);
  await flags.init();
  sl.registerSingleton(flags);

  // Networking
  final auth = FirebaseAuthRepository(auth: FirebaseAuth.instance);
  final chaos = ChaosController();
  final connectivity = ConnectivityMonitor();
  final breakers = CircuitBreakerRegistry();
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.bffBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 8),
      contentType: Headers.jsonContentType,
    ),
  )..interceptors.add(ChaosInterceptor(chaos));
  final api = ApiClient(
    dio: dio,
    cache: await HiveCacheStore.open(),
    tokenProvider: auth.idToken,
    breakers: breakers,
    isOnline: () async =>
        !chaos.value.forceOffline && await connectivity.isOnline(),
    cacheScope: () => FirebaseAuth.instance.currentUser?.uid ?? 'anon',
    logger: logger,
    tracer: sl<PerformanceTracer>(),
  );

  sl
    ..registerSingleton(chaos)
    ..registerSingleton(connectivity)
    ..registerSingleton(breakers)
    ..registerSingleton(api)
    // Repositories per domain
    ..registerSingleton<AuthRepository>(auth)
    ..registerSingleton<CustomerRepository>(ApiCustomerRepository(api))
    ..registerSingleton<AccountsRepository>(ApiAccountsRepository(api))
    ..registerSingleton(HomeRepository(api))
    ..registerSingleton(FxRepository(api))
    ..registerLazySingleton(
      () => PushService(
        messaging: FirebaseMessagingGateway(),
        local: FlutterLocalNotifier(),
        registerToken: apiTokenRegistrar(api, platform: 'android'),
        logger: logger,
      ),
    );
}
