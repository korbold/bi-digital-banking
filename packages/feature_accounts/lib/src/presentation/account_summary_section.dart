import 'package:design_system/design_system.dart';
import 'package:feature_accounts/src/application/accounts_cubit.dart';
import 'package:feature_accounts/src/domain/models.dart';
import 'package:feature_accounts/src/presentation/formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Compact accounts carousel for the home screen (SDUI type
/// `account_summary`). It renders data owned by the accounts domain: the
/// server layout only decides *where* it appears, never its contents.
///
/// Requires an [AccountsCubit] above it in the tree.
class AccountSummarySection extends StatelessWidget {
  const AccountSummarySection({required this.onAccountTap, super.key});

  final ValueChanged<Account> onAccountTap;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AccountsCubit, AccountsState>(
        builder: (context, state) {
          final cubit = context.read<AccountsCubit>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                'Mis cuentas',
                trailing: IconButton(
                  tooltip: state.balancesHidden
                      ? 'Mostrar saldos'
                      : 'Ocultar saldos',
                  icon: Icon(
                    state.balancesHidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: cubit.toggleBalances,
                ),
              ),
              if (state.isStale && state.fetchedAt != null) ...[
                StatusBanner(
                  tone: BannerTone.warning,
                  message: staleDataMessage(state.fetchedAt!, state.failure),
                  action: 'Reintentar',
                  onAction: cubit.refresh,
                ),
                const SizedBox(height: BiSpacing.sm),
              ],
              SizedBox(height: 132, child: _body(context, state, cubit)),
            ],
          );
        },
      );

  Widget _body(BuildContext context, AccountsState state, AccountsCubit cubit) {
    if (!state.hasData && state.status == AccountsStatus.failure) {
      return Card(
        child: ErrorView(
          message: accountsFailureMessage(state.failure!),
          onRetry: cubit.refresh,
        ),
      );
    }
    if (!state.hasData) {
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 2,
        separatorBuilder: (_, _) => const SizedBox(width: BiSpacing.md),
        itemBuilder: (_, _) =>
            const SizedBox(width: 240, child: _CardSkeleton()),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: state.accounts.length,
      separatorBuilder: (_, _) => const SizedBox(width: BiSpacing.md),
      itemBuilder: (_, i) => SizedBox(
        width: 240,
        child: AccountCard(
          account: state.accounts[i],
          hidden: state.balancesHidden,
          onTap: () => onAccountTap(state.accounts[i]),
        ),
      ),
    );
  }
}

class AccountCard extends StatelessWidget {
  const AccountCard({
    required this.account,
    required this.hidden,
    required this.onTap,
    super.key,
  });

  final Account account;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label:
          '${account.alias}, ${account.type.label} ${account.number}. '
          'Saldo ${hidden ? 'oculto' : formatMoney(account.balance, currency: account.currency)}',
      excludeSemantics: true,
      child: Card(
        color: scheme.primaryContainer,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(BiSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.alias,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${account.type.label} ${account.number}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                Text('Saldo disponible', style: theme.textTheme.labelSmall),
                if (hidden)
                  Text('••••••', style: theme.textTheme.headlineSmall)
                else
                  MoneyText(
                    account.available,
                    currency: account.currency,
                    style: theme.textTheme.headlineSmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(BiSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120),
          SizedBox(height: BiSpacing.sm),
          SkeletonBox(width: 80, height: 12),
          Spacer(),
          SkeletonBox(width: 140, height: 28),
        ],
      ),
    ),
  );
}
