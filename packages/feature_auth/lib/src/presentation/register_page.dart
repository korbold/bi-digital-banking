import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/application/credentials_cubit.dart';
import 'package:feature_auth/src/domain/auth_repository.dart';
import 'package:feature_auth/src/presentation/auth_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({
    required this.authRepository,
    required this.onGoToLogin,
    super.key,
    this.analytics = const NoopAnalytics(),
  });

  final AuthRepository authRepository;
  final VoidCallback onGoToLogin;
  final AnalyticsTracker analytics;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => RegisterCubit(authRepository, analytics: analytics),
    child: RegisterView(onGoToLogin: onGoToLogin),
  );
}

class RegisterView extends StatefulWidget {
  const RegisterView({required this.onGoToLogin, super.key});

  final VoidCallback onGoToLogin;

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<RegisterCubit>().submit(
      email: _email.text,
      password: _password.text,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<RegisterCubit, CredentialsState>(
    builder: (context, state) => AuthScaffold(
      title: 'Abre tu cuenta',
      subtitle: '100% digital, en minutos',
      leading: BackButton(onPressed: widget.onGoToLogin),
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
                autofillHints: const [AutofillHints.email],
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
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: CredentialValidators.password,
              ),
              const SizedBox(height: BiSpacing.md),
              PasswordField(
                controller: _confirm,
                fieldKey: const Key('confirm_field'),
                label: 'Confirmar contraseña',
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) =>
                    v != _password.text ? 'Las contraseñas no coinciden' : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: BiSpacing.lg),
              SubmitButton(
                key: const Key('register_button'),
                label: 'Crear cuenta',
                loading: state.isSubmitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
