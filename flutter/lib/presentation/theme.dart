import 'package:flutter/material.dart';

import '../domain/layer.dart';

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

  // Ground type indicators, independent of editable outline colours.
  static const groundZone = Color(0xFF6B7280);
  static const groundFlat = Color(0xFFBF5700);
  static const groundRow = Color(0xFF98DFC2);
  static const groundGrow = Color(0xFF00875A);

  static const valid = Color(0xFF2E7D32);
  static const invalid = Color(0xFFC62828);
  static const hatch = Color(0xFFB8BCB4);

  // Growing calendars: one colour per kind of job.
  static const directSow = Color(0xFF3F8A4F);
  static const greenhouse = Color(0xFFB9822F);
  static const plantOut = Color(0xFF3C74A6);
  static const harvest = Color(0xFFC0583A);
  static const caution = Color(0xFFB7791F);
}

/// The outline colour used for a layer on the canvas and in Layers.
Color layerColor(Layer layer) => switch (layer.properties) {
  PropertyProperties p => Color(p.color.argb),
  ZoneProperties p => Color(p.color.argb),
};

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
