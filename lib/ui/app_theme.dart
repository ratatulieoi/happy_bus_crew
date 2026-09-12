import 'package:flutter/material.dart';

/// Shared colors and sizing for the crew app. No network fonts are required.
abstract final class AppColors {
  static const brand = Color(0xFFBC1535);
  static const ink = Color(0xFF20252B);
  static const muted = Color(0xFF667078);
  static const canvas = Color(0xFFF5F5F3);
  static const border = Color(0xFFE3E5E6);
  static const success = Color(0xFF217454);
  static const successSoft = Color(0xFFEAF5EF);
  static const warning = Color(0xFF925B08);
  static const warningSoft = Color(0xFFFFF3DC);
  static const danger = Color(0xFFB32636);
  static const dangerSoft = Color(0xFFFCECEF);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
    surface: Colors.white,
  ).copyWith(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.muted,
    outlineVariant: AppColors.border,
    error: AppColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  const rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: base.textTheme.copyWith(
      headlineLarge: const TextStyle(
          fontSize: 32,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: AppColors.ink),
      headlineMedium: const TextStyle(
          fontSize: 26,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: -.6,
          color: AppColors.ink),
      titleLarge: const TextStyle(
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: AppColors.ink),
      titleMedium: const TextStyle(
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: AppColors.ink),
      bodyLarge:
          const TextStyle(fontSize: 16, height: 1.5, color: AppColors.ink),
      bodyMedium:
          const TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink),
      bodySmall:
          const TextStyle(fontSize: 12, height: 1.45, color: AppColors.muted),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFAFAF9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5)),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: rounded),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          side: const BorderSide(color: AppColors.border),
          shape: rounded,
          foregroundColor: AppColors.ink),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: const BorderSide(color: AppColors.border),
      shape: const StadiumBorder(),
      selectedColor: const Color(0xFFFCECEF),
      labelStyle: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    dividerTheme: const DividerThemeData(
        color: AppColors.border, thickness: 1, space: 24),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.brand),
    dialogTheme: const DialogTheme(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24))),
        backgroundColor: Colors.white),
  );
}
