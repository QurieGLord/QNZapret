import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF0F7C70);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      primary: isDark ? const Color(0xFF6AE0D0) : _seed,
      secondary: isDark ? const Color(0xFF95CAFF) : const Color(0xFF1F5A86),
      tertiary: isDark ? const Color(0xFFFFB37E) : const Color(0xFFF06A3F),
      surface: isDark ? const Color(0xFF0A1418) : const Color(0xFFFFFBF5),
    );

    final textTheme =
        (isDark
                ? Typography.material2021().white
                : Typography.material2021().black)
            .apply(
              bodyColor: isDark
                  ? const Color(0xFFE2F2EE)
                  : const Color(0xFF193037),
              displayColor: isDark ? Colors.white : const Color(0xFF122227),
              fontFamily: 'Manrope',
            );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF071014)
          : const Color(0xFFF4F3ED),
      fontFamily: 'Manrope',
      textTheme: textTheme.copyWith(
        displayMedium: textTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark
            ? const Color(0xFF112126).withValues(alpha: 0.82)
            : Colors.white.withValues(alpha: 0.76),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: BorderSide(
            color: isDark ? const Color(0xFF25424A) : const Color(0xFFDFE7DF),
          ),
        ),
        margin: EdgeInsets.zero,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF102228).withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.92),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF29454C) : const Color(0xFFD6E1D8),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF29454C) : const Color(0xFFD6E1D8),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFFB9D6D1) : const Color(0xFF4A6163),
        ),
        helperStyle: TextStyle(
          color: isDark ? const Color(0xFF7EA29B) : const Color(0xFF6B7E7F),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          backgroundColor: scheme.primary,
          foregroundColor: isDark ? const Color(0xFF06211E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide(
            color: isDark ? const Color(0xFF355860) : const Color(0xFFD6E1D8),
          ),
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.02)
              : Colors.white.withValues(alpha: 0.55),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: scheme.primary.withValues(alpha: 0.4));
            }
            return BorderSide(
              color: isDark ? const Color(0xFF355860) : const Color(0xFFD6E1D8),
            );
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12);
            }
            return isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.6);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return isDark ? const Color(0xFFD5ECE7) : const Color(0xFF355258);
          }),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return isDark ? const Color(0xFF9FB8B1) : const Color(0xFF5E7474);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.34);
          }
          return isDark ? const Color(0xFF22373C) : const Color(0xFFE4D5C4);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerColor: isDark ? const Color(0xFF1E373D) : const Color(0xFFDCE4DD),
    );
  }
}
