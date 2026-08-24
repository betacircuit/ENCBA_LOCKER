import 'dart:async';
import 'dart:js_interop';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:web/web.dart' as web;

class WebNotificationService {
  static const _enabledKey = 'encba.notifications.enabled.v1';
  static const _icon = 'icons/Icon-192.png';

  Future<bool> enableAndTest() async {
    final permission =
        (await web.Notification.requestPermission().toDart).toDart;
    if (permission != 'granted') return false;
    await LocalStore().setString(_enabledKey, 'true');
    // 브라우저가 알림 아래에 PWA 이름(manifest의 short_name)을 자동으로
    // 붙이므로, 제목에 앱 이름을 다시 쓰면 "ENCBA LOCKER from LOCKER"처럼
    // 보인다. 제목에는 알림 내용만 적는다.
    web.Notification(
      '웹 알림이 켜졌습니다',
      web.NotificationOptions(
        body: '새 공지와 일정 변경을 알려드릴게요.',
        icon: _icon,
      ),
    );
    return true;
  }

  Future<bool> isEnabled() async =>
      web.Notification.permission == 'granted' &&
      await LocalStore().getString(_enabledKey) == 'true';

  Future<void> disable() => LocalStore().setString(_enabledKey, 'false');

  Future<bool> show(String title, String body) async {
    if (!await isEnabled()) return false;
    web.Notification(title, web.NotificationOptions(body: body, icon: _icon));
    return true;
  }

  Future<bool> scheduleAt(
    String id,
    String title,
    String body,
    DateTime scheduledAt,
  ) async {
    if (!await isEnabled()) return false;
    final delay = scheduledAt.difference(DateTime.now()).inMilliseconds;
    if (delay <= 0) return show(title, body);
    Timer(Duration(milliseconds: delay), () => show(title, body));
    return true;
  }
}
