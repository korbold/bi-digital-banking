import 'package:bi_digital_banking/src/config/env.dart';
import 'package:bi_digital_banking/src/config/remote_flags.dart';
import 'package:bi_digital_banking/src/di.dart';
import 'package:bi_digital_banking/src/router.dart';
import 'package:bi_digital_banking/src/theme_controller.dart';
import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sdui/sdui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds the SDUI registry: generic sections from `sdui`, home-owned
/// sections (fx) and sections owned by other domains (accounts). This is the
/// only place where domains meet (ADR 0001).
SduiRegistry buildSduiRegistry() {
  final registry = SduiRegistry();
  registerDefaults(registry);
  registerHomeSections(registry, fxRepository: sl<FxRepository>());
  registry.register(
    'account_summary',
    (context, section, onAction) => AccountSummarySection(
      onAccountTap: (account) => onAction(
        NavigateAction(Routes.account(account.id)),
        sourceSectionId: section.id,
      ),
    ),
  );
  return registry;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final SduiRegistry _registry = buildSduiRegistry();

  void _onAction(SduiAction action, {String? sourceSectionId}) {
    final logger = sl<AppLogger>();
    switch (action) {
      case NavigateAction(:final route):
        if (!route.startsWith('/')) {
          return logger.warning(
            'Rejected SDUI route',
            context: {'route': route},
          );
        }
        if (route == Routes.transfer && !sl<RemoteFlags>().transfersEnabled) {
          return _snack('Transferencias en mantenimiento. Intenta más tarde.');
        }
        context.push(route);
      case OpenMiniAppAction(:final miniAppId, :final params):
        final query = params.isEmpty
            ? ''
            : '?${Uri(queryParameters: params.map((k, v) => MapEntry(k, '$v'))).query}';
        context.push('${Routes.miniApp(miniAppId)}$query');
      case OpenUrlAction(:final url):
        launchUrl(url, mode: LaunchMode.externalApplication);
      case UnknownAction():
        logger.warning(
          'Unknown SDUI action',
          context: {'section': sourceSectionId},
        );
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _sendTestPush() async {
    final result = await sl<ApiClient>().post<Object?>(
      '/api/notifications/test',
      decode: (j) => j,
    );
    if (!mounted) return;
    _snack(
      result.failureOrNull == null
          ? 'Notificación enviada'
          : failureMessage(result.failureOrNull!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionCubit>();
    final maintenance = sl<RemoteFlags>().maintenanceMessage;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BI Digital'),
        actions: [
          if (Env.enableChaosPanel)
            IconButton(
              tooltip: 'Escenarios degradados',
              icon: const Icon(Icons.science_outlined),
              onPressed: () => context.push(Routes.chaos),
            ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (value) => switch (value) {
              'push' => _sendTestPush(),
              'transfer' => context.push(Routes.transfer),
              _ => session.signOut(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'transfer', child: Text('Transferir')),
              PopupMenuItem(
                value: 'push',
                child: Text('Enviarme una notificación de prueba'),
              ),
              PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (maintenance.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BiSpacing.md,
                BiSpacing.sm,
                BiSpacing.md,
                0,
              ),
              child: StatusBanner(
                message: maintenance,
                tone: BannerTone.warning,
              ),
            ),
          Expanded(
            child: HomePage(
              repository: sl(),
              registry: _registry,
              onAction: _onAction,
              onScreenLoaded: (screen) =>
                  sl<ThemeController>().applySeed(screen.themeSeed),
              onSkipped: (section, reason) =>
                  sl<AnalyticsTracker>().track('sdui_section_skipped', {
                    'type': section.type,
                    'reason': reason.name,
                  }),
              onSectionError: (section, error, stack) => sl<AppLogger>().error(
                'SDUI section failed: ${section.type}',
                error: error,
                stackTrace: stack,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
