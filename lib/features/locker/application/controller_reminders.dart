part of 'locker_controller.dart';

/// RemindersApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin RemindersApi on StateNotifier<LockerState>, ControllerCore {
  void refreshUndecidedReminders() => unawaited(_scheduleUndecidedReminder());

  @override
  Future<void> _scheduleUndecidedReminder() async {
    if (_repository == null) return;
    _undecidedReminderTimer?.cancel();
    final store = LocalStore();
    final raw = await store.getString(LockerController._reminderStoreKey);
    var sent = <String>{};
    if (raw != null) {
      try {
        sent = (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
      } on Object {
        await store.remove(LockerController._reminderStoreKey);
      }
    }
    final now = DateTime.now();
    final undecided = state.events.where((event) {
      final response = state.attendance[event.id];
      return (response == null || response == '미정') && event.start.isAfter(now);
    });
    final due = undecided.where(
      (event) =>
          !sent.contains(event.id) &&
          !now.isBefore(event.start.subtract(const Duration(hours: 3))),
    );
    var changed = false;
    for (final event in due) {
      const title = '일정을 확정해 주세요';
      final body =
          '${event.title} · ${event.start.month}.${event.start.day} ${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')}';
      final shown = await WebNotificationService().show(title, body);
      if (shown) {
        await _notificationHistory.add(title: title, body: body);
        sent.add(event.id);
        changed = true;
      }
    }
    if (changed) {
      await store.setString(LockerController._reminderStoreKey, jsonEncode(sent.toList()));
    }
    final futureTargets =
        undecided
            .where((event) => !sent.contains(event.id))
            .map((event) => event.start.subtract(const Duration(hours: 3)))
            .where((target) => target.isAfter(now))
            .toList()
          ..sort();
    if (futureTargets.isNotEmpty) {
      _undecidedReminderTimer = Timer(
        futureTargets.first.difference(now),
        () => unawaited(_scheduleUndecidedReminder()),
      );
    }
  }

Future<void> scheduleReservationOpeningReminder({
    required bool isReservationManager,
  }) async {
    if (!isReservationManager || !await WebNotificationService().isEnabled()) {
      return;
    }
    final serverNow = await this.serverNow();
    final opening = nextCourtReservationOpening(serverNow);
    final times = courtReservationReminderTimes(opening);
    final reminders = <({String id, DateTime at, String title, String body})>[
      (
        id: 'encba-court-reservation-eve',
        at: times.eve,
        title: '내일 체육관 예약이 열립니다',
        body: '71동·71-1동 다음 주 예약이 내일 오전 9시 30분에 열려요.',
      ),
      (
        id: 'encba-court-reservation-morning',
        at: times.morning,
        title: '오늘 체육관 예약이 열립니다',
        body: '오전 9시 30분에 71동·71-1동 다음 주 예약이 열려요.',
      ),
    ];
    for (final reminder in reminders) {
      if (!reminder.at.isAfter(serverNow)) continue;
      final deviceTarget = DateTime.now().add(
        reminder.at.difference(serverNow),
      );
      await WebNotificationService().scheduleAt(
        reminder.id,
        reminder.title,
        reminder.body,
        deviceTarget,
      );
    }
  }
}
