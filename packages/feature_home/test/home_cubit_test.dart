import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sdui/sdui.dart';

class _MockHomeRepository extends Mock implements HomeRepository {}

void main() {
  late _MockHomeRepository repository;
  final cachedAt = DateTime(2026, 10, 4, 9);
  final freshAt = DateTime(2026, 10, 4, 10);
  const cachedScreen = SduiScreen(
    screen: 'home',
    sections: [SduiSection(id: 'g', type: 'greeting')],
  );
  const freshScreen = SduiScreen(
    screen: 'home',
    sections: [SduiSection(id: 'g2', type: 'greeting')],
  );

  setUp(() => repository = _MockHomeRepository());

  blocTest<HomeCubit, HomeState>(
    'emits cached layout while refreshing, then the fresh one',
    setUp: () => when(() => repository.watchHome()).thenAnswer(
      (_) => Stream.fromIterable([
        Result.success(
          Fetched(cachedScreen, source: DataSource.cache, fetchedAt: cachedAt),
        ),
        Result.success(
          Fetched(freshScreen, source: DataSource.network, fetchedAt: freshAt),
        ),
      ]),
    ),
    build: () => HomeCubit(repository),
    act: (cubit) => cubit.load(),
    expect: () => [
      const HomeLoading(),
      HomeLoaded(
        screen: cachedScreen,
        fetchedAt: cachedAt,
        isStale: true,
        isRefreshing: true,
      ),
      HomeLoaded(screen: freshScreen, fetchedAt: freshAt),
    ],
  );

  blocTest<HomeCubit, HomeState>(
    'network failure after a cache hit keeps cached data and flags it stale',
    setUp: () => when(() => repository.watchHome()).thenAnswer(
      (_) => Stream.fromIterable([
        Result.success(
          Fetched(cachedScreen, source: DataSource.cache, fetchedAt: cachedAt),
        ),
        const Result.failure(OfflineFailure()),
      ]),
    ),
    build: () => HomeCubit(repository),
    act: (cubit) => cubit.load(),
    expect: () => [
      const HomeLoading(),
      HomeLoaded(
        screen: cachedScreen,
        fetchedAt: cachedAt,
        isStale: true,
        isRefreshing: true,
      ),
      HomeLoaded(
        screen: cachedScreen,
        fetchedAt: cachedAt,
        isStale: true,
        refreshFailure: const OfflineFailure(),
      ),
    ],
  );

  blocTest<HomeCubit, HomeState>(
    'no cache and network failure -> HomeFailure (no invented data)',
    setUp: () =>
        when(
          () => repository.watchHome(),
        ).thenAnswer(
          (_) => Stream.value(
            const Result.failure(ServiceUnavailableFailure('home')),
          ),
        ),
    build: () => HomeCubit(repository),
    act: (cubit) => cubit.load(),
    expect: () => [
      const HomeLoading(),
      const HomeFailure(ServiceUnavailableFailure('home')),
    ],
  );
}
