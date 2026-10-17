import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_typography.dart';

final class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.background,
        secondary: AppColors.primaryMid,
        onSecondary: AppColors.white,
        surface: AppColors.surfaceDark,
        onSurface: AppColors.textPrimary,
        error: Color(0xFFD84040),
        onError: AppColors.white,
      ),
      textTheme: TextTheme(
        displayLarge: AppTypography.heading24Bold,
        bodyLarge: AppTypography.body16Regular,
        bodyMedium: AppTypography.body14Regular,
        labelLarge: AppTypography.buttonBold16,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: AppColors.inputStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: AppColors.inputStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      useMaterial3: true,
    );
  }
}
