import 'package:encba_locker/core/storage/local_store.dart';

/// 알림을 켤 수 있는 항목 종류. 전체 알림 스위치가 켜져 있어도
/// 이 중 원하는 항목만 골라 끌 수 있다.
enum NotificationCategory { announcements, events, videos }

/// 항목별 알림 켜짐/꺼짐을 기기에 저장한다. 서버 동기화는 하지 않는
/// 로컬 설정이라, 브라우저 알림 권한 자체와 마찬가지로 기기마다 따로 관리된다.
class NotificationCategoryPrefs {
  NotificationCategoryPrefs([LocalStore? store]) : _store = store ?? LocalStore();

  final LocalStore _store;

  static String _key(NotificationCategory category) =>
      'encba.notify.${category.name}.v1';

  /// 값을 저장한 적이 없으면 기본값은 켜짐이다.
  Future<bool> isEnabled(NotificationCategory category) async {
    final value = await _store.getString(_key(category));
    return value != 'false';
  }

  Future<void> setEnabled(NotificationCategory category, bool value) =>
      _store.setString(_key(category), value.toString());
}
