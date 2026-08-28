import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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
  return 'BlackHanSans';
}

// Jua·BlackHanSans는 자주 쓰는 한글 2,300여 자만 담고 있다(전체 11,172자
// 중 일부). 이 범위를 벗어난 글자는 물론이고, 커버리지가 일부뿐인 폰트는
// 웹 CanvasKit 렌더러가 아예 신뢰하지 않아 담고 있는 글자까지 기본
// 폰트로 새어 나간다. 한글을 전부 담은 GowunDodum을 폴백에 둬서 어떤
// 한글이 오더라도(공지 등 자유 입력 텍스트 포함) 깨지지 않게 한다.
const encbaFontFallback = <String>['GowunDodum', 'Arial'];

TextStyle? _fallback(TextStyle? style) =>
    style?.copyWith(fontFamilyFallback: encbaFontFallback);

TextTheme _withKoreanFallback(TextTheme theme) => theme.copyWith(
  displayLarge: _fallback(theme.displayLarge),
  displayMedium: _fallback(theme.displayMedium),
  displaySmall: _fallback(theme.displaySmall),
  headlineLarge: _fallback(theme.headlineLarge),
  headlineMedium: _fallback(theme.headlineMedium),
  headlineSmall: _fallback(theme.headlineSmall),
  titleLarge: _fallback(theme.titleLarge),
  titleMedium: _fallback(theme.titleMedium),
  titleSmall: _fallback(theme.titleSmall),
  bodyLarge: _fallback(theme.bodyLarge),
  bodyMedium: _fallback(theme.bodyMedium),
  bodySmall: _fallback(theme.bodySmall),
  labelLarge: _fallback(theme.labelLarge),
  labelMedium: _fallback(theme.labelMedium),
  labelSmall: _fallback(theme.labelSmall),
);

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
    final text = _withKoreanFallback(
      base.textTheme.copyWith(
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
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: EncbaColors.canvas,
      textTheme: text,
      pageTransitionsTheme: kIsWeb
          ? const PageTransitionsTheme(
              // 웹에서는 Flutter가 스스로 뒤로가기 제스처를 달면 안 된다.
              // 브라우저의 가장자리 스와이프가 이미 히스토리를 되돌리는데
              // Cupertino/Predictive 전환이 같은 손짓으로 라우트를 한 번 더
              // 팝해서, 한 번 드래그하면 두 화면이 넘어갔다. 제스처가 없는
              // 전환만 써서 브라우저에게 뒤로가기를 온전히 맡긴다.
              builders: {
                TargetPlatform.android: _WebSlidePageTransitionsBuilder(),
                TargetPlatform.fuchsia: _WebSlidePageTransitionsBuilder(),
                TargetPlatform.iOS: _WebSlidePageTransitionsBuilder(),
                TargetPlatform.linux: _WebSlidePageTransitionsBuilder(),
                TargetPlatform.macOS: _WebSlidePageTransitionsBuilder(),
                TargetPlatform.windows: _WebSlidePageTransitionsBuilder(),
              },
            )
          : const PageTransitionsTheme(
              builders: {
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
                TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
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
        labelStyle: const TextStyle(
          color: EncbaColors.muted,
          fontFamilyFallback: encbaFontFallback,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFFA1A5AD),
          fontFamilyFallback: encbaFontFallback,
        ),
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
            TextStyle(
              fontFamily: 'Jua',
              fontFamilyFallback: encbaFontFallback,
              fontSize: 14,
            ),
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


/// 뒤로가기 제스처가 없는 가로 슬라이드 전환. 모양은 iOS 전환과 비슷하지만
/// 가장자리 드래그를 가로채지 않아 웹에서 브라우저 뒤로가기와 겹치지 않는다.
class _WebSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _WebSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = Curves.easeOutCubic;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: curve)),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-.22, 0),
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: curve)),
        child: child,
      ),
    );
  }
}
