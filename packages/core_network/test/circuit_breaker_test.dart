import 'package:core_network/core_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late CircuitBreaker breaker;

  setUp(() {
    now = DateTime(2026, 10, 4, 10);
    breaker = CircuitBreaker(
      name: 'accounts',
      failureThreshold: 2,
      openDuration: const Duration(seconds: 10),
      clock: () => now,
    );
  });

  test('opens after consecutive failures reach the threshold', () {
    breaker.recordFailure();
    expect(breaker.state, CircuitState.closed);
    breaker.recordFailure();
    expect(breaker.state, CircuitState.open);
    expect(breaker.allowsRequest, isFalse);
  });

  test('moves to half-open after the open window and closes on success', () {
    breaker
      ..recordFailure()
      ..recordFailure();
    now = now.add(const Duration(seconds: 10));
    expect(breaker.state, CircuitState.halfOpen);
    expect(breaker.allowsRequest, isTrue);
    breaker.recordSuccess();
    expect(breaker.state, CircuitState.closed);
  });

  test('a failed probe in half-open re-opens immediately', () {
    breaker
      ..recordFailure()
      ..recordFailure();
    now = now.add(const Duration(seconds: 11));
    expect(breaker.state, CircuitState.halfOpen);
    breaker.recordFailure();
    expect(breaker.state, CircuitState.open);
  });

  test('success resets the failure count', () {
    breaker
      ..recordFailure()
      ..recordSuccess()
      ..recordFailure();
    expect(breaker.state, CircuitState.closed);
  });
}
