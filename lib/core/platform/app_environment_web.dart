import 'dart:js_interop';

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
      final ua = 'navigator.userAgent'.toJS.toDart.toLowerCase();
      final isIosLike =
          ua.contains('iphone') ||
          ua.contains('ipad') ||
          (ua.contains('macintosh') && ua.contains('safari'));
      return isIosLike && !ua.contains('crios') && !ua.contains('fxios');
    } on Object {
      return false;
    }
  }();

  @override
  bool get isStandalone => _standalone;

  @override
  bool get isAppleMobileWeb => _appleMobile;

  @override
  bool get prefersReducedData {
    final connection = _connection;
    if (connection == null) return false;
    if (connection.saveData == true) return true;
    final effectiveType = connection.effectiveType;
    return effectiveType == 'slow-2g' || effectiveType == '2g';
  }
}