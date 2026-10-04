import 'package:flutter_test/flutter_test.dart';
import 'package:sdui/sdui.dart';

void main() {
  group('SduiScreen.fromJson', () {
    test('parses valid sections and drops malformed ones', () {
      final screen = SduiScreen.fromJson(const {
        'schemaVersion': 1,
        'screen': 'home',
        'segment': 'retail',
        'theme': {'seed': '#F07F09'},
        'sections': [
          {
            'id': 'greeting',
            'type': 'greeting',
            'props': {'title': 'Hola'},
          },
          {'type': 'text_card'}, // no id
          'not-a-map',
          {'id': 'x', 'type': 'brand_new_widget', 'minAppVersion': 3},
        ],
      });

      expect(screen.sections.map((s) => s.id), ['greeting', 'x']);
      expect(screen.invalidSections, 2);
      expect(screen.sections.last.minAppVersion, 3);
      expect(screen.themeSeed, 0xFFF07F09);
      expect(screen.segment, 'retail');
    });

    test('missing sections list yields empty screen, non-map root throws', () {
      expect(SduiScreen.fromJson(const {'screen': 'home'}).sections, isEmpty);
      expect(() => SduiScreen.fromJson(const ['bad']), throwsFormatException);
    });
  });

  group('SduiAction.fromJson', () {
    test('parses known action types', () {
      expect(
        SduiAction.fromJson(const {'type': 'navigate', 'route': '/transfer'}),
        const NavigateAction('/transfer'),
      );
      expect(
        SduiAction.fromJson(const {
          'type': 'open_miniapp',
          'miniappId': 'insurance',
          'params': {'product': 'travel'},
        }),
        const OpenMiniAppAction('insurance', params: {'product': 'travel'}),
      );
      expect(
        SduiAction.fromJson(const {
          'type': 'open_url',
          'url': 'https://bancointernacional.ec',
        }),
        OpenUrlAction(Uri.parse('https://bancointernacional.ec')),
      );
    });

    test('unknown or unsafe actions degrade to UnknownAction', () {
      expect(
        SduiAction.fromJson(const {'type': 'teleport'}),
        isA<UnknownAction>(),
      );
      expect(
        SduiAction.fromJson(const {'type': 'navigate', 'route': 'http://evil'}),
        isA<UnknownAction>(),
      );
      expect(
        SduiAction.fromJson(const {
          'type': 'open_url',
          'url': 'http://insecure.example',
        }),
        isA<UnknownAction>(),
      );
      expect(SduiAction.fromJson(null), isA<UnknownAction>());
    });
  });
}
