import 'package:equatable/equatable.dart';

/// Every error that crosses a layer boundary is mapped to one of these.
///
/// The UI never sees raw exceptions: it switches on the failure type to pick
/// a degraded-state message, and [isRetryable] decides whether a retry
/// button makes sense.
sealed class AppFailure extends Equatable implements Exception {
  const AppFailure(this.message);

  /// Developer-facing detail. User-facing copy lives in the UI layer.
  final String message;

  bool get isRetryable;

  @override
  List<Object?> get props => [runtimeType, message];

  @override
  String toString() => 'AppFailure: $message';
}

/// Device has no usable connection.
final class OfflineFailure extends AppFailure {
  const OfflineFailure([super.message = 'No connection']);

  @override
  bool get isRetryable => true;
}

/// The request exceeded its deadline (high latency).
final class TimeoutFailure extends AppFailure {
  const TimeoutFailure([super.message = 'Request timed out']);

  @override
  bool get isRetryable => true;
}

/// A downstream service is failing and its circuit breaker is open, so we
/// fail fast instead of hammering it.
final class ServiceUnavailableFailure extends AppFailure {
  const ServiceUnavailableFailure(this.service, {this.retryAfter})
    : super('Service "$service" unavailable');

  final String service;
  final Duration? retryAfter;

  @override
  bool get isRetryable => true;

  @override
  List<Object?> get props => [...super.props, service];
}

/// 5xx or malformed response.
final class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {this.statusCode});

  final int? statusCode;

  @override
  bool get isRetryable => (statusCode ?? 500) >= 500;

  @override
  List<Object?> get props => [...super.props, statusCode];
}

/// Session missing or expired.
final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([super.message = 'Unauthorized']);

  @override
  bool get isRetryable => false;
}

/// Business-rule rejection (insufficient funds, invalid input...).
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {this.code});

  final String? code;

  @override
  bool get isRetryable => false;

  @override
  List<Object?> get props => [...super.props, code];
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure([super.message = 'Unexpected error']);

  @override
  bool get isRetryable => true;
}
