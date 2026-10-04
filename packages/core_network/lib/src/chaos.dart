import 'dart:math';

import 'package:flutter/foundation.dart';

/// Fault-injection settings used to demonstrate degraded scenarios on a real
/// device: added latency, random failures and per-service outages.
///
/// Only the debug/demo panel mutates it; in a production build it stays at
/// [ChaosConfig.none] and the interceptor is a no-op.
@immutable
class ChaosConfig {
  const ChaosConfig({
    this.extraLatency = Duration.zero,
    this.failureRate = 0,
    this.downServices = const {},
    this.forceOffline = false,
  });

  static const none = ChaosConfig();

  /// Delay added before every request (simulates high latency / 3G).
  final Duration extraLatency;

  /// 0..1 probability that a request fails with a 503.
  final double failureRate;

  /// Services (first path segment after /api, e.g. "accounts", "home", "fx")
  /// that always answer 503 — partial unavailability.
  final Set<String> downServices;

  /// Every request fails as if the device had no connection.
  final bool forceOffline;

  bool get isActive =>
      extraLatency > Duration.zero ||
      failureRate > 0 ||
      downServices.isNotEmpty ||
      forceOffline;

  ChaosConfig copyWith({
    Duration? extraLatency,
    double? failureRate,
    Set<String>? downServices,
    bool? forceOffline,
  }) => ChaosConfig(
    extraLatency: extraLatency ?? this.extraLatency,
    failureRate: failureRate ?? this.failureRate,
    downServices: downServices ?? this.downServices,
    forceOffline: forceOffline ?? this.forceOffline,
  );
}

/// Observable holder so the demo panel and the interceptor share state.
class ChaosController extends ValueNotifier<ChaosConfig> {
  ChaosController({Random? random})
    : _random = random ?? Random(),
      super(ChaosConfig.none);

  final Random _random;

  bool rollFailure() =>
      value.failureRate > 0 && _random.nextDouble() < value.failureRate;

  void toggleService(String service) {
    final next = {...value.downServices};
    if (!next.remove(service)) next.add(service);
    value = value.copyWith(downServices: next);
  }

  void reset() => value = ChaosConfig.none;
}
