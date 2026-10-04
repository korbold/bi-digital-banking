import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late MockAccountsRepository repository;

  setUp(() => repository = MockAccountsRepository());

  void stubWatch(List<Result<Fetched<List<Account>>>> emissions) => when(
    repository.watchAccounts,
  ).thenAnswer((_) => Stream.fromIterable(emissions));

  blocTest<AccountsCubit, AccountsState>(
    'shows cached accounts first, then fresh ones',
    setUp: () => stubWatch([
      Result.success(cached([savings])),
      Result.success(network([savings, checking])),
    ]),
    build: () => AccountsCubit(repository),
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      expect(cubit.state.status, AccountsStatus.loaded);
      expect(cubit.state.accounts, [savings, checking]);
      expect(cubit.state.isStale, isFalse);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.refreshing, isFalse);
    },
  );

  blocTest<AccountsCubit, AccountsState>(
    'keeps cached data and records the cause when the refresh fails',
    setUp: () => stubWatch([
      Result.success(cached([savings])),
      const Result.failure(ServiceUnavailableFailure('accounts')),
    ]),
    build: () => AccountsCubit(repository),
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      expect(cubit.state.status, AccountsStatus.loaded);
      expect(cubit.state.accounts, [savings]);
      expect(cubit.state.isStale, isTrue);
      expect(cubit.state.failure, const ServiceUnavailableFailure('accounts'));
    },
  );

  blocTest<AccountsCubit, AccountsState>(
    'emits failure when there is nothing cached',
    setUp: () => stubWatch([const Result.failure(OfflineFailure())]),
    build: () => AccountsCubit(repository),
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      expect(cubit.state.status, AccountsStatus.failure);
      expect(cubit.state.failure, const OfflineFailure());
    },
  );

  test('reloads automatically when connectivity comes back', () async {
    stubWatch([
      Result.success(network([savings])),
    ]);
    final connectivity = StreamController<bool>();
    final cubit = AccountsCubit(
      repository,
      connectivityChanges: connectivity.stream,
    );

    connectivity
      ..add(false)
      ..add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    verify(repository.watchAccounts).called(1);
    await cubit.close();
    await connectivity.close();
  });

  blocTest<AccountsCubit, AccountsState>(
    'applyReceipt updates both balances',
    build: () => AccountsCubit(repository),
    seed: () => const AccountsState(
      status: AccountsStatus.loaded,
      accounts: [savings, checking],
    ),
    act: (cubit) => cubit.applyReceipt(
      TransferReceipt(
        transferId: 't',
        fromAccountId: 'acc_a',
        fromBalance: 75,
        toAccountId: 'acc_b',
        toBalance: 525,
        createdAt: fetchedAt,
      ),
    ),
    verify: (cubit) {
      expect(cubit.state.byId('acc_a')!.balance, 75);
      expect(cubit.state.byId('acc_b')!.available, 525);
    },
  );

  blocTest<AccountsCubit, AccountsState>(
    'toggleBalances flips the privacy flag',
    build: () => AccountsCubit(repository),
    act: (cubit) => cubit.toggleBalances(),
    expect: () => [const AccountsState(balancesHidden: true)],
  );
}
