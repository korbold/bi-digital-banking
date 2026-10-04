import 'dart:async';

import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_auth/src/domain/auth_repository.dart';
import 'package:feature_auth/src/domain/auth_user.dart';
import 'package:feature_auth/src/domain/customer.dart';
import 'package:feature_auth/src/domain/customer_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => [];
}

/// Splash: we do not know yet whether there is a persisted session.
final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

/// Signed in with the IdP, but no banking customer yet.
final class SessionNeedsOnboarding extends SessionState {
  const SessionNeedsOnboarding(this.user);

  final AuthUser user;

  @override
  List<Object?> get props => [user];
}

final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.user, this.customer);

  final AuthUser user;
  final Customer customer;

  @override
  List<Object?> get props => [user, customer];
}

/// Signed in, but the profile could not be loaded (offline on a cold start
/// with no cache). The UI offers a retry instead of logging the user out.
final class SessionProfileUnavailable extends SessionState {
  const SessionProfileUnavailable(this.user, this.failure);

  final AuthUser user;
  final AppFailure failure;

  @override
  List<Object?> get props => [user, failure];
}

/// Single source of truth for "who is using the app". The router listens to
/// it to decide between login, onboarding and the home shell.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required AuthRepository authRepository,
    required CustomerRepository customerRepository,
    AnalyticsTracker analytics = const NoopAnalytics(),
  }) : _auth = authRepository,
       _customers = customerRepository,
       _analytics = analytics,
       super(const SessionUnknown()) {
    _subscription = _auth.authStateChanges().listen(_onAuthChanged);
  }

  final AuthRepository _auth;
  final CustomerRepository _customers;
  final AnalyticsTracker _analytics;
  late final StreamSubscription<AuthUser?> _subscription;
  AuthUser? _user;

  Future<void> _onAuthChanged(AuthUser? user) async {
    final previous = _user;
    _user = user;
    if (user == null) {
      await _analytics.setUserId(null);
      emit(const SessionUnauthenticated());
      return;
    }
    if (previous?.uid == user.uid && state is SessionAuthenticated) return;
    await _analytics.setUserId(user.uid);
    await refreshProfile();
  }

  /// Loads `/api/me` for the current identity.
  Future<void> refreshProfile() async {
    final user = _user;
    if (user == null) return;
    final result = await _customers.getMe();
    if (isClosed || _user?.uid != user.uid) return;
    switch (result) {
      case Success(value: final customer?):
        await _analytics.setUserProperty('segment', customer.segment);
        emit(SessionAuthenticated(user, customer));
      case Success(value: null):
        emit(SessionNeedsOnboarding(user));
      case Failure(:final failure):
        emit(SessionProfileUnavailable(user, failure));
    }
  }

  void onboardingCompleted(Customer customer) {
    final user = _user;
    if (user == null) return;
    unawaited(
      _analytics.track('onboarding_completed', {'segment': customer.segment}),
    );
    emit(SessionAuthenticated(user, customer));
  }

  Future<void> signOut() async {
    await _analytics.track('sign_out');
    await _auth.signOut();
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
