import 'package:design_system/src/tokens.dart';
import 'package:flutter/material.dart';

/// Material 3 theme seeded from the brand color. `seed` lets the
/// personalization layer tint the app per segment (e.g. premium) without
/// shipping a new build.
abstract final class BiTheme {
  static ThemeData light({Color seed = BiColors.brand}) => _build(
    ColorScheme.fromSeed(seedColor: seed, primary: seed),
  );

  static ThemeData dark({Color seed = BiColors.brand}) => _build(
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
  );

  static ThemeData _build(ColorScheme scheme) => ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BiRadius.card),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    ),
  );
}
