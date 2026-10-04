import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sdui/src/models.dart';
import 'package:sdui/src/registry.dart';

/// Icon names the server may send. Unknown names fall back to a neutral icon.
const sduiIcons = <String, IconData>{
  'swap_horiz': Icons.swap_horiz,
  'shield': Icons.shield_outlined,
  'payments': Icons.payments_outlined,
  'savings': Icons.savings_outlined,
  'credit_card': Icons.credit_card,
  'qr_code': Icons.qr_code_2,
  'receipt': Icons.receipt_long_outlined,
  'flight': Icons.flight_takeoff,
  'phone': Icons.phone_iphone,
  'currency_exchange': Icons.currency_exchange,
  'support': Icons.support_agent,
  'notifications': Icons.notifications_outlined,
  'lightbulb': Icons.lightbulb_outline,
  'trending_down': Icons.trending_down,
  'trending_up': Icons.trending_up,
  'shopping_cart': Icons.shopping_cart_outlined,
  'restaurant': Icons.restaurant_outlined,
};

IconData sduiIcon(String? name) => sduiIcons[name] ?? Icons.apps;

/// Registers the presentation-only sections owned by the SDUI engine.
void registerDefaults(SduiRegistry registry) {
  registry
    ..register(
      'greeting',
      (context, section, _) => GreetingSection(section: section),
    )
    ..register(
      'quick_actions',
      (context, section, onAction) =>
          QuickActionsSection(section: section, onAction: onAction),
    )
    ..register(
      'promo_banner',
      (context, section, onAction) =>
          PromoBannerSection(section: section, onAction: onAction),
    )
    ..register(
      'text_card',
      (context, section, _) => TextCardSection(section: section),
    )
    ..register(
      'spending_insight',
      (context, section, _) => SpendingInsightSection(section: section),
    );
}

class GreetingSection extends StatelessWidget {
  const GreetingSection({required this.section, super.key});

  final SduiSection section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitle = section.string('subtitle');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            section.string('title') ?? 'Hola',
            style: text.headlineSmall,
          ),
        ),
        if (subtitle != null) Text(subtitle, style: text.bodyMedium),
      ],
    );
  }
}

class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({
    required this.section,
    required this.onAction,
    super.key,
  });

  final SduiSection section;
  final SduiActionHandler onAction;

  @override
  Widget build(BuildContext context) {
    final actions = section
        .list('actions')
        .whereType<Map<Object?, Object?>>()
        .toList();
    if (actions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: BiSpacing.sm,
      runSpacing: BiSpacing.sm,
      children: [
        for (final a in actions)
          SizedBox(
            width: 84,
            child: Semantics(
              button: true,
              label: '${a['label'] ?? ''}',
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('quick-${a['id']}'),
                borderRadius: BiRadius.card,
                onTap: () => onAction(
                  SduiAction.fromJson(a['action']),
                  sourceSectionId: section.id,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: BiSpacing.sm),
                    child: Column(
                      children: [
                        CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: Icon(sduiIcon(a['icon'] as String?)),
                        ),
                        const SizedBox(height: BiSpacing.xs),
                        Text(
                          '${a['label'] ?? ''}',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PromoBannerSection extends StatelessWidget {
  const PromoBannerSection({
    required this.section,
    required this.onAction,
    super.key,
  });

  final SduiSection section;
  final SduiActionHandler onAction;

  @override
  Widget build(BuildContext context) {
    final bgValue = parseHexColor(section.string('background'));
    final background = bgValue == null
        ? Theme.of(context).colorScheme.primary
        : Color(bgValue);
    // Pick readable foreground for whatever color the server sends (contrast).
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : BiColors.ink;
    final cta = section.properties['cta'];
    final ctaMap = cta is Map ? cta : null;
    final body = section.string('body');
    return Material(
      color: background,
      borderRadius: BiRadius.card,
      child: Padding(
        padding: const EdgeInsets.all(BiSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                section.string('title') ?? '',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: foreground),
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: BiSpacing.xs),
              Text(body, style: TextStyle(color: foreground)),
            ],
            if (ctaMap != null) ...[
              const SizedBox(height: BiSpacing.sm),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: foreground,
                  side: BorderSide(color: foreground),
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () => onAction(
                  SduiAction.fromJson(ctaMap['action']),
                  sourceSectionId: section.id,
                ),
                child: Text('${ctaMap['label'] ?? 'Ver más'}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TextCardSection extends StatelessWidget {
  const TextCardSection({required this.section, super.key});

  final SduiSection section;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.lightbulb_outline),
      title: Text(section.string('title') ?? ''),
      subtitle: Text(section.string('body') ?? ''),
    ),
  );
}

class SpendingInsightSection extends StatelessWidget {
  const SpendingInsightSection({required this.section, super.key});

  final SduiSection section;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: Icon(sduiIcon(section.string('icon') ?? 'trending_down')),
      title: Text(section.string('title') ?? 'Tus gastos'),
      subtitle: Text(section.string('body') ?? ''),
    ),
  );
}
