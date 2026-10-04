import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney', () {
    test('adds thousands separators and two decimals', () {
      expect(formatMoney(1234567.5), r'$1,234,567.50');
    });

    test('signs movements when asked', () {
      expect(formatMoney(-12.3, signed: true), r'-$12.30');
      expect(formatMoney(5, signed: true), r'+$5.00');
    });
  });

  testWidgets('MoneyText exposes an accessible debit label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: MoneyText(-20, signed: true)),
    );
    expect(find.bySemanticsLabel(r'Débito de -$20.00'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('ErrorView calls onRetry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorView(message: 'Sin conexión', onRetry: () => retried = true),
      ),
    );
    await tester.tap(find.text('Reintentar'));
    expect(retried, isTrue);
  });
}
