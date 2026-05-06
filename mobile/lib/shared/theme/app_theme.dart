import 'package:flutter/material.dart';

import 'kundi_tokens.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: KundiPalette.lightPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: KundiPalette.lightPrimary,
          secondary: KundiPalette.lightSecondary,
          error: KundiPalette.danger,
          surface: KundiPalette.lightSurface,
          onSurface: KundiPalette.lightTextPrimary,
        ),
        scaffoldBackgroundColor: KundiPalette.lightBackground,
        cardTheme: const CardThemeData(
          elevation: KundiElevation.card,
          shape: RoundedRectangleBorder(borderRadius: KundiRadius.md),
          margin: EdgeInsets.symmetric(
            horizontal: KundiSpace.sm,
            vertical: KundiSpace.xs,
          ),
        ),
        chipTheme: ChipThemeData(
          shape: const RoundedRectangleBorder(borderRadius: KundiRadius.pill),
          side: BorderSide.none,
          backgroundColor: KundiPalette.lightElevated,
          labelStyle: const TextStyle(fontSize: 12),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: KundiPalette.lightTextPrimary,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: KundiPalette.lightSurface,
          border: OutlineInputBorder(
            borderRadius: KundiRadius.sm,
            borderSide: BorderSide(color: KundiPalette.lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: KundiRadius.sm,
            borderSide: BorderSide(color: KundiPalette.lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: KundiRadius.sm,
            borderSide: BorderSide(color: KundiPalette.lightPrimary),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: KundiSpace.sm,
            vertical: KundiSpace.sm,
          ),
        ),
        useMaterial3: true,
      );

  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: KundiPalette.darkPrimary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: KundiPalette.darkPrimary,
          secondary: KundiPalette.darkSecondary,
          error: KundiPalette.danger,
          surface: KundiPalette.darkSurface,
          onSurface: KundiPalette.darkTextPrimary,
        ),
        scaffoldBackgroundColor: KundiPalette.darkBackground,
        cardTheme: CardThemeData(
          elevation: KundiElevation.raised,
          shape: const RoundedRectangleBorder(borderRadius: KundiRadius.md),
          margin: const EdgeInsets.symmetric(
            horizontal: KundiSpace.sm,
            vertical: KundiSpace.xs,
          ),
          color: KundiPalette.darkSurface,
        ),
        chipTheme: ChipThemeData(
          shape: const RoundedRectangleBorder(borderRadius: KundiRadius.pill),
          side: BorderSide.none,
          backgroundColor: KundiPalette.darkElevated,
          labelStyle: const TextStyle(fontSize: 12),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: KundiPalette.darkTextPrimary,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: KundiPalette.darkSurface,
          border: OutlineInputBorder(
            borderRadius: KundiRadius.sm,
            borderSide: BorderSide(color: KundiPalette.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: KundiRadius.sm,
            borderSide: BorderSide(color: KundiPalette.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: KundiRadius.sm,
            borderSide: BorderSide(color: KundiPalette.darkPrimary),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: KundiSpace.sm,
            vertical: KundiSpace.sm,
          ),
        ),
        useMaterial3: true,
      );
}
