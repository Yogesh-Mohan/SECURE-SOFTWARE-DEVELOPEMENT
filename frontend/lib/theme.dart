import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryEmergency = Color(0xFFE63946); // Emergency Red
  static const Color background = Color(0xFFF1FAEE); // Off-White
  static const Color accentLight = Color(0xFFA8DADC); // Light Blue
  static const Color accentMedium = Color(0xFF457B9D); // Steel Blue
  static const Color darkBlue = Color(0xFF1D3557); // Dark Grey/Prussian Blue
}

final ThemeData appTheme = ThemeData(
  primaryColor: AppColors.primaryEmergency,
  scaffoldBackgroundColor: AppColors.background,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.primaryEmergency,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryEmergency,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 50),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.bold),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primaryEmergency, width: 2),
    ),
  ),
);
