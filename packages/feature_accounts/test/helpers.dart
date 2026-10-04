import 'package:core/core.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:mocktail/mocktail.dart';

class MockAccountsRepository extends Mock implements AccountsRepository {}

const savings = Account(
  id: 'acc_a',
  type: AccountType.savings,
  alias: 'Ahorros',
  number: '****4821',
  balance: 100,
  available: 100,
);
const checking = Account(
  id: 'acc_b',
  type: AccountType.checking,
  alias: 'Corriente',
  number: '****1234',
  balance: 500,
  available: 500,
);

final fetchedAt = DateTime(2026, 10, 4, 10, 42);

Fetched<T> network<T>(T data) =>
    Fetched(data, source: DataSource.network, fetchedAt: fetchedAt);
Fetched<T> cached<T>(T data) =>
    Fetched(data, source: DataSource.cache, fetchedAt: fetchedAt);

Movement movement(String id, double amount, {DateTime? date}) => Movement(
  id: id,
  accountId: 'acc_a',
  date: date ?? DateTime(2026, 10, 3, 14, 22),
  description: 'Mov $id',
  amount: amount,
  category: 'groceries',
  balanceAfter: 100,
);
