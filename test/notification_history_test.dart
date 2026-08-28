import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/services/notification_category_prefs.dart';
import 'package:encba_locker/features/locker/services/notification_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 기기 저장소 대신 쓰는 메모리 저장소.
class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async =>
      values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  test('기록은 항목 종류와 열 주소까지 그대로 남는다', () async {
    final service = NotificationHistoryService(_MemoryStore());

    final added = await service.add(
      title: '새 공지가 올라왔습니다',
      body: '이번 주 훈련 안내',
      category: NotificationCategory.announcements,
      route: '/announcements/abc',
    );

    expect(added, isTrue);
    final entries = await service.load();
    expect(entries.single.category, NotificationCategory.announcements);
    expect(entries.single.route, '/announcements/abc');
  });

  test('같은 알림이 다른 알림 뒤에 또 와도 한 번만 남는다', () async {
    final service = NotificationHistoryService(_MemoryStore());
    final at = DateTime(2026, 8, 29, 12);

    await service.add(title: '공지', body: '내용', receivedAt: at);
    await service.add(title: '다른 알림', body: '', receivedAt: at);
    final duplicated = await service.add(
      title: '공지',
      body: '내용',
      receivedAt: at.add(const Duration(seconds: 30)),
    );

    expect(duplicated, isFalse);
    final entries = await service.load();
    expect(entries.where((entry) => entry.title == '공지').length, 1);
  });

  test('중복 판정 시간이 지난 같은 알림은 새 기록으로 남는다', () async {
    final service = NotificationHistoryService(_MemoryStore());
    final at = DateTime(2026, 8, 29, 12);

    await service.add(title: '공지', body: '내용', receivedAt: at);
    final later = await service.add(
      title: '공지',
      body: '내용',
      receivedAt: at.add(const Duration(hours: 1)),
    );

    expect(later, isTrue);
    expect((await service.load()).length, 2);
  });

  test('늦게 도착한 지난 알림도 받은 시각 순으로 정렬된다', () async {
    final service = NotificationHistoryService(_MemoryStore());

    await service.add(
      title: '어제 알림',
      body: '',
      receivedAt: DateTime(2026, 8, 28, 9),
    );
    await service.add(
      title: '그제 알림',
      body: '',
      receivedAt: DateTime(2026, 8, 27, 9),
    );

    final entries = await service.load();
    expect(entries.map((entry) => entry.title), ['어제 알림', '그제 알림']);
  });

  test('옛 형식으로 저장된 기록도 버리지 않고 읽는다', () async {
    final store = _MemoryStore()
      ..values['encba.notifications.history.v1'] =
          '[{"title":"옛 알림","body":"내용",'
          '"receivedAt":"2026-08-20T00:00:00.000Z"}]';
    final service = NotificationHistoryService(store);

    final entries = await service.load();

    expect(entries.single.title, '옛 알림');
    expect(entries.single.category, isNull);
    expect(entries.single.route, isNull);
  });
}
