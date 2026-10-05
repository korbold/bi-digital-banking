import 'package:feature_notifications/src/push_message.dart';

/// Minimal surface of the push provider (FCM) the service relies on.
abstract interface class MessagingGateway {
  /// Asks the OS for notification permission (Android 13+ / iOS).
  Future<bool> requestPermission();
  Future<String?> getToken();

  /// Invalidates the current token; the next [getToken] returns a new one.
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;

  /// Messages received while the app is in the foreground.
  Stream<PushMessage> get onForegroundMessage;

  /// User tapped a system notification while the app was in background.
  Stream<PushMessage> get onMessageOpenedApp;

  /// Notification that launched the app from terminated state.
  Future<PushMessage?> getInitialMessage();
}

/// Shows notifications while the app is in foreground (FCM does not).
abstract interface class LocalNotifier {
  /// [onTap] receives the payload (route) of a tapped local notification.
  Future<void> initialize({required void Function(String? payload) onTap});
  Future<void> show(PushMessage message);

  /// Payload of the local notification that launched the app, if any.
  Future<String?> launchPayload();
}

/// Sends the device token to the backend (`POST /api/devices`).
typedef TokenRegistrar = Future<void> Function(String token);
