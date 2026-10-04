import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:feature_auth/src/domain/customer.dart';
import 'package:feature_auth/src/domain/customer_repository.dart';

class ApiCustomerRepository implements CustomerRepository {
  ApiCustomerRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<Customer?>> getMe() async {
    final result = await _api.get<Customer>(
      '/api/me',
      decode: (json) => Customer.fromJson(json! as Map<String, dynamic>),
    );
    return switch (result) {
      Success(:final value) => Result.success(value.data),
      Failure(failure: ValidationFailure(code: 'onboarding_required')) =>
        const Result.success(null),
      Failure(:final failure) => Result.failure(failure),
    };
  }

  @override
  Future<Result<Customer>> completeOnboarding(
    OnboardingRequest request,
  ) => _api.post<Customer>(
    '/api/onboarding',
    body: request.toJson(),
    // Onboarding is idempotent per uid server-side, so a stable key is safe.
    idempotencyKey: 'onboarding-${request.documentId}',
    decode: (json) => Customer.fromJson(json! as Map<String, dynamic>),
  );

  @override
  Future<Result<Customer>> updateInterests(List<String> interests) =>
      _api.patch<Customer>(
        '/api/me/preferences',
        body: {'interests': interests},
        decode: (json) => Customer.fromJson(json! as Map<String, dynamic>),
      );
}
