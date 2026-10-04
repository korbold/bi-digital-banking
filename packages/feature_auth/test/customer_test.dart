import 'package:core/core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Customer.fromJson reads profile and interests', () {
    final customer = Customer.fromJson(const {
      'uid': 'u1',
      'name': 'Ana María López',
      'email': 'ana@test.com',
      'segment': 'young',
      'preferences': {
        'interests': ['travel', 'tech'],
      },
      'onboardingCompleted': true,
    });
    expect(customer.firstName, 'Ana');
    expect(customer.segment, 'young');
    expect(customer.interests, ['travel', 'tech']);
  });

  test('OnboardingRequest serializes the contract shape', () {
    const request = OnboardingRequest(
      name: 'Ana López',
      documentId: '1710034065',
      ageRange: '18-25',
      monthlyIncome: 1200,
      interests: ['travel'],
    );
    expect(request.toJson(), {
      'name': 'Ana López',
      'documentId': '1710034065',
      'profile': {
        'ageRange': '18-25',
        'monthlyIncome': 1200,
        'interests': ['travel'],
      },
    });
  });

  test('Firebase error codes map to Spanish messages', () {
    expect(
      (mapFirebaseAuthCode('wrong-password') as ValidationFailure).message,
      'Correo o contraseña incorrectos.',
    );
    expect(
      mapFirebaseAuthCode('network-request-failed'),
      isA<OfflineFailure>(),
    );
  });
}
