import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sdui/src/models.dart';
import 'package:sdui/src/registry.dart';

enum SkipReason { unknownType, unsupportedVersion }

typedef SduiSkippedCallback =
    void Function(SduiSection section, SkipReason reason);
typedef SduiErrorCallback =
    void Function(SduiSection section, Object error, StackTrace stackTrace);

/// Builds the list of renderable sections and wraps each one in an error
/// boundary, so one broken section never takes down the whole screen.
class SduiRenderer extends StatelessWidget {
  const SduiRenderer({
    required this.screen,
    required this.registry,
    required this.onAction,
    super.key,
    this.onSkipped,
    this.onSectionError,
    this.padding = const EdgeInsets.all(BiSpacing.md),
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.header,
  });

  final SduiScreen screen;
  final SduiRegistry registry;
  final SduiActionHandler onAction;
  final SduiSkippedCallback? onSkipped;
  final SduiErrorCallback? onSectionError;
  final EdgeInsets padding;
  final ScrollPhysics physics;

  /// Optional widget pinned above the sections (e.g. stale-data banner).
  final Widget? header;

  /// Sections that will actually render, in order. Reports skipped ones.
  List<SduiSection> resolveSections() {
    final visible = <SduiSection>[];
    for (final section in screen.sections) {
      if (section.minAppVersion > kSduiVersion) {
        onSkipped?.call(section, SkipReason.unsupportedVersion);
      } else if (!registry.supports(section.type)) {
        onSkipped?.call(section, SkipReason.unknownType);
      } else {
        visible.add(section);
      }
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final sections = resolveSections();
    return ListView.separated(
      padding: padding,
      physics: physics,
      itemCount: sections.length + (header == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: BiSpacing.md),
      itemBuilder: (context, index) {
        if (header != null && index == 0) return header;
        final sectionIndex = header == null ? index : index - 1;
        final section = sections[sectionIndex];
        return KeyedSubtree(
          key: ValueKey('sdui-${section.id}'),
          child: SduiSectionBoundary(
            section: section,
            onError: onSectionError,
            builder: (context) =>
                registry.builderFor(section.type)!(context, section, onAction),
          ),
        );
      },
    );
  }
}

/// Catches exceptions thrown while *building* a section and renders nothing
/// in its place. (Layout/paint errors are still reported by Flutter's
/// global handler, which the app wires to Crashlytics.)
class SduiSectionBoundary extends StatelessWidget {
  const SduiSectionBoundary({
    required this.section,
    required this.builder,
    super.key,
    this.onError,
  });

  final SduiSection section;
  final WidgetBuilder builder;
  final SduiErrorCallback? onError;

  @override
  Widget build(BuildContext context) {
    try {
      return builder(context);
    } on Object catch (error, stackTrace) {
      onError?.call(section, error, stackTrace);
      return const SizedBox.shrink();
    }
  }
}
