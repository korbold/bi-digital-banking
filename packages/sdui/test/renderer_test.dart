import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdui/sdui.dart';

void main() {
  late SduiRegistry registry;
  late List<(String, SkipReason)> skipped;
  late List<String> errored;
  late List<SduiAction> actions;

  setUp(() {
    registry = SduiRegistry();
    registerDefaults(registry);
    registry.register('boom', (_, _, _) => throw StateError('bad props'));
    skipped = [];
    errored = [];
    actions = [];
  });

  Future<void> pump(WidgetTester tester, Map<String, Object?> json) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SduiRenderer(
              screen: SduiScreen.fromJson(json),
              registry: registry,
              onAction: (action, {sourceSectionId}) => actions.add(action),
              onSkipped: (s, reason) => skipped.add((s.id, reason)),
              onSectionError: (s, _, _) => errored.add(s.id),
            ),
          ),
        ),
      );

  testWidgets('skips unknown types and newer sections, renders the rest', (
    tester,
  ) async {
    await pump(tester, {
      'sections': [
        {
          'id': 'g',
          'type': 'greeting',
          'props': {'title': 'Buenas tardes, Danny'},
        },
        {'id': 'u', 'type': 'hologram'},
        {
          'id': 'v',
          'type': 'text_card',
          'minAppVersion': 99,
          'props': {'title': 'Futuro'},
        },
        {
          'id': 't',
          'type': 'text_card',
          'props': {'title': 'Consejo', 'body': 'Ahorra'},
        },
      ],
    });

    expect(find.text('Buenas tardes, Danny'), findsOneWidget);
    expect(find.text('Consejo'), findsOneWidget);
    expect(find.text('Futuro'), findsNothing);
    expect(skipped, [
      ('u', SkipReason.unknownType),
      ('v', SkipReason.unsupportedVersion),
    ]);
  });

  testWidgets('a throwing section is isolated and reported', (tester) async {
    await pump(tester, {
      'sections': [
        {'id': 'bad', 'type': 'boom'},
        {
          'id': 't',
          'type': 'text_card',
          'props': {'title': 'Sigo vivo'},
        },
      ],
    });

    expect(tester.takeException(), isNull);
    expect(find.text('Sigo vivo'), findsOneWidget);
    expect(errored, ['bad']);
  });

  testWidgets('quick action tap dispatches the parsed action', (tester) async {
    await pump(tester, {
      'sections': [
        {
          'id': 'q',
          'type': 'quick_actions',
          'props': {
            'actions': [
              {
                'id': 'transfer',
                'label': 'Transferir',
                'icon': 'swap_horiz',
                'action': {'type': 'navigate', 'route': '/transfer'},
              },
            ],
          },
        },
      ],
    });

    await tester.tap(find.byKey(const ValueKey('quick-transfer')));
    expect(actions, [const NavigateAction('/transfer')]);
  });

  testWidgets('promo banner CTA meets the 48dp tap target guideline', (
    tester,
  ) async {
    await pump(tester, {
      'sections': [
        {
          'id': 'p',
          'type': 'promo_banner',
          'props': {
            'title': 'Viaja sin comisiones',
            'background': '#0B57D0',
            'cta': {
              'label': 'Ver más',
              'action': {'type': 'open_miniapp', 'miniappId': 'insurance'},
            },
          },
        },
      ],
    });

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.tap(find.text('Ver más'));
    expect(actions.single, const OpenMiniAppAction('insurance'));
  });
}
