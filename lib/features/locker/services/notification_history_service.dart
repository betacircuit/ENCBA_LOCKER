import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/services/notification_category_prefs.dart';
import 'package:flutter/foundation.dart';

/// 알림 패널에 쌓이는 기록 한 건.
@immutable
class NotificationHistoryEntry {
  const NotificationHistoryEntry({
    required this.title,
    required this.body,
    required this.receivedAt,
    this.category,
    this.route,
    this.readAt,
  });

  final String title;
  final String body;
  final DateTime receivedAt;

  /// 어떤 항목의 알림이었는지. 예전 형식으로 저장된 기록은 null이다.
  final NotificationCategory? category;

  /// 눌렀을 때 열 앱 내 주소. 없으면 기록만 남는다.
  final String? route;

  /// 읽은 시각. null이면 아직 안 읽은 알림이다.
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// 같은 알림인지 가리는 열쇠. 시각까지 넣어야 제목이 같은 알림 둘을
  /// 구분할 수 있다.
  String get key => '$title|$body|${receivedAt.toIso8601String()}';

  /// 저장 형식이 깨졌거나 옛 버전이면 그 항목만 버린다.
  static NotificationHistoryEntry? tryParse(Object? value) {
    if (value is! Map) return null;
    final title = value['title'];
    final receivedAt = DateTime.tryParse(value['receivedAt'] as String? ?? '');
    if (title is! String || title.isEmpty || receivedAt == null) return null;
    final categoryName = value['category'] as String?;
    final route = value['route'] as String?;
    return NotificationHistoryEntry(
      title: title,
      body: value['body'] as String? ?? '',
      receivedAt: receivedAt.toLocal(),
      category: NotificationCategory.values
          .where((item) => item.name == categoryName)
          .firstOrNull,
      route: route == null || route.isEmpty ? null : route,
      readAt: DateTime.tryParse(value['readAt'] as String? ?? '')?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'receivedAt': receivedAt.toIso8601String(),
    if (category != null) 'category': category!.name,
    if (route != null) 'route': route,
    if (readAt != null) 'readAt': readAt!.toIso8601String(),
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

  /// 같은 알림이 여러 경로로 도착해도(실시간 구독 + 푸시) 한 번만 남기는 간격.
  /// 예전에는 맨 앞 기록 하나만 비교해서, 두 알림이 번갈아 들어오면 같은
  /// 내용이 목록에 두 번 찍혔다.
  static const _duplicateWindow = Duration(minutes: 5);

  Future<List<NotificationHistoryEntry>> load() async {
    // 기기 저장소를 못 쓰는 자리도 있다(시크릿 창, 사이트 데이터 차단,
    // 위젯 테스트). 기록이 없는 것으로 보고 화면은 그대로 그린다.
    final String? raw;
    try {
      raw = await _store.getString(_key);
    } on Object {
      return const [];
    }
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
    // 저장 순서를 믿지 않고 받은 시각으로 다시 세운다. 오프라인에 있다가
    // 밀린 알림이 한꺼번에 들어오면 순서가 뒤섞여 저장될 수 있다.
    entries.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return entries;
  }

  /// 최신 기록을 맨 앞에 넣는다. 알림 표시에 실패해도(권한 거부 등)
  /// 기록은 남겨 두어야 패널에서 지난 알림을 확인할 수 있다.
  ///
  /// 이미 같은 알림이 [_duplicateWindow] 안에 있으면 아무것도 하지 않고
  /// false를 돌려준다. 호출한 쪽은 이 값으로 안 읽은 알림 배지를 올릴지
  /// 정한다. 그래야 배지 숫자와 패널 목록이 어긋나지 않는다.
  Future<bool> add({
    required String title,
    required String body,
    DateTime? receivedAt,
    NotificationCategory? category,
    String? route,
  }) async {
    if (title.isEmpty) return false;
    final at = (receivedAt ?? DateTime.now()).toLocal();
    final entries = await load();
    final isDuplicate = entries.any(
      (entry) =>
          entry.title == title &&
          entry.body == body &&
          at.difference(entry.receivedAt).abs() < _duplicateWindow,
    );
    if (isDuplicate) return false;
    await _write([
      NotificationHistoryEntry(
        title: title,
        body: body,
        receivedAt: at,
        category: category,
        route: route,
      ),
      ...entries,
    ]);
    return true;
  }

  /// 알림 하나를 읽음으로 표시한다.
  Future<void> markRead(NotificationHistoryEntry entry) async {
    final entries = await load();
    final next = [
      for (final item in entries)
        if (item.key == entry.key && !item.isRead)
          NotificationHistoryEntry(
            title: item.title,
            body: item.body,
            receivedAt: item.receivedAt,
            category: item.category,
            route: item.route,
            readAt: DateTime.now(),
          )
        else
          item,
    ];
    await _write(next);
  }

  /// 목록을 연 순간 전부 읽음으로 표시한다.
  Future<void> markAllRead() async {
    final entries = await load();
    final now = DateTime.now();
    await _write([
      for (final item in entries)
        if (item.isRead)
          item
        else
          NotificationHistoryEntry(
            title: item.title,
            body: item.body,
            receivedAt: item.receivedAt,
            category: item.category,
            route: item.route,
            readAt: now,
          ),
    ]);
  }

  /// 읽은 알림만 지운다. 아직 못 읽은 알림은 남겨 둬야 실수로 놓치지 않는다.
  Future<List<NotificationHistoryEntry>> clearRead() async {
    final remaining = [
      for (final entry in await load())
        if (!entry.isRead) entry,
    ];
    await _write(remaining);
    return remaining;
  }

  Future<void> _write(List<NotificationHistoryEntry> entries) async {
    final sorted = [...entries]
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    try {
      await _store.setString(
        _key,
        jsonEncode([
          for (final entry in sorted.take(maxEntries)) entry.toJson(),
        ]),
      );
    } on Object {
      // 저장하지 못해도 알림 자체는 이미 떴다. 기록만 남지 않는다.
    }
  }

  Future<void> clear() => _store.remove(_key);
}
