import 'package:flutter/material.dart';

/// Shared visual tokens for the dark-only Habitex interface.
abstract final class HabitexColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceElevated = Color(0xFF2C2C2E);
  static const primary = Color(0xFF007AFF);
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFF9500);
  static const error = Color(0xFFFF6B63);
  static const errorSoft = Color(0xFFFFD9D7);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8E8E93);
}

abstract final class HabitexSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class HabitexRadii {
  static const compact = 12.0;
  static const card = 16.0;
  static const sheet = 22.0;
  static const pill = 999.0;
}

abstract final class HabitexText {
  static const body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const section = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
  static const button = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
}

ThemeData habitexDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: '.SF Pro Text',
    scaffoldBackgroundColor: HabitexColors.background,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: HabitexColors.primary,
      onPrimary: HabitexColors.textPrimary,
      secondary: HabitexColors.success,
      onSecondary: HabitexColors.textPrimary,
      error: HabitexColors.error,
      onError: HabitexColors.textPrimary,
      surface: HabitexColors.surface,
      onSurface: HabitexColors.textPrimary,
      surfaceContainerHighest: HabitexColors.surfaceElevated,
      onSurfaceVariant: HabitexColors.textSecondary,
    ),
    textTheme: Typography.whiteCupertino.apply(
      fontFamily: '.SF Pro Text',
      bodyColor: HabitexColors.textPrimary,
      displayColor: HabitexColors.textPrimary,
    ),
  );
}

extension HabitexColorsFromContext on BuildContext {
  Color get habitexDivider =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.08);

  Color get habitexSubtleBorder =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.12);
}
