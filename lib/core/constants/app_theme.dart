import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract class AppTheme {
  // ── Dark theme (default) ────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: AppColors.primaryContainer,
          onPrimaryContainer: AppColors.primaryLight,
          secondary: AppColors.secondary,
          onSecondary: Colors.white,
          error: AppColors.error,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.cardDark,
        ),
        scaffoldBackgroundColor: AppColors.backgroundDark,
        // ── AppBar ──────────────────────────────────────────────────────────
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surfaceDark,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: AppColors.textPrimary),
        ),
        // ── Cards ────────────────────────────────────────────────────────────
        cardTheme: CardThemeData(
          color: AppColors.cardDark,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.borderDark),
          ),
        ),
        // ── Navigation Rail ─────────────────────────────────────────────────
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: AppColors.surfaceDark,
          indicatorColor: AppColors.primaryContainer,
          selectedIconTheme: IconThemeData(color: AppColors.primaryLight),
          unselectedIconTheme: IconThemeData(color: AppColors.textSecondary),
          selectedLabelTextStyle: TextStyle(color: AppColors.primaryLight, fontSize: 12),
          unselectedLabelTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        // ── Navigation Bar (mobile) ──────────────────────────────────────────
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surfaceDark,
          indicatorColor: AppColors.primaryContainer,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: AppColors.primaryLight);
            }
            return const IconThemeData(color: AppColors.textSecondary);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(color: AppColors.primaryLight, fontSize: 11);
            }
            return const TextStyle(color: AppColors.textSecondary, fontSize: 11);
          }),
        ),
        // ── Buttons ──────────────────────────────────────────────────────────
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.borderDark,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        // ── Inputs ───────────────────────────────────────────────────────────
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cardDark,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.borderDark),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.borderDark),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          hintStyle: const TextStyle(color: AppColors.textDisabled, fontSize: 13),
        ),
        // ── Divider ──────────────────────────────────────────────────────────
        dividerTheme: const DividerThemeData(
          color: AppColors.borderDark,
          thickness: 1,
          space: 1,
        ),
        // ── Chip ─────────────────────────────────────────────────────────────
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.cardDark,
          selectedColor: AppColors.primaryContainer,
          labelStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          side: const BorderSide(color: AppColors.borderDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        // ── Snackbar ─────────────────────────────────────────────────────────
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.cardDark,
          contentTextStyle: const TextStyle(color: AppColors.textPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
        // ── Dialog ───────────────────────────────────────────────────────────
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderDark),
          ),
          titleTextStyle: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        // ── Tooltip ──────────────────────────────────────────────────────────
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.borderDark),
          ),
          textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
      );

  // ── Light theme ─────────────────────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.backgroundLight,
        cardTheme: CardThemeData(
          color: AppColors.surfaceLight,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.borderLight),
          ),
        ),
      );
}
