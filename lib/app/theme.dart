import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF0B1B3A);
  static const navyLight = Color(0xFF13285A);
  static const surface = Color(0xFF0F2148);
  static const card = Color(0xFF162B5C);
  static const gold = Color(0xFFF2B544);
  static const teal = Color(0xFF2ED3B7);
  static const red = Color(0xFFFF5D6C);
  static const muted = Color(0xFF9AA8C7);
  static const code = Color(0xFF07122A);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.gold,
    brightness: Brightness.dark,
    surface: AppColors.navy,
    primary: AppColors.gold,
    secondary: AppColors.teal,
    error: AppColors.red,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.navy,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.navy,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppColors.muted),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.surface,
      side: BorderSide.none,
      labelStyle: TextStyle(fontSize: 12),
    ),
  );
}
