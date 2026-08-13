import 'dart:io';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:flutter/services.dart';

class WebNotificationService {
  static const _channel = MethodChannel('encba/notifications');
  static const _enabledKey = 'encba.notifications.enabled.v1';

  Future<bool> enableAndTest() async {
    if (!Platform.isIOS) return false;
    final granted =
        await _channel.invokeMethod<bool>('requestPermission') ?? false;
    if (!granted) return false;
    await LocalStore().setString(_enabledKey, 'true');
    return show('ENCBA LOCKER', '알림이 켜졌습니다. 새 공지와 일정 변경을 알려드릴게요.');
  }

  Future<bool> isEnabled() async =>
      await LocalStore().getString(_enabledKey) == 'true';

  Future<void> disable() => LocalStore().setString(_enabledKey, 'false');

  Future<bool> show(String title, String body) async {
    if (!Platform.isIOS || !await isEnabled()) return false;
    return await _channel.invokeMethod<bool>('show', {
          'title': title,
          'body': body,
        }) ??
        false;
  }

  Future<bool> scheduleAt(
    String id,
    String title,
    String body,
    DateTime scheduledAt,
  ) async {
    if (!Platform.isIOS || !await isEnabled()) return false;
    return await _channel.invokeMethod<bool>('schedule', {
          'id': id,
          'title': title,
          'body': body,
          'scheduledAtMs': scheduledAt.millisecondsSinceEpoch,
        }) ??
        false;
  }
}
