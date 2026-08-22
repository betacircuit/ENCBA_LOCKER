import 'dart:io';

import 'app_environment.dart';

/// 네이티브 앱은 항상 "설치된 앱"이므로 설치 안내·데이터 절약 감쇠가
/// 필요 없다. iOS 여부만 프로필 화면 표기 등에 쓴다.
class AppEnvironmentImpl implements AppEnvironment {
  const AppEnvironmentImpl();

  @override
  bool get isStandalone => true;

  @override
  bool get isAppleMobileWeb => Platform.operatingSystem == 'ios';

  @override
  bool get prefersReducedData => false;
}