import 'package:feature_notifications/src/gateways.dart';
import 'package:feature_notifications/src/push_message.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

PushMessage _fromRemote(RemoteMessage m) => PushMessage(
  title: m.notification?.title,
  body: m.notification?.body,
  data: Map<String, Object?>.from(m.data),
);

/// FCM-backed gateway.
class FirebaseMessagingGateway implements MessagingGateway {
  FirebaseMessagingGateway([FirebaseMessaging? messaging])
    : _fcm = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _fcm;

  @override
  Future<bool> requestPermission() async {
    final settings = await _fcm.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _fcm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_fromRemote);

  @override
  Stream<PushMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_fromRemote);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final m = await _fcm.getInitialMessage();
    return m == null ? null : _fromRemote(m);
  }
}

/// flutter_local_notifications-backed notifier, Android channel `transactions`.
class FlutterLocalNotifier implements LocalNotifier {
  FlutterLocalNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  int _nextId = 0;

  static const channel = AndroidNotificationChannel(
    'transactions',
    'Movimientos y transferencias',
    description: 'Avisos de transferencias y movimientos de tus cuentas',
    importance: Importance.high,
  );

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  @override
  Future<void> show(PushMessage message) => _plugin.show(
    _nextId++,
    message.title,
    message.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: message.route,
  );

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false
        ? details?.notificationResponse?.payload
        : null;
  }
}

/// Must be registered in `main()` before `runApp`:
/// `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);`
///
/// Notification messages are displayed by the OS while in background; this
/// handler only needs to exist for data messages (e.g. future silent
/// balance refresh).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background push: ${message.messageId} ${message.data}');
}
