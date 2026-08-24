import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:flutter/foundation.dart';

/// 알림 패널에 쌓이는 기록 한 건.
@immutable
class NotificationHistoryEntry {
  const NotificationHistoryEntry({
    required this.title,
    required this.body,
    required this.receivedAt,
  });

  final String title;
  final String body;
  final DateTime receivedAt;

  /// 저장 형식이 깨졌거나 옛 버전이면 그 항목만 버린다.
  static NotificationHistoryEntry? tryParse(Object? value) {
    if (value is! Map) return null;
    final title = value['title'];
    final receivedAt = DateTime.tryParse(value['receivedAt'] as String? ?? '');
    if (title is! String || title.isEmpty || receivedAt == null) return null;
    return NotificationHistoryEntry(
      title: title,
      body: value['body'] as String? ?? '',
      receivedAt: receivedAt.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'receivedAt': receivedAt.toIso8601String(),
  };
}

/// 받은 알림을 기기에 남겨 알림 패널에서 다시 볼 수 있게 한다.
/// 서버 동기화 없이 기기별로만 쌓이며, 최신 [maxEntries]건까지 보관한다.
class NotificationHistoryService {
  NotificationHistoryService([LocalStore? store])
    : _store = store ?? LocalStore();

  final LocalStore _store;

  static const _key = 'encba.notifications.history.v1';
  static const maxEntries = 50;

  /// 실시간 구독이 같은 변경을 두 번 흘려도 기록이 겹치지 않게 하는 간격.
  static const _duplicateWindow = Duration(minutes: 1);

  Future<List<NotificationHistoryEntry>> load() async {
    final raw = await _store.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } on Object {
      await _store.remove(_key);
      return const [];
    }
    final entries = <NotificationHistoryEntry>[];
    for (final item in decoded) {
      final entry = NotificationHistoryEntry.tryParse(item);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// 최신 기록을 맨 앞에 넣는다. 알림 표시에 실패해도(권한 거부 등)
  /// 기록은 남겨 두어야 패널에서 지난 알림을 확인할 수 있다.
  Future<void> add({
    required String title,
    required String body,
    DateTime? receivedAt,
  }) async {
    if (title.isEmpty) return;
    final at = (receivedAt ?? DateTime.now()).toLocal();
    final entries = await load();
    if (entries.isNotEmpty) {
      final latest = entries.first;
      final isDuplicate =
          latest.title == title &&
          latest.body == body &&
          at.difference(latest.receivedAt).abs() < _duplicateWindow;
      if (isDuplicate) return;
    }
    final next = [
      NotificationHistoryEntry(title: title, body: body, receivedAt: at),
      ...entries,
    ].take(maxEntries).toList();
    await _store.setString(
      _key,
      jsonEncode([for (final entry in next) entry.toJson()]),
    );
  }

  Future<void> clear() => _store.remove(_key);
}
