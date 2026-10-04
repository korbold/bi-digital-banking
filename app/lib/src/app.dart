import 'dart:async';

import 'package:bi_digital_banking/src/di.dart';
import 'package:bi_digital_banking/src/online_signal.dart';
import 'package:bi_digital_banking/src/router.dart';
import 'package:bi_digital_banking/src/theme_controller.dart';
import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_notifications/feature_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class BiApp extends StatefulWidget {
  const BiApp({super.key});

  @override
  State<BiApp> createState() => _BiAppState();
}

class _BiAppState extends State<BiApp> {
  late final SessionCubit _session = SessionCubit(
    authRepository: sl(),
    customerRepository: sl(),
    analytics: sl(),
  );
  late final GoRouter _router = buildRouter(_session);

  @override
  void dispose() {
    unawaited(_session.close());
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _session,
    child: ValueListenableBuilder<Color>(
      valueListenable: sl<ThemeController>(),
      builder: (context, seed, _) => MaterialApp.router(
        title: 'BI Digital',
        debugShowCheckedModeBanner: false,
        theme: BiTheme.light(seed: seed),
        darkTheme: BiTheme.dark(seed: seed),
        routerConfig: _router,
        builder: (context, child) =>
            _SessionScope(router: _router, child: child!),
      ),
    ),
  );
}

/// Per-session resources: the accounts cubit (shared by home and detail
/// screens), push registration, and cache cleanup on logout. Keyed by uid so
/// nothing from one customer survives into another customer's session.
class _SessionScope extends StatefulWidget {
  const _SessionScope({required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  State<_SessionScope> createState() => _SessionScopeState();
}

class _SessionScopeState extends State<_SessionScope> {
  AccountsCubit? _accounts;
  String? _uid;
  StreamSubscription<String>? _deepLinks;

  void _onSession(SessionState state) {
    final uid = state is SessionAuthenticated ? state.user.uid : null;
    if (uid == _uid) return;
    final previous = _accounts;
    setState(() {
      _uid = uid;
      _accounts = uid == null
          ? null
          : (AccountsCubit(
              sl(),
              connectivityChanges: sl<OnlineSignal>().changes,
            )..load());
    });
    unawaited(previous?.close());
    if (state is SessionAuthenticated) {
      unawaited(sl<AnalyticsTracker>().setUserId(uid));
      unawaited(
        sl<AnalyticsTracker>().setUserProperty(
          'segment',
          state.customer.segment,
        ),
      );
      unawaited(_startPush());
    } else if (state is SessionUnauthenticated) {
      unawaited(sl<ApiClient>().clearCache());
      unawaited(sl<AnalyticsTracker>().setUserId(null));
    }
  }

  Future<void> _startPush() async {
    final push = sl<PushService>();
    await push.start();
    // Single subscription for the app lifetime: routes from notification taps.
    _deepLinks ??= push.deepLinks.listen((route) => widget.router.push(route));
  }

  @override
  void initState() {
    super.initState();
    _onSession(context.read<SessionCubit>().state);
  }

  @override
  void dispose() {
    unawaited(_deepLinks?.cancel());
    unawaited(_accounts?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<SessionCubit, SessionState>(
        listener: (_, state) => _onSession(state),
        child: _accounts == null
            ? widget.child
            : BlocProvider<AccountsCubit>.value(
                value: _accounts!,
                child: widget.child,
              ),
      );
}
