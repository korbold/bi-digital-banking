import 'dart:async';

import 'package:core/core.dart';
import 'package:feature_home/src/data/home_repository.dart';
import 'package:feature_home/src/presentation/home_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._repository, {Stream<bool>? connectivityChanges})
    : super(const HomeLoading()) {
    // Recovery: when connectivity returns, refresh without user action.
    _connectivity = connectivityChanges
        ?.where((online) => online)
        .listen((_) => load());
  }

  final HomeRepository _repository;
  StreamSubscription<Object?>? _subscription;
  StreamSubscription<bool>? _connectivity;

  Future<void> load() async {
    final current = state;
    if (current is HomeLoaded) {
      emit(current.copyWith(isRefreshing: true, clearFailure: true));
    } else {
      emit(const HomeLoading());
    }

    await _subscription?.cancel();
    final done = Completer<void>();
    _subscription = _repository.watchHome().listen(
      (result) {
        switch (result) {
          case Success(:final value):
            emit(
              HomeLoaded(
                screen: value.data,
                fetchedAt: value.fetchedAt,
                isStale: value.isFromCache,
                // A cache hit is followed by the network attempt.
                isRefreshing: value.isFromCache,
              ),
            );
          case Failure(:final failure):
            final s = state;
            emit(
              s is HomeLoaded
                  ? HomeLoaded(
                      screen: s.screen,
                      fetchedAt: s.fetchedAt,
                      isStale: true,
                      refreshFailure: failure,
                    )
                  : HomeFailure(failure),
            );
        }
      },
      onDone: () {
        final s = state;
        if (s is HomeLoaded && s.isRefreshing) {
          emit(s.copyWith(isRefreshing: false));
        }
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  Future<void> refresh() => load();

  @override
  Future<void> close() async {
    await _connectivity?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
