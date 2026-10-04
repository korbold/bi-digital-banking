import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_auth/src/domain/cedula_validator.dart';
import 'package:feature_auth/src/domain/customer.dart';
import 'package:feature_auth/src/domain/customer_repository.dart';
import 'package:feature_auth/src/presentation/failure_messages.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum OnboardingStep { personal, profile }

enum OnboardingStatus { editing, submitting, success, failure }

const ageRanges = ['18-25', '26-40', '41-60', '60+'];

/// id -> Spanish label. Ids are the contract with the BFF personalization.
const interestOptions = {
  'travel': 'Viajes',
  'tech': 'Tecnología',
  'savings': 'Ahorro',
  'shopping': 'Compras',
  'food': 'Gastronomía',
  'health': 'Salud',
  'education': 'Educación',
  'investing': 'Inversiones',
};

class OnboardingState extends Equatable {
  const OnboardingState({
    this.step = OnboardingStep.personal,
    this.name = '',
    this.documentId = '',
    this.ageRange,
    this.monthlyIncome = '',
    this.interests = const {},
    this.errors = const {},
    this.status = OnboardingStatus.editing,
    this.failureMessage,
    this.customer,
  });

  final OnboardingStep step;
  final String name;
  final String documentId;
  final String? ageRange;
  final String monthlyIncome;
  final Set<String> interests;

  /// field name -> error message, only for fields the user tried to submit.
  final Map<String, String> errors;
  final OnboardingStatus status;
  final String? failureMessage;
  final Customer? customer;

  OnboardingState copyWith({
    OnboardingStep? step,
    String? name,
    String? documentId,
    String? ageRange,
    String? monthlyIncome,
    Set<String>? interests,
    Map<String, String>? errors,
    OnboardingStatus? status,
    String? failureMessage,
    Customer? customer,
  }) => OnboardingState(
    step: step ?? this.step,
    name: name ?? this.name,
    documentId: documentId ?? this.documentId,
    ageRange: ageRange ?? this.ageRange,
    monthlyIncome: monthlyIncome ?? this.monthlyIncome,
    interests: interests ?? this.interests,
    errors: errors ?? this.errors,
    status: status ?? this.status,
    failureMessage: failureMessage,
    customer: customer ?? this.customer,
  );

  @override
  List<Object?> get props => [
    step,
    name,
    documentId,
    ageRange,
    monthlyIncome,
    interests,
    errors,
    status,
    failureMessage,
    customer,
  ];
}

class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit(
    this._customers, {
    String initialName = '',
    AnalyticsTracker analytics = const NoopAnalytics(),
  }) : _analytics = analytics,
       super(OnboardingState(name: initialName));

  final CustomerRepository _customers;
  final AnalyticsTracker _analytics;

  void nameChanged(String v) =>
      emit(state.copyWith(name: v, errors: _without('name')));
  void documentChanged(String v) =>
      emit(state.copyWith(documentId: v, errors: _without('documentId')));
  void ageRangeChanged(String v) =>
      emit(state.copyWith(ageRange: v, errors: _without('ageRange')));
  void incomeChanged(String v) =>
      emit(state.copyWith(monthlyIncome: v, errors: _without('monthlyIncome')));

  void toggleInterest(String id) {
    final next = {...state.interests};
    if (!next.remove(id)) next.add(id);
    emit(state.copyWith(interests: next, errors: _without('interests')));
  }

  /// Validates step 1 and advances. Returns whether it advanced.
  bool next() {
    final errors = <String, String>{};
    if (state.name.trim().split(RegExp(r'\s+')).length < 2) {
      errors['name'] = 'Ingresa nombre y apellido';
    }
    if (!isValidCedula(state.documentId)) {
      errors['documentId'] = 'Cédula no válida';
    }
    if (errors.isNotEmpty) {
      emit(state.copyWith(errors: errors));
      return false;
    }
    _analytics.track('onboarding_step', {'step': 'profile'}).ignore();
    emit(state.copyWith(step: OnboardingStep.profile, errors: const {}));
    return true;
  }

  void back() => emit(state.copyWith(step: OnboardingStep.personal));

  Future<void> submit() async {
    if (state.status == OnboardingStatus.submitting) return;
    final errors = <String, String>{};
    if (state.ageRange == null) {
      errors['ageRange'] = 'Selecciona tu rango de edad';
    }
    final income = num.tryParse(state.monthlyIncome.replaceAll(',', '.'));
    if (income == null || income < 0) {
      errors['monthlyIncome'] = 'Ingresa un monto válido';
    }
    if (state.interests.isEmpty) {
      errors['interests'] = 'Elige al menos un interés';
    }
    if (errors.isNotEmpty) {
      emit(state.copyWith(errors: errors));
      return;
    }

    emit(state.copyWith(status: OnboardingStatus.submitting));
    final result = await _customers.completeOnboarding(
      OnboardingRequest(
        name: state.name.trim(),
        documentId: state.documentId.trim(),
        ageRange: state.ageRange!,
        monthlyIncome: income!,
        interests: state.interests.toList()..sort(),
      ),
    );
    switch (result) {
      case Success(:final value):
        emit(state.copyWith(status: OnboardingStatus.success, customer: value));
      case Failure(:final failure):
        emit(
          state.copyWith(
            status: OnboardingStatus.failure,
            failureMessage: authFailureMessage(failure),
          ),
        );
    }
  }

  Map<String, String> _without(String key) => {...state.errors}..remove(key);
}
