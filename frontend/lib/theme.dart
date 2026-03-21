import 'package:flutter/material.dart';

class AppColors {
  // Exact colors from the reference image
  static const Color primaryRed = Color(0xFFD90429);     // Vibrant Emergency Red
  static const Color primaryBlue = Color(0xFF003566);    // Deep Clinical Blue
  static const Color accentBlue = Color(0xFF0077B6);     // Bright Navigation Blue
  static const Color background = Color(0xFFFFFFFF);    // Pure White
  static const Color surfaceCard = Color(0xFFF8F9FA);   // Very Light Grey Card
  static const Color borderLight = Color(0xFFE9ECEF);   // Subtle Border
  
  static const Color textPrimary = Color(0xFF212529);   // Near Black
  static const Color textSecondary = Color(0xFF6C757D); // Slate Grey
  static const Color error = Color(0xFFD90429);         // Red for errors
  static const Color success = Color(0xFF2B9348);       // Green for success
}

final ThemeData medicalTheme = ThemeData(
  brightness: Brightness.light,
  primaryColor: AppColors.primaryRed,
  scaffoldBackgroundColor: AppColors.background,
  fontFamily: 'Roboto',
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    ),
    iconTheme: IconThemeData(color: AppColors.textPrimary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryRed,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 54),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 16,
        letterSpacing: 0.5,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primaryBlue,
      side: const BorderSide(color: AppColors.primaryBlue, width: 2),
      minimumSize: const Size(double.infinity, 54),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceCard,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.borderLight),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.borderLight),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
    ),
    labelStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
    hintStyle: const TextStyle(color: AppColors.textSecondary),
    prefixIconColor: AppColors.primaryBlue,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 32,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
    ),
    headlineMedium: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 24,
      fontWeight: FontWeight.w800,
    ),
    bodyLarge: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 16,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      color: AppColors.textSecondary,
      fontSize: 14,
    ),
  ),
);
