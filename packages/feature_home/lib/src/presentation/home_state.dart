import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:sdui/sdui.dart';

sealed class HomeState extends Equatable {
  const HomeState();

  @override
  List<Object?> get props => [];
}

final class HomeLoading extends HomeState {
  const HomeLoading();
}

final class HomeLoaded extends HomeState {
  const HomeLoaded({
    required this.screen,
    required this.fetchedAt,
    this.isStale = false,
    this.isRefreshing = false,
    this.refreshFailure,
  });

  final SduiScreen screen;
  final DateTime fetchedAt;

  /// Data comes from the local cache, not from a fresh network response.
  final bool isStale;
  final bool isRefreshing;

  /// Why the last refresh failed while we kept showing [screen].
  final AppFailure? refreshFailure;

  HomeLoaded copyWith({
    bool? isRefreshing,
    AppFailure? refreshFailure,
    bool clearFailure = false,
  }) => HomeLoaded(
    screen: screen,
    fetchedAt: fetchedAt,
    isStale: isStale,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailure: clearFailure
        ? null
        : (refreshFailure ?? this.refreshFailure),
  );

  @override
  List<Object?> get props => [
    screen,
    fetchedAt,
    isStale,
    isRefreshing,
    refreshFailure,
  ];
}

/// Nothing cached and the network failed: no data to show at all.
final class HomeFailure extends HomeState {
  const HomeFailure(this.failure);

  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}
