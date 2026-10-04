import 'package:core/core.dart';
import 'package:feature_auth/src/domain/auth_user.dart';

/// Identity provider port. The app binds it to Firebase Auth; tests bind a
/// fake. Swapping to another IdP (Keycloak, Cognito) only touches the adapter.
abstract interface class AuthRepository {
  Stream<AuthUser?> authStateChanges();

  AuthUser? get currentUser;

  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  });

  Future<Result<AuthUser>> register({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> signOut();

  /// Short-lived ID token sent to the BFF. Used as ApiClient's TokenProvider.
  Future<String?> idToken({bool forceRefresh = false});
}
