import 'package:flutter/material.dart';

abstract final class SadhanaColors {
  static const background = Color(0xFFFAF7F2);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF2B2A28);
  static const inkSoft = Color(0xFF6E6A64);
  static const green = Color(0xFF3E5C2F);
  static const greenTint = Color(0xFFEDF0E6);
  static const gold = Color(0xFFB8894A);
  static const line = Color(0xFFEDE6DC);
  static const searchFill = Color(0xFFF7F0EB);
}

/// Serif used for display type. Georgia on iOS; the platform serif elsewhere.
TextStyle serif({
  double size = 16,
  Color? color,
  FontStyle? style,
  FontWeight? weight,
  double? height,
}) => TextStyle(
  fontFamily: 'Georgia',
  fontFamilyFallback: const ['Noto Serif', 'serif'],
  fontSize: size,
  color: color,
  fontStyle: style,
  fontWeight: weight,
  height: height,
);

ThemeData sadhanaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SadhanaColors.green,
    surface: SadhanaColors.background,
  );
  Color navColor(Set<WidgetState> states) =>
      states.contains(WidgetState.selected)
      ? SadhanaColors.green
      : SadhanaColors.inkSoft;

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: SadhanaColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: SadhanaColors.background,
      foregroundColor: SadhanaColors.ink,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SadhanaColors.surface,
      indicatorColor: Colors.transparent,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 13,
          color: navColor(states),
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: navColor(states), size: 28),
      ),
    ),
  );
}
