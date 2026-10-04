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

void main() {
  late MockAccountsRepository repository;
  late MockAccountsCubit accounts;

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
    accounts = MockAccountsCubit();
    when(() => accounts.state).thenReturn(
      AccountsState(
        status: AccountsStatus.loaded,
        accounts: const [savings, checking],
        fetchedAt: fetchedAt,
      ),
    );
    when(accounts.refresh).thenAnswer((_) async {});
  });

  Widget host(Widget child) => MaterialApp(
    home: BlocProvider<AccountsCubit>.value(value: accounts, child: child),
  );

  testWidgets(
    'AccountDetailPage shows cached banner and movements grouped by day',
    (tester) async {
      when(
        () => repository.getMovements('acc_a', limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => Result.success(
          cached(MovementsPage(items: [movement('1', -54.2)])),
        ),
      );

      await tester.pumpWidget(
        host(AccountDetailPage(accountId: 'acc_a', repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stale_banner')), findsOneWidget);
      expect(find.text('Mostrando datos guardados de 10:42.'), findsOneWidget);
      expect(find.text('Mov 1'), findsOneWidget);
      expect(find.text(r'-$54.20'), findsOneWidget);
    },
  );

  testWidgets(
    'AccountDetailPage shows ErrorView with retry when nothing is cached',
    (tester) async {
      when(
        () => repository.getMovements('acc_a', limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async =>
            const Result.failure(ServiceUnavailableFailure('accounts')),
      );

      await tester.pumpWidget(
        host(AccountDetailPage(accountId: 'acc_a', repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('El servicio de cuentas no está disponible por ahora.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    },
  );

  testWidgets('TransferPage shows insufficient funds from the server', (
    tester,
  ) async {
    when(() => repository.transfer(any())).thenAnswer(
      (_) async => const Result.failure(
        ValidationFailure('Saldo insuficiente', code: 'insufficient_funds'),
      ),
    );

    await tester.pumpWidget(
      host(TransferPage(repository: repository, onClose: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('transfer_to')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriente ****1234').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('transfer_amount')), '50');
    await tester.tap(find.byKey(const Key('transfer_continue')));
    await tester.pumpAndSettle();

    expect(find.text('Confirma tu transferencia'), findsOneWidget);
    await tester.tap(find.byKey(const Key('transfer_confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transfer_error')), findsOneWidget);
    expect(
      find.text('Saldo insuficiente en la cuenta de origen.'),
      findsOneWidget,
    );
    expect(
      find.text('Reintentar'),
      findsNothing,
      reason: 'business errors are not retryable',
    );
  });

  testWidgets('AccountSummarySection hides balances when toggled', (
    tester,
  ) async {
    when(() => accounts.state).thenReturn(
      const AccountsState(
        status: AccountsStatus.loaded,
        accounts: [savings],
        balancesHidden: true,
      ),
    );
    await tester.pumpWidget(
      host(Scaffold(body: AccountSummarySection(onAccountTap: (_) {}))),
    );

    expect(find.text('••••••'), findsOneWidget);
    expect(find.byTooltip('Mostrar saldos'), findsOneWidget);
  });
}
