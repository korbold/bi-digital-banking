import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late MockCustomerRepository customers;

  setUpAll(
    () => registerFallbackValue(
      const OnboardingRequest(
        name: '',
        documentId: '',
        ageRange: '',
        monthlyIncome: 0,
        interests: [],
      ),
    ),
  );

  setUp(() => customers = MockCustomerRepository());

  blocTest<OnboardingCubit, OnboardingState>(
    'does not advance with an invalid cédula',
    build: () => OnboardingCubit(customers),
    act: (cubit) => cubit
      ..nameChanged('Ana López')
      ..documentChanged('1234567890')
      ..next(),
    skip: 2,
    expect: () => [
      isA<OnboardingState>()
          .having((s) => s.step, 'step', OnboardingStep.personal)
          .having((s) => s.errors['documentId'], 'error', 'Cédula no válida'),
    ],
  );

  blocTest<OnboardingCubit, OnboardingState>(
    'completes onboarding with a valid profile',
    setUp: () => when(
      () => customers.completeOnboarding(any()),
    ).thenAnswer((_) async => const Result.success(customer)),
    build: () => OnboardingCubit(customers),
    act: (cubit) async {
      cubit
        ..nameChanged('Ana López')
        ..documentChanged('1710034065');
      expect(cubit.next(), isTrue);
      cubit
        ..ageRangeChanged('18-25')
        ..incomeChanged('1200')
        ..toggleInterest('travel');
      await cubit.submit();
    },
    verify: (cubit) {
      expect(cubit.state.status, OnboardingStatus.success);
      expect(cubit.state.customer, customer);
      final request =
          verify(
                () => customers.completeOnboarding(captureAny()),
              ).captured.single
              as OnboardingRequest;
      expect(request.monthlyIncome, 1200);
      expect(request.interests, ['travel']);
    },
  );

  blocTest<OnboardingCubit, OnboardingState>(
    'requires age, income and interests on the profile step',
    build: () => OnboardingCubit(customers),
    seed: () => const OnboardingState(
      step: OnboardingStep.profile,
      name: 'Ana López',
      documentId: '1710034065',
    ),
    act: (cubit) => cubit.submit(),
    expect: () => [
      isA<OnboardingState>().having(
        (s) => s.errors.keys,
        'errors',
        containsAll(['ageRange', 'monthlyIncome', 'interests']),
      ),
    ],
    verify: (_) => verifyNever(() => customers.completeOnboarding(any())),
  );
}
