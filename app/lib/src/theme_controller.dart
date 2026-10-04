import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Holds the brand seed color; the server may tint the app per segment
/// (e.g. premium) through the SDUI `theme.seed` field.
class ThemeController extends ValueNotifier<Color> {
  ThemeController() : super(BiColors.brand);

  void applySeed(int? argb) =>
      value = argb == null ? BiColors.brand : Color(argb);
}
