import 'package:flutter/widgets.dart';
import 'package:sdui/src/models.dart';

/// Supplied by the app shell: resolves an [SduiAction] (navigation, opening
/// a micro-app, external URL). Keeps this package free of routing deps.
typedef SduiActionHandler =
    void Function(SduiAction action, {String? sourceSectionId});

typedef SduiSectionBuilder =
    Widget Function(
      BuildContext context,
      SduiSection section,
      SduiActionHandler onAction,
    );

/// Maps section `type` -> builder. Domains register their own native
/// sections (e.g. feature_accounts registers `account_summary`), so the home
/// screen composes widgets owned by independent teams.
class SduiRegistry {
  final Map<String, SduiSectionBuilder> _builders = {};

  void register(String type, SduiSectionBuilder builder) =>
      _builders[type] = builder;

  bool supports(String type) => _builders.containsKey(type);

  SduiSectionBuilder? builderFor(String type) => _builders[type];

  Iterable<String> get types => _builders.keys;
}
