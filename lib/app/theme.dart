import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Light-only palette inspired by iOS / iPadOS system colors.
abstract final class AppColors {
  static const background = Color(0xFFF4F4F6);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111114);
  static const inkSecondary = Color(0xFF6E6E76);
  static const inkTertiary = Color(0xFFA9A9B0);
  static const hairline = Color(0x14000000);
  static const accent = Color(0xFFFF6B35); // makako orange
  static const accentSoft = Color(0xFFFFE6DC);
  static const green = Color(0xFF34C759);
  static const blue = Color(0xFF0A84FF);
  static const purple = Color(0xFF8E5CF7);
  static const paper = Color(0xFFFFFFFF);
  static const sepia = Color(0xFFF7F0E1);
}

abstract final class AppRadii {
  static const card = 22.0;
  static const cover = 10.0;
  static const pill = 999.0;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.ink,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: Color(0xFFFF3B30),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    // iOS-style navigation on every platform.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  final text = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

  return base.copyWith(
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      bodyMedium: text.bodyMedium?.copyWith(color: AppColors.ink, height: 1.35),
      bodySmall: text.bodySmall?.copyWith(color: AppColors.inkSecondary),
      labelSmall: text.labelSmall?.copyWith(color: AppColors.inkSecondary, letterSpacing: 0.2),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: AppColors.ink,
      centerTitle: true,
      // Transparent app bars would otherwise get light (invisible) status icons.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.ink,
      inactiveTrackColor: Color(0x1F000000),
      thumbColor: AppColors.ink,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      trackHeight: 3,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x0F000000),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      hintStyle: const TextStyle(color: AppColors.inkTertiary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    cupertinoOverrideTheme: const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.ink,
    ),
  );
}

/// Soft shadow used on floating elements (cards, nav bar, buttons).
const softShadow = [
  BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
];
