import 'package:feature_auth/feature_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('both password fields have their own visibility toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RegisterPage(
          authRepository: MockAuthRepository(),
          onGoToLogin: () {},
        ),
      ),
    );

    expect(find.byTooltip('Mostrar contraseña'), findsNWidgets(2));

    // Toggling the confirmation does not reveal the password, and vice versa.
    await tester.tap(find.byTooltip('Mostrar contraseña').last);
    await tester.pump();
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
  });

  testWidgets(
    'registration asks only for credentials (name is captured in onboarding)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(
            authRepository: MockAuthRepository(),
            onGoToLogin: () {},
          ),
        ),
      );
      expect(find.text('Nombre completo'), findsNothing);
      expect(find.byKey(const Key('email_field')), findsOneWidget);
      expect(find.byKey(const Key('password_field')), findsOneWidget);
      expect(find.byKey(const Key('confirm_field')), findsOneWidget);
    },
  );
}
