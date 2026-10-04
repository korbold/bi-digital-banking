import 'package:feature_accounts/feature_accounts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Account.fromJson parses the contract shape', () {
    final account = Account.fromJson(const {
      'id': 'acc_x',
      'type': 'checking',
      'alias': 'Cuenta Corriente',
      'number': '****4821',
      'currency': 'USD',
      'balance': 2450.75,
      'available': 2400,
    });
    expect(account.type, AccountType.checking);
    expect(account.available, 2400.0);
    expect(account.balance, 2450.75);
  });

  test('MovementsPage.fromJson parses items and cursor', () {
    final page = MovementsPage.fromJson(const {
      'items': [
        {
          'id': 'mov_1',
          'accountId': 'acc_x',
          'date': '2026-10-03T14:22:00Z',
          'description': 'Supermaxi',
          'amount': -54.2,
          'category': 'groceries',
          'balanceAfter': 2450.75,
          'transferId': null,
        },
      ],
      'nextCursor': 'c2',
    });
    expect(page.items.single.isDebit, isTrue);
    expect(
      page.items.single.date.isUtc,
      isFalse,
      reason: 'converted to local time for display',
    );
    expect(page.nextCursor, 'c2');
  });

  test('TransferReceipt.fromJson parses both legs', () {
    final receipt = TransferReceipt.fromJson(const {
      'transferId': 'trf_1',
      'from': {'id': 'acc_a', 'balance': 74.5},
      'to': {'id': 'acc_b', 'balance': 525.5},
      'createdAt': '2026-10-04T15:00:00Z',
    });
    expect(receipt.fromBalance, 74.5);
    expect(receipt.toAccountId, 'acc_b');
  });

  test(
    'TransferRequest body excludes the idempotency key (sent as header)',
    () {
      const request = TransferRequest(
        fromAccountId: 'a',
        toAccountId: 'b',
        amount: 10,
        idempotencyKey: 'k',
      );
      expect(request.toJson().containsKey('idempotencyKey'), isFalse);
    },
  );

  test('formatDayHeader', () {
    final now = DateTime(2026, 10, 4, 12);
    expect(formatDayHeader(DateTime(2026, 10, 4, 8), now: now), 'Hoy');
    expect(formatDayHeader(DateTime(2026, 10, 3, 23), now: now), 'Ayer');
    expect(
      formatDayHeader(DateTime(2026, 9, 28), now: now),
      '28 de septiembre',
    );
    expect(
      formatDayHeader(DateTime(2025, 12, 31), now: now),
      '31 de diciembre de 2025',
    );
  });
}
