import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cycl0ps colors. Each color has one meaning (see CLAUDE.md, section 4).
class BB {
  static const ground = Color(0xFFF5F4F0); // page background
  static const ink = Color(0xFF1C1F24); // text, dark cards
  static const muted = Color(0xFF4B5160); // secondary text
  static const line = Color(0xFFE2E3E6); // borders
  static const accent = Color(0xFFC2410C); // hazards, main action
  static const hazardSoft = Color(0xFFFFF7ED);
  static const safe = Color(0xFF15803D);
  static const safeSoft = Color(0xFFDCFCE7);
  static const help = Color(0xFFF97316);
  static const helpText = Color(0xFF431407);
  static const noAnswer = Color(0xFF7F1D1D);
  static const danger = Color(0xFFB91C1C);
  static const exit = Color(0xFF1D4ED8);
  static const exitSoft = Color(0xFFDBEAFE);
  static const white = Color(0xFFFFFFFF);
}

/// Space Grotesk, for headings and big numbers.
TextStyle heading(double size, {Color color = BB.ink, FontWeight weight = FontWeight.w700}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight, color: color, height: 1.05);

/// Inter, for body text.
TextStyle body(double size, {Color color = BB.ink, FontWeight weight = FontWeight.w400}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: 1.35);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: BB.ground,
    colorScheme: ColorScheme.fromSeed(seedColor: BB.accent).copyWith(
      primary: BB.accent,
      surface: BB.ground,
      onSurface: BB.ink,
      error: BB.danger,
    ),
  );
  return base.copyWith(
    // Inter for all normal text. (google_fonts 9 has its own TextTheme type, so we
    // only take the font family name from it.)
    textTheme: base.textTheme.apply(
        fontFamily: GoogleFonts.inter().fontFamily, bodyColor: BB.ink, displayColor: BB.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: BB.ground,
      foregroundColor: BB.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: heading(20),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BB.white,
      hintStyle: body(16, color: const Color(0xFF9AA0AC)), // lighter than typed text
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BB.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BB.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BB.ink, width: 2),
      ),
    ),
  );
}

/// White card with a thin border, used across screens.
BoxDecoration cardBox({Color color = BB.white, Color border = BB.line}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border),
    );
