/// Light and dark themes based on the APH design palette.
library aph_mobile.core.theme;

import 'package:flutter/material.dart';
import 'package:aph_mobile/core/constants/app_constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.deepNavy,
      colorScheme: const ColorScheme.light(
        primary: AppColors.deepNavy,
        secondary: AppColors.medicalBlue,
        surface: AppColors.white,
        background: AppColors.softBackground,
        onPrimary: AppColors.white,
        onSurface: AppColors.deepNavy,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.softBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.deepNavy,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.medicalBlue,
          foregroundColor: AppColors.white,
        ),
      ),
      fontFamily: 'Tajawal',
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(borderSide: BorderSide.none),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppColors.deepNavy,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.deepNavy,
        secondary: AppColors.medicalBlue,
        surface: AppColors.deepNavy,
        background: Color(0xFF0B1B2B),
        onPrimary: AppColors.white,
        onSurface: AppColors.white,
        error: Color(0xFFFF6B6B),
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1B2B),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.deepNavy,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.medicalBlue,
          foregroundColor: AppColors.white,
        ),
      ),
      fontFamily: 'Tajawal',
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF16293D),
        border: OutlineInputBorder(borderSide: BorderSide.none),
      ),
    );
  }
}
