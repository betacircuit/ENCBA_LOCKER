part of 'locker_controller.dart';

/// EventsApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin EventsApi on StateNotifier<LockerState>, ControllerCore {
Future<void> loadMoreEvents() async {
    final repository = _repository;
    if (repository == null ||
        !state.hasMoreEvents ||
        state.isLoadingMoreEvents) {
      return;
    }
    state = state.copyWith(isLoadingMoreEvents: true);
    try {
      final offset = state.events.where((event) => !event.isLocked).length;
      final page = await repository.loadMoreEvents(offset: offset);
      final byId = {for (final event in state.events) event.id: event};
      for (final event in page.events) {
        byId[event.id] = event;
      }
      final events = byId.values.toList()
        ..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
      state = state.copyWith(
        events: events,
        hasMoreEvents: page.hasMore,
        isLoadingMoreEvents: false,
        clearError: true,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA event page failed: $error\n$stackTrace');
      state = state.copyWith(
        isLoadingMoreEvents: false,
        error: '일정을 더 불러오지 못했습니다.',
      );
    }
  }

/// 초기 페이지에 없는 일정도 공유 주소의 ID로 읽어 현재 상태에 합친다.
  Future<bool> ensureEvent(String id) async {
    if (state.plannerEvents.any((event) => event.id == id)) return true;
    final repository = _repository;
    if (repository == null) return false;
    final event = await repository.loadEvent(id);
    if (event == null) return false;
    final byId = {
      for (final item in state.events) item.id: item,
      event.id: event,
    };
    final events = byId.values.toList()
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    state = state.copyWith(events: events, clearError: true);
    return true;
  }

Future<void> loadEventAttendance(String eventId) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final responses = await repository.loadEventAttendance(eventId);
      state = state.copyWith(
        eventAttendance: {...state.eventAttendance, eventId: responses},
        clearError: true,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA attendance detail failed: $error\n$stackTrace');
      state = state.copyWith(error: '참석 현황을 불러오지 못했습니다.');
    }
  }

Future<bool> vote(
    String eventId,
    String value, {
    String? absenceReason,
  }) async {
    final revision = (_voteRevisions[eventId] ?? 0) + 1;
    _voteRevisions[eventId] = revision;
    final previous = state.attendance;
    final previousEvents = state.events;
    final previousValue = previous[eventId] ?? '미정';
    final next = {...state.attendance, eventId: value};
    final delta = (value == '참석' ? 1 : 0) - (previousValue == '참석' ? 1 : 0);
    final nextEvents = state.events
        .map(
          (event) => event.id == eventId
              ? event.copyWith(
                  attending: (event.attending + delta).clamp(0, 999999).toInt(),
                )
              : event,
        )
        .toList();
    state = state.copyWith(attendance: next, events: nextEvents);

    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (_voteRevisions[eventId] != revision) return true;

    final priorWrite = _voteWriteTails[eventId] ?? Future<void>.value();
    final write = priorWrite.catchError((_) {}).then((_) async {
      if (_voteRevisions[eventId] != revision) return;
      await _repository?.vote(eventId, value, absenceReason: absenceReason);
    });
    _voteWriteTails[eventId] = write;
    try {
      await write;
      if (_voteRevisions[eventId] != revision) return true;
      unawaited(_scheduleUndecidedReminder());
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA attendance save failed: $error\n$stackTrace');
      if (_voteRevisions[eventId] != revision) return false;
      state = state.copyWith(
        attendance: previous,
        events: previousEvents,
        error: '참석 응답을 저장하지 못했습니다.',
      );
      return false;
    }
  }

Future<bool> applyExternalEvent(String eventId) async {
    try {
      await _repository?.applyExternalEvent(eventId);
      return true;
    } on Object {
      state = state.copyWith(error: '외부 경기 참여 신청을 저장하지 못했습니다.');
      return false;
    }
  }

Future<void> loadEventRoster(String eventId) async {
    if (_repository == null) return;
    try {
      final roster = await _repository.loadEventRoster(eventId);
      state = state.copyWith(
        eventRosters: {...state.eventRosters, eventId: roster},
      );
    } on Object {
      state = state.copyWith(error: '출전 신청 명단을 불러오지 못했습니다.');
    }
  }

Future<bool> setEventRosterStatus({
    required String eventId,
    required EventRosterMember member,
    required String status,
  }) async {
    final previous = state.eventRosters[eventId] ?? const <EventRosterMember>[];
    state = state.copyWith(
      eventRosters: {
        ...state.eventRosters,
        eventId: previous
            .map(
              (item) => item.profileId == member.profileId
                  ? item.copyWith(status: status)
                  : item,
            )
            .toList(),
      },
    );
    try {
      await _repository?.setEventRosterStatus(
        eventId: eventId,
        profileId: member.profileId,
        status: status,
      );
      return true;
    } on Object {
      state = state.copyWith(
        eventRosters: {...state.eventRosters, eventId: previous},
      );
      return false;
    }
  }

Future<bool> saveEvent(LockerEvent event) async {
    try {
      final saved = await _repository?.saveEvent(event) ?? event;
      final index = state.events.indexWhere((item) => item.id == event.id);
      final next = [...state.events];
      if (index == -1) {
        next.add(saved);
      } else {
        next[index] = saved;
      }
      next.sort((a, b) => a.start.compareTo(b.start));
      state = state.copyWith(events: next, clearError: true);
      if (index == -1 && event.isRecurring && _repository != null) {
        try {
          final refreshed = await _repository.load();
          state = state.copyWith(
            events: refreshed.events,
            attendance: refreshed.attendance,
            videos: refreshed.videos,
            likedVideoIds: refreshed.likedVideoIds,
            hasMoreEvents: refreshed.hasMoreEvents,
            isOfflineCache: refreshed.fromCache,
            clearError: true,
          );
        } on Object {
          // 부모 일정은 저장되었으므로 성공을 유지하고 다음 동기화에서 회차를 갱신한다.
        }
      }
      return true;
    } on LockerRepositoryException catch (error, stackTrace) {
      debugPrint('ENCBA event save failed: $error\n$stackTrace');
      state = state.copyWith(error: error.message);
      return false;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA event save failed: $error\n$stackTrace');
      state = state.copyWith(error: '일정을 저장하지 못했습니다.');
      return false;
    }
  }

Future<List<AttendanceReportRow>> loadAttendanceReport({
    required DateTime from,
    required DateTime to,
    required bool freshmenOnly,
  }) async {
    final repository = _repository;
    if (repository == null) return const [];
    return repository.loadAttendanceReport(
      from: from,
      to: to,
      freshmenOnly: freshmenOnly,
    );
  }

Future<void> loadEventStrategy(String eventId) async {
    if (state.eventStrategies.containsKey(eventId)) return;
    try {
      final strategy =
          await _repository?.loadEventStrategy(eventId) ??
          EventStrategy(eventId: eventId);
      state = state.copyWith(
        eventStrategies: {...state.eventStrategies, eventId: strategy},
      );
    } on Object {
      state = state.copyWith(
        eventStrategies: {
          ...state.eventStrategies,
          eventId: EventStrategy(eventId: eventId),
        },
      );
    }
  }

Future<bool> saveEventStrategy(EventStrategy strategy) async {
    try {
      final saved = await _repository?.saveEventStrategy(strategy) ?? strategy;
      state = state.copyWith(
        eventStrategies: {...state.eventStrategies, strategy.eventId: saved},
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '전술을 저장하지 못했습니다.');
      return false;
    }
  }

Future<bool> deleteEvent(String id) async {
    try {
      await _repository?.deleteEvent(id);
      final next = state.events.where((event) => event.id != id).toList();
      state = state.copyWith(events: next, clearError: true);
      return true;
    } on Object {
      state = state.copyWith(error: '일정을 삭제하지 못했습니다.');
      return false;
    }
  }
}
