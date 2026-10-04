import 'dart:math';

/// Exponential backoff with full jitter.
///
/// delay(n) = random(0, min(maxDelay, base * 2^n)). Jitter avoids every
/// client retrying in lockstep after a backend hiccup (thundering herd).
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
    this.maxDelay = const Duration(seconds: 4),
  });

  static const none = RetryPolicy(maxAttempts: 1);

  /// Total attempts including the first one.
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  Duration delayFor(int retryIndex, Random random) {
    final exp = baseDelay.inMilliseconds * pow(2, retryIndex);
    final capped = min(exp, maxDelay.inMilliseconds).toInt();
    return Duration(milliseconds: random.nextInt(capped + 1));
  }
}
