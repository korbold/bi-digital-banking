import 'package:core/core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late MockAuthRepository auth;

  setUp(() => auth = MockAuthRepository());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: LoginPage(authRepository: auth, onGoToRegister: () {}),
    ),
  );

  testWidgets('shows validation errors and does not call the repository', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pump();

    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    verifyNever(
      () => auth.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    );
  });

  testWidgets('shows the server error banner on wrong credentials', (
    tester,
  ) async {
    when(
      () => auth.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer(
      (_) async => Result.failure(mapFirebaseAuthCode('invalid-credential')),
    );
    await pump(tester);

    await tester.enterText(
      find.byKey(const Key('email_field')),
      'ana@test.com',
    );
    await tester.enterText(find.byKey(const Key('password_field')), 'secret1');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
  });

  testWidgets('password visibility toggle is accessible', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });
}
