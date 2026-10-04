import 'package:equatable/equatable.dart';

enum AccountType {
  savings('Ahorros'),
  checking('Corriente')
  ;

  const AccountType(this.label);

  final String label;

  static AccountType parse(String? raw) => AccountType.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => AccountType.savings,
  );
}

double _toDouble(Object? v) => (v as num?)?.toDouble() ?? 0;

class Account extends Equatable {
  const Account({
    required this.id,
    required this.type,
    required this.alias,
    required this.number,
    required this.balance,
    required this.available,
    this.currency = 'USD',
    this.accountNumber = '',
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    type: AccountType.parse(json['type'] as String?),
    alias: json['alias'] as String? ?? '',
    number: json['number'] as String? ?? '',
    accountNumber: json['accountNumber'] as String? ?? '',
    currency: json['currency'] as String? ?? 'USD',
    balance: _toDouble(json['balance']),
    available: _toDouble(json['available'] ?? json['balance']),
  );

  final String id;
  final AccountType type;
  final String alias;

  /// Masked number (****1234) for lists and receipts.
  final String number;

  /// Full 10-digit number, visible only to its owner so they can share it to
  /// receive transfers. Empty for payloads cached before v1.1.
  final String accountNumber;
  final String currency;
  final double balance;
  final double available;

  Account withBalance(double value) => Account(
    id: id,
    type: type,
    alias: alias,
    number: number,
    accountNumber: accountNumber,
    currency: currency,
    balance: value,
    available: value,
  );

  @override
  List<Object?> get props => [
    id,
    type,
    alias,
    number,
    accountNumber,
    currency,
    balance,
    available,
  ];
}

class Movement extends Equatable {
  const Movement({
    required this.id,
    required this.accountId,
    required this.date,
    required this.description,
    required this.amount,
    required this.category,
    required this.balanceAfter,
    this.transferId,
  });

  factory Movement.fromJson(Map<String, dynamic> json) => Movement(
    id: json['id'] as String,
    accountId: json['accountId'] as String? ?? '',
    date: DateTime.parse(json['date'] as String).toLocal(),
    description: json['description'] as String? ?? '',
    amount: _toDouble(json['amount']),
    category: json['category'] as String? ?? 'other',
    balanceAfter: _toDouble(json['balanceAfter']),
    transferId: json['transferId'] as String?,
  );

  final String id;
  final String accountId;
  final DateTime date;
  final String description;

  /// Positive = credit, negative = debit.
  final double amount;
  final String category;
  final double balanceAfter;
  final String? transferId;

  bool get isDebit => amount < 0;

  @override
  List<Object?> get props => [
    id,
    accountId,
    date,
    description,
    amount,
    category,
    balanceAfter,
    transferId,
  ];
}

class MovementsPage extends Equatable {
  const MovementsPage({required this.items, this.nextCursor});

  factory MovementsPage.fromJson(Map<String, dynamic> json) => MovementsPage(
    items: (json['items'] as List<dynamic>? ?? const [])
        .map((e) => Movement.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextCursor: json['nextCursor'] as String?,
  );

  final List<Movement> items;
  final String? nextCursor;

  @override
  List<Object?> get props => [items, nextCursor];
}

class TransferRequest extends Equatable {
  /// Exactly one of [toAccountId] (own account) or [toAccountNumber]
  /// (any account, including third parties) must be provided.
  const TransferRequest({
    required this.fromAccountId,
    required this.amount,
    required this.idempotencyKey,
    this.toAccountId,
    this.toAccountNumber,
    this.description = '',
  }) : assert(
         (toAccountId == null) != (toAccountNumber == null),
         'Provide exactly one destination',
       );

  final String fromAccountId;
  final String? toAccountId;
  final String? toAccountNumber;
  final double amount;
  final String description;

  /// One key per user intent, reused on every retry of that intent so the
  /// BFF can deduplicate and the transfer is applied at most once.
  final String idempotencyKey;

  Map<String, dynamic> toJson() => {
    'fromAccountId': fromAccountId,
    'toAccountId': ?toAccountId,
    'toAccountNumber': ?toAccountNumber,
    'amount': amount,
    'description': description,
  };

  @override
  List<Object?> get props => [
    fromAccountId,
    toAccountId,
    toAccountNumber,
    amount,
    description,
    idempotencyKey,
  ];
}

class TransferReceipt extends Equatable {
  const TransferReceipt({
    required this.transferId,
    required this.fromAccountId,
    required this.fromBalance,
    required this.createdAt,
    this.toAccountId,
    this.toBalance,
    this.toHolderName,
    this.toMaskedNumber,
    this.isThirdParty = false,
  });

  factory TransferReceipt.fromJson(Map<String, dynamic> json) {
    final from = json['from'] as Map<String, dynamic>;
    final to = json['to'] as Map<String, dynamic>;
    final thirdParty = json['kind'] == 'third_party';
    return TransferReceipt(
      transferId: json['transferId'] as String,
      fromAccountId: from['id'] as String,
      fromBalance: _toDouble(from['balance']),
      // Third-party receipts never expose the recipient's balance.
      toAccountId: thirdParty ? null : to['id'] as String?,
      toBalance: thirdParty || to['balance'] == null
          ? null
          : _toDouble(to['balance']),
      toHolderName: to['holderName'] as String?,
      toMaskedNumber: to['accountNumber'] as String?,
      isThirdParty: thirdParty,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  final String transferId;
  final String fromAccountId;
  final double fromBalance;
  final String? toAccountId;
  final double? toBalance;
  final String? toHolderName;
  final String? toMaskedNumber;
  final bool isThirdParty;
  final DateTime createdAt;

  @override
  List<Object?> get props => [
    transferId,
    fromAccountId,
    fromBalance,
    toAccountId,
    toBalance,
    toHolderName,
    toMaskedNumber,
    isThirdParty,
    createdAt,
  ];
}

/// Result of GET /api/beneficiaries/lookup: who will receive the money,
/// shown before confirming. Never includes balances or full names.
class BeneficiaryPreview extends Equatable {
  const BeneficiaryPreview({
    required this.accountNumber,
    required this.maskedNumber,
    required this.holderName,
    required this.type,
    this.isOwn = false,
    this.accountId,
  });

  factory BeneficiaryPreview.fromJson(Map<String, dynamic> json) =>
      BeneficiaryPreview(
        accountNumber: json['accountNumber'] as String? ?? '',
        maskedNumber: json['maskedNumber'] as String? ?? '',
        holderName: json['holderName'] as String? ?? '',
        type: AccountType.parse(json['type'] as String?),
        isOwn: json['isOwn'] as bool? ?? false,
        accountId: json['accountId'] as String?,
      );

  final String accountNumber;
  final String maskedNumber;
  final String holderName;
  final AccountType type;
  final bool isOwn;
  final String? accountId;

  @override
  List<Object?> get props => [
    accountNumber,
    maskedNumber,
    holderName,
    type,
    isOwn,
    accountId,
  ];
}
