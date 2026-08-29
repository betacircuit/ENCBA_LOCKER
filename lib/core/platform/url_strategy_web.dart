import 'package:flutter_web_plugins/url_strategy.dart';

/// 웹 주소를 `/schedule/123` 처럼 경로로 쓴다.
///
/// 기본값(해시 전략)이면 Flutter가 자기 경로를 `#` 뒤에 붙인다. Vercel은
/// 모든 요청을 index.html로 넘기므로 브라우저 주소는 이미 `/sign-in`인데
/// 거기에 Flutter가 `#/sign-in`을 또 붙여서 `/sign-in#/sign-in`처럼
/// 같은 경로가 두 번 적혔다. 공유한 링크도 보기 흉하고, OAuth 리디렉트
/// 주소와도 어긋난다.
///
/// 경로 전략을 쓰면 주소가 한 번만 적히고 새로고침·공유가 그대로 된다.
/// (vercel.json이 이미 모든 경로를 index.html로 되돌려 준다.)
void useEncbaUrlStrategy() => usePathUrlStrategy();
