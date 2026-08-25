part of 'locker_controller.dart';

/// NotificationsApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin NotificationsApi on StateNotifier<LockerState>, ControllerCore {
/// 항목별 알림 설정이 꺼져 있으면 브라우저 알림 자체를 띄우지 않는다.
  Future<void> _notifyIfEnabled(
    NotificationCategory category,
    String title,
    String body,
  ) async {
    if (!await _notificationPrefs.isEnabled(category)) return;
    await _notify(title, body);
  }

/// 알림을 띄우기 전에 기록부터 남긴다. 브라우저 권한이 꺼져 있어
  /// 알림이 뜨지 않더라도 알림 패널에서는 지난 알림을 볼 수 있어야 한다.
  Future<void> _notify(String title, String body) async {
    await _notificationHistory.add(title: title, body: body);
    await WebNotificationService().show(title, body);
  }

void readNotifications() => state = state.copyWith(unreadNotifications: 0);
}
