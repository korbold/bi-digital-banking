import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a valid cédula', () {
    expect(isValidCedula('1710034065'), isTrue);
  });

  test('rejects a wrong check digit', () {
    expect(isValidCedula('1710034064'), isFalse);
  });

  test('rejects invalid province, third digit and length', () {
    expect(
      isValidCedula('2510034065'),
      isFalse,
      reason: 'province 25 does not exist',
    );
    expect(isValidCedula('1770034065'), isFalse, reason: 'third digit >= 6');
    expect(isValidCedula('171003406'), isFalse);
    expect(isValidCedula('17100340AB'), isFalse);
  });
}
