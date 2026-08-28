import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/services/announcement_read_store.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// 저장소가 아예 동작하지 않는 기기(시크릿 창 등)를 흉내 낸다.
class _BrokenStore implements LocalStore {
  @override
  Future<String?> getString(String key) async => throw StateError('no storage');

  @override
  Future<void> setString(String key, String value) async =>
      throw StateError('no storage');

  @override
  Future<void> remove(String key) async => throw StateError('no storage');
}

void main() {
  test('읽은 공지를 기억하고, 같은 공지를 두 번 세지 않는다', () async {
    final store = AnnouncementReadStore(_MemoryStore());

    expect(await store.markRead('a1'), isTrue);
    expect(await store.markRead('a1'), isFalse);
    await store.markRead('a2');

    expect(await store.load(), {'a1', 'a2'});
  });

  test('빈 ID는 무시한다', () async {
    final store = AnnouncementReadStore(_MemoryStore());

    expect(await store.markRead(''), isFalse);
    expect(await store.load(), isEmpty);
  });

  test('저장 형식이 깨져 있으면 안 읽은 것으로 보고 넘어간다', () async {
    final memory = _MemoryStore()
      ..values['encba.announcements.read.v1'] = 'not json';

    expect(await AnnouncementReadStore(memory).load(), isEmpty);
  });

  test('저장소를 못 쓰는 기기에서도 화면이 죽지 않는다', () async {
    final store = AnnouncementReadStore(_BrokenStore());

    // 흐려지지 않을 뿐, 예외를 던져 목록을 못 그리게 하면 안 된다.
    expect(await store.load(), isEmpty);
    expect(await store.markRead('a1'), isTrue);
  });
}
