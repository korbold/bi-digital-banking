import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/application/onboarding_cubit.dart'
    show interestOptions;
import 'package:feature_auth/src/application/profile_cubit.dart';
import 'package:feature_auth/src/domain/customer.dart';
import 'package:feature_auth/src/domain/customer_repository.dart';
import 'package:feature_auth/src/presentation/failure_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _segmentLabels = {
  'young': 'Joven',
  'retail': 'Personas',
  'premium': 'Premium',
  'business': 'Empresas',
};

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.customer,
    required this.customerRepository,
    required this.onSaved,
    required this.onSignOut,
    this.analytics = const NoopAnalytics(),
    super.key,
  });

  final Customer customer;
  final CustomerRepository customerRepository;
  final ValueChanged<Customer> onSaved;
  final VoidCallback onSignOut;
  final AnalyticsTracker analytics;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ProfileCubit(
      customerRepository,
      customer: customer,
      analytics: analytics,
    ),
    child: _ProfileView(onSaved: onSaved, onSignOut: onSignOut),
  );
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.onSaved, required this.onSignOut});

  final ValueChanged<Customer> onSaved;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          final cubit = context.read<ProfileCubit>();
          final customer = state.customer;
          return ListView(
            padding: const EdgeInsets.all(BiSpacing.md),
            children: [
              Text(customer.name, style: theme.textTheme.headlineSmall),
              if (customer.email != null)
                Text(customer.email!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: BiSpacing.sm),
              Wrap(
                children: [
                  Chip(
                    avatar: const Icon(
                      Icons.workspace_premium_outlined,
                      size: 18,
                    ),
                    label: Text(
                      'Segmento: ${_segmentLabels[customer.segment] ?? customer.segment}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BiSpacing.lg),
              const SectionHeader('Tus intereses'),
              Text(
                'Personalizamos tu inicio con ellos: ofertas, consejos y accesos.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: BiSpacing.sm),
              Wrap(
                spacing: BiSpacing.sm,
                runSpacing: BiSpacing.sm,
                children: [
                  for (final entry in interestOptions.entries)
                    FilterChip(
                      key: Key('interest_${entry.key}'),
                      label: Text(entry.value),
                      selected: state.interests.contains(entry.key),
                      onSelected: (_) => cubit.toggleInterest(entry.key),
                    ),
                ],
              ),
              const SizedBox(height: BiSpacing.md),
              if (state.status == ProfileStatus.failure &&
                  state.failure != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: BiSpacing.sm),
                  child: StatusBanner(
                    message: authFailureMessage(state.failure!),
                    tone: BannerTone.error,
                  ),
                ),
              if (state.status == ProfileStatus.saved)
                const Padding(
                  padding: EdgeInsets.only(bottom: BiSpacing.sm),
                  child: StatusBanner(
                    message: 'Listo. Tu inicio se actualizó con tus intereses.',
                  ),
                ),
              FilledButton(
                key: const Key('profile_save'),
                onPressed: state.isDirty && state.status != ProfileStatus.saving
                    ? () async {
                        final saved = await cubit.save();
                        if (saved != null) onSaved(saved);
                      }
                    : null,
                child: state.status == ProfileStatus.saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar intereses'),
              ),
              const SizedBox(height: BiSpacing.xl),
              OutlinedButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ],
          );
        },
      ),
    );
  }
}
