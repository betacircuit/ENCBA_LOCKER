import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';

/// 이미 읽은 공지의 ID를 기기에 남긴다.
///
/// 서버에 두지 않은 이유: 공지를 읽었는지는 "이 기기에서 내가 봤는가"에
/// 가까운 정보라 계정마다 서버 왕복을 더할 만큼의 값이 없고, 기록이 없어도
/// 안 읽음으로 보일 뿐 아무것도 망가지지 않는다.
class AnnouncementReadStore {
  AnnouncementReadStore([LocalStore? store]) : _store = store ?? LocalStore();

  final LocalStore _store;

  static const _key = 'encba.announcements.read.v1';

  /// 너무 오래 쌓이지 않게 최근 것만 들고 있는다. 공지는 목록에서 밀려나면
  /// 다시 볼 일이 거의 없다.
  static const maxEntries = 300;

  Future<Set<String>> load() async {
    // 저장소를 못 쓰면 "아직 아무것도 안 읽음"으로 본다. 흐려지지 않을 뿐
    // 목록은 그대로 보인다.
    final String? raw;
    try {
      raw = await _store.getString(_key);
    } on Object {
      return <String>{};
    }
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return {
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      };
    } on Object {
      await _store.remove(_key);
      return <String>{};
    }
  }

  /// 읽은 공지를 더한다. 이미 있으면 아무 일도 하지 않고 false를 준다.
  Future<bool> markRead(String announcementId) async {
    if (announcementId.isEmpty) return false;
    final ids = await load();
    if (!ids.add(announcementId)) return false;
    // 가장 최근에 더한 것이 뒤에 오도록 두고 앞에서부터 잘라 낸다.
    final trimmed = ids.length <= maxEntries
        ? ids
        : ids.skip(ids.length - maxEntries).toSet();
    try {
      await _store.setString(_key, jsonEncode(trimmed.toList()));
    } on Object {
      // 다음에 열면 다시 안 읽음으로 보일 뿐이다.
    }
    return true;
  }

  Future<void> clear() => _store.remove(_key);
}
