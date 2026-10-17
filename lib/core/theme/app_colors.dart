import 'package:flutter/material.dart';

/// Turfinn brand palette — derived from the wordmark logo.
///
/// Anchors (source-of-truth):
///   primary   = #E7FF2A  (electric yellow CTA — the "T" mark color)
///   secondary = #022026  (dark teal canvas — the logo backdrop)
///
/// Everything else is a tonal step from these two so the palette stays
/// coherent across the player app, manager web, and super-admin web.
abstract final class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF022026); // canvas (logo backdrop)
  static const Color surfaceDark = Color(0xFF033640); // raised card / sidebar

  // Brand yellows
  static const Color primary = Color(0xFFE7FF2A);    // primary action / CTA fill
  static const Color primaryMid = Color(0xFFC8DC10); // mid-yellow (tagline, icons)
  static const Color primaryDark = Color(0xFF6E7B00); // deep olive (hover, glow base, border indicator)
  static const Color primaryDeep = Color(0xFF04404A); // deepest dark-teal (dividers, strokes)

  // Text — kept neutral for contrast on the new dark-teal canvas
  static const Color textPrimary = Color(0xFFE6E7E7);   // headings / body on dark
  static const Color textSecondary = Color(0xFF8B9191); // subtitle / helper
  static const Color textMuted = Color(0xFFB1B5B5);     // placeholder / muted
  static const Color textDisabled = Color(0xFF353F3F);  // disabled state

  // Overlay / glow
  static const Color glowBase = Color(0xFF6E7B00);    // 10% opacity glow orb fill
  static const Color glowInner = Color(0xFFE7FF2A);   // inner ellipse of glow

  // Input
  static const Color inputFill = Color(0x0DE7FF2A);   // 5% yellow tint on input bg
  static const Color inputStroke = Color(0xFF04404A); // input border

  // System
  static const Color bottomIndicator = Color(0xFF033640);

  // White / transparent helpers
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);
}
