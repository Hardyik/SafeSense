import 'package:flutter/material.dart';

/// SafeSense brand color system (spec Section 25) — the single source of
/// truth for these values. main.dart's kPrimary/kDanger/etc. constants
/// point at these rather than duplicating hex codes, so changing a brand
/// color here propagates everywhere instead of requiring a find-and-replace
/// across a 2500+ line file.
class AppColors {
  AppColors._();

  static const Color deepNavy = Color(0xFF0B1F33);
  static const Color secondaryNavy = Color(0xFF163A5F);
  static const Color safetyCyan = Color(0xFF00B8D9);
  static const Color lightCyan = Color(0xFF67E8F9);
  static const Color safe = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color lightBg = Color(0xFFF4F8FB);
  static const Color darkBg = Color(0xFF071521);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color darkCard = Color(0xFF102536);
  static const Color mainTextLight = Color(0xFF102A43);
  static const Color mainTextDark = Color(0xFFE6F1F7);
  static const Color secondaryText = Color(0xFF64748B);
}

/// Brightness-aware surface/ink colors for the handful of places that
/// can't use ThemeData directly (raw Containers, overlays, borders).
/// Always prefer Theme.of(context) when a theme slot exists — reach for
/// these helpers only where a const Color was hardcoded before.
class AppSurfaces {
  AppSurfaces._();

  /// Card/container background in either mode.
  static Color card(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkCard
          : AppColors.lightCard;

  /// Page background in either mode (same value the Scaffold uses).
  static Color page(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkBg
          : AppColors.lightBg;

  /// Hairline border on cards/list tiles.
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade800
          : Colors.grey.shade200;

  /// Muted secondary text that stays readable in both modes.
  static Color secondaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade400
          : Colors.grey.shade600;
}

/// NOTE: kBg and kInk are legacy LIGHT-mode constants kept only because
/// older call sites still reference them. They do NOT flip in dark mode —
/// new code must use Theme.of(context).scaffoldBackgroundColor /
/// colorScheme.onSurface (or AppSurfaces) instead. Screens still using
/// kBg/kInk directly are being migrated to the theme-aware values.
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.lightBg,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.safetyCyan,
          brightness: Brightness.light,
          primary: AppColors.safetyCyan,
          secondary: AppColors.secondaryNavy,
          error: AppColors.danger,
          surface: AppColors.lightCard,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
              fontSize: 16, height: 1.4, color: AppColors.mainTextLight),
          bodyLarge: TextStyle(
              fontSize: 17, height: 1.4, color: AppColors.mainTextLight),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.safetyCyan,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size.fromHeight(58),
            textStyle:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.safetyCyan,
            minimumSize: const Size.fromHeight(58),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            side: const BorderSide(color: AppColors.safetyCyan, width: 1.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.safetyCyan, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cardTheme: CardThemeData(
          color: AppColors.lightCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkBg,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.safetyCyan,
          brightness: Brightness.dark,
          primary: AppColors.lightCyan,
          secondary: AppColors.secondaryNavy,
          error: AppColors.danger,
          surface: AppColors.darkCard,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
              fontSize: 16, height: 1.4, color: AppColors.mainTextDark),
          bodyLarge: TextStyle(
              fontSize: 17, height: 1.4, color: AppColors.mainTextDark),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkBg,
          foregroundColor: AppColors.mainTextDark,
          elevation: 0,
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.lightCyan,
            foregroundColor: AppColors.deepNavy,
            elevation: 0,
            minimumSize: const Size.fromHeight(58),
            textStyle:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.lightCyan,
            minimumSize: const Size.fromHeight(58),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            side: const BorderSide(color: AppColors.lightCyan, width: 1.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.lightCyan, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade800),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: AppColors.darkCard,
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.darkCard,
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.secondaryNavy,
          contentTextStyle: TextStyle(color: AppColors.mainTextDark),
        ),
      );
}
