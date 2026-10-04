import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late MockCustomerRepository repository;
  const updated = Customer(
    uid: 'u1',
    name: 'Ana López',
    segment: 'retail',
    interests: ['travel'],
  );

  setUp(() => repository = MockCustomerRepository());

  test('toggling interests marks the form dirty', () {
    final cubit = ProfileCubit(repository, customer: customer)
      ..toggleInterest('travel');
    expect(cubit.state.isDirty, isTrue);
    cubit.toggleInterest('travel');
    expect(cubit.state.isDirty, isFalse);
  });

  blocTest<ProfileCubit, ProfileState>(
    'save sends interests and adopts the server profile',
    setUp: () => when(
      () => repository.updateInterests(['travel']),
    ).thenAnswer((_) async => const Result.success(updated)),
    build: () => ProfileCubit(repository, customer: customer),
    act: (cubit) async {
      cubit.toggleInterest('travel');
      expect(await cubit.save(), updated);
    },
    skip: 1,
    expect: () => [
      isA<ProfileState>().having(
        (s) => s.status,
        'status',
        ProfileStatus.saving,
      ),
      isA<ProfileState>()
          .having((s) => s.status, 'status', ProfileStatus.saved)
          .having((s) => s.customer, 'customer', updated)
          .having((s) => s.isDirty, 'dirty', isFalse),
    ],
  );

  blocTest<ProfileCubit, ProfileState>(
    'save failure keeps the edits so the user can retry',
    setUp: () => when(
      () => repository.updateInterests(any()),
    ).thenAnswer((_) async => const Result.failure(OfflineFailure())),
    build: () => ProfileCubit(repository, customer: customer),
    act: (cubit) async {
      cubit.toggleInterest('tech');
      expect(await cubit.save(), isNull);
    },
    verify: (cubit) {
      expect(cubit.state.status, ProfileStatus.failure);
      expect(cubit.state.interests, {'tech'});
    },
  );
}
