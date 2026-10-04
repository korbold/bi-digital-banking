import 'package:flutter/material.dart';

/// Brand and spacing tokens. Features never hard-code colors or paddings;
/// they read these so a re-brand or a segment theme is a one-file change.
abstract final class BiColors {
  static const brand = Color(0xFFF07F09); // naranja institucional
  static const brandDark = Color(0xFFB85C00);
  static const ink = Color(0xFF1F2430);
  static const surface = Color(0xFFF7F7F9);
  static const positive = Color(0xFF1E8E3E);
  static const negative = Color(0xFFC5221F);
  static const warning = Color(0xFFB06000);
  static const info = Color(0xFF1A73E8);
}

abstract final class BiSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class BiRadius {
  static const card = BorderRadius.all(Radius.circular(16));
  static const chip = BorderRadius.all(Radius.circular(999));
}
