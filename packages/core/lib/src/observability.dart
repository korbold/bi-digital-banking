import 'dart:developer' as developer;

/// Logging and telemetry contracts. Features depend on these abstractions;
/// the app shell binds them to Crashlytics / Analytics / Performance, and
/// tests bind them to no-ops.
abstract interface class AppLogger {
  void debug(String message, {Map<String, Object?>? context});
  void info(String message, {Map<String, Object?>? context});
  void warning(String message, {Map<String, Object?>? context});
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool fatal = false,
  });
}

abstract interface class AnalyticsTracker {
  Future<void> track(String event, [Map<String, Object> params = const {}]);
  Future<void> setUserProperty(String name, String? value);
  Future<void> setUserId(String? id);
}

/// Measures a named operation (network call, screen load) for latency SLOs.
abstract interface class PerformanceTracer {
  Future<T> trace<T>(
    String name,
    Future<T> Function() body, {
    Map<String, String> attributes,
  });
}

class ConsoleLogger implements AppLogger {
  const ConsoleLogger();

  @override
  void debug(String message, {Map<String, Object?>? context}) =>
      developer.log(message, name: 'DEBUG', error: context);

  @override
  void info(String message, {Map<String, Object?>? context}) =>
      developer.log(message, name: 'INFO', error: context);

  @override
  void warning(String message, {Map<String, Object?>? context}) =>
      developer.log(message, name: 'WARN', error: context);

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool fatal = false,
  }) => developer.log(
    message,
    name: 'ERROR',
    error: error,
    stackTrace: stackTrace,
  );
}

class NoopAnalytics implements AnalyticsTracker {
  const NoopAnalytics();

  @override
  Future<void> track(
    String event, [
    Map<String, Object> params = const {},
  ]) async {}

  @override
  Future<void> setUserProperty(String name, String? value) async {}

  @override
  Future<void> setUserId(String? id) async {}
}

class NoopTracer implements PerformanceTracer {
  const NoopTracer();

  @override
  Future<T> trace<T>(
    String name,
    Future<T> Function() body, {
    Map<String, String> attributes = const {},
  }) => body();
}
