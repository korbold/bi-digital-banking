import 'dart:convert';

import 'package:feature_miniapps/feature_miniapps.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHost implements MiniAppHost {
  String? token = 'id-token';
  final tracked = <(String, Map<String, Object?>)>[];
  final notified = <(String, String)>[];
  Object? closedWith = #notClosed;

  @override
  Future<Map<String, Object?>> getContext() async => {
    'name': 'Danny',
    'segment': 'retail',
    'locale': 'es-EC',
  };

  @override
  Future<String?> getAuthToken() async => token;

  @override
  void track(String event, Map<String, Object?> params) =>
      tracked.add((event, params));

  @override
  void notifyHost(String title, String body) => notified.add((title, body));

  @override
  void close(Object? result) => closedWith = result;
}

String msg(String id, String method, [Map<String, Object?>? params]) =>
    jsonEncode({'id': id, 'method': method, 'params': ?params});

void main() {
  late _FakeHost host;
  late MiniAppBridge bridge;

  setUp(() {
    host = _FakeHost();
    bridge = MiniAppBridge(host);
  });

  test('getContext resolves with host context', () async {
    final r = await bridge.handle(msg('1', 'getContext'));
    expect(r.ok, isTrue);
    expect(r.payload, containsPair('segment', 'retail'));
    expect(
      r.script,
      startsWith('window.biBridgeResolve && window.biBridgeResolve("1", {'),
    );
  });

  test('methods outside the allowlist are rejected', () async {
    final r = await bridge.handle(msg('2', 'transferMoney', {'amount': 1000}));
    expect(r.ok, isFalse);
    expect((r.payload! as Map)['code'], 'method_not_allowed');
    expect(r.script, contains('biBridgeReject("2"'));
  });

  test('malformed messages are rejected without a script to run', () async {
    for (final raw in [
      'not json',
      '[1,2]',
      jsonEncode({'method': 'getContext'}),
    ]) {
      final r = await bridge.handle(raw);
      expect(r.ok, isFalse, reason: raw);
      expect((r.payload! as Map)['code'], 'malformed');
      expect(r.script, isNull);
    }
  });

  test('getAuthToken rejects when there is no session', () async {
    host.token = null;
    final r = await bridge.handle(msg('3', 'getAuthToken'));
    expect((r.payload! as Map)['code'], 'unauthenticated');
  });

  test('track, notifyHost and close reach the host', () async {
    await bridge.handle(
      msg('4', 'track', {
        'event': 'quote_viewed',
        'params': {'product': 'travel'},
      }),
    );
    await bridge.handle(
      msg('5', 'notifyHost', {'title': 'Listo', 'body': 'Cotización enviada'}),
    );
    await bridge.handle(
      msg('6', 'close', {
        'result': {'quoteId': 'q1'},
      }),
    );

    expect(host.tracked.single.$1, 'quote_viewed');
    expect(host.tracked.single.$2, {'product': 'travel'});
    expect(host.notified.single, ('Listo', 'Cotización enviada'));
    expect(host.closedWith, {'quoteId': 'q1'});
  });

  test('ids containing quotes cannot break out of the JS call', () async {
    final r = await bridge.handle(msg('x"); alert(1); ("', 'getContext'));
    expect(r.script, contains(r'"x\"); alert(1); (\""'));
  });

  group('MiniAppDescriptor', () {
    final app = MiniAppDescriptor(
      id: 'insurance',
      title: 'Seguros',
      url: Uri.parse(
        'https://bi-digital-banking.vercel.app/miniapps/insurance/',
      ),
    );

    test('only allows https navigation on the micro-app origin', () {
      expect(
        app.allowsNavigation(
          Uri.parse(
            'https://bi-digital-banking.vercel.app/miniapps/insurance/quote',
          ),
        ),
        isTrue,
      );
      expect(
        app.allowsNavigation(
          Uri.parse('http://bi-digital-banking.vercel.app/'),
        ),
        isFalse,
      );
      expect(
        app.allowsNavigation(Uri.parse('https://evil.example/phish')),
        isFalse,
      );
    });

    test('launchUri appends params', () {
      expect(app.launchUri({'product': 'travel'}).queryParameters, {
        'product': 'travel',
      });
    });
  });
}
