import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

void main() {
  late MockAccountsRepository repository;
  late int keys;

  setUpAll(
    () => registerFallbackValue(
      const TransferRequest(
        fromAccountId: '',
        toAccountId: '',
        amount: 0,
        idempotencyKey: '',
      ),
    ),
  );

  setUp(() {
    repository = MockAccountsRepository();
    keys = 0;
  });

  TransferCubit build() => TransferCubit(
    repository,
    accounts: () => const [savings, checking],
    initialFromAccountId: 'acc_a',
    newIdempotencyKey: () => 'key-${++keys}',
  );

  final receipt = TransferReceipt(
    transferId: 'trf_1',
    fromAccountId: 'acc_a',
    fromBalance: 75,
    toAccountId: 'acc_b',
    toBalance: 525,
    createdAt: fetchedAt,
  );

  blocTest<TransferCubit, TransferState>(
    'validates destination and amount against available balance',
    build: build,
    act: (cubit) => cubit
      ..amountChanged('150')
      ..review(),
    verify: (cubit) {
      expect(cubit.state.errors['to'], 'Selecciona la cuenta de destino');
      expect(cubit.state.errors['amount'], 'Supera tu saldo disponible');
      expect(cubit.state.status, TransferStatus.editing);
    },
  );

  blocTest<TransferCubit, TransferState>(
    'rejects more than two decimals',
    build: build,
    act: (cubit) => cubit
      ..toChanged('acc_b')
      ..amountChanged('1.234')
      ..review(),
    verify: (cubit) =>
        expect(cubit.state.errors['amount'], 'Máximo 2 decimales'),
  );

  blocTest<TransferCubit, TransferState>(
    'successful transfer emits the receipt',
    setUp: () => when(
      () => repository.transfer(any()),
    ).thenAnswer((_) async => Result.success(receipt)),
    build: build,
    act: (cubit) async {
      cubit
        ..toChanged('acc_b')
        ..amountChanged('25')
        ..review();
      await cubit.confirm();
    },
    verify: (cubit) {
      expect(cubit.state.status, TransferStatus.success);
      expect(cubit.state.receipt, receipt);
      final request =
          verify(() => repository.transfer(captureAny())).captured.single
              as TransferRequest;
      expect(request.amount, 25);
      expect(request.idempotencyKey, 'key-1');
    },
  );

  blocTest<TransferCubit, TransferState>(
    'retry after a timeout reuses the same idempotency key',
    setUp: () {
      var call = 0;
      when(() => repository.transfer(any())).thenAnswer(
        (_) async => call++ == 0
            ? const Result.failure(TimeoutFailure())
            : Result.success(receipt),
      );
    },
    build: build,
    act: (cubit) async {
      cubit
        ..toChanged('acc_b')
        ..amountChanged('25')
        ..review();
      await cubit.confirm();
      expect(cubit.state.canRetry, isTrue);
      await cubit.confirm();
    },
    verify: (cubit) {
      final keysSent = verify(() => repository.transfer(captureAny())).captured
          .cast<TransferRequest>()
          .map(
            (r) => r.idempotencyKey,
          );
      expect(keysSent, ['key-1', 'key-1']);
      expect(cubit.state.status, TransferStatus.success);
    },
  );

  blocTest<TransferCubit, TransferState>(
    'editing the intent mints a new key',
    setUp: () => when(
      () => repository.transfer(any()),
    ).thenAnswer((_) async => const Result.failure(TimeoutFailure())),
    build: build,
    act: (cubit) async {
      cubit
        ..toChanged('acc_b')
        ..amountChanged('25')
        ..review();
      await cubit.confirm();
      cubit
        ..amountChanged('30')
        ..review();
      await cubit.confirm();
    },
    verify: (_) {
      final keysSent = verify(() => repository.transfer(captureAny())).captured
          .cast<TransferRequest>()
          .map(
            (r) => r.idempotencyKey,
          );
      expect(keysSent, ['key-1', 'key-2']);
    },
  );

  blocTest<TransferCubit, TransferState>(
    'insufficient funds from the server is shown in Spanish and is not retryable',
    setUp: () => when(() => repository.transfer(any())).thenAnswer(
      (_) async => const Result.failure(
        ValidationFailure('Saldo insuficiente', code: 'insufficient_funds'),
      ),
    ),
    build: build,
    act: (cubit) async {
      cubit
        ..toChanged('acc_b')
        ..amountChanged('25')
        ..review();
      await cubit.confirm();
    },
    verify: (cubit) {
      expect(cubit.state.status, TransferStatus.failure);
      expect(
        cubit.state.failureMessage,
        'Saldo insuficiente en la cuenta de origen.',
      );
      expect(cubit.state.canRetry, isFalse);
    },
  );
}
