import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter/material.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Semantics(
        label: 'Cargando sesión',
        child: const CircularProgressIndicator(),
      ),
    ),
  );
}

/// Logged in but the profile service is unreachable and nothing is cached:
/// offer retry instead of bouncing the customer back to login.
class ProfileUnavailablePage extends StatelessWidget {
  const ProfileUnavailablePage({required this.session, super.key});

  final SessionCubit session;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        TextButton(
          onPressed: session.signOut,
          child: const Text('Cerrar sesión'),
        ),
      ],
    ),
    body: ErrorView(
      message:
          'No pudimos cargar tu perfil. Revisa tu conexión e inténtalo de nuevo.',
      onRetry: session.refreshProfile,
    ),
  );
}

class UnavailableRoutePage extends StatelessWidget {
  const UnavailableRoutePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: const ErrorView(
      message: 'Esta sección aún no está disponible en tu versión de la app.',
    ),
  );
}
