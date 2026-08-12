import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class EncbaColors {
  static const snuBlue = Color(0xFF00539B);
  static const deepBlue = Color(0xFF123A72);
  static const navy = Color(0xFF0B2347);
  static const ink = Color(0xFF171A20);
  static const muted = Color(0xFF6D727C);
  static const canvas = Color(0xFFF5F7FA);
  static const paper = Color(0xFFFFFFFF);
  static const line = Color(0xFFE2E6EC);
  static const attending = Color(0xFF167A50);
  static const late = Color(0xFFE28A12);
  static const absent = Color(0xFFCC3B46);
  static const undecided = Color(0xFF697080);
  static const highlight = Color(0xFFEEF4FA);
  static const timeMarker = Color(0xFFBFE3FF);
  static const placeMarker = Color(0xFFFFED72);
}

String encbaFontFor(String text, {bool display = false}) {
  final hasKorean = RegExp(r'[가-힣]').hasMatch(text);
  if (hasKorean) return 'Jua';
  return display ? 'BlackHanSans' : 'Arial';
}

class AppTheme {
  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Jua',
      colorScheme: const ColorScheme.light(
        primary: EncbaColors.snuBlue,
        onPrimary: Colors.white,
        secondary: EncbaColors.deepBlue,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: EncbaColors.ink,
        error: EncbaColors.absent,
      ),
    );
    final text = base.textTheme.copyWith(
      displaySmall: const TextStyle(
        fontFamily: 'Jua',
        fontSize: 34,
        height: 1.12,
        color: EncbaColors.navy,
      ),
      headlineLarge: const TextStyle(
        fontFamily: 'Jua',
        fontSize: 30,
        height: 1.1,
        color: EncbaColors.navy,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'Jua',
        fontSize: 25,
        height: 1.15,
        color: EncbaColors.navy,
      ),
      titleLarge: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: EncbaColors.ink,
      ),
      titleMedium: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: EncbaColors.ink,
      ),
      bodyLarge: const TextStyle(fontSize: 16, height: 1.55),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );

    return base.copyWith(
      scaffoldBackgroundColor: EncbaColors.canvas,
      textTheme: text,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: EncbaColors.canvas,
        foregroundColor: EncbaColors.navy,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: EncbaColors.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: EncbaColors.line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.white,
        indicatorColor: EncbaColors.highlight,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? EncbaColors.deepBlue
                : EncbaColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? EncbaColors.deepBlue
                : EncbaColors.muted,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: EncbaColors.muted),
        hintStyle: const TextStyle(color: Color(0xFFA1A5AD)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: EncbaColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: EncbaColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: EncbaColors.snuBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: EncbaColors.absent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          backgroundColor: EncbaColors.snuBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          side: const BorderSide(color: EncbaColors.line),
          foregroundColor: EncbaColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? EncbaColors.navy
                : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : EncbaColors.ink,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: EncbaColors.navy),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: 'Jua', fontSize: 14),
          ),
        ),
      ),
      dividerColor: EncbaColors.line,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: EncbaColors.ink,
      ),
    );
  }
}
