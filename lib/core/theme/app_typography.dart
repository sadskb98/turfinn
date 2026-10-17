import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Typography extracted from Figma.
/// Using Google Fonts as runtime substitutes:
///   Axiforma  → Nunito    (same rounded humanist feel)
///   Satoshi   → DM Sans   (same geometric neo-grotesque feel)
/// Drop in the real TTFs to assets/fonts/ and revert to fontFamily strings
/// once you have the Axiforma/Satoshi licenses.
abstract final class AppTypography {
  // --- Axiforma substitutes (headings / display) ---

  static TextStyle get heading24Bold => GoogleFonts.nunito(
        fontWeight: FontWeight.w700,
        fontSize: 24,
        height: 1.24,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      );

  static TextStyle get tagline12Regular => GoogleFonts.nunito(
        fontWeight: FontWeight.w400,
        fontSize: 12,
        height: 1.0,
        letterSpacing: 0.24,
        color: AppColors.primaryMid,
      );

  static TextStyle get label14Medium => GoogleFonts.nunito(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        height: 1.28,
        letterSpacing: -0.28,
        color: AppColors.primaryDeep,
      );

  // --- Satoshi substitutes (body / buttons / inputs) ---

  static TextStyle get body16Regular => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 16,
        height: 1.32,
        letterSpacing: 0,
        color: AppColors.textSecondary,
      );

  static TextStyle get body16Medium => GoogleFonts.dmSans(
        fontWeight: FontWeight.w500,
        fontSize: 16,
        height: 1.32,
        letterSpacing: -0.32,
        color: AppColors.primaryMid,
      );

  static TextStyle get buttonBold16 => GoogleFonts.dmSans(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        height: 1.32,
        letterSpacing: -0.32,
        color: AppColors.background,
      );

  static TextStyle get body14Regular => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        height: 1.32,
        letterSpacing: 0,
        color: AppColors.textSecondary,
      );

  static TextStyle get input16Medium => GoogleFonts.dmSans(
        fontWeight: FontWeight.w500,
        fontSize: 16,
        height: 1.35,
        letterSpacing: -0.32,
        color: AppColors.textMuted,
      );

  static TextStyle get logoText => GoogleFonts.nunito(
        fontWeight: FontWeight.w800,
        fontSize: 32,
        letterSpacing: 2,
        color: AppColors.primary,
      );
}
