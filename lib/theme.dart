import 'package:flutter/material.dart';

const ink = Color(0xFF0C0D10);
const panel = Color(0xFF17191E);
const panelHigh = Color(0xFF22262C);
const line = Color(0xFF31363E);
const brass = Color(0xFFD7A35A);
const ivory = Color(0xFFF4F0E6);
const muted = Color(0xFFA39E93);
const danger = Color(0xFFE06A5C);
const okGreen = Color(0xFF7EBF9A);

ThemeData buildTheme() {
  final scheme = const ColorScheme.dark(
    surface: ink,
    primary: brass,
    onPrimary: Color(0xFF1A1408),
    secondary: Color(0xFF8FB9A8),
    onSecondary: Color(0xFF10211B),
    error: danger,
    onError: ivory,
    onSurface: ivory,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: ink,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: ink,
      foregroundColor: ivory,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF121318),
      indicatorColor: brass.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    dividerColor: line,
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      labelStyle: const TextStyle(color: muted),
      hintStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: brass, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brass,
        foregroundColor: const Color(0xFF1A1408),
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: panelHigh,
      contentTextStyle: TextStyle(color: ivory),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: brass),
  );
}
