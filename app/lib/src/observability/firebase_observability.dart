import 'package:core/core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Binds the `core` observability contracts to Firebase.
///
/// - Logs become Crashlytics breadcrumbs, so a crash report carries the
///   network/degradation history that led to it.
/// - Non-fatal errors are recorded (e.g. decode failures, SDUI sections that
///   failed to render) to detect UX problems that never crash the app.
class CrashlyticsLogger implements AppLogger {
  CrashlyticsLogger(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;
  static const _console = ConsoleLogger();

  @override
  void debug(String message, {Map<String, Object?>? context}) {
    if (kDebugMode) _console.debug(message, context: context);
  }

  @override
  void info(String message, {Map<String, Object?>? context}) {
    _console.info(message, context: context);
    _crashlytics.log('[I] $message ${context ?? ''}');
  }

  @override
  void warning(String message, {Map<String, Object?>? context}) {
    _console.warning(message, context: context);
    _crashlytics.log('[W] $message ${context ?? ''}');
  }

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool fatal = false,
  }) {
    _console.error(message, error: error, stackTrace: stackTrace);
    _crashlytics.recordError(
      error ?? message,
      stackTrace,
      reason: message,
      fatal: fatal,
    );
  }
}

class FirebaseAnalyticsTracker implements AnalyticsTracker {
  FirebaseAnalyticsTracker(this._analytics);

  final FirebaseAnalytics _analytics;

  @override
  Future<void> track(String event, [Map<String, Object> params = const {}]) =>
      _analytics.logEvent(name: event, parameters: params);

  @override
  Future<void> setUserProperty(String name, String? value) =>
      _analytics.setUserProperty(name: name, value: value);

  @override
  Future<void> setUserId(String? id) => _analytics.setUserId(id: id);
}

/// Custom traces per backend service (`api_accounts`, `api_home`...) feed the
/// latency dashboards and p95 alerts described in docs/operations.md.
class FirebasePerformanceTracer implements PerformanceTracer {
  FirebasePerformanceTracer(this._performance);

  final FirebasePerformance _performance;

  @override
  Future<T> trace<T>(
    String name,
    Future<T> Function() body, {
    Map<String, String> attributes = const {},
  }) async {
    final trace = _performance.newTrace(name);
    attributes.forEach(trace.putAttribute);
    await trace.start();
    try {
      final result = await body();
      trace.putAttribute('outcome', 'ok');
      return result;
    } on Object {
      trace.putAttribute('outcome', 'error');
      rethrow;
    } finally {
      await trace.stop();
    }
  }
}
