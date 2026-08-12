import 'dart:io';

import 'package:flutter/services.dart';

class WebNotificationService {
  static const _channel = MethodChannel('encba/notifications');

  Future<bool> enableAndTest() async {
    if (!Platform.isIOS) return false;
    final granted =
        await _channel.invokeMethod<bool>('requestPermission') ?? false;
    if (!granted) return false;
    return show('ENCBA LOCKER', '알림이 켜졌습니다. 새 공지와 일정 변경을 알려드릴게요.');
  }

  Future<bool> show(String title, String body) async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('show', {
          'title': title,
          'body': body,
        }) ??
        false;
  }
}
