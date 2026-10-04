import 'package:core/core.dart';
import 'package:flutter/material.dart';

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String _two(int v) => v.toString().padLeft(2, '0');

String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// "Hoy", "Ayer" or "3 de octubre" (adds the year when not the current one).
String formatDayHeader(DateTime day, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final d = DateUtils.dateOnly(day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  final base = '${d.day} de ${_months[d.month - 1]}';
  return d.year == today.year ? base : '$base de ${d.year}';
}

/// Spanish copy for degraded states, distinguishing the three causes the
/// user can act on differently.
String accountsFailureMessage(AppFailure failure) => switch (failure) {
  OfflineFailure() => 'Sin conexión a internet.',
  TimeoutFailure() => 'La conexión está lenta y no pudimos actualizar.',
  ServiceUnavailableFailure() =>
    'El servicio de cuentas no está disponible por ahora.',
  UnauthorizedFailure() => 'Tu sesión expiró. Ingresa nuevamente.',
  ValidationFailure(:final message) => message,
  ServerFailure() || UnknownFailure() => 'No pudimos cargar la información.',
};

/// Banner text when showing cached data.
String staleDataMessage(DateTime fetchedAt, AppFailure? cause) {
  final prefix = cause == null ? '' : '${accountsFailureMessage(cause)} ';
  return '${prefix}Mostrando datos guardados de ${formatTime(fetchedAt)}.';
}

/// Business-rule codes from POST /api/transfers.
String transferFailureMessage(AppFailure failure) => switch (failure) {
  ValidationFailure(code: 'insufficient_funds') =>
    'Saldo insuficiente en la cuenta de origen.',
  ValidationFailure(code: 'same_account') =>
    'La cuenta de origen y destino deben ser distintas.',
  ValidationFailure(code: 'invalid_amount') => 'El monto no es válido.',
  ValidationFailure(code: 'idempotency_conflict') =>
    'Esta transferencia ya está en proceso.',
  OfflineFailure() =>
    'Sin conexión. Tu transferencia no se envió; puedes reintentar sin riesgo de duplicarla.',
  TimeoutFailure() ||
  ServiceUnavailableFailure() ||
  ServerFailure() ||
  UnknownFailure() =>
    'No pudimos confirmar la transferencia. Reintenta: no se duplicará.',
  _ => accountsFailureMessage(failure),
};

IconData categoryIcon(String category) => switch (category) {
  'groceries' => Icons.shopping_cart_outlined,
  'food' || 'restaurants' => Icons.restaurant_outlined,
  'transport' => Icons.directions_car_outlined,
  'salary' || 'income' => Icons.payments_outlined,
  'transfer' => Icons.swap_horiz,
  'services' || 'utilities' => Icons.receipt_long_outlined,
  'health' => Icons.local_hospital_outlined,
  'entertainment' => Icons.movie_outlined,
  'shopping' => Icons.shopping_bag_outlined,
  'education' => Icons.school_outlined,
  'travel' => Icons.flight_outlined,
  _ => Icons.account_balance_wallet_outlined,
};
