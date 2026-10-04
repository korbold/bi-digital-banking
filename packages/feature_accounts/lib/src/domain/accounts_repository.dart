import 'package:core/core.dart';
import 'package:feature_accounts/src/domain/models.dart';

abstract interface class AccountsRepository {
  /// Stale-while-revalidate: cached accounts first (if any), then fresh ones
  /// or the failure that prevented the refresh.
  Stream<Result<Fetched<List<Account>>>> watchAccounts();

  /// Network-first page of movements, falling back to the cached page.
  Future<Result<Fetched<MovementsPage>>> getMovements(
    String accountId, {
    String? cursor,
    int limit = 20,
  });

  Future<Result<TransferReceipt>> transfer(TransferRequest request);
}
