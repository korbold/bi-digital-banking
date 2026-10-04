import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_accounts/src/domain/accounts_repository.dart';
import 'package:feature_accounts/src/domain/models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum MovementsStatus { loading, loaded, failure }

class MovementsState extends Equatable {
  const MovementsState({
    this.status = MovementsStatus.loading,
    this.items = const [],
    this.nextCursor,
    this.isStale = false,
    this.fetchedAt,
    this.loadingMore = false,
    this.failure,
    this.loadMoreFailure,
  });

  final MovementsStatus status;
  final List<Movement> items;
  final String? nextCursor;
  final bool isStale;
  final DateTime? fetchedAt;
  final bool loadingMore;

  /// Why the first page could not be fetched from the network.
  final AppFailure? failure;

  /// Why the last "load more" failed (inline retry at the bottom).
  final AppFailure? loadMoreFailure;

  bool get hasMore => nextCursor != null;

  @override
  List<Object?> get props => [
    status,
    items,
    nextCursor,
    isStale,
    fetchedAt,
    loadingMore,
    failure,
    loadMoreFailure,
  ];
}

class MovementsCubit extends Cubit<MovementsState> {
  MovementsCubit(
    this._repository, {
    required this.accountId,
    this.pageSize = 20,
  }) : super(const MovementsState());

  final AccountsRepository _repository;
  final String accountId;
  final int pageSize;

  /// Loads (or reloads) the first page. Keeps current items on screen while
  /// refreshing so pull-to-refresh never blanks the list.
  Future<void> load() async {
    if (state.items.isEmpty) emit(const MovementsState());
    final result = await _repository.getMovements(accountId, limit: pageSize);
    if (isClosed) return;
    switch (result) {
      case Success(:final value):
        emit(
          MovementsState(
            status: MovementsStatus.loaded,
            items: value.data.items,
            nextCursor: value.isFromCache ? null : value.data.nextCursor,
            isStale: value.isFromCache,
            fetchedAt: value.fetchedAt,
          ),
        );
      case Failure(:final failure):
        emit(
          state.items.isEmpty
              ? MovementsState(
                  status: MovementsStatus.failure,
                  failure: failure,
                )
              : MovementsState(
                  status: MovementsStatus.loaded,
                  items: state.items,
                  nextCursor: state.nextCursor,
                  isStale: true,
                  fetchedAt: state.fetchedAt,
                  failure: failure,
                ),
        );
    }
  }

  Future<void> refresh() => load();

  Future<void> loadMore() async {
    if (!state.hasMore ||
        state.loadingMore ||
        state.status != MovementsStatus.loaded) {
      return;
    }
    emit(_copy(loadingMore: true));
    final result = await _repository.getMovements(
      accountId,
      cursor: state.nextCursor,
      limit: pageSize,
    );
    if (isClosed) return;
    switch (result) {
      case Success(:final value):
        emit(
          MovementsState(
            status: MovementsStatus.loaded,
            items: [...state.items, ...value.data.items],
            nextCursor: value.data.nextCursor,
            isStale: state.isStale,
            fetchedAt: state.fetchedAt,
            failure: state.failure,
          ),
        );
      case Failure(:final failure):
        emit(_copy(loadingMore: false, loadMoreFailure: failure));
    }
  }

  MovementsState _copy({
    required bool loadingMore,
    AppFailure? loadMoreFailure,
  }) => MovementsState(
    status: state.status,
    items: state.items,
    nextCursor: state.nextCursor,
    isStale: state.isStale,
    fetchedAt: state.fetchedAt,
    loadingMore: loadingMore,
    failure: state.failure,
    loadMoreFailure: loadMoreFailure,
  );
}
