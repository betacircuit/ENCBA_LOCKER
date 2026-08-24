export 'app_environment_native.dart'
    if (dart.library.js_interop) 'app_environment_web.dart';

/// 실행 환경의 공통 질의. 웹에서는 브라우저 API를, 네이티브에서는
/// Platform 값을 사용한다. 구현은 플랫폼별 파일에 있다.
abstract class AppEnvironment {
  /// PWA로 홈 화면에 추가해 "standalone"으로 실행 중인지.
  bool get isStandalone;

  /// iOS·iPadOS Safari(홈 화면 추가 안내가 필요한 플랫폼)인지.
  bool get isAppleMobileWeb;

  /// Android 모바일 브라우저에서 웹으로 실행 중인지.
  bool get isAndroidMobileWeb;

  /// 사용자가 데이터 절약 모드를 켰거나 매우 느린 연결인지.
  /// true면 네트워크 썸네일을 생략하고 가벼운 화면을 보여준다.
  bool get prefersReducedData;
}
