import 'package:equatable/equatable.dart';

/// Banking customer profile returned by `GET /api/me`.
class Customer extends Equatable {
  const Customer({
    required this.uid,
    required this.name,
    required this.segment,
    this.email,
    this.interests = const [],
    this.onboardingCompleted = true,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    uid: json['uid'] as String,
    name: json['name'] as String? ?? '',
    email: json['email'] as String?,
    segment: json['segment'] as String? ?? 'retail',
    interests:
        ((json['preferences'] as Map<String, dynamic>?)?['interests']
                    as List<dynamic>? ??
                const [])
            .cast<String>(),
    onboardingCompleted: json['onboardingCompleted'] as bool? ?? true,
  );

  final String uid;
  final String name;
  final String? email;

  /// young | retail | premium | business — drives personalization server-side.
  final String segment;
  final List<String> interests;
  final bool onboardingCompleted;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  @override
  List<Object?> get props => [
    uid,
    name,
    email,
    segment,
    interests,
    onboardingCompleted,
  ];
}

/// Payload for `POST /api/onboarding`.
class OnboardingRequest extends Equatable {
  const OnboardingRequest({
    required this.name,
    required this.documentId,
    required this.ageRange,
    required this.monthlyIncome,
    required this.interests,
  });

  final String name;
  final String documentId;
  final String ageRange;
  final num monthlyIncome;
  final List<String> interests;

  Map<String, dynamic> toJson() => {
    'name': name,
    'documentId': documentId,
    'profile': {
      'ageRange': ageRange,
      'monthlyIncome': monthlyIncome,
      'interests': interests,
    },
  };

  @override
  List<Object?> get props => [
    name,
    documentId,
    ageRange,
    monthlyIncome,
    interests,
  ];
}
