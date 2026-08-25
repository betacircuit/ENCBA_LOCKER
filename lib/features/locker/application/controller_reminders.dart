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
    var opening = DateTime(
      serverNow.year,
      serverNow.month,
      serverNow.day,
      9,
      30,
    );
    final daysUntilTuesday = (DateTime.tuesday - serverNow.weekday + 7) % 7;
    opening = opening.add(Duration(days: daysUntilTuesday));
    if (!opening.isAfter(serverNow)) {
      opening = opening.add(const Duration(days: 7));
    }
    final reminderAt = opening.subtract(const Duration(minutes: 5));
    final deviceTarget = DateTime.now().add(reminderAt.difference(serverNow));
    await WebNotificationService().scheduleAt(
      'encba-court-reservation-opening',
      '체육관 예약 오픈 5분 전',
      '71동·71-1동 다음 주 예약이 곧 열립니다.',
      deviceTarget,
    );
  }
}
