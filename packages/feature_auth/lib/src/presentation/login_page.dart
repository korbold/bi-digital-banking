import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/application/credentials_cubit.dart';
import 'package:feature_auth/src/domain/auth_repository.dart';
import 'package:feature_auth/src/presentation/auth_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({
    required this.authRepository,
    required this.onGoToRegister,
    super.key,
    this.analytics = const NoopAnalytics(),
  });

  final AuthRepository authRepository;
  final VoidCallback onGoToRegister;
  final AnalyticsTracker analytics;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => LoginCubit(authRepository, analytics: analytics),
    child: LoginView(onGoToRegister: onGoToRegister),
  );
}

class LoginView extends StatefulWidget {
  const LoginView({required this.onGoToRegister, super.key});

  final VoidCallback onGoToRegister;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<LoginCubit>().submit(
      email: _email.text,
      password: _password.text,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<LoginCubit, CredentialsState>(
    builder: (context, state) => AuthScaffold(
      title: 'Bienvenido',
      subtitle: 'Ingresa a tu banca digital',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormErrorText(
                state.status == FormStatus.failure ? state.errorMessage : null,
              ),
              TextFormField(
                key: const Key('email_field'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
                textInputAction: TextInputAction.next,
                validator: CredentialValidators.email,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: BiSpacing.md),
              PasswordField(
                controller: _password,
                validator: CredentialValidators.password,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: BiSpacing.lg),
              SubmitButton(
                key: const Key('login_button'),
                label: 'Ingresar',
                loading: state.isSubmitting,
                onPressed: _submit,
              ),
              const SizedBox(height: BiSpacing.sm),
              TextButton(
                onPressed: state.isSubmitting ? null : widget.onGoToRegister,
                child: const Text('¿Eres nuevo? Abre tu cuenta'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
