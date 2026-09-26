import 'package:flutter/material.dart';

/// The app's colours. Chrome is a quiet neutral grey so the drawing stands
/// out; green is kept for the accent and for land.
abstract final class Palette {
  // Text.
  static const ink = Color(0xFF1F2328);
  static const muted = Color(0xFF6B7280);
  static const faint = Color(0xFF9CA3AF);

  // Surfaces, from the window frame inwards.
  static const chrome = Color(0xFFF1F2F4);
  static const paper = Color(0xFFFFFFFF);
  static const field = Color(0xFFF3F4F6);

  // Lines and states.
  static const rule = Color(0xFFE3E5E8);
  static const panelBorder = Color(0xFFD9DCE1);
  static const hover = Color(0xFFEDEFF2);
  static const accent = Color(0xFF2F6B3F);
  static const wash = Color(0xFFE6F0E8);

  // Drawing.
  static const canvas = Color(0xFFF7F8F5);

  /// Outline colour for areas, which have no colour setting.
  static const area = Color(0xFF6B7F4F);
  static const valid = Color(0xFF2E7D32);
  static const invalid = Color(0xFFC62828);
  static const hatch = Color(0xFFB8BCB4);
}

/// Sizes shared across the screen, in logical pixels.
abstract final class Metrics {
  static const headerHeight = 44.0;
  static const statusHeight = 26.0;
  static const railWidth = 40.0;
  static const radius = 6.0;
}

/// Small caps-style heading used for panel and group titles.
const sectionTitleStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.6,
  color: Palette.muted,
);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.accent,
      primary: Palette.accent,
      surface: Palette.paper,
      onSurface: Palette.ink,
    ),
    scaffoldBackgroundColor: Palette.chrome,
    visualDensity: VisualDensity.compact,
  );
  final radius = BorderRadius.circular(Metrics.radius);
  return base.copyWith(
    dividerColor: Palette.rule,
    dividerTheme: const DividerThemeData(
      color: Palette.rule,
      space: 1,
      thickness: 1,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Palette.ink,
      displayColor: Palette.ink,
    ),
    iconTheme: const IconThemeData(color: Palette.ink, size: 18),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Palette.field,
      hoverColor: Palette.hover,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Palette.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Palette.invalid),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 13),
      ),
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Palette.paper),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        textStyle: const TextStyle(fontSize: 13),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Palette.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
      decoration: BoxDecoration(
        color: Palette.ink.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Palette.accent
            : Palette.panelBorder,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
