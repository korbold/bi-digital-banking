import 'dart:async';

import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:feature_notifications/src/gateways.dart';
import 'package:feature_notifications/src/push_message.dart';

/// Orchestrates push: permission, token registration (and refresh),
/// foreground display and deep links from tapped notifications.
class PushService {
  PushService({
    required MessagingGateway messaging,
    required LocalNotifier local,
    required TokenRegistrar registerToken,
    AppLogger logger = const ConsoleLogger(),
  }) : _messaging = messaging,
       _local = local,
       _registerToken = registerToken,
       _logger = logger;

  final MessagingGateway _messaging;
  final LocalNotifier _local;
  final TokenRegistrar _registerToken;
  final AppLogger _logger;

  // Single-subscription controller buffers a deep link that arrives (e.g.
  // the launch notification) before the router starts listening.
  final StreamController<String> _deepLinks = StreamController<String>();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  bool _initialized = false;
  bool _signedIn = false;

  /// In-app routes to open, from tapped notifications.
  Stream<String> get deepLinks => _deepLinks.stream;

  /// Call on every sign-in. The FCM token belongs to the device, but the
  /// backend stores it under the customer, so each new session registers it
  /// again for the customer now signed in.
  Future<void> start() async {
    _signedIn = true;
    if (!_initialized) {
      _initialized = true;
      await _local.initialize(onTap: _emitRoute);
      final granted = await _messaging.requestPermission();
      if (!granted) _logger.warning('Push permission denied');

      _subscriptions
        ..add(
          _messaging.onTokenRefresh.listen((t) {
            if (_signedIn) unawaited(_register(t));
          }),
        )
        ..add(
          _messaging.onForegroundMessage.listen(
            (m) => unawaited(_local.show(m)),
          ),
        )
        ..add(_messaging.onMessageOpenedApp.listen((m) => _emitRoute(m.route)));

      final initial = await _messaging.getInitialMessage();
      _emitRoute(initial?.route ?? await _local.launchPayload());
    }

    final token = await _messaging.getToken();
    if (token != null) await _register(token);
  }

  /// Call on sign-out. Deleting the token stops this device from receiving
  /// the previous customer's notifications: the backend still holds the old
  /// token, but FCM rejects it as unregistered and the notifier prunes it on
  /// the next send.
  Future<void> stop() async {
    if (!_signedIn) return;
    _signedIn = false;
    try {
      await _messaging.deleteToken();
    } on Object catch (e, st) {
      _logger.error('Push token deletion failed', error: e, stackTrace: st);
    }
  }

  Future<void> _register(String token) async {
    try {
      await _registerToken(token);
    } on Object catch (e, st) {
      // Not fatal: retried on next start/token refresh.
      _logger.error('Token registration failed', error: e, stackTrace: st);
    }
  }

  void _emitRoute(String? route) {
    final safe = route == null ? null : PushMessage.routeOf({'route': route});
    if (safe != null && !_deepLinks.isClosed) _deepLinks.add(safe);
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _deepLinks.close();
  }
}

/// Default registrar backed by the BFF.
TokenRegistrar apiTokenRegistrar(ApiClient api, {required String platform}) =>
    (token) async {
      final result = await api.post<void>(
        '/api/devices',
        body: {'token': token, 'platform': platform},
        decode: (_) {},
      );
      final failure = result.failureOrNull;
      if (failure != null) throw failure;
    };
