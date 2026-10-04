import 'package:core/src/failures.dart';

/// Explicit success/failure return type so repositories never throw.
sealed class Result<T> {
  const Result();

  const factory Result.success(T value) = Success<T>;
  const factory Result.failure(AppFailure failure) = Failure<T>;

  R fold<R>(
    R Function(AppFailure failure) onFailure,
    R Function(T value) onSuccess,
  ) => switch (this) {
    Success(:final value) => onSuccess(value),
    Failure(:final failure) => onFailure(failure),
  };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Success(:final value) => Result.success(transform(value)),
    Failure(:final failure) => Result.failure(failure),
  };

  T? get valueOrNull => switch (this) {
    Success(:final value) => value,
    Failure() => null,
  };

  AppFailure? get failureOrNull => switch (this) {
    Success() => null,
    Failure(:final failure) => failure,
  };
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.failure);
  final AppFailure failure;
}
