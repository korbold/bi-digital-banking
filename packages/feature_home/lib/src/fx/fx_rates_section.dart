import 'package:design_system/design_system.dart';
import 'package:feature_home/src/fx/fx_cubit.dart';
import 'package:feature_home/src/fx/fx_repository.dart';
import 'package:feature_home/src/presentation/home_cubit.dart';
import 'package:feature_home/src/presentation/home_page.dart' show formatTime;
import 'package:feature_home/src/presentation/home_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdui/sdui.dart';

/// SDUI `fx_rates` section. Fetches its own data so a failure of the
/// external rates provider degrades only this card, never the home screen.
class FxRatesSection extends StatelessWidget {
  const FxRatesSection({
    required this.section,
    required this.repository,
    super.key,
  });

  final SduiSection section;
  final FxRepository repository;

  @override
  Widget build(BuildContext context) {
    final base = section.string('base') ?? 'USD';
    final symbols = section.list('symbols').whereType<String>().toList();
    return BlocProvider(
      create: (_) => FxCubit(repository, base: base, symbols: symbols)..load(),
      child: const _HomeRefreshListener(child: _FxCard()),
    );
  }
}

/// Re-fetches rates whenever the surrounding home refreshes (pull-to-refresh
/// or automatic recovery), so an fx outage or recovery shows up right away.
/// Outside a home (e.g. in isolation tests) it is a no-op.
class _HomeRefreshListener extends StatelessWidget {
  const _HomeRefreshListener({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final home = context.read<HomeCubit?>();
    if (home == null) return child;
    return BlocListener<HomeCubit, HomeState>(
      bloc: home,
      listenWhen: (previous, current) =>
          current is HomeLoaded &&
          current.isRefreshing &&
          !(previous is HomeLoaded && previous.isRefreshing),
      listener: (context, _) => context.read<FxCubit>().load(silent: true),
      child: child,
    );
  }
}

class _FxCard extends StatelessWidget {
  const _FxCard();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(BiSpacing.md),
      child: BlocBuilder<FxCubit, FxState>(
        builder: (context, state) => switch (state) {
          FxLoading() => const Column(
            children: [
              SkeletonBox(width: 160),
              SizedBox(height: BiSpacing.sm),
              SkeletonBox(height: 40),
            ],
          ),
          FxUnavailable() => Row(
            key: const ValueKey('fx-unavailable'),
            children: [
              const Icon(Icons.currency_exchange, size: 20),
              const SizedBox(width: BiSpacing.sm),
              const Expanded(child: Text('Tipos de cambio no disponibles')),
              TextButton(
                onPressed: () => context.read<FxCubit>().load(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
          FxLoaded(:final rates, :final isStale, :final fetchedAt) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isStale)
                Padding(
                  key: const ValueKey('fx-stale'),
                  padding: const EdgeInsets.only(bottom: BiSpacing.sm),
                  child: StatusBanner(
                    message:
                        'Tasas guardadas de ${formatTime(fetchedAt)} · servicio no disponible',
                    tone: BannerTone.warning,
                    action: 'Reintentar',
                    onAction: () => context.read<FxCubit>().load(),
                  ),
                ),
              SectionHeader(
                'Tipos de cambio (1 ${rates.base})',
                trailing: isStale
                    ? const Tooltip(
                        message: 'Datos guardados',
                        child: Icon(Icons.history, size: 18),
                      )
                    : null,
              ),
              Wrap(
                spacing: BiSpacing.lg,
                runSpacing: BiSpacing.sm,
                children: [
                  for (final e in rates.rates.entries)
                    Semantics(
                      label:
                          '1 ${rates.base} equivale a ${e.value.toStringAsFixed(2)} ${e.key}',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(
                            e.value >= 100
                                ? e.value.toStringAsFixed(0)
                                : e.value.toStringAsFixed(4),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (rates.provider != null) ...[
                const SizedBox(height: BiSpacing.sm),
                Text(
                  'Fuente: ${rates.provider}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        },
      ),
    ),
  );
}
