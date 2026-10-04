import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/application/onboarding_cubit.dart';
import 'package:feature_auth/src/domain/customer.dart';
import 'package:feature_auth/src/domain/customer_repository.dart';
import 'package:feature_auth/src/presentation/auth_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    required this.customerRepository,
    required this.onCompleted,
    required this.onSignOut,
    super.key,
    this.initialName = '',
    this.analytics = const NoopAnalytics(),
  });

  final CustomerRepository customerRepository;
  final ValueChanged<Customer> onCompleted;
  final VoidCallback onSignOut;
  final String initialName;
  final AnalyticsTracker analytics;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => OnboardingCubit(
      customerRepository,
      initialName: initialName,
      analytics: analytics,
    ),
    child: OnboardingView(onCompleted: onCompleted, onSignOut: onSignOut),
  );
}

class OnboardingView extends StatelessWidget {
  const OnboardingView({
    required this.onCompleted,
    required this.onSignOut,
    super.key,
  });

  final ValueChanged<Customer> onCompleted;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<OnboardingCubit, OnboardingState>(
        listenWhen: (a, b) =>
            a.status != b.status && b.status == OnboardingStatus.success,
        listener: (_, state) => onCompleted(state.customer!),
        builder: (context, state) {
          final cubit = context.read<OnboardingCubit>();
          final personal = state.step == OnboardingStep.personal;
          return PopScope(
            canPop: personal,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) cubit.back();
            },
            child: AuthScaffold(
              title: personal ? 'Cuéntanos de ti' : 'Personaliza tu banca',
              subtitle: 'Paso ${personal ? 1 : 2} de 2',
              leading: personal
                  ? IconButton(
                      tooltip: 'Cerrar sesión',
                      icon: const Icon(Icons.logout),
                      onPressed: onSignOut,
                    )
                  : BackButton(onPressed: cubit.back),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: 'Progreso: paso ${personal ? 1 : 2} de 2',
                    child: LinearProgressIndicator(value: personal ? 0.5 : 1),
                  ),
                  const SizedBox(height: BiSpacing.lg),
                  FormErrorText(
                    state.status == OnboardingStatus.failure
                        ? state.failureMessage
                        : null,
                  ),
                  if (personal)
                    _PersonalStep(state: state)
                  else
                    _ProfileStep(state: state),
                ],
              ),
            ),
          );
        },
      );
}

class _PersonalStep extends StatelessWidget {
  const _PersonalStep({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('onboarding_name'),
          initialValue: state.name,
          onChanged: cubit.nameChanged,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: InputDecoration(
            labelText: 'Nombres y apellidos',
            errorText: state.errors['name'],
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: BiSpacing.md),
        TextFormField(
          key: const Key('onboarding_document'),
          initialValue: state.documentId,
          onChanged: cubit.documentChanged,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            labelText: 'Número de cédula',
            helperText: '10 dígitos',
            errorText: state.errors['documentId'],
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: BiSpacing.lg),
        FilledButton(
          key: const Key('onboarding_next'),
          onPressed: cubit.next,
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnboardingCubit>();
    final theme = Theme.of(context);
    final submitting = state.status == OnboardingStatus.submitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Rango de edad'),
        Wrap(
          spacing: BiSpacing.sm,
          children: [
            for (final range in ageRanges)
              ChoiceChip(
                label: Text(range),
                selected: state.ageRange == range,
                onSelected: (_) => cubit.ageRangeChanged(range),
              ),
          ],
        ),
        _FieldError(state.errors['ageRange']),
        const SizedBox(height: BiSpacing.md),
        TextFormField(
          key: const Key('onboarding_income'),
          initialValue: state.monthlyIncome,
          onChanged: cubit.incomeChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Ingreso mensual aproximado (USD)',
            errorText: state.errors['monthlyIncome'],
            prefixIcon: const Icon(Icons.attach_money),
          ),
        ),
        const SizedBox(height: BiSpacing.md),
        const SectionHeader('¿Qué te interesa?'),
        Text(
          'Usaremos esto para mostrarte contenido relevante.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: BiSpacing.sm),
        Wrap(
          spacing: BiSpacing.sm,
          runSpacing: BiSpacing.xs,
          children: [
            for (final entry in interestOptions.entries)
              FilterChip(
                label: Text(entry.value),
                selected: state.interests.contains(entry.key),
                onSelected: (_) => cubit.toggleInterest(entry.key),
              ),
          ],
        ),
        _FieldError(state.errors['interests']),
        const SizedBox(height: BiSpacing.lg),
        SubmitButton(
          key: const Key('onboarding_submit'),
          label: 'Abrir mi cuenta',
          loading: submitting,
          onPressed: cubit.submit,
        ),
      ],
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: BiSpacing.xs),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
