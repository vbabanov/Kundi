import 'package:flutter/material.dart';

class KundiSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
}

class KundiRadius {
  static const BorderRadius sm = BorderRadius.all(Radius.circular(10));
  static const BorderRadius md = BorderRadius.all(Radius.circular(14));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(20));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class KundiElevation {
  static const double card = 1.0;
  static const double raised = 3.0;
}

class KundiTypography {
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );
}

class KundiPalette {
  static const Color darkBackground = Color(0xFF1A0F2E);
  static const Color darkSurface = Color(0xFF2D1B4E);
  static const Color darkElevated = Color(0xFF3D2C5E);
  static const Color darkBorder = Color(0xFF4A3B6B);
  static const Color darkPrimary = Color(0xFF9B7ED8);
  static const Color darkSecondary = Color(0xFF6B5B95);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFB8A9D9);
  static const Color darkTextTertiary = Color(0xFF7A6B9E);

  static const Color lightBackground = Color(0xFFF7F3FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFEFE7FF);
  static const Color lightBorder = Color(0xFFDED2F5);
  static const Color lightPrimary = Color(0xFF7C5CCB);
  static const Color lightSecondary = Color(0xFFA68BE8);
  static const Color lightTextPrimary = Color(0xFF1A0F2E);
  static const Color lightTextSecondary = Color(0xFF5F527A);
  static const Color lightTextTertiary = Color(0xFF8E82A8);

  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color danger = Color(0xFFF44336);
}

extension KundiColorSchemeX on ColorScheme {
  bool get isDarkKundi => brightness == Brightness.dark;

  Color get kundiBackground =>
      isDarkKundi ? KundiPalette.darkBackground : KundiPalette.lightBackground;

  Color get kundiSurface =>
      isDarkKundi ? KundiPalette.darkSurface : KundiPalette.lightSurface;

  Color get kundiElevated =>
      isDarkKundi ? KundiPalette.darkElevated : KundiPalette.lightElevated;

  Color get kundiBorder =>
      isDarkKundi ? KundiPalette.darkBorder : KundiPalette.lightBorder;

  Color get kundiTextSecondary => isDarkKundi
      ? KundiPalette.darkTextSecondary
      : KundiPalette.lightTextSecondary;

  Color get kundiTextTertiary => isDarkKundi
      ? KundiPalette.darkTextTertiary
      : KundiPalette.lightTextTertiary;
}
