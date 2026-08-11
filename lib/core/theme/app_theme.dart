import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF002856), // primary
        onPrimary: Colors.white,
        primaryContainer: Color(0xFF003e7e), // primary-container
        onPrimaryContainer: Color(0xFF82abf2),
        secondary: Color(0xFF3e59ae), // secondary
        onSecondary: Colors.white,
        tertiary: Color(0xFF27292a), // tertiary
        onTertiary: Colors.white,
        error: Color(0xFFba1a1a), // error
        onError: Colors.white,
        background: Color(0xFFf9f9fe), // background
        onBackground: Color(0xFF1a1c1f), // on-background
        surface: Color(0xFFf9f9fe), // surface
        onSurface: Color(0xFF1a1c1f), // on-surface
        surfaceVariant: Color(0xFFe2e2e7), // surface-variant
        onSurfaceVariant: Color(0xFF434750), // on-surface-variant
        outline: Color(0xFF737781), // outline
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme(), // 한글 폰트 적용 (대체)
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F3287), // snu-blue-deep
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF002856), // primary
        unselectedItemColor: Color(0xFF434750), // on-surface-variant
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
