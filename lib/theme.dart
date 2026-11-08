import 'package:flutter/material.dart';

const ink = Color(0xFF101114);
const panel = Color(0xFF1A1C21);
const panelHigh = Color(0xFF262A31);
const line = Color(0xFF31363E);
const brass = Color(0xFFD7A35A);
const ivory = Color(0xFFF6F3EC);
const muted = Color(0xFF8E8A82);
const danger = Color(0xFFE06A5C);
const okGreen = Color(0xFF2F9E6B);

class CinemaColors extends ThemeExtension<CinemaColors> {
  const CinemaColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.glass,
    required this.shadow,
    required this.dark,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color line;
  final Color glass;
  final Color shadow;
  final bool dark;

  static const light = CinemaColors(
    background: Color(0xFFE8E4DC),
    surface: Color(0xFFF7F4EE),
    text: Color(0xFF1B1916),
    muted: Color(0xFF6F6A62),
    line: Color(0xFFD9D3C8),
    glass: Color(0xBFFFFFFF),
    shadow: Color(0x22000000),
    dark: false,
  );

  static const night = CinemaColors(
    background: Color(0xFF101114),
    surface: Color(0xFF1C1E24),
    text: ivory,
    muted: Color(0xFFA39E93),
    line: Color(0xFF31363E),
    glass: Color(0x6614181E),
    shadow: Color(0x66000000),
    dark: true,
  );

  @override
  CinemaColors copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? muted,
    Color? line,
    Color? glass,
    Color? shadow,
    bool? dark,
  }) {
    return CinemaColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      glass: glass ?? this.glass,
      shadow: shadow ?? this.shadow,
      dark: dark ?? this.dark,
    );
  }

  @override
  CinemaColors lerp(ThemeExtension<CinemaColors>? other, double t) {
    if (other is! CinemaColors) return this;
    return CinemaColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      dark: t < 0.5 ? dark : other.dark,
    );
  }
}

extension CinemaContext on BuildContext {
  CinemaColors get cinema => Theme.of(this).extension<CinemaColors>() ?? CinemaColors.night;
}

ThemeData buildTheme([Brightness brightness = Brightness.dark]) {
  final darkMode = brightness == Brightness.dark;
  final cinema = darkMode ? CinemaColors.night : CinemaColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    surface: cinema.background,
    primary: darkMode ? ivory : const Color(0xFF1B1916),
    onPrimary: darkMode ? const Color(0xFF1B1916) : Colors.white,
    secondary: okGreen,
    onSecondary: Colors.white,
    error: danger,
    onError: Colors.white,
    onSurface: cinema.text,
  );
  final radius = BorderRadius.circular(16);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: cinema.background,
    extensions: [cinema],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: cinema.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    dividerColor: cinema.line,
    cardTheme: CardThemeData(
      color: cinema.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cinema.surface,
      labelStyle: TextStyle(color: cinema.muted),
      hintStyle: TextStyle(color: cinema.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cinema.line)),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cinema.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: okGreen, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: darkMode ? panelHigh : const Color(0xFF2A2723),
      contentTextStyle: const TextStyle(color: ivory),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: okGreen),
  );
}
