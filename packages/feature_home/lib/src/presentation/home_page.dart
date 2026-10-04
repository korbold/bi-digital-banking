import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_home/src/data/home_repository.dart';
import 'package:feature_home/src/presentation/home_cubit.dart';
import 'package:feature_home/src/presentation/home_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdui/sdui.dart';

/// Personalized home. Layout and content come from the server; this widget
/// only owns the loading / degraded / error envelope around it.
class HomePage extends StatelessWidget {
  const HomePage({
    required this.repository,
    required this.registry,
    required this.onAction,
    super.key,
    this.onSkipped,
    this.onSectionError,
    this.onScreenLoaded,
    this.connectivityChanges,
  });

  final HomeRepository repository;
  final SduiRegistry registry;
  final SduiActionHandler onAction;
  final SduiSkippedCallback? onSkipped;
  final SduiErrorCallback? onSectionError;

  /// e.g. to re-tint the app theme with `screen.themeSeed`.
  final ValueChanged<SduiScreen>? onScreenLoaded;

  /// Emits `true` when the device is back online, to refresh automatically.
  final Stream<bool>? connectivityChanges;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        HomeCubit(repository, connectivityChanges: connectivityChanges)..load(),
    child: HomeView(
      registry: registry,
      onAction: (action, {sourceSectionId}) {
        final target = switch (action) {
          NavigateAction(:final route) => route,
          OpenMiniAppAction(:final miniAppId) => 'miniapp:$miniAppId',
          OpenUrlAction(:final url) => url.host,
          UnknownAction() => null,
        };
        if (target != null) repository.trackEvent('action_used', target);
        onAction(action, sourceSectionId: sourceSectionId);
      },
      onSkipped: onSkipped,
      onSectionError: onSectionError,
      onScreenLoaded: onScreenLoaded,
    ),
  );
}

class HomeView extends StatelessWidget {
  const HomeView({
    required this.registry,
    required this.onAction,
    super.key,
    this.onSkipped,
    this.onSectionError,
    this.onScreenLoaded,
  });

  final SduiRegistry registry;
  final SduiActionHandler onAction;
  final SduiSkippedCallback? onSkipped;
  final SduiErrorCallback? onSectionError;
  final ValueChanged<SduiScreen>? onScreenLoaded;

  @override
  Widget build(BuildContext context) => BlocConsumer<HomeCubit, HomeState>(
    listenWhen: (prev, next) =>
        next is HomeLoaded &&
        (prev is! HomeLoaded || prev.screen != next.screen),
    listener: (_, state) => onScreenLoaded?.call((state as HomeLoaded).screen),
    builder: (context, state) => switch (state) {
      HomeLoading() => const _HomeSkeleton(),
      HomeFailure(:final failure) => ErrorView(
        message: failureMessage(failure),
        onRetry: () => context.read<HomeCubit>().refresh(),
      ),
      HomeLoaded() => RefreshIndicator(
        onRefresh: () => context.read<HomeCubit>().refresh(),
        child: SduiRenderer(
          screen: state.screen,
          registry: registry,
          onAction: onAction,
          onSkipped: onSkipped,
          onSectionError: onSectionError,
          header: _banner(context, state),
        ),
      ),
    },
  );

  Widget? _banner(BuildContext context, HomeLoaded state) {
    if (state.refreshFailure == null) {
      if (state.isStale && state.isRefreshing) {
        return const LinearProgressIndicator(semanticsLabel: 'Actualizando');
      }
      return null;
    }
    final time = formatTime(state.fetchedAt);
    final message = state.refreshFailure is OfflineFailure
        ? 'Sin conexión. Mostrando datos guardados de las $time.'
        : 'No pudimos actualizar. Mostrando datos de las $time.';
    return StatusBanner(
      key: const ValueKey('home-stale-banner'),
      message: message,
      tone: BannerTone.warning,
      action: 'Reintentar',
      onAction: () => context.read<HomeCubit>().refresh(),
    );
  }
}

/// User-facing copy for each failure type (Spanish).
String failureMessage(AppFailure failure) => switch (failure) {
  OfflineFailure() =>
    'Sin conexión a internet. Revisa tu red e intenta de nuevo.',
  TimeoutFailure() =>
    'El servicio está tardando más de lo normal. Intenta de nuevo.',
  ServiceUnavailableFailure() =>
    'Este servicio no está disponible por ahora. Intenta en unos segundos.',
  UnauthorizedFailure() => 'Tu sesión expiró. Vuelve a ingresar.',
  ValidationFailure(:final message) => message,
  ServerFailure() || UnknownFailure() => 'Algo salió mal. Intenta de nuevo.',
};

String formatTime(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(BiSpacing.md),
    children: const [
      SkeletonBox(height: 28, width: 220),
      SizedBox(height: BiSpacing.md),
      SkeletonBox(height: 120),
      SizedBox(height: BiSpacing.md),
      SkeletonBox(height: 72),
      SizedBox(height: BiSpacing.md),
      SkeletonBox(height: 96),
    ],
  );
}
