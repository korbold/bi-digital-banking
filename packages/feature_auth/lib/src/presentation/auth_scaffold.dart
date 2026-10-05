import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Shared layout for the unauthenticated screens: brand header, scrollable
/// body that stays usable with large text scale and the keyboard open.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: leading == null ? null : AppBar(leading: leading),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BiSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.account_balance_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: BiSpacing.md),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: BiSpacing.sm),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: BiSpacing.lg),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Password field with an accessible show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    super.key,
    this.label = 'Contraseña',
    this.validator,
    this.autofillHints = const [AutofillHints.password],
    this.onSubmitted,
    this.fieldKey = const Key('password_field'),
    this.textInputAction = TextInputAction.done,
  });

  /// Key of the inner text field (tests and E2E target it).
  final Key fieldKey;
  final TextInputAction textInputAction;

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final Iterable<String> autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: widget.fieldKey,
    controller: widget.controller,
    obscureText: _obscure,
    autofillHints: widget.autofillHints,
    validator: widget.validator,
    textInputAction: widget.textInputAction,
    onFieldSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: widget.label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
        icon: Icon(
          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
  );
}

class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: BiSpacing.md),
      child: StatusBanner(message: message!, tone: BannerTone.error),
    );
  }
}

class SubmitButton extends StatelessWidget {
  const SubmitButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: loading ? null : onPressed,
    child: loading
        ? Semantics(
            label: 'Procesando',
            child: const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          )
        : Text(label),
  );
}
