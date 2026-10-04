import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:feature_accounts/src/domain/accounts_repository.dart';
import 'package:feature_accounts/src/domain/models.dart';

class ApiAccountsRepository implements AccountsRepository {
  ApiAccountsRepository(this._api);

  final ApiClient _api;

  static List<Account> _decodeAccounts(Object? json) =>
      ((json! as Map<String, dynamic>)['items'] as List<dynamic>)
          .map((e) => Account.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Stream<Result<Fetched<List<Account>>>> watchAccounts() =>
      _api.watch('/api/accounts', decode: _decodeAccounts);

  @override
  Future<Result<Fetched<MovementsPage>>> getMovements(
    String accountId, {
    String? cursor,
    int limit = 20,
  }) => _api.get(
    '/api/accounts/$accountId/movements',
    query: {'limit': limit, 'cursor': ?cursor},
    decode: (json) => MovementsPage.fromJson(json! as Map<String, dynamic>),
  );

  @override
  Future<Result<TransferReceipt>> transfer(TransferRequest request) =>
      _api.post(
        '/api/transfers',
        body: request.toJson(),
        idempotencyKey: request.idempotencyKey,
        decode: (json) =>
            TransferReceipt.fromJson(json! as Map<String, dynamic>),
      );
}
