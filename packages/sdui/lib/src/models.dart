import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Highest schema/section version this client knows how to render.
/// Sections with a higher `minAppVersion` are skipped.
const kSduiVersion = 1;

/// What happens when the user taps something rendered from the server.
sealed class SduiAction extends Equatable {
  const SduiAction();

  /// Unknown or malformed actions become [UnknownAction] instead of throwing,
  /// so a bad CTA disables one button, not the whole screen.
  factory SduiAction.fromJson(Object? json) {
    if (json is! Map) return const UnknownAction('missing');
    final type = json['type'];
    switch (type) {
      case 'navigate':
        final route = json['route'];
        return route is String && route.startsWith('/')
            ? NavigateAction(route)
            : const UnknownAction('navigate');
      case 'open_miniapp':
        final id = json['miniappId'];
        if (id is! String || id.isEmpty) {
          return const UnknownAction('open_miniapp');
        }
        final params = json['params'];
        return OpenMiniAppAction(
          id,
          params: params is Map
              ? params.map((k, v) => MapEntry('$k', v))
              : const {},
        );
      case 'open_url':
        final url = Uri.tryParse('${json['url']}');
        return url != null && url.scheme == 'https'
            ? OpenUrlAction(url)
            : const UnknownAction('open_url');
      default:
        return UnknownAction('$type');
    }
  }
}

final class NavigateAction extends SduiAction {
  const NavigateAction(this.route);
  final String route;

  @override
  List<Object?> get props => [route];
}

final class OpenMiniAppAction extends SduiAction {
  const OpenMiniAppAction(this.miniAppId, {this.params = const {}});
  final String miniAppId;
  final Map<String, Object?> params;

  @override
  List<Object?> get props => [miniAppId, params];
}

final class OpenUrlAction extends SduiAction {
  const OpenUrlAction(this.url);
  final Uri url;

  @override
  List<Object?> get props => [url];
}

final class UnknownAction extends SduiAction {
  const UnknownAction(this.type);
  final String type;

  @override
  List<Object?> get props => [type];
}

@immutable
class SduiSection extends Equatable {
  const SduiSection({
    required this.id,
    required this.type,
    this.properties = const {},
    this.minAppVersion = 1,
  });

  final String id;
  final String type;

  /// The section's `props` object from the payload.
  final Map<String, Object?> properties;
  final int minAppVersion;

  /// Returns null when the section is structurally invalid.
  static SduiSection? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final type = json['type'];
    if (id is! String || type is! String || id.isEmpty || type.isEmpty) {
      return null;
    }
    final props = json['props'];
    final min = json['minAppVersion'];
    return SduiSection(
      id: id,
      type: type,
      properties: props is Map
          ? props.map((k, v) => MapEntry('$k', v))
          : const {},
      minAppVersion: min is int ? min : 1,
    );
  }

  String? string(String key) {
    final v = properties[key];
    return v is String ? v : null;
  }

  List<Object?> list(String key) {
    final v = properties[key];
    return v is List ? v : const [];
  }

  @override
  List<Object?> get props => [id, type, properties, minAppVersion];
}

@immutable
class SduiScreen extends Equatable {
  const SduiScreen({
    required this.screen,
    required this.sections,
    this.schemaVersion = 1,
    this.segment,
    this.themeSeed,
    this.generatedAt,
    this.invalidSections = 0,
  });

  /// Tolerant parser: invalid sections are dropped and counted in
  /// [invalidSections]; only a non-object root throws [FormatException].
  factory SduiScreen.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('SDUI root must be an object');
    }
    final raw = json['sections'];
    final sections = <SduiSection>[];
    var invalid = 0;
    for (final item in raw is List ? raw : const []) {
      final section = SduiSection.tryParse(item);
      if (section == null) {
        invalid++;
      } else {
        sections.add(section);
      }
    }
    final theme = json['theme'];
    final seed = theme is Map ? theme['seed'] : null;
    return SduiScreen(
      screen: json['screen'] is String ? json['screen'] as String : 'unknown',
      schemaVersion: json['schemaVersion'] is int
          ? json['schemaVersion'] as int
          : 1,
      segment: json['segment'] is String ? json['segment'] as String : null,
      themeSeed: seed is String ? parseHexColor(seed) : null,
      generatedAt: DateTime.tryParse('${json['generatedAt']}'),
      sections: sections,
      invalidSections: invalid,
    );
  }

  final String screen;
  final int schemaVersion;
  final String? segment;
  final int? themeSeed;
  final DateTime? generatedAt;
  final List<SduiSection> sections;
  final int invalidSections;

  @override
  List<Object?> get props => [
    screen,
    schemaVersion,
    segment,
    themeSeed,
    generatedAt,
    sections,
    invalidSections,
  ];
}

/// Parses `#RRGGBB` / `#AARRGGBB` into an ARGB int, null if invalid.
int? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  return int.tryParse(h, radix: 16);
}
