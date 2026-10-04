import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_accounts/src/application/accounts_cubit.dart';
import 'package:feature_accounts/src/application/transfer_cubit.dart';
import 'package:feature_accounts/src/domain/accounts_repository.dart';
import 'package:feature_accounts/src/domain/models.dart';
import 'package:feature_accounts/src/presentation/formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Transfer to own accounts or to anyone by account number:
/// form -> review -> receipt.
/// Requires an [AccountsCubit] above it.
class TransferPage extends StatelessWidget {
  const TransferPage({
    required this.repository,
    required this.onClose,
    super.key,
    this.initialFromAccountId,
    this.analytics = const NoopAnalytics(),
    this.newIdempotencyKey,
  });

  final AccountsRepository repository;
  final VoidCallback onClose;
  final String? initialFromAccountId;
  final AnalyticsTracker analytics;

  /// Test seam; defaults to UUID v4.
  final String Function()? newIdempotencyKey;

  @override
  Widget build(BuildContext context) {
    final accounts = context.read<AccountsCubit>();
    return BlocProvider(
      create: (_) => TransferCubit(
        repository,
        accounts: () => accounts.state.accounts,
        initialFromAccountId:
            initialFromAccountId ?? _firstId(accounts.state.accounts),
        analytics: analytics,
        newIdempotencyKey: newIdempotencyKey,
      ),
      child: TransferView(onClose: onClose),
    );
  }

  static String? _firstId(List<Account> accounts) =>
      accounts.isEmpty ? null : accounts.first.id;
}

class TransferView extends StatelessWidget {
  const TransferView({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<TransferCubit, TransferState>(
        listenWhen: (a, b) =>
            a.status != b.status && b.status == TransferStatus.success,
        listener: (context, state) {
          final accounts = context.read<AccountsCubit>()
            ..applyReceipt(state.receipt!);
          unawaited(accounts.refresh());
        },
        builder: (context, state) {
          final accounts = context.select((AccountsCubit c) => c.state);
          final Widget body = switch (state.status) {
            TransferStatus.success => _Receipt(
              state: state,
              accounts: accounts,
              onClose: onClose,
            ),
            TransferStatus.reviewing || TransferStatus.submitting => _Review(
              state: state,
              accounts: accounts,
            ),
            TransferStatus.editing ||
            TransferStatus.failure => _Form(state: state, accounts: accounts),
          };
          return Scaffold(
            appBar: AppBar(
              title: const Text('Transferir'),
              leading: state.status == TransferStatus.success
                  ? const SizedBox.shrink()
                  : CloseButton(onPressed: onClose),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BiSpacing.md),
                child: body,
              ),
            ),
          );
        },
      );
}

class _Form extends StatelessWidget {
  const _Form({required this.state, required this.accounts});

  final TransferState state;
  final AccountsState accounts;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TransferCubit>();
    final list = accounts.accounts;
    if (list.isEmpty) {
      return ErrorView(
        message: accounts.failure == null
            ? 'Cargando tus cuentas…'
            : accountsFailureMessage(accounts.failure!),
        onRetry: context.read<AccountsCubit>().refresh,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.status == TransferStatus.failure) ...[
          StatusBanner(
            key: const Key('transfer_error'),
            tone: BannerTone.error,
            message: state.failureMessage!,
            action: state.canRetry ? 'Reintentar' : null,
            onAction: state.canRetry ? cubit.confirm : null,
          ),
          const SizedBox(height: BiSpacing.md),
        ],
        DropdownButtonFormField<String>(
          key: const Key('transfer_from'),
          initialValue: state.fromAccountId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Desde',
            errorText: state.errors['from'],
          ),
          items: [
            for (final a in list)
              DropdownMenuItem(value: a.id, child: Text(_label(a))),
          ],
          onChanged: (v) => v == null ? null : cubit.fromChanged(v),
        ),
        const SizedBox(height: BiSpacing.md),
        SegmentedButton<DestinationMode>(
          key: const Key('transfer_mode'),
          segments: const [
            ButtonSegment(
              value: DestinationMode.own,
              label: Text('Mis cuentas'),
              icon: Icon(Icons.account_balance_wallet_outlined),
            ),
            ButtonSegment(
              value: DestinationMode.thirdParty,
              label: Text('Otra persona'),
              icon: Icon(Icons.person_outline),
            ),
          ],
          selected: {state.mode},
          onSelectionChanged: (s) => cubit.modeChanged(s.first),
        ),
        const SizedBox(height: BiSpacing.md),
        if (state.mode == DestinationMode.own)
          DropdownButtonFormField<String>(
            key: const Key('transfer_to'),
            initialValue: state.toAccountId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Hacia',
              errorText: state.errors['to'],
            ),
            items: [
              for (final a in list.where((a) => a.id != state.fromAccountId))
                DropdownMenuItem(value: a.id, child: Text(_label(a))),
            ],
            onChanged: (v) => v == null ? null : cubit.toChanged(v),
          )
        else
          _ThirdPartyDestination(state: state),
        const SizedBox(height: BiSpacing.md),
        TextFormField(
          key: const Key('transfer_amount'),
          initialValue: state.amount,
          onChanged: cubit.amountChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: 'Monto (USD)',
            prefixText: r'$ ',
            errorText: state.errors['amount'],
            helperText: _availableHelper(list, state.fromAccountId),
          ),
        ),
        const SizedBox(height: BiSpacing.md),
        TextFormField(
          key: const Key('transfer_description'),
          initialValue: state.description,
          onChanged: cubit.descriptionChanged,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Descripción (opcional)',
          ),
        ),
        const SizedBox(height: BiSpacing.md),
        FilledButton(
          key: const Key('transfer_continue'),
          onPressed: cubit.review,
          child: const Text('Continuar'),
        ),
      ],
    );
  }

  static String? _availableHelper(List<Account> list, String? fromId) {
    for (final a in list) {
      if (a.id == fromId) return 'Disponible: ${formatMoney(a.available)}';
    }
    return null;
  }
}

String _label(Account a) => '${a.alias} ${a.number}';

class _Review extends StatelessWidget {
  const _Review({required this.state, required this.accounts});

  final TransferState state;
  final AccountsState accounts;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TransferCubit>();
    final submitting = state.status == TransferStatus.submitting;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Confirma tu transferencia',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: BiSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(BiSpacing.md),
            child: Column(
              children: [
                MoneyText(
                  state.parsedAmount ?? 0,
                  style: theme.textTheme.displaySmall,
                ),
                const Divider(height: BiSpacing.xl),
                _Row('Desde', _accountLabel(accounts, state.fromAccountId)),
                _Row(
                  'Hacia',
                  state.mode == DestinationMode.thirdParty
                      ? _beneficiaryLabel(state.beneficiary!)
                      : _accountLabel(accounts, state.toAccountId),
                ),
                if (state.description.trim().isNotEmpty)
                  _Row('Descripción', state.description.trim()),
                const _Row('Costo', r'$0.00'),
              ],
            ),
          ),
        ),
        const SizedBox(height: BiSpacing.lg),
        FilledButton(
          key: const Key('transfer_confirm'),
          onPressed: submitting ? null : cubit.confirm,
          child: submitting
              ? Semantics(
                  label: 'Enviando transferencia',
                  child: const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : const Text('Confirmar'),
        ),
        TextButton(
          onPressed: submitting ? null : cubit.backToEdit,
          child: const Text('Editar'),
        ),
      ],
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({
    required this.state,
    required this.accounts,
    required this.onClose,
  });

  final TransferState state;
  final AccountsState accounts;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final receipt = state.receipt!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: BiSpacing.lg),
        const ExcludeSemantics(
          child: Icon(Icons.check_circle, size: 72, color: BiColors.positive),
        ),
        const SizedBox(height: BiSpacing.md),
        Semantics(
          liveRegion: true,
          header: true,
          child: Text(
            '¡Transferencia exitosa!',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        if (receipt.isThirdParty) ...[
          const SizedBox(height: BiSpacing.sm),
          Text(
            'Enviaste ${formatMoney(state.parsedAmount ?? 0)} a '
            '${receipt.toHolderName ?? 'el destinatario'} '
            '(${receipt.toMaskedNumber ?? ''})',
            key: const Key('transfer_receipt_summary'),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: BiSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(BiSpacing.md),
            child: Column(
              children: [
                MoneyText(
                  state.parsedAmount ?? 0,
                  style: theme.textTheme.headlineMedium,
                ),
                const Divider(height: BiSpacing.xl),
                _Row('Desde', _accountLabel(accounts, receipt.fromAccountId)),
                _Row('Nuevo saldo', formatMoney(receipt.fromBalance)),
                if (receipt.isThirdParty)
                  _Row(
                    'Hacia',
                    '${receipt.toHolderName ?? '—'} (${receipt.toMaskedNumber ?? ''})',
                  )
                else ...[
                  _Row('Hacia', _accountLabel(accounts, receipt.toAccountId)),
                  if (receipt.toBalance != null)
                    _Row('Nuevo saldo', formatMoney(receipt.toBalance!)),
                ],
                _Row('Comprobante', receipt.transferId),
                _Row(
                  'Fecha',
                  '${formatDayHeader(receipt.createdAt)} ${formatTime(receipt.createdAt)}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: BiSpacing.lg),
        FilledButton(
          key: const Key('transfer_done'),
          onPressed: onClose,
          child: const Text('Listo'),
        ),
      ],
    );
  }
}

String _beneficiaryLabel(BeneficiaryPreview b) =>
    '${b.holderName} · ${b.type.label} ${b.maskedNumber}';

/// Account-number input, "Verificar" and the beneficiary confirmation card.
class _ThirdPartyDestination extends StatelessWidget {
  const _ThirdPartyDestination({required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TransferCubit>();
    final loading = state.lookupStatus == LookupStatus.loading;
    final preview = state.beneficiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('transfer_account_number'),
                initialValue: state.accountNumber,
                onChanged: cubit.accountNumberChanged,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: 'Número de cuenta del destinatario',
                  helperText: '10 dígitos',
                  errorText:
                      state.errors['to'] ??
                      (state.lookupStatus == LookupStatus.failed
                          ? state.lookupError
                          : null),
                ),
              ),
            ),
            const SizedBox(width: BiSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: BiSpacing.xs),
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  key: const Key('transfer_verify'),
                  onPressed: loading ? null : cubit.verifyBeneficiary,
                  child: loading
                      ? Semantics(
                          label: 'Verificando cuenta',
                          child: const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Text('Verificar'),
                ),
              ),
            ),
          ],
        ),
        if (preview != null) ...[
          const SizedBox(height: BiSpacing.sm),
          Semantics(
            key: const Key('transfer_beneficiary'),
            container: true,
            liveRegion: true,
            label:
                'Destinatario verificado: ${preview.holderName}, '
                'cuenta de ${preview.type.label} terminada en '
                '${preview.maskedNumber.replaceAll('*', '')}',
            excludeSemantics: true,
            child: Card(
              child: ListTile(
                leading: const Icon(
                  Icons.verified_user_outlined,
                  color: BiColors.positive,
                ),
                title: Text('Titular: ${preview.holderName}'),
                subtitle: Text(
                  preview.isOwn
                      ? 'Es una de tus cuentas · '
                            '${preview.type.label} ${preview.maskedNumber}'
                      : '${preview.type.label} ${preview.maskedNumber}',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _accountLabel(AccountsState accounts, String? id) {
  final a = id == null ? null : accounts.byId(id);
  return a == null ? '—' : _label(a);
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: BiSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Flexible(flex: 2, child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}
