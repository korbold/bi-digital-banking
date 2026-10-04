import 'package:equatable/equatable.dart';

/// Identity as seen by the app: decoupled from firebase_auth's User so
/// cubits and tests never touch the Firebase SDK.
class AuthUser extends Equatable {
  const AuthUser({required this.uid, this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;

  @override
  List<Object?> get props => [uid, email, displayName];
}
