// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

class WebNotificationService {
  Future<bool> enableAndTest() async {
    final permission = await html.Notification.requestPermission();
    if (permission != 'granted') return false;
    html.Notification(
      'ENCBA LOCKER',
      body: '웹 알림이 켜졌습니다. 새 공지와 일정 변경을 알려드릴게요.',
      icon: 'icons/Icon-192.png',
    );
    return true;
  }

  bool show(String title, String body) {
    if (html.Notification.permission != 'granted') return false;
    html.Notification(title, body: body, icon: 'icons/Icon-192.png');
    return true;
  }
}
