import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

class MockAccountsCubit extends MockCubit<AccountsState>
    implements AccountsCubit {}

const ownSavings = Account(
  id: 'acc_a',
  type: AccountType.savings,
  alias: 'Ahorros',
  number: '****4821',
  accountNumber: '2201234821',
  balance: 100,
  available: 100,
);

const preview = BeneficiaryPreview(
  accountNumber: '2209876543',
  maskedNumber: '****6543',
  holderName: 'Danny B.',
  type: AccountType.savings,
);

void main() {
  setUpAll(
    () => registerFallbackValue(
      const TransferRequest(
        fromAccountId: '',
        toAccountNumber: '',
        amount: 0,
        idempotencyKey: '',
      ),
    ),
  );

  group('models', () {
    test('parses a third-party receipt without the recipient balance', () {
      final receipt = TransferReceipt.fromJson(const {
        'transferId': 'trf_1',
        'kind': 'third_party',
        'from': {'id': 'acc_a', 'balance': 74.5},
        'to': {'accountNumber': '****6543', 'holderName': 'Danny B.'},
        'createdAt': '2026-10-04T15:00:00Z',
      });
      expect(receipt.isThirdParty, isTrue);
      expect(receipt.fromBalance, 74.5);
      expect(receipt.toBalance, isNull);
      expect(receipt.toAccountId, isNull);
      expect(receipt.toHolderName, 'Danny B.');
      expect(receipt.toMaskedNumber, '****6543');
    });

    test('parses own receipts as before', () {
      final receipt = TransferReceipt.fromJson(const {
        'transferId': 'trf_2',
        'kind': 'own',
        'from': {'id': 'acc_a', 'balance': 10},
        'to': {'id': 'acc_b', 'balance': 20},
        'createdAt': '2026-10-04T15:00:00Z',
      });
      expect(receipt.isThirdParty, isFalse);
      expect(receipt.toAccountId, 'acc_b');
      expect(receipt.toBalance, 20);
    });

    test('parses a beneficiary preview and the full account number', () {
      final p = BeneficiaryPreview.fromJson(const {
        'accountNumber': '2209876543',
        'maskedNumber': '****6543',
        'holderName': 'Danny B.',
        'type': 'checking',
        'isOwn': true,
        'accountId': 'acc_b',
      });
      expect(p.type, AccountType.checking);
      expect(p.isOwn, isTrue);
      expect(p.accountId, 'acc_b');
      expect(
        Account.fromJson(const {
          'id': 'x',
          'accountNumber': '2201234821',
          'number': '****4821',
        }).accountNumber,
        '2201234821',
      );
    });

    test('TransferRequest serialises only the chosen destination', () {
      const request = TransferRequest(
        fromAccountId: 'acc_a',
        toAccountNumber: '2209876543',
        amount: 5,
        idempotencyKey: 'k',
      );
      expect(request.toJson().containsKey('toAccountId'), isFalse);
      expect(request.toJson()['toAccountNumber'], '2209876543');
    });
  });

  group('TransferCubit third party', () {
    late MockAccountsRepository repository;
    late int keys;

    setUp(() {
      repository = MockAccountsRepository();
      keys = 0;
    });

    TransferCubit build() => TransferCubit(
      repository,
      accounts: () => const [ownSavings, checking],
      initialFromAccountId: 'acc_a',
      newIdempotencyKey: () => 'key-${++keys}',
    );

    blocTest<TransferCubit, TransferState>(
      'verifying a number shows the beneficiary',
      setUp: () => when(
        () => repository.lookupBeneficiary('2209876543'),
      ).thenAnswer((_) async => const Result.success(preview)),
      build: build,
      act: (cubit) async {
        cubit
          ..modeChanged(DestinationMode.thirdParty)
          ..accountNumberChanged('2209876543');
        await cubit.verifyBeneficiary();
      },
      verify: (cubit) {
        expect(cubit.state.lookupStatus, LookupStatus.found);
        expect(cubit.state.beneficiary, preview);
      },
    );

    blocTest<TransferCubit, TransferState>(
      'unknown number reports not found and blocks review',
      setUp: () => when(() => repository.lookupBeneficiary(any())).thenAnswer(
        (_) async => const Result.failure(
          ValidationFailure('x', code: 'beneficiary_not_found'),
        ),
      ),
      build: build,
      act: (cubit) async {
        cubit
          ..modeChanged(DestinationMode.thirdParty)
          ..accountNumberChanged('2200000000')
          ..amountChanged('5');
        await cubit.verifyBeneficiary();
        cubit.review();
      },
      verify: (cubit) {
        expect(cubit.state.lookupStatus, LookupStatus.failed);
        expect(
          cubit.state.errors['to'],
          'Verifica el número de cuenta del destinatario',
        );
        expect(cubit.state.status, TransferStatus.editing);
      },
    );

    blocTest<TransferCubit, TransferState>(
      'rejects the origin account number without calling the server',
      build: build,
      act: (cubit) async {
        cubit
          ..modeChanged(DestinationMode.thirdParty)
          ..accountNumberChanged('2201234821');
        await cubit.verifyBeneficiary();
      },
      verify: (cubit) {
        expect(cubit.state.lookupError, 'Es la misma cuenta de origen');
        verifyNever(() => repository.lookupBeneficiary(any()));
      },
    );

    blocTest<TransferCubit, TransferState>(
      'editing the number discards the preview',
      setUp: () => when(
        () => repository.lookupBeneficiary(any()),
      ).thenAnswer((_) async => const Result.success(preview)),
      build: build,
      act: (cubit) async {
        cubit
          ..modeChanged(DestinationMode.thirdParty)
          ..accountNumberChanged('2209876543');
        await cubit.verifyBeneficiary();
        cubit.accountNumberChanged('220987654');
      },
      verify: (cubit) {
        expect(cubit.state.beneficiary, isNull);
        expect(cubit.state.lookupStatus, LookupStatus.idle);
      },
    );

    test(
      'retry after a timeout reuses the key; a new number mints a new one',
      () async {
        final requests = <TransferRequest>[];
        when(() => repository.lookupBeneficiary(any())).thenAnswer(
          (inv) async => Result.success(
            BeneficiaryPreview(
              accountNumber: inv.positionalArguments.first as String,
              maskedNumber: '****6543',
              holderName: 'Danny B.',
              type: AccountType.savings,
            ),
          ),
        );
        when(() => repository.transfer(any())).thenAnswer((inv) async {
          requests.add(inv.positionalArguments.first as TransferRequest);
          return const Result.failure(TimeoutFailure());
        });

        final cubit = build()
          ..modeChanged(DestinationMode.thirdParty)
          ..accountNumberChanged('2209876543')
          ..amountChanged('5');
        await cubit.verifyBeneficiary();
        expect(cubit.review(), isTrue);
        await cubit.confirm();
        await cubit.confirm(); // "Reintentar"

        cubit.accountNumberChanged('2209876544');
        await cubit.verifyBeneficiary();
        cubit.review();
        await cubit.confirm();

        expect(requests.map((r) => r.toAccountNumber), [
          '2209876543',
          '2209876543',
          '2209876544',
        ]);
        expect(requests.map((r) => r.toAccountId), everyElement(isNull));
        expect(requests[0].idempotencyKey, requests[1].idempotencyKey);
        expect(requests[2].idempotencyKey, isNot(requests[0].idempotencyKey));
        await cubit.close();
      },
    );
  });

  testWidgets('third-party mode verifies and shows the beneficiary card', (
    tester,
  ) async {
    final repository = MockAccountsRepository();
    final accounts = MockAccountsCubit();
    when(() => accounts.state).thenReturn(
      AccountsState(
        status: AccountsStatus.loaded,
        accounts: const [ownSavings, checking],
        fetchedAt: fetchedAt,
      ),
    );
    when(
      () => repository.lookupBeneficiary('2209876543'),
    ).thenAnswer((_) async => const Result.success(preview));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AccountsCubit>.value(
          value: accounts,
          child: TransferPage(repository: repository, onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Otra persona'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('transfer_account_number')),
      '22098-76543x',
    );
    await tester.tap(find.byKey(const Key('transfer_verify')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transfer_beneficiary')), findsOneWidget);
    expect(find.text('Titular: Danny B.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Destinatario verificado: Danny B.')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('transfer_amount')), '5');
    await tester.tap(find.byKey(const Key('transfer_continue')));
    await tester.pumpAndSettle();
    expect(find.text('Danny B. · Ahorros ****6543'), findsOneWidget);
  });
}
