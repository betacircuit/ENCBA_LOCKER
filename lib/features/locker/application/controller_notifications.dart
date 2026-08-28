part of 'locker_controller.dart';

/// NotificationsApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin NotificationsApi on StateNotifier<LockerState>, ControllerCore {
  /// 항목별 알림 설정이 꺼져 있으면 브라우저 알림도, 기록도 남기지 않는다.
  /// 받지 않은 알림이 히스토리에 적히면 그 목록은 더 이상 "받은 알림"이
  /// 아니게 된다.
  Future<void> _notifyIfEnabled(
    NotificationCategory category,
    String title,
    String body, {
    String? route,
    DateTime? occurredAt,
  }) async {
    if (!await _notificationPrefs.isEnabled(category)) return;
    await _notify(
      title,
      body,
      category: category,
      route: route,
      occurredAt: occurredAt,
    );
  }

  /// 알림을 띄우기 전에 기록부터 남긴다. 브라우저 권한이 꺼져 있어
  /// 알림이 뜨지 않더라도 알림 패널에서는 지난 알림을 볼 수 있어야 한다.
  ///
  /// 안 읽은 알림 배지도 여기서 함께 올린다. 예전에는 배지를 부르는 쪽에서
  /// 따로 올려서, 같은 알림이 두 경로로 들어오면 기록은 하나인데 배지만
  /// 두 번 올라갔다.
  Future<void> _notify(
    String title,
    String body, {
    NotificationCategory? category,
    String? route,
    DateTime? occurredAt,
  }) async {
    final recorded = await _notificationHistory.add(
      title: title,
      body: body,
      category: category,
      route: route,
      receivedAt: occurredAt,
    );
    if (!recorded) return;
    state = state.copyWith(
      unreadNotifications: state.unreadNotifications + 1,
    );
    await WebNotificationService().show(title, body);
  }

  void readNotifications() => state = state.copyWith(unreadNotifications: 0);
}
