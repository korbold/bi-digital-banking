import 'package:bi_digital_banking/src/config/env.dart';
import 'package:bi_digital_banking/src/config/remote_flags.dart';
import 'package:bi_digital_banking/src/demo/chaos_panel.dart';
import 'package:bi_digital_banking/src/di.dart';
import 'package:bi_digital_banking/src/miniapp_catalog.dart';
import 'package:bi_digital_banking/src/pages/home_shell.dart';
import 'package:bi_digital_banking/src/pages/simple_pages.dart';
import 'package:bi_digital_banking/src/session_refresh.dart';
import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:feature_accounts/feature_accounts.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_miniapps/feature_miniapps.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const onboarding = '/onboarding';
  static const profileError = '/profile-error';
  static const home = '/home';
  static const transfer = '/transfer';
  static const chaos = '/demo/chaos';
  static const accounts = '/accounts';
  static const profile = '/profile';
  static String account(String id) => '/accounts/$id';
  static String miniApp(String id) => '/miniapp/$id';
}

const Set<String> _publicRoutes = {Routes.login, Routes.register};

/// Single source of navigation. Redirects derive from [SessionCubit] so a
/// deep link (e.g. from a push) can never bypass login or onboarding.
GoRouter buildRouter(SessionCubit session) => GoRouter(
  initialLocation: Routes.splash,
  refreshListenable: StreamRefresh(session.stream),
  observers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
  // Server-driven actions may reference routes an older app build does not
  // know. Degrade gracefully and report it instead of a router error page.
  errorBuilder: (context, state) {
    sl<AppLogger>().warning(
      'Unknown route',
      context: {'location': state.uri.toString()},
    );
    return const UnavailableRoutePage();
  },
  redirect: (context, state) {
    final location = state.matchedLocation;
    return switch (session.state) {
      SessionUnknown() => location == Routes.splash ? null : Routes.splash,
      SessionUnauthenticated() =>
        _publicRoutes.contains(location) ? null : Routes.login,
      SessionNeedsOnboarding() =>
        location == Routes.onboarding ? null : Routes.onboarding,
      SessionProfileUnavailable() =>
        location == Routes.profileError ? null : Routes.profileError,
      SessionAuthenticated() =>
        location == Routes.splash ||
                _publicRoutes.contains(location) ||
                location == Routes.onboarding
            ? Routes.home
            : null,
    };
  },
  routes: [
    GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
    GoRoute(
      path: Routes.login,
      builder: (context, _) => LoginPage(
        authRepository: sl(),
        analytics: sl(),
        onGoToRegister: () => context.go(Routes.register),
      ),
    ),
    GoRoute(
      path: Routes.register,
      builder: (context, _) => RegisterPage(
        authRepository: sl(),
        analytics: sl(),
        onGoToLogin: () => context.go(Routes.login),
      ),
    ),
    GoRoute(
      path: Routes.onboarding,
      builder: (context, _) {
        final state = session.state;
        return OnboardingPage(
          customerRepository: sl(),
          analytics: sl(),
          initialName: state is SessionNeedsOnboarding
              ? state.user.displayName ?? ''
              : '',
          onCompleted: session.onboardingCompleted,
          onSignOut: session.signOut,
        );
      },
    ),
    GoRoute(
      path: Routes.profileError,
      builder: (_, _) => ProfileUnavailablePage(session: session),
    ),
    GoRoute(path: Routes.home, builder: (_, _) => const HomeShell()),
    GoRoute(
      path: Routes.accounts,
      builder: (context, _) => AccountsListPage(
        onAccountTap: (account) => context.push(Routes.account(account.id)),
      ),
    ),
    GoRoute(
      path: Routes.profile,
      redirect: (_, _) =>
          session.state is SessionAuthenticated ? null : Routes.home,
      builder: (context, _) => ProfilePage(
        customer: (session.state as SessionAuthenticated).customer,
        customerRepository: sl(),
        analytics: sl(),
        onSaved: session.customerUpdated,
        onSignOut: session.signOut,
      ),
    ),
    GoRoute(
      path: '/accounts/:id',
      builder: (context, state) => AccountDetailPage(
        accountId: state.pathParameters['id']!,
        repository: sl(),
        onTransfer: (from) => context.push('${Routes.transfer}?from=$from'),
      ),
    ),
    GoRoute(
      path: Routes.transfer,
      redirect: (_, _) =>
          sl<RemoteFlags>().transfersEnabled ? null : Routes.home,
      builder: (context, state) => TransferPage(
        repository: sl(),
        analytics: sl(),
        initialFromAccountId: state.uri.queryParameters['from'],
        onClose: () =>
            context.canPop() ? context.pop() : context.go(Routes.home),
      ),
    ),
    GoRoute(
      path: '/miniapp/:id',
      redirect: (_, state) =>
          sl<RemoteFlags>().miniAppsEnabled &&
              MiniAppCatalog.byId(state.pathParameters['id']!) != null
          ? null
          : Routes.home,
      builder: (context, state) {
        final miniApp = MiniAppCatalog.byId(state.pathParameters['id']!)!;
        final current = session.state;
        return MiniAppPage(
          miniApp: miniApp,
          params: state.uri.queryParameters,
          getContext: () async => {
            if (current is SessionAuthenticated) ...{
              'name': current.customer.name,
              'segment': current.customer.segment,
            },
            'locale': 'es-EC',
            'theme': Theme.of(context).brightness.name,
          },
          getAuthToken: () => sl<AuthRepository>().idToken(),
          onTrack: (event, params) =>
              sl<AnalyticsTracker>().track('miniapp_$event', {
                'miniapp': miniApp.id,
                ...params.map((k, v) => MapEntry(k, '$v')),
              }),
        );
      },
    ),
    if (Env.enableChaosPanel)
      GoRoute(
        path: Routes.chaos,
        builder: (context, _) => ChaosPanelPage(
          chaos: sl<ChaosController>(),
          breakers: sl<CircuitBreakerRegistry>(),
          onClearCache: () => sl<ApiClient>().clearCache(),
        ),
      ),
  ],
);
