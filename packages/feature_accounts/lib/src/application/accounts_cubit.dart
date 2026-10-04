import 'dart:async';

import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_accounts/src/domain/accounts_repository.dart';
import 'package:feature_accounts/src/domain/models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum AccountsStatus { loading, loaded, failure }

class AccountsState extends Equatable {
  const AccountsState({
    this.status = AccountsStatus.loading,
    this.accounts = const [],
    this.fetchedAt,
    this.isStale = false,
    this.refreshing = false,
    this.failure,
    this.balancesHidden = false,
  });

  final AccountsStatus status;
  final List<Account> accounts;
  final DateTime? fetchedAt;

  /// True when [accounts] come from the local cache.
  final bool isStale;

  /// A background refresh is in flight while data is already shown.
  final bool refreshing;

  /// With data: why the last refresh failed (shown as a banner).
  /// Without data: why there is nothing to show (shown as ErrorView).
  final AppFailure? failure;

  /// Privacy toggle: masks amounts on screen (kept in memory only).
  final bool balancesHidden;

  bool get hasData => accounts.isNotEmpty;

  double get totalBalance => accounts.fold(0, (sum, a) => sum + a.balance);

  Account? byId(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  AccountsState copyWith({
    AccountsStatus? status,
    List<Account>? accounts,
    DateTime? fetchedAt,
    bool? isStale,
    bool? refreshing,
    AppFailure? Function()? failure,
    bool? balancesHidden,
  }) => AccountsState(
    status: status ?? this.status,
    accounts: accounts ?? this.accounts,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    isStale: isStale ?? this.isStale,
    refreshing: refreshing ?? this.refreshing,
    failure: failure != null ? failure() : this.failure,
    balancesHidden: balancesHidden ?? this.balancesHidden,
  );

  @override
  List<Object?> get props => [
    status,
    accounts,
    fetchedAt,
    isStale,
    refreshing,
    failure,
    balancesHidden,
  ];
}

/// Owns the customer's accounts for the whole authenticated shell (home
/// summary, detail header, transfer form), so they are fetched once and
/// refreshed in one place.
class AccountsCubit extends Cubit<AccountsState> {
  AccountsCubit(this._repository, {Stream<bool>? connectivityChanges})
    : super(const AccountsState()) {
    // Auto-recover: when the device comes back online, refresh silently.
    _connectivity = connectivityChanges
        ?.where((online) => online)
        .listen((_) => load());
  }

  final AccountsRepository _repository;
  StreamSubscription<bool>? _connectivity;
  StreamSubscription<Result<Fetched<List<Account>>>>? _loading;

  Future<void> load() async {
    await _loading?.cancel();
    emit(
      state.copyWith(
        refreshing: state.hasData,
        status: state.hasData ? null : AccountsStatus.loading,
      ),
    );
    final done = Completer<void>();
    _loading = _repository.watchAccounts().listen(
      _onResult,
      onDone: () {
        if (!isClosed) emit(state.copyWith(refreshing: false));
        done.complete();
      },
    );
    return done.future;
  }

  Future<void> refresh() => load();

  void _onResult(Result<Fetched<List<Account>>> result) {
    if (isClosed) return;
    switch (result) {
      case Success(:final value):
        emit(
          state.copyWith(
            status: AccountsStatus.loaded,
            accounts: value.data,
            fetchedAt: value.fetchedAt,
            isStale: value.isFromCache,
            failure: value.isFromCache ? null : () => null,
          ),
        );
      case Failure(:final failure):
        emit(
          state.copyWith(
            status: state.hasData
                ? AccountsStatus.loaded
                : AccountsStatus.failure,
            isStale: state.hasData ? true : null,
            failure: () => failure,
          ),
        );
    }
  }

  void toggleBalances() =>
      emit(state.copyWith(balancesHidden: !state.balancesHidden));

  /// Applies balances returned by a transfer receipt immediately, before the
  /// background refresh lands (optimistic but server-confirmed values).
  void applyReceipt(TransferReceipt receipt) {
    final updated = [
      for (final a in state.accounts)
        if (a.id == receipt.fromAccountId)
          a.withBalance(receipt.fromBalance)
        else if (a.id == receipt.toAccountId && receipt.toBalance != null)
          a.withBalance(receipt.toBalance!)
        else
          a,
    ];
    emit(state.copyWith(accounts: updated));
  }

  @override
  Future<void> close() async {
    await _connectivity?.cancel();
    await _loading?.cancel();
    return super.close();
  }
}
