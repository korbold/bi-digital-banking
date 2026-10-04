import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sdui/sdui.dart';

class _MockHomeCubit extends MockCubit<HomeState> implements HomeCubit {}

void main() {
  late _MockHomeCubit cubit;
  late SduiRegistry registry;

  setUp(() {
    cubit = _MockHomeCubit();
    registry = SduiRegistry();
    registerDefaults(registry);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider<HomeCubit>.value(
          value: cubit,
          child: HomeView(
            registry: registry,
            onAction: (_, {sourceSectionId}) {},
          ),
        ),
      ),
    ),
  );

  testWidgets('stale data shows the offline banner on top of cached content', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(
      HomeLoaded(
        screen: const SduiScreen(
          screen: 'home',
          sections: [
            SduiSection(
              id: 'g',
              type: 'greeting',
              properties: {'title': 'Hola Danny'},
            ),
          ],
        ),
        fetchedAt: DateTime(2026, 10, 4, 10, 42),
        isStale: true,
        refreshFailure: const OfflineFailure(),
      ),
    );
    await pump(tester);

    expect(find.text('Hola Danny'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-stale-banner')), findsOneWidget);
    expect(find.textContaining('Sin conexión'), findsOneWidget);
  });

  testWidgets('failure without cache shows ErrorView with retry', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(const HomeFailure(TimeoutFailure()));
    when(() => cubit.refresh()).thenAnswer((_) async {});
    await pump(tester);

    await tester.tap(find.text('Reintentar'));
    verify(() => cubit.refresh()).called(1);
  });
}
