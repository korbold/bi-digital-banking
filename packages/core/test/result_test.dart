import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result', () {
    test('fold routes success to onSuccess', () {
      const result = Result<int>.success(2);
      expect(result.fold((_) => -1, (v) => v * 2), 4);
      expect(result.valueOrNull, 2);
      expect(result.failureOrNull, isNull);
    });

    test('map keeps failure untouched', () {
      const failure = OfflineFailure();
      const result = Result<int>.failure(failure);
      final mapped = result.map((v) => '$v');
      expect(mapped.failureOrNull, failure);
      expect(mapped.valueOrNull, isNull);
    });
  });

  group('AppFailure.isRetryable', () {
    test('transport failures are retryable, business ones are not', () {
      expect(const OfflineFailure().isRetryable, isTrue);
      expect(const TimeoutFailure().isRetryable, isTrue);
      expect(const ServiceUnavailableFailure('accounts').isRetryable, isTrue);
      expect(const ServerFailure('boom', statusCode: 503).isRetryable, isTrue);
      expect(const ServerFailure('bad', statusCode: 404).isRetryable, isFalse);
      expect(const UnauthorizedFailure().isRetryable, isFalse);
      expect(const ValidationFailure('insufficient funds').isRetryable, isFalse);
    });
  });
}
