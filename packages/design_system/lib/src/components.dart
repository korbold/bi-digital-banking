import 'package:design_system/src/tokens.dart';
import 'package:flutter/material.dart';

/// Money formatting kept in one place: two decimals, thousands separator,
/// sign for movements. Avoids pulling intl into every package.
String formatMoney(num amount, {String currency = 'USD', bool signed = false}) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final symbol = currency == 'USD' ? r'$' : '$currency ';
  final sign = negative ? '-' : (signed ? '+' : '');
  return '$sign$symbol$intPart.${parts[1]}';
}

/// Amount with semantic color and an accessible label ("débito de 12 dólares").
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.currency = 'USD',
    this.signed = false,
    this.style,
  });

  final num amount;
  final String currency;
  final bool signed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = !signed
        ? null
        : (amount < 0 ? BiColors.negative : BiColors.positive);
    final text = formatMoney(amount, currency: currency, signed: signed);
    return Semantics(
      label: signed ? '${amount < 0 ? 'Débito' : 'Crédito'} de $text' : text,
      excludeSemantics: true,
      child: Text(
        text,
        style: (style ?? const TextStyle()).copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

enum BannerTone { info, warning, error }

/// Inline status banner used for degraded states: offline, stale data,
/// partial outage. Announced to screen readers as a live region.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    required this.message,
    super.key,
    this.tone = BannerTone.info,
    this.action,
    this.onAction,
  });

  final String message;
  final BannerTone tone;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (tone) {
      BannerTone.info => (BiColors.info, Icons.info_outline),
      BannerTone.warning => (BiColors.warning, Icons.cloud_off_outlined),
      BannerTone.error => (BiColors.negative, Icons.error_outline),
    };
    return Semantics(
      liveRegion: true,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BiRadius.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BiSpacing.md,
            vertical: BiSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: BiSpacing.sm),
              Expanded(
                child: Text(message, style: TextStyle(color: color)),
              ),
              if (action != null && onAction != null)
                TextButton(onPressed: onAction, child: Text(action!)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-area error with retry, for when there is no cached data to show.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(BiSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48),
          const SizedBox(height: BiSpacing.md),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: BiSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Shimmer-free skeleton block: cheap, respects reduced motion by default.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width = double.infinity,
  });

  final double height;
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Cargando',
    child: Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

/// Section title used across home and detail screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: BiSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
