import 'package:flutter/material.dart';

// Design tokens. Keep these flat and stupid — three sizes per axis is enough
// for a single-developer course project; resist the urge to add semantic
// aliases (cardRadius / dialogRadius / etc.) until two callers actually need
// the same alias.
class AppRadius {
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppDuration {
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 500);
}

const Color _seedColor = Color(0xFF2E7D32);

ThemeData buildLightTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
  useMaterial3: true,
);

ThemeData buildDarkTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
);
