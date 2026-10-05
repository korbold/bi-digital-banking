import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late MockAuthRepository auth;

  setUp(() => auth = MockAuthRepository());

  group('LoginCubit', () {
    blocTest<LoginCubit, CredentialsState>(
      'emits submitting then success',
      setUp: () => when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => const Result.success(user)),
      build: () => LoginCubit(auth),
      act: (cubit) => cubit.submit(email: 'ana@test.com', password: 'secret1'),
      expect: () => [
        const CredentialsState(status: FormStatus.submitting),
        const CredentialsState(status: FormStatus.success),
      ],
    );

    blocTest<LoginCubit, CredentialsState>(
      'emits failure with the Spanish message on bad credentials',
      setUp: () =>
          when(
            () => auth.signIn(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenAnswer(
            (_) async =>
                Result.failure(mapFirebaseAuthCode('invalid-credential')),
          ),
      build: () => LoginCubit(auth),
      act: (cubit) => cubit.submit(email: 'ana@test.com', password: 'bad'),
      expect: () => [
        const CredentialsState(status: FormStatus.submitting),
        const CredentialsState(
          status: FormStatus.failure,
          errorMessage: 'Correo o contraseña incorrectos.',
        ),
      ],
    );
  });

  group('RegisterCubit', () {
    blocTest<RegisterCubit, CredentialsState>(
      'maps offline failure to a connectivity message',
      setUp: () => when(
        () => auth.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => const Result.failure(OfflineFailure())),
      build: () => RegisterCubit(auth),
      act: (cubit) => cubit.submit(email: 'ana@test.com', password: 'secret1'),
      expect: () => [
        const CredentialsState(status: FormStatus.submitting),
        const CredentialsState(
          status: FormStatus.failure,
          errorMessage:
              'Sin conexión a internet. Revisa tu red e intenta de nuevo.',
        ),
      ],
    );
  });

  test('validators', () {
    expect(CredentialValidators.email('bad'), 'Correo no válido');
    expect(CredentialValidators.email('a@b.co'), isNull);
    expect(CredentialValidators.password('123'), 'Mínimo 6 caracteres');
  });
}
