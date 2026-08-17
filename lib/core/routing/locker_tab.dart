/// 하단 탭. 순서와 주소의 첫 구간을 한 곳에서 정의한다.
enum LockerTab {
  videos('videos'),
  games('games'),
  home('home'),
  schedule('schedule'),
  profile('profile');

  const LockerTab(this.segment);

  final String segment;

  String get path => '/$segment';

  /// `/:tab(videos|games|home|schedule|profile)` 형태의 경로 제약에 쓴다.
  static String get pathPattern => values.map((tab) => tab.segment).join('|');

  static LockerTab? fromPath(String path) {
    final segment = path.startsWith('/') ? path.substring(1) : path;
    for (final tab in values) {
      if (tab.segment == segment) return tab;
    }
    return null;
  }
}
