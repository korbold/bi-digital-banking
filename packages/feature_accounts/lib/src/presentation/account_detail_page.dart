import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_accounts/src/application/accounts_cubit.dart';
import 'package:feature_accounts/src/application/movements_cubit.dart';
import 'package:feature_accounts/src/domain/accounts_repository.dart';
import 'package:feature_accounts/src/domain/models.dart';
import 'package:feature_accounts/src/presentation/formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Balance header + movements grouped by day with infinite scroll.
/// Requires an [AccountsCubit] above it (for the live balance).
class AccountDetailPage extends StatelessWidget {
  const AccountDetailPage({
    required this.accountId,
    required this.repository,
    super.key,
    this.onTransfer,
  });

  final String accountId;
  final AccountsRepository repository;
  final ValueChanged<String>? onTransfer;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => MovementsCubit(repository, accountId: accountId)..load(),
    child: AccountDetailView(accountId: accountId, onTransfer: onTransfer),
  );
}

class AccountDetailView extends StatefulWidget {
  const AccountDetailView({
    required this.accountId,
    super.key,
    this.onTransfer,
  });

  final String accountId;
  final ValueChanged<String>? onTransfer;

  @override
  State<AccountDetailView> createState() => _AccountDetailViewState();
}

class _AccountDetailViewState extends State<AccountDetailView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Movements are fetched fresh on open; refresh the balance too so the
    // header never contradicts the list (e.g. after receiving money).
    unawaited(context.read<AccountsCubit>().refresh());
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) {
        unawaited(context.read<MovementsCubit>().loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() => Future.wait([
    context.read<MovementsCubit>().refresh(),
    context.read<AccountsCubit>().refresh(),
  ]);

  @override
  Widget build(BuildContext context) {
    final account = context.select(
      (AccountsCubit c) => c.state.byId(widget.accountId),
    );
    final hidden = context.select((AccountsCubit c) => c.state.balancesHidden);
    return Scaffold(
      appBar: AppBar(title: Text(account?.alias ?? 'Cuenta')),
      floatingActionButton: widget.onTransfer == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => widget.onTransfer!(widget.accountId),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Transferir'),
            ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: BlocBuilder<MovementsCubit, MovementsState>(
          builder: (context, state) => CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(BiSpacing.md),
                sliver: SliverList.list(
                  children: [
                    if (account != null)
                      _BalanceHeader(account: account, hidden: hidden),
                    if (state.isStale && state.fetchedAt != null) ...[
                      const SizedBox(height: BiSpacing.md),
                      StatusBanner(
                        key: const Key('stale_banner'),
                        tone: BannerTone.warning,
                        message: staleDataMessage(
                          state.fetchedAt!,
                          state.failure,
                        ),
                        action: 'Reintentar',
                        onAction: context.read<MovementsCubit>().refresh,
                      ),
                    ],
                    const SizedBox(height: BiSpacing.md),
                    const SectionHeader('Movimientos'),
                  ],
                ),
              ),
              ..._movements(context, state, hidden),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _movements(
    BuildContext context,
    MovementsState state,
    bool hidden,
  ) {
    if (state.status == MovementsStatus.loading) {
      return [
        SliverList.builder(
          itemCount: 6,
          itemBuilder: (_, _) => const _MovementSkeleton(),
        ),
      ];
    }
    if (state.status == MovementsStatus.failure) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(
            message: accountsFailureMessage(state.failure!),
            onRetry: context.read<MovementsCubit>().load,
          ),
        ),
      ];
    }
    if (state.items.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('Aún no tienes movimientos')),
        ),
      ];
    }

    final rows = <Widget>[];
    DateTime? currentDay;
    for (final m in state.items) {
      final day = DateUtils.dateOnly(m.date);
      if (day != currentDay) {
        currentDay = day;
        rows.add(_DayHeader(formatDayHeader(day)));
      }
      rows.add(MovementTile(movement: m, hidden: hidden));
    }
    return [
      SliverList.list(children: rows),
      SliverToBoxAdapter(child: _Footer(state: state)),
      const SliverToBoxAdapter(child: SizedBox(height: 88)),
    ];
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.account, required this.hidden});

  final Account account;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(BiSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    // The full number is shareable but follows the privacy
                    // toggle together with the balance.
                    '${account.type.label} '
                    '${hidden || account.accountNumber.isEmpty ? account.number : account.accountNumber}',
                    key: const Key('account_number'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (account.accountNumber.isNotEmpty)
                  IconButton(
                    key: const Key('copy_account_number'),
                    tooltip: 'Copiar número de cuenta',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: account.accountNumber),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('Número copiado')),
                        );
                    },
                  ),
              ],
            ),
            const SizedBox(height: BiSpacing.sm),
            Text('Saldo disponible', style: theme.textTheme.labelMedium),
            if (hidden)
              Semantics(
                label: 'Saldo oculto',
                child: Text('••••••', style: theme.textTheme.displaySmall),
              )
            else
              MoneyText(
                account.available,
                currency: account.currency,
                style: theme.textTheme.displaySmall,
              ),
            if (!hidden && account.balance != account.available)
              Text(
                'Saldo contable ${formatMoney(account.balance)}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      BiSpacing.md,
      BiSpacing.md,
      BiSpacing.md,
      BiSpacing.xs,
    ),
    child: Semantics(
      header: true,
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    ),
  );
}

class MovementTile extends StatelessWidget {
  const MovementTile({required this.movement, required this.hidden, super.key});

  final Movement movement;
  final bool hidden;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: CircleAvatar(
      child: Icon(categoryIcon(movement.category), size: 20),
    ),
    title: Text(
      movement.description,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(formatTime(movement.date)),
    trailing: hidden
        ? const Text('••••')
        : MoneyText(movement.amount, signed: true),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final MovementsState state;

  @override
  Widget build(BuildContext context) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(BiSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.loadMoreFailure != null) {
      return Padding(
        padding: const EdgeInsets.all(BiSpacing.md),
        child: StatusBanner(
          tone: BannerTone.error,
          message: accountsFailureMessage(state.loadMoreFailure!),
          action: 'Reintentar',
          onAction: context.read<MovementsCubit>().loadMore,
        ),
      );
    }
    if (!state.hasMore && state.isStale) {
      return const Padding(
        padding: EdgeInsets.all(BiSpacing.md),
        child: Center(child: Text('Conéctate para ver movimientos anteriores')),
      );
    }
    return const SizedBox.shrink();
  }
}

class _MovementSkeleton extends StatelessWidget {
  const _MovementSkeleton();

  @override
  Widget build(BuildContext context) => const ListTile(
    leading: CircleAvatar(),
    title: SkeletonBox(width: 160),
    subtitle: Padding(
      padding: EdgeInsets.only(top: 4),
      child: SkeletonBox(width: 60, height: 12),
    ),
    trailing: SkeletonBox(width: 64),
  );
}
