import 'package:core/core.dart';
import 'package:feature_auth/src/domain/auth_repository.dart';
import 'package:feature_auth/src/domain/auth_user.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static AuthUser? _map(User? user) => user == null
      ? null
      : AuthUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
        );

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) => _guard(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<Result<AuthUser>> register({
    required String email,
    required String password,
    String? displayName,
  }) => _guard(() async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (displayName != null && displayName.isNotEmpty) {
      await credential.user?.updateDisplayName(displayName);
    }
    return credential;
  });

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _auth.currentUser?.getIdToken(forceRefresh);

  Future<Result<AuthUser>> _guard(
    Future<UserCredential> Function() body,
  ) async {
    try {
      final credential = await body();
      return Result.success(_map(credential.user)!);
    } on FirebaseAuthException catch (e) {
      return Result.failure(mapFirebaseAuthCode(e.code));
    } on Object catch (e) {
      return Result.failure(UnknownFailure('$e'));
    }
  }
}

/// Firebase error codes -> Spanish copy. Kept public for tests.
AppFailure mapFirebaseAuthCode(String code) => switch (code) {
  'invalid-email' => const ValidationFailure(
    'El correo no es válido.',
    code: 'invalid-email',
  ),
  'user-disabled' => const ValidationFailure(
    'Esta cuenta está deshabilitada.',
    code: 'user-disabled',
  ),
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' => const ValidationFailure(
    'Correo o contraseña incorrectos.',
    code: 'invalid-credential',
  ),
  'email-already-in-use' => const ValidationFailure(
    'Ya existe una cuenta con este correo.',
    code: 'email-already-in-use',
  ),
  'weak-password' => const ValidationFailure(
    'La contraseña debe tener al menos 6 caracteres.',
    code: 'weak-password',
  ),
  'too-many-requests' => const ValidationFailure(
    'Demasiados intentos. Espera unos minutos e intenta de nuevo.',
    code: 'too-many-requests',
  ),
  'network-request-failed' => const OfflineFailure(),
  _ => UnknownFailure('auth/$code'),
};
