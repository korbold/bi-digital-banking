import 'dart:async';

import 'package:core/core.dart';
import 'package:feature_notifications/feature_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMessaging implements MessagingGateway {
  bool granted = true;
  String? token = 'fcm-token-1';
  PushMessage? initial;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushMessage> get onMessageOpenedApp => opened.stream;

  @override
  Future<PushMessage?> getInitialMessage() async => initial;
}

class _FakeLocal implements LocalNotifier {
  void Function(String?)? tap;
  final shown = <PushMessage>[];

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async => tap = onTap;

  @override
  Future<void> show(PushMessage message) async => shown.add(message);

  @override
  Future<String?> launchPayload() async => null;
}

void main() {
  late _FakeMessaging messaging;
  late _FakeLocal local;
  late List<String> registered;
  late PushService service;

  setUp(() {
    messaging = _FakeMessaging();
    local = _FakeLocal();
    registered = [];
    service = PushService(
      messaging: messaging,
      local: local,
      registerToken: (t) async => registered.add(t),
    );
  });

  test('PushMessage.route accepts only in-app paths', () {
    expect(
      const PushMessage(data: {'route': '/accounts/acc_1'}).route,
      '/accounts/acc_1',
    );
    expect(
      const PushMessage(data: {'route': 'https://evil.example'}).route,
      isNull,
    );
    expect(const PushMessage(data: {'route': '//evil.example'}).route, isNull);
    expect(const PushMessage().route, isNull);
  });

  test('registers the token on start and again on refresh', () async {
    await service.start();
    messaging.refresh.add('fcm-token-2');
    await pumpEventQueue();
    expect(registered, ['fcm-token-1', 'fcm-token-2']);
  });

  test('registration failure does not break start', () async {
    service = PushService(
      messaging: messaging,
      local: local,
      registerToken: (_) async => throw const OfflineFailure(),
    );
    await expectLater(service.start(), completes);
  });

  test('foreground messages are shown locally', () async {
    await service.start();
    messaging.foreground.add(
      const PushMessage(
        title: 'Transferencia realizada',
        data: {'route': '/accounts/a'},
      ),
    );
    await pumpEventQueue();
    expect(local.shown.single.title, 'Transferencia realizada');
  });

  test(
    'deep links come from launch message, opened messages and local taps',
    () async {
      messaging.initial = const PushMessage(
        data: {'route': '/accounts/launch'},
      );
      final links = <String>[];
      service.deepLinks.listen(links.add);

      await service.start();
      messaging.opened.add(
        const PushMessage(data: {'route': '/accounts/opened'}),
      );
      local.tap!('/accounts/local');
      local.tap!('javascript:alert(1)');
      await pumpEventQueue();

      expect(
        links,
        unorderedEquals([
          '/accounts/launch',
          '/accounts/opened',
          '/accounts/local',
        ]),
      );
    },
  );

  test('a launch deep link is buffered until the router subscribes', () async {
    messaging.initial = const PushMessage(data: {'route': '/accounts/late'});
    await service.start();
    expect(await service.deepLinks.first, '/accounts/late');
  });
}
