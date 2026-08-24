import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'app_environment.dart';

@JS('navigator.standalone')
external bool? get _navigatorStandalone;

extension type _Connection(JSObject _) {
  external bool? get saveData;
  external String? get effectiveType;
}

@JS('navigator.connection')
external _Connection? get _connection;

extension type _MediaQueryList(JSObject _) {
  external bool get matches;
}

@JS('matchMedia')
external _MediaQueryList? _matchMedia(JSString query);

/// 웹 구현. iOS Safari는 PWA standalone 여부를 `navigator.standalone`으로,
/// 그 외 브라우저는 display-mode 미디어 쿼리로 판정한다.
class AppEnvironmentImpl implements AppEnvironment {
  const AppEnvironmentImpl();

  static final bool _standalone = () {
    if (_navigatorStandalone == true) return true;
    try {
      return _matchMedia(
            '(display-mode: standalone)'.toJS,
          )?.matches ??
          false;
    } on Object {
      return false;
    }
  }();

  static final bool _appleMobile = () {
    try {
      final navigator = web.window.navigator;
      final ua = navigator.userAgent.toLowerCase();
      final isIosLike =
          ua.contains('iphone') ||
          ua.contains('ipad') ||
          ua.contains('ipod') ||
          (ua.contains('macintosh') && navigator.maxTouchPoints > 1);
      return isIosLike && !ua.contains('crios') && !ua.contains('fxios');
    } on Object {
      return false;
    }
  }();

  static final bool _androidMobile = () {
    try {
      return web.window.navigator.userAgent.toLowerCase().contains('android');
    } on Object {
      return false;
    }
  }();

  // Chrome·Edge(크로미움 계열) 데스크톱만 주소창에 설치 아이콘을 지원한다.
  // Firefox·Safari 데스크톱은 이 방식의 설치가 없다.
  static final bool _chromiumDesktop = () {
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      if (_appleMobile || _androidMobile) return false;
      return ua.contains('edg/') ||
          (ua.contains('chrome/') && !ua.contains('chromium'));
    } on Object {
      return false;
    }
  }();

  @override
  bool get isStandalone => _standalone;

  @override
  bool get isAppleMobileWeb => _appleMobile;

  @override
  bool get isAndroidMobileWeb => _androidMobile;

  @override
  bool get isChromiumDesktopWeb => _chromiumDesktop;

  @override
  bool get prefersReducedData {
    final connection = _connection;
    if (connection == null) return false;
    if (connection.saveData == true) return true;
    final effectiveType = connection.effectiveType;
    return effectiveType == 'slow-2g' || effectiveType == '2g';
  }
}
