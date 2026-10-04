import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late MockAuthRepository auth;
  late MockCustomerRepository customers;
  late StreamController<AuthUser?> authStream;

  setUp(() {
    auth = MockAuthRepository();
    customers = MockCustomerRepository();
    authStream = StreamController<AuthUser?>();
    when(auth.authStateChanges).thenAnswer((_) => authStream.stream);
    when(auth.signOut).thenAnswer((_) async {});
  });

  tearDown(() => authStream.close());

  SessionCubit build() =>
      SessionCubit(authRepository: auth, customerRepository: customers);

  blocTest<SessionCubit, SessionState>(
    'emits unauthenticated when there is no user',
    build: build,
    act: (_) => authStream.add(null),
    expect: () => [const SessionUnauthenticated()],
  );

  blocTest<SessionCubit, SessionState>(
    'emits authenticated when the customer exists',
    setUp: () => when(
      customers.getMe,
    ).thenAnswer((_) async => const Result.success(customer)),
    build: build,
    act: (_) => authStream.add(user),
    expect: () => [const SessionAuthenticated(user, customer)],
  );

  blocTest<SessionCubit, SessionState>(
    'emits needsOnboarding when the BFF has no customer, then authenticated after onboarding',
    setUp: () => when(
      customers.getMe,
    ).thenAnswer((_) async => const Result.success(null)),
    build: build,
    act: (cubit) async {
      authStream.add(user);
      await Future<void>.delayed(Duration.zero);
      cubit.onboardingCompleted(customer);
    },
    expect: () => [
      const SessionNeedsOnboarding(user),
      const SessionAuthenticated(user, customer),
    ],
  );

  blocTest<SessionCubit, SessionState>(
    'emits profileUnavailable when /me fails, and recovers on refresh',
    setUp: () {
      var calls = 0;
      when(customers.getMe).thenAnswer(
        (_) async => calls++ == 0
            ? const Result.failure(OfflineFailure())
            : const Result.success(customer),
      );
    },
    build: build,
    act: (cubit) async {
      authStream.add(user);
      await Future<void>.delayed(Duration.zero);
      await cubit.refreshProfile();
    },
    expect: () => [
      const SessionProfileUnavailable(user, OfflineFailure()),
      const SessionAuthenticated(user, customer),
    ],
  );

  blocTest<SessionCubit, SessionState>(
    'signOut delegates to the repository',
    build: build,
    act: (cubit) => cubit.signOut(),
    verify: (_) => verify(auth.signOut).called(1),
  );
}
