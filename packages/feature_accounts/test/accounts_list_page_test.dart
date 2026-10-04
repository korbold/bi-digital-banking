import 'package:bloc_test/bloc_test.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

class _MockAccountsCubit extends MockCubit<AccountsState>
    implements AccountsCubit {}

void main() {
  testWidgets('lists accounts and opens the tapped one', (tester) async {
    final cubit = _MockAccountsCubit();
    when(() => cubit.state).thenReturn(
      AccountsState(
        status: AccountsStatus.loaded,
        accounts: const [savings, checking],
        fetchedAt: fetchedAt,
      ),
    );
    Account? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AccountsCubit>.value(
          value: cubit,
          child: AccountsListPage(onAccountTap: (a) => opened = a),
        ),
      ),
    );

    expect(find.text('Ahorros'), findsWidgets);
    expect(find.text('Corriente'), findsWidgets);
    await tester.tap(find.byKey(const Key('account_tile_acc_b')));
    expect(opened, checking);
  });
}
