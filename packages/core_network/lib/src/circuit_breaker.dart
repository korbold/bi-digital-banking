import 'package:flutter/foundation.dart';

enum CircuitState { closed, open, halfOpen }

/// Classic three-state circuit breaker, one instance per backend service.
///
/// After [failureThreshold] consecutive failures the circuit opens and
/// requests fail immediately for [openDuration]; then one probe request is
/// let through (half-open). Success closes it, failure re-opens it.
///
/// Why: when the accounts service is down we want the UI to fall back to
/// cache instantly instead of making the user wait through retries + timeouts
/// on every screen.
class CircuitBreaker {
  CircuitBreaker({
    required this.name,
    this.failureThreshold = 3,
    this.openDuration = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String name;
  final int failureThreshold;
  final Duration openDuration;
  final DateTime Function() _clock;

  CircuitState _state = CircuitState.closed;
  int _consecutiveFailures = 0;
  DateTime? _openedAt;

  CircuitState get state {
    if (_state == CircuitState.open &&
        _openedAt != null &&
        _clock().difference(_openedAt!) >= openDuration) {
      _state = CircuitState.halfOpen;
    }
    return _state;
  }

  /// Time left until a probe is allowed, null when not open.
  Duration? get retryAfter {
    if (state != CircuitState.open || _openedAt == null) return null;
    return openDuration - _clock().difference(_openedAt!);
  }

  bool get allowsRequest => state != CircuitState.open;

  void recordSuccess() {
    _consecutiveFailures = 0;
    _state = CircuitState.closed;
    _openedAt = null;
  }

  void recordFailure() {
    _consecutiveFailures++;
    if (_state == CircuitState.halfOpen ||
        _consecutiveFailures >= failureThreshold) {
      _state = CircuitState.open;
      _openedAt = _clock();
    }
  }

  @visibleForTesting
  int get consecutiveFailures => _consecutiveFailures;
}

/// Lazily creates one breaker per service name.
class CircuitBreakerRegistry {
  CircuitBreakerRegistry({
    this.failureThreshold = 3,
    this.openDuration = const Duration(seconds: 15),
  });

  final int failureThreshold;
  final Duration openDuration;
  final Map<String, CircuitBreaker> _breakers = {};

  CircuitBreaker of(String service) => _breakers.putIfAbsent(
    service,
    () => CircuitBreaker(
      name: service,
      failureThreshold: failureThreshold,
      openDuration: openDuration,
    ),
  );

  Map<String, CircuitState> snapshot() => {
    for (final e in _breakers.entries) e.key: e.value.state,
  };
}
