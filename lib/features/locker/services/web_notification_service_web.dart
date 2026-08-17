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
    web.Notification(
      'ENCBA LOCKER',
      web.NotificationOptions(
        body: '웹 알림이 켜졌습니다. 새 공지와 일정 변경을 알려드릴게요.',
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
