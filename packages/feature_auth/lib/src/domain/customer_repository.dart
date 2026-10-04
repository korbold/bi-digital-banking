import 'package:core/core.dart';
import 'package:feature_auth/src/domain/customer.dart';

abstract interface class CustomerRepository {
  /// `Success(null)` means the identity exists but the customer has not
  /// completed onboarding yet (BFF answers 404 `onboarding_required`).
  Future<Result<Customer?>> getMe();

  Future<Result<Customer>> completeOnboarding(OnboardingRequest request);
}
