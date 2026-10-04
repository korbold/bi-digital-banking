import 'package:core/core.dart';

/// User-facing Spanish copy for a failure.
String authFailureMessage(AppFailure failure) => switch (failure) {
  ValidationFailure(:final message) => message,
  OfflineFailure() =>
    'Sin conexión a internet. Revisa tu red e intenta de nuevo.',
  TimeoutFailure() => 'La conexión está lenta. Intenta de nuevo.',
  ServiceUnavailableFailure() =>
    'El servicio no está disponible en este momento. Intenta en unos segundos.',
  UnauthorizedFailure() => 'Tu sesión expiró. Ingresa nuevamente.',
  ServerFailure() ||
  UnknownFailure() => 'Ocurrió un problema. Intenta de nuevo.',
};
