/// Validates an Ecuadorian cédula (10 digits) with the official modulo-10
/// algorithm used by the Registro Civil.
///
/// - Digits 1-2: province code 01..24 (or 30 for Ecuadorians abroad).
/// - Digit 3: < 6 for natural persons.
/// - Digit 10: check digit. Odd positions (1,3,5,7,9) are doubled and 9 is
///   subtracted when the result exceeds 9; check = (10 - sum % 10) % 10.
bool isValidCedula(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{10}$').hasMatch(value)) return false;

  final digits = value.split('').map(int.parse).toList();
  final province = digits[0] * 10 + digits[1];
  if (!((province >= 1 && province <= 24) || province == 30)) return false;
  if (digits[2] >= 6) return false;

  var sum = 0;
  for (var i = 0; i < 9; i++) {
    var d = digits[i];
    if (i.isEven) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  final check = (10 - sum % 10) % 10;
  return check == digits[9];
}
