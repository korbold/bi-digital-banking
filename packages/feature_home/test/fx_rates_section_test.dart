import 'package:core/core.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sdui/sdui.dart';

class _MockFxRepository extends Mock implements FxRepository {}

void main() {
  late _MockFxRepository repository;
  const section = SduiSection(
    id: 'fx',
    type: 'fx_rates',
    properties: {
      'base': 'USD',
      'symbols': ['EUR', 'COP'],
    },
  );

  setUp(() => repository = _MockFxRepository());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FxRatesSection(section: section, repository: repository),
      ),
    ),
  );

  testWidgets('provider outage degrades only the card and allows retry', (
    tester,
  ) async {
    var calls = 0;
    when(
      () => repository.fetch(base: 'USD', symbols: ['EUR', 'COP']),
    ).thenAnswer((_) async {
      calls++;
      return calls == 1
          ? const Result.failure(ServiceUnavailableFailure('fx'))
          : Result.success(
              Fetched(
                const FxRates(
                  base: 'USD',
                  rates: {'EUR': 0.9123, 'COP': 4100},
                  provider: 'open.er-api.com',
                ),
                source: DataSource.network,
                fetchedAt: DateTime(2026, 10, 4),
              ),
            );
    });

    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fx-unavailable')), findsOneWidget);
    expect(find.text('Tipos de cambio no disponibles'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('EUR'), findsOneWidget);
    expect(find.text('0.9123'), findsOneWidget);
    expect(find.text('4100'), findsOneWidget);
  });
}
