import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_accounts/src/domain/accounts_repository.dart';
import 'package:feature_accounts/src/domain/models.dart';
import 'package:feature_accounts/src/presentation/formatting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

enum TransferStatus { editing, reviewing, submitting, success, failure }

/// Own accounts (pick from a list) or any account by its 10-digit number.
enum DestinationMode { own, thirdParty }

enum LookupStatus { idle, loading, found, failed }

class TransferState extends Equatable {
  const TransferState({
    this.fromAccountId,
    this.toAccountId,
    this.amount = '',
    this.description = '',
    this.errors = const {},
    this.status = TransferStatus.editing,
    this.failure,
    this.receipt,
    this.mode = DestinationMode.own,
    this.accountNumber = '',
    this.beneficiary,
    this.lookupStatus = LookupStatus.idle,
    this.lookupError,
  });

  final DestinationMode mode;
  final String accountNumber;
  final BeneficiaryPreview? beneficiary;
  final LookupStatus lookupStatus;
  final String? lookupError;
  final String? fromAccountId;
  final String? toAccountId;
  final String amount;
  final String description;
  final Map<String, String> errors;
  final TransferStatus status;
  final AppFailure? failure;
  final TransferReceipt? receipt;

  double? get parsedAmount => double.tryParse(amount.replaceAll(',', '.'));

  String? get failureMessage =>
      failure == null ? null : transferFailureMessage(failure!);

  /// Whether the last failure can be retried safely with the same key.
  bool get canRetry =>
      status == TransferStatus.failure && (failure?.isRetryable ?? false);

  TransferState copyWith({
    String? fromAccountId,
    String? toAccountId,
    String? amount,
    String? description,
    Map<String, String>? errors,
    TransferStatus? status,
    AppFailure? failure,
    TransferReceipt? receipt,
    DestinationMode? mode,
    String? accountNumber,
    BeneficiaryPreview? beneficiary,
    bool clearBeneficiary = false,
    LookupStatus? lookupStatus,
    String? lookupError,
  }) => TransferState(
    mode: mode ?? this.mode,
    accountNumber: accountNumber ?? this.accountNumber,
    beneficiary: clearBeneficiary ? null : beneficiary ?? this.beneficiary,
    lookupStatus: lookupStatus ?? this.lookupStatus,
    lookupError: lookupError,
    fromAccountId: fromAccountId ?? this.fromAccountId,
    toAccountId: toAccountId ?? this.toAccountId,
    amount: amount ?? this.amount,
    description: description ?? this.description,
    errors: errors ?? this.errors,
    status: status ?? this.status,
    failure: failure,
    receipt: receipt ?? this.receipt,
  );

  @override
  List<Object?> get props => [
    mode,
    accountNumber,
    beneficiary,
    lookupStatus,
    lookupError,
    fromAccountId,
    toAccountId,
    amount,
    description,
    errors,
    status,
    failure,
    receipt,
  ];
}

/// Transfer to an own account or, by account number, to anyone.
///
/// Third-party flow: the number is verified first (lookup shows the masked
/// holder name) and review is blocked until a preview matches the number
/// typed. Editing the number discards the preview and the idempotency key.
///
/// Idempotency: a key is minted when the user confirms a given intent
/// (from, to, amount, description) and reused for every retry of that same
/// intent. Editing any field mints a new one. So a timeout followed by a
/// retry can never move money twice.
class TransferCubit extends Cubit<TransferState> {
  TransferCubit(
    this._repository, {
    required List<Account> Function() accounts,
    String? initialFromAccountId,
    String Function()? newIdempotencyKey,
    AnalyticsTracker analytics = const NoopAnalytics(),
  }) : _accounts = accounts,
       _newKey = newIdempotencyKey ?? const Uuid().v4,
       _analytics = analytics,
       super(TransferState(fromAccountId: initialFromAccountId));

  final AccountsRepository _repository;
  final List<Account> Function() _accounts;
  final String Function() _newKey;
  final AnalyticsTracker _analytics;
  String? _idempotencyKey;

  void fromChanged(String id) =>
      _edit(state.copyWith(fromAccountId: id, errors: _without('from')));
  void toChanged(String id) =>
      _edit(state.copyWith(toAccountId: id, errors: _without('to')));
  void amountChanged(String v) =>
      _edit(state.copyWith(amount: v, errors: _without('amount')));
  void descriptionChanged(String v) => _edit(state.copyWith(description: v));

  void modeChanged(DestinationMode mode) => _edit(
    state.copyWith(mode: mode, errors: _without('to')),
  );

  void accountNumberChanged(String v) => _edit(
    state.copyWith(
      accountNumber: v,
      clearBeneficiary: true,
      lookupStatus: LookupStatus.idle,
      errors: _without('to'),
    ),
  );

  static final _accountNumberPattern = RegExp(r'^\d{10}$');

  /// Verifies the typed number and shows who will receive the money.
  Future<void> verifyBeneficiary() async {
    final number = state.accountNumber.trim();
    if (!_accountNumberPattern.hasMatch(number)) {
      emit(
        state.copyWith(
          lookupStatus: LookupStatus.failed,
          lookupError: 'El número de cuenta tiene 10 dígitos',
        ),
      );
      return;
    }
    final from = _fromAccount();
    if (from != null && from.accountNumber == number) {
      emit(
        state.copyWith(
          lookupStatus: LookupStatus.failed,
          lookupError: 'Es la misma cuenta de origen',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        lookupStatus: LookupStatus.loading,
        clearBeneficiary: true,
      ),
    );
    final result = await _repository.lookupBeneficiary(number);
    if (isClosed || state.accountNumber.trim() != number) return;
    switch (result) {
      case Success(:final value):
        emit(
          state.copyWith(
            beneficiary: value,
            lookupStatus: LookupStatus.found,
            errors: _without('to'),
          ),
        );
      case Failure(:final failure):
        emit(
          state.copyWith(
            lookupStatus: LookupStatus.failed,
            lookupError: transferFailureMessage(failure),
          ),
        );
    }
  }

  Account? _fromAccount() {
    for (final a in _accounts()) {
      if (a.id == state.fromAccountId) return a;
    }
    return null;
  }

  void _edit(TransferState next) {
    _idempotencyKey = null;
    emit(next.copyWith(status: TransferStatus.editing));
  }

  /// Validates and moves to the confirmation step.
  bool review() {
    final errors = _validate();
    if (errors.isNotEmpty) {
      emit(state.copyWith(errors: errors, status: TransferStatus.editing));
      return false;
    }
    emit(state.copyWith(status: TransferStatus.reviewing, errors: const {}));
    return true;
  }

  void backToEdit() => emit(state.copyWith(status: TransferStatus.editing));

  Future<void> confirm() async {
    if (state.status == TransferStatus.submitting) return;
    if (_validate().isNotEmpty) return;
    final key = _idempotencyKey ??= _newKey();
    emit(state.copyWith(status: TransferStatus.submitting));

    final result = await _repository.transfer(
      TransferRequest(
        fromAccountId: state.fromAccountId!,
        toAccountId: state.mode == DestinationMode.own
            ? state.toAccountId
            : null,
        toAccountNumber: state.mode == DestinationMode.thirdParty
            ? state.beneficiary!.accountNumber
            : null,
        amount: state.parsedAmount!,
        description: state.description.trim(),
        idempotencyKey: key,
      ),
    );
    if (isClosed) return;
    switch (result) {
      case Success(:final value):
        _idempotencyKey = null;
        _analytics.track('transfer_success', {
          'amount_bucket': _bucket(state.parsedAmount!),
          'destination': state.mode.name,
        }).ignore();
        emit(state.copyWith(status: TransferStatus.success, receipt: value));
      case Failure(:final failure):
        _analytics.track('transfer_failure', {
          'reason': failure.runtimeType.toString(),
        }).ignore();
        // Business rejections invalidate this intent; transport errors keep
        // the key so "Reintentar" is safe.
        if (!failure.isRetryable) _idempotencyKey = null;
        emit(state.copyWith(status: TransferStatus.failure, failure: failure));
    }
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    final from = _fromAccount();
    if (from == null) errors['from'] = 'Selecciona la cuenta de origen';
    if (state.mode == DestinationMode.thirdParty) {
      final preview = state.beneficiary;
      if (preview == null ||
          preview.accountNumber != state.accountNumber.trim()) {
        errors['to'] = 'Verifica el número de cuenta del destinatario';
      } else if (from != null && preview.accountId == from.id) {
        errors['to'] = 'Es la misma cuenta de origen';
      }
    } else if (state.toAccountId == null) {
      errors['to'] = 'Selecciona la cuenta de destino';
    } else if (state.toAccountId == state.fromAccountId) {
      errors['to'] = 'Elige una cuenta distinta a la de origen';
    }
    final amount = state.parsedAmount;
    if (amount == null || amount <= 0) {
      errors['amount'] = 'Ingresa un monto mayor a 0';
    } else if (!RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(state.amount.trim())) {
      errors['amount'] = 'Máximo 2 decimales';
    } else if (from != null && amount > from.available) {
      errors['amount'] = 'Supera tu saldo disponible';
    }
    return errors;
  }

  Map<String, String> _without(String key) => {...state.errors}..remove(key);

  static String _bucket(double amount) => switch (amount) {
    < 50 => '<50',
    < 500 => '50-500',
    _ => '500+',
  };
}
