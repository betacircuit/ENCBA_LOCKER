// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'package:encba_locker/core/storage/local_store.dart';

class WebNotificationService {
  static const _enabledKey = 'encba.notifications.enabled.v1';

  Future<bool> enableAndTest() async {
    final permission = await html.Notification.requestPermission();
    if (permission != 'granted') return false;
    await LocalStore().setString(_enabledKey, 'true');
    html.Notification(
      'ENCBA LOCKER',
      body: '웹 알림이 켜졌습니다. 새 공지와 일정 변경을 알려드릴게요.',
      icon: 'icons/Icon-192.png',
    );
    return true;
  }

  Future<bool> isEnabled() async =>
      html.Notification.permission == 'granted' &&
      await LocalStore().getString(_enabledKey) == 'true';

  Future<void> disable() => LocalStore().setString(_enabledKey, 'false');

  Future<bool> show(String title, String body) async {
    if (!await isEnabled()) return false;
    html.Notification(title, body: body, icon: 'icons/Icon-192.png');
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
