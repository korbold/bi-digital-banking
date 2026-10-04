import 'package:design_system/design_system.dart';
import 'package:feature_accounts/src/application/accounts_cubit.dart';
import 'package:feature_accounts/src/domain/models.dart';
import 'package:feature_accounts/src/presentation/formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// All accounts as a list — entry point to each account's movements.
/// Requires [AccountsCubit] in the tree (provided by the session scope).
class AccountsListPage extends StatelessWidget {
  const AccountsListPage({required this.onAccountTap, super.key});

  final ValueChanged<Account> onAccountTap;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis cuentas')),
    body: BlocBuilder<AccountsCubit, AccountsState>(
      builder: (context, state) {
        final cubit = context.read<AccountsCubit>();
        if (!state.hasData && state.status == AccountsStatus.loading) {
          return const Padding(
            padding: EdgeInsets.all(BiSpacing.md),
            child: Column(
              children: [
                SkeletonBox(height: 72),
                SizedBox(height: BiSpacing.sm),
                SkeletonBox(height: 72),
              ],
            ),
          );
        }
        if (!state.hasData) {
          return ErrorView(
            message: state.failure == null
                ? 'No tienes cuentas'
                : accountsFailureMessage(state.failure!),
            onRetry: cubit.refresh,
          );
        }
        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: ListView(
            padding: const EdgeInsets.all(BiSpacing.md),
            children: [
              if (state.isStale && state.fetchedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: BiSpacing.sm),
                  child: StatusBanner(
                    message: staleDataMessage(state.fetchedAt!, state.failure),
                    tone: BannerTone.warning,
                  ),
                ),
              for (final account in state.accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: BiSpacing.sm),
                  child: Card(
                    child: ListTile(
                      key: Key('account_tile_${account.id}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: BiSpacing.md,
                        vertical: BiSpacing.xs,
                      ),
                      leading: Icon(
                        account.type == AccountType.savings
                            ? Icons.savings_outlined
                            : Icons.account_balance_wallet_outlined,
                      ),
                      title: Text(account.alias),
                      subtitle: Text('${account.type.label} ${account.number}'),
                      trailing: state.balancesHidden
                          ? const Text('••••••')
                          : MoneyText(
                              account.available,
                              currency: account.currency,
                            ),
                      onTap: () => onAccountTap(account),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
