import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late MockAccountsRepository repository;

  setUp(() => repository = MockAccountsRepository());

  void stubPage(Result<Fetched<MovementsPage>> result, {String? cursor}) =>
      when(
        () => repository.getMovements(
          'acc_a',
          cursor: cursor,
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => result);

  blocTest<MovementsCubit, MovementsState>(
    'loads the first page from the network',
    setUp: () => stubPage(
      Result.success(
        network(MovementsPage(items: [movement('1', -5)], nextCursor: 'c2')),
      ),
    ),
    build: () => MovementsCubit(repository, accountId: 'acc_a'),
    act: (cubit) => cubit.load(),
    expect: () => [
      const MovementsState(),
      MovementsState(
        status: MovementsStatus.loaded,
        items: [movement('1', -5)],
        nextCursor: 'c2',
        fetchedAt: fetchedAt,
      ),
    ],
  );

  blocTest<MovementsCubit, MovementsState>(
    'marks cached pages as stale and disables pagination',
    setUp: () => stubPage(
      Result.success(
        cached(MovementsPage(items: [movement('1', -5)], nextCursor: 'c2')),
      ),
    ),
    build: () => MovementsCubit(repository, accountId: 'acc_a'),
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      expect(cubit.state.isStale, isTrue);
      expect(cubit.state.hasMore, isFalse);
    },
  );

  blocTest<MovementsCubit, MovementsState>(
    'emits failure when nothing could be loaded',
    setUp: () => stubPage(const Result.failure(TimeoutFailure())),
    build: () => MovementsCubit(repository, accountId: 'acc_a'),
    act: (cubit) => cubit.load(),
    expect: () => [
      const MovementsState(),
      const MovementsState(
        status: MovementsStatus.failure,
        failure: TimeoutFailure(),
      ),
    ],
  );

  blocTest<MovementsCubit, MovementsState>(
    'loadMore appends the next page',
    setUp: () => stubPage(
      Result.success(network(MovementsPage(items: [movement('2', 10)]))),
      cursor: 'c2',
    ),
    build: () => MovementsCubit(repository, accountId: 'acc_a'),
    seed: () => MovementsState(
      status: MovementsStatus.loaded,
      items: [movement('1', -5)],
      nextCursor: 'c2',
      fetchedAt: fetchedAt,
    ),
    act: (cubit) => cubit.loadMore(),
    verify: (cubit) {
      expect(cubit.state.items.map((m) => m.id), ['1', '2']);
      expect(cubit.state.hasMore, isFalse);
      expect(cubit.state.loadingMore, isFalse);
    },
  );

  blocTest<MovementsCubit, MovementsState>(
    'loadMore failure keeps items and exposes an inline error',
    setUp: () => stubPage(const Result.failure(OfflineFailure()), cursor: 'c2'),
    build: () => MovementsCubit(repository, accountId: 'acc_a'),
    seed: () => MovementsState(
      status: MovementsStatus.loaded,
      items: [movement('1', -5)],
      nextCursor: 'c2',
    ),
    act: (cubit) => cubit.loadMore(),
    verify: (cubit) {
      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.loadMoreFailure, const OfflineFailure());
    },
  );
}
