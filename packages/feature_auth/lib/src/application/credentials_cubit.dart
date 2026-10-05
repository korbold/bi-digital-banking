import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_auth/src/domain/auth_repository.dart';
import 'package:feature_auth/src/domain/auth_user.dart';
import 'package:feature_auth/src/presentation/failure_messages.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum FormStatus { idle, submitting, success, failure }

class CredentialsState extends Equatable {
  const CredentialsState({this.status = FormStatus.idle, this.errorMessage});

  final FormStatus status;
  final String? errorMessage;

  bool get isSubmitting => status == FormStatus.submitting;

  @override
  List<Object?> get props => [status, errorMessage];
}

/// Field validators shared by login and register forms (and their tests).
abstract final class CredentialValidators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu correo';
    if (!_email.hasMatch(v)) return 'Correo no válido';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Ingresa tu contraseña';
    if (value.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 3) return 'Ingresa tu nombre completo';
    return null;
  }
}

/// On success the SessionCubit picks up the new identity from the auth
/// stream; these cubits only own the form submission lifecycle.
class LoginCubit extends Cubit<CredentialsState> {
  LoginCubit(this._auth, {AnalyticsTracker analytics = const NoopAnalytics()})
    : _analytics = analytics,
      super(const CredentialsState());

  final AuthRepository _auth;
  final AnalyticsTracker _analytics;

  Future<void> submit({required String email, required String password}) async {
    if (state.isSubmitting) return;
    emit(const CredentialsState(status: FormStatus.submitting));
    final result = await _auth.signIn(email: email, password: password);
    _emitResult(result, 'login');
  }

  void _emitResult(Result<AuthUser> result, String method) {
    switch (result) {
      case Success():
        _analytics.track('login_success', {'method': method}).ignore();
        emit(const CredentialsState(status: FormStatus.success));
      case Failure(:final failure):
        _analytics.track('login_failure', {
          'reason': failure.runtimeType.toString(),
        }).ignore();
        emit(
          CredentialsState(
            status: FormStatus.failure,
            errorMessage: authFailureMessage(failure),
          ),
        );
    }
  }
}

class RegisterCubit extends Cubit<CredentialsState> {
  RegisterCubit(
    this._auth, {
    AnalyticsTracker analytics = const NoopAnalytics(),
  }) : _analytics = analytics,
       super(const CredentialsState());

  final AuthRepository _auth;
  final AnalyticsTracker _analytics;

  /// Only credentials here: the legal name is captured once, in onboarding,
  /// next to the cédula (KYC), instead of asking for it twice.
  Future<void> submit({required String email, required String password}) async {
    if (state.isSubmitting) return;
    emit(const CredentialsState(status: FormStatus.submitting));
    final result = await _auth.register(email: email, password: password);
    switch (result) {
      case Success():
        _analytics.track('sign_up').ignore();
        emit(const CredentialsState(status: FormStatus.success));
      case Failure(:final failure):
        emit(
          CredentialsState(
            status: FormStatus.failure,
            errorMessage: authFailureMessage(failure),
          ),
        );
    }
  }
}
