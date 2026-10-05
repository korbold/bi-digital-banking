// Critical E2E flow against the REAL backend (Firebase Auth + BFF on Vercel):
//   register -> onboarding -> personalized home -> transfer between own
//   accounts -> receipt -> balances refreshed.
//
// Run on a device/emulator:  cd app && flutter test integration_test
import 'package:bi_digital_banking/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// pumpAndSettle never settles with progress indicators; poll instead.
extension on WidgetTester {
  Future<void> pumpUntilFound(
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await pump(const Duration(milliseconds: 250));
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out waiting for $finder');
  }

  Future<void> enter(Key key, String text) async {
    await enterText(find.byKey(key), text);
    await pump();
  }

  Future<void> tapAndPump(Finder finder) async {
    await ensureVisible(finder);
    await tap(finder);
    await pump(const Duration(milliseconds: 300));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new customer can onboard and transfer between own accounts', (
    tester,
  ) async {
    final email = 'e2e+${DateTime.now().millisecondsSinceEpoch}@bidigital.test';

    await app.main();
    // The device may keep a previous session: start every run logged out.
    await tester.pumpUntilFound(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == '¿Eres nuevo? Abre tu cuenta' || w.data == 'BI Digital'),
      ),
    );
    if (find.text('BI Digital').evaluate().isNotEmpty) {
      await tester.tapAndPump(find.byTooltip('Más opciones'));
      await tester.tapAndPump(find.text('Cerrar sesión'));
    }
    await tester.pumpUntilFound(find.text('¿Eres nuevo? Abre tu cuenta'));

    // 1. Register
    await tester.tapAndPump(find.text('¿Eres nuevo? Abre tu cuenta'));
    await tester.pumpUntilFound(find.byKey(const Key('register_button')));
    await tester.enter(const Key('email_field'), email);
    // Both password inputs reuse PasswordField; the first one is the password.
    await tester.enterText(
      find.byKey(const Key('password_field')).first,
      'Secreta123!',
    );
    await tester.enter(const Key('confirm_field'), 'Secreta123!');
    await tester.tapAndPump(find.byKey(const Key('register_button')));

    // 2. Onboarding (real cédula required by the BFF)
    await tester.pumpUntilFound(find.byKey(const Key('onboarding_document')));
    await tester.enter(const Key('onboarding_name'), 'Cliente E2E');
    await tester.enter(const Key('onboarding_document'), '1003821293');
    await tester.tapAndPump(find.byKey(const Key('onboarding_next')));
    await tester.pumpUntilFound(find.byKey(const Key('onboarding_income')));
    await tester.tapAndPump(find.text('26-40'));
    await tester.enter(const Key('onboarding_income'), '1500');
    await tester.tapAndPump(find.text('Viajes'));
    await tester.tapAndPump(find.byKey(const Key('onboarding_submit')));

    // 3. Personalized home with real accounts
    await tester.pumpUntilFound(
      find.text('BI Digital'),
      timeout: const Duration(seconds: 45),
    );
    await tester.pumpUntilFound(
      find.textContaining('Cuenta'),
      timeout: const Duration(seconds: 45),
    );

    // 4. Transfer $1.25 between own accounts
    await tester.tapAndPump(find.byTooltip('Más opciones'));
    await tester.tapAndPump(find.text('Transferir').last);
    await tester.pumpUntilFound(find.byKey(const Key('transfer_amount')));

    await tester.tapAndPump(find.byKey(const Key('transfer_to')));
    await tester.tapAndPump(find.byType(DropdownMenuItem<String>).last);
    await tester.enter(const Key('transfer_amount'), '1.25');
    await tester.enter(const Key('transfer_description'), 'Prueba E2E');
    await tester.tapAndPump(find.byKey(const Key('transfer_continue')));

    await tester.pumpUntilFound(find.byKey(const Key('transfer_confirm')));
    await tester.tapAndPump(find.byKey(const Key('transfer_confirm')));

    // 5. Receipt from the server, then back home
    await tester.pumpUntilFound(
      find.byKey(const Key('transfer_done')),
      timeout: const Duration(seconds: 45),
    );
    await tester.tapAndPump(find.byKey(const Key('transfer_done')));
    await tester.pumpUntilFound(find.text('BI Digital'));
  });
}
