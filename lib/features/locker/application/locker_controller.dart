import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/locker/data/supabase_locker_repository.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/services/web_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LockerState {
  const LockerState({
    this.isReady = false,
    this.tabIndex = 2,
    this.gameSegment = 1,
    this.gameSubSegment = 0,
    this.videoSegment = 0,
    this.memberSegment = 0,
    this.unreadNotifications = 0,
    this.attendance = const {},
    this.events = const [],
    this.videos = const [],
    this.likedVideoIds = const {},
    this.videoComments = const {},
    this.members = const [],
    this.announcements = const [],
    this.operations = const [],
    this.homecomingContacts = const [],
    this.homecomingCampaign,
    this.videoWatchSummaries = const {},
    this.eventRosters = const {},
    this.auditEntries = const [],
    this.attendanceRates = const AttendanceRates(),
    this.hasMoreEvents = false,
    this.isLoadingMoreEvents = false,
    this.isOfflineCache = false,
    this.error,
  });

  final bool isReady;
  final int tabIndex;
  final int gameSegment;
  final int gameSubSegment;
  final int videoSegment;
  final int memberSegment;
  final int unreadNotifications;
  final Map<String, String> attendance;
  final List<LockerEvent> events;
  final List<VideoItem> videos;
  final Set<String> likedVideoIds;
  final Map<String, List<VideoCommentItem>> videoComments;
  final List<MemberProfile> members;
  final List<AnnouncementItem> announcements;
  final List<OperationAssignment> operations;
  final List<HomecomingContact> homecomingContacts;
  final HomecomingCampaign? homecomingCampaign;
  final Map<String, List<VideoWatchSummary>> videoWatchSummaries;
  final Map<String, List<EventRosterMember>> eventRosters;
  final List<AuditEntry> auditEntries;
  final AttendanceRates attendanceRates;
  final bool hasMoreEvents;
  final bool isLoadingMoreEvents;
  final bool isOfflineCache;
  final String? error;

  LockerState copyWith({
    bool? isReady,
    int? tabIndex,
    int? gameSegment,
    int? gameSubSegment,
    int? videoSegment,
    int? memberSegment,
    int? unreadNotifications,
    Map<String, String>? attendance,
    List<LockerEvent>? events,
    List<VideoItem>? videos,
    Set<String>? likedVideoIds,
    Map<String, List<VideoCommentItem>>? videoComments,
    List<MemberProfile>? members,
    List<AnnouncementItem>? announcements,
    List<OperationAssignment>? operations,
    List<HomecomingContact>? homecomingContacts,
    HomecomingCampaign? homecomingCampaign,
    bool clearHomecomingCampaign = false,
    Map<String, List<VideoWatchSummary>>? videoWatchSummaries,
    Map<String, List<EventRosterMember>>? eventRosters,
    List<AuditEntry>? auditEntries,
    AttendanceRates? attendanceRates,
    bool? hasMoreEvents,
    bool? isLoadingMoreEvents,
    bool? isOfflineCache,
    String? error,
    bool clearError = false,
  }) => LockerState(
    isReady: isReady ?? this.isReady,
    tabIndex: tabIndex ?? this.tabIndex,
    gameSegment: gameSegment ?? this.gameSegment,
    gameSubSegment: gameSubSegment ?? this.gameSubSegment,
    videoSegment: videoSegment ?? this.videoSegment,
    memberSegment: memberSegment ?? this.memberSegment,
    unreadNotifications: unreadNotifications ?? this.unreadNotifications,
    attendance: attendance ?? this.attendance,
    events: events ?? this.events,
    videos: videos ?? this.videos,
    likedVideoIds: likedVideoIds ?? this.likedVideoIds,
    videoComments: videoComments ?? this.videoComments,
    members: members ?? this.members,
    announcements: announcements ?? this.announcements,
    operations: operations ?? this.operations,
    homecomingContacts: homecomingContacts ?? this.homecomingContacts,
    homecomingCampaign: clearHomecomingCampaign
        ? null
        : homecomingCampaign ?? this.homecomingCampaign,
    videoWatchSummaries: videoWatchSummaries ?? this.videoWatchSummaries,
    eventRosters: eventRosters ?? this.eventRosters,
    auditEntries: auditEntries ?? this.auditEntries,
    attendanceRates: attendanceRates ?? this.attendanceRates,
    hasMoreEvents: hasMoreEvents ?? this.hasMoreEvents,
    isLoadingMoreEvents: isLoadingMoreEvents ?? this.isLoadingMoreEvents,
    isOfflineCache: isOfflineCache ?? this.isOfflineCache,
    error: clearError ? null : error ?? this.error,
  );
}

class LockerController extends StateNotifier<LockerState> {
  LockerController(this._repository) : super(const LockerState()) {
    _load();
  }

  LockerController.seeded()
    : _repository = null,
      super(
        LockerState(
          isReady: true,
          events: _seedEvents(),
          videos: _seedVideos(),
          members: _seedMembers(),
        ),
      );

  final SupabaseLockerRepository? _repository;
  RealtimeChannel? _announcementChannel;
  Timer? _undecidedReminderTimer;
  static const _reminderStoreKey = 'encba.undecided-reminders.v1';

  Future<void> _load() async {
    final repository = _repository!;
    try {
      final snapshot = await repository.load();
      state = state.copyWith(
        isReady: true,
        events: snapshot.events,
        attendance: snapshot.attendance,
        videos: snapshot.videos,
        likedVideoIds: snapshot.likedVideoIds,
        hasMoreEvents: snapshot.hasMoreEvents,
        isOfflineCache: snapshot.fromCache,
        clearError: true,
      );

      final result = await Future.wait([
        _orDefault(repository.loadMembers(), const <MemberProfile>[]),
        _orDefault(repository.loadAnnouncements(), const <AnnouncementItem>[]),
        _orDefault(repository.loadOperations(), const <OperationAssignment>[]),
        _orDefault(
          repository.loadHomecomingContacts(),
          const <HomecomingContact>[],
        ),
        _orDefault(repository.loadAuditLogs(), const <AuditEntry>[]),
        _orDefault(repository.loadActiveHomecomingCampaign(), null),
        _orDefault(repository.loadAttendanceRates(), const AttendanceRates()),
      ]);
      state = state.copyWith(
        members: result[0] as List<MemberProfile>,
        announcements: result[1] as List<AnnouncementItem>,
        operations: result[2] as List<OperationAssignment>,
        homecomingContacts: result[3] as List<HomecomingContact>,
        auditEntries: result[4] as List<AuditEntry>,
        homecomingCampaign: result[5] as HomecomingCampaign?,
        attendanceRates: result[6] as AttendanceRates,
      );
      unawaited(_scheduleUndecidedReminder());
      _announcementChannel ??= repository.subscribeToAnnouncements((record) {
        final announcement = AnnouncementItem(
          id: record['id'] as String,
          title: record['title'] as String,
          body: record['body'] as String,
          author: '운영진',
          publishedAt: DateTime.parse(
            record['published_at'] as String,
          ).toLocal(),
        );
        if (state.announcements.any((item) => item.id == announcement.id)) {
          return;
        }
        state = state.copyWith(
          announcements: [announcement, ...state.announcements],
          unreadNotifications: state.unreadNotifications + 1,
        );
        unawaited(
          WebNotificationService().show(announcement.title, announcement.body),
        );
      });
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA data sync failed: $error\n$stackTrace');
      state = state.copyWith(
        isReady: true,
        events: const [],
        videos: const [],
        error: '서버 데이터를 불러오지 못했습니다.',
      );
    }
  }

  @override
  void dispose() {
    _undecidedReminderTimer?.cancel();
    final channel = _announcementChannel;
    if (channel != null) _repository?.unsubscribe(channel);
    super.dispose();
  }

  Future<T> _orDefault<T>(Future<T> future, T fallback) async {
    try {
      return await future;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA secondary sync failed: $error\n$stackTrace');
      return fallback;
    }
  }

  void selectTab(int index) => state = state.copyWith(tabIndex: index);
  void selectGameSegment(int index) =>
      state = state.copyWith(gameSegment: index, gameSubSegment: 0);
  void selectGameSubSegment(int index) =>
      state = state.copyWith(gameSubSegment: index);
  void selectVideoSegment(int index) =>
      state = state.copyWith(videoSegment: index);
  void selectMemberSegment(int index) => _selectMemberSegment(index);

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

  void readNotifications() => state = state.copyWith(unreadNotifications: 0);
  void refreshUndecidedReminders() => unawaited(_scheduleUndecidedReminder());

  Future<void> _selectMemberSegment(int index) async {
    state = state.copyWith(memberSegment: index);
    if (_repository == null) return;
    try {
      final members = await _repository.loadMembers(
        membership: index == 0 ? 'ALL' : 'MILITARY',
      );
      state = state.copyWith(members: members, clearError: true);
    } on Object {
      state = state.copyWith(error: '멤버 정보를 불러오지 못했습니다.');
    }
  }

  Future<void> searchMembers(String query) async {
    if (_repository == null) return;
    try {
      final members = await _repository.loadMembers(query: query);
      state = state.copyWith(members: members, clearError: true);
    } on Object {
      state = state.copyWith(error: '멤버 검색에 실패했습니다.');
    }
  }

  Future<bool> setMemberActive(MemberProfile member, bool isActive) async {
    if (_repository == null || member.id == null) return false;
    final previous = state.members;
    state = state.copyWith(
      members: previous
          .map(
            (item) =>
                item.id == member.id ? item.copyWith(isActive: isActive) : item,
          )
          .toList(),
    );
    try {
      await _repository.setMemberActive(member.id!, isActive);
      return true;
    } on Object {
      state = state.copyWith(members: previous, error: '계정 상태를 변경하지 못했습니다.');
      return false;
    }
  }

  Future<bool> updateMember(MemberProfile member) async {
    if (_repository == null || member.id == null) return false;
    try {
      await _repository.updateMember(member);
      final members = state.members
          .map((item) => item.id == member.id ? member : item)
          .toList();
      state = state.copyWith(members: members, clearError: true);
      return true;
    } on Object {
      state = state.copyWith(error: '멤버 정보를 수정하지 못했습니다.');
      return false;
    }
  }

  Future<bool> updateHomecomingContact(HomecomingContact contact) async {
    final previous = state.homecomingContacts;
    final next = previous
        .map((item) => item.id == contact.id ? contact : item)
        .toList();
    state = state.copyWith(homecomingContacts: next);
    try {
      await _repository?.updateHomecomingContact(contact);
      return true;
    } on Object {
      state = state.copyWith(
        homecomingContacts: previous,
        error: '홈커밍 연락 상태를 저장하지 못했습니다.',
      );
      return false;
    }
  }

  Future<bool> activateHomecomingCampaign({
    required int academicYear,
    required int term,
    required DateTime eventDate,
    required String startsAt,
    required String endsAt,
    required String venue,
  }) async {
    try {
      final campaign = await _repository?.activateHomecomingCampaign(
        academicYear: academicYear,
        term: term,
        eventDate: eventDate,
        startsAt: startsAt,
        endsAt: endsAt,
        venue: venue,
      );
      state = state.copyWith(homecomingCampaign: campaign, clearError: true);
      return campaign != null;
    } on Object {
      state = state.copyWith(error: '홈커밍 캠페인을 열지 못했습니다.');
      return false;
    }
  }

  Future<bool> importHomecomingContacts({
    required String fileName,
    required List<Map<String, dynamic>> contacts,
  }) async {
    final campaign = state.homecomingCampaign;
    if (campaign == null || _repository == null) return false;
    try {
      await _repository.importHomecomingContacts(
        campaignId: campaign.id,
        fileName: fileName,
        contacts: contacts,
      );
      final refreshed = await _repository.loadHomecomingContacts();
      state = state.copyWith(homecomingContacts: refreshed, clearError: true);
      return true;
    } on Object {
      state = state.copyWith(error: '엑셀 연락망을 가져오지 못했습니다.');
      return false;
    }
  }

  Future<({int imported, int unmatched})?> importOperations({
    required String fileName,
    required int academicYear,
    required int term,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final repository = _repository;
    if (repository == null) return null;
    try {
      final result = await repository.importOperations(
        fileName: fileName,
        academicYear: academicYear,
        term: term,
        assignments: assignments,
      );
      final operations = await repository.loadOperations();
      state = state.copyWith(operations: operations, clearError: true);
      return result;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation import failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영표를 가져오지 못했습니다.');
      return null;
    }
  }

  Future<bool> vote(
    String eventId,
    String value, {
    String? absenceReason,
  }) async {
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
    try {
      await _repository?.vote(eventId, value, absenceReason: absenceReason);
      unawaited(_scheduleUndecidedReminder());
      return true;
    } on Object {
      state = state.copyWith(
        attendance: previous,
        events: previousEvents,
        error: '참석 응답을 저장하지 못했습니다.',
      );
      return false;
    }
  }

  Future<void> _scheduleUndecidedReminder() async {
    if (_repository == null) return;
    _undecidedReminderTimer?.cancel();
    final store = LocalStore();
    final raw = await store.getString(_reminderStoreKey);
    var sent = <String>{};
    if (raw != null) {
      try {
        sent = (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
      } on Object {
        await store.remove(_reminderStoreKey);
      }
    }
    final now = DateTime.now();
    final undecided = state.events.where(
      (event) => state.attendance[event.id] == '미정' && event.start.isAfter(now),
    );
    final due = undecided.where(
      (event) =>
          !sent.contains(event.id) &&
          !now.isBefore(event.start.subtract(const Duration(hours: 3))),
    );
    var changed = false;
    for (final event in due) {
      final shown = await WebNotificationService().show(
        '일정을 확정해 주세요',
        '${event.title} · ${event.start.month}.${event.start.day} ${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')}',
      );
      if (shown) {
        sent.add(event.id);
        changed = true;
      }
    }
    if (changed) {
      await store.setString(_reminderStoreKey, jsonEncode(sent.toList()));
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

  Future<void> recordVideoWatch({
    required String videoId,
    required int watchedSeconds,
    required int lastPositionSeconds,
    required bool completed,
  }) async {
    try {
      await _repository?.recordVideoWatch(
        videoId: videoId,
        watchedSeconds: watchedSeconds,
        lastPositionSeconds: lastPositionSeconds,
        completed: completed,
      );
    } on Object {
      // 시청 기록 실패가 재생을 방해하지 않도록 다음 주기에 다시 보낸다.
    }
  }

  Future<void> loadVideoWatchSummary(String videoId) async {
    if (_repository == null) return;
    try {
      final summary = await _repository.loadVideoWatchSummary(videoId);
      state = state.copyWith(
        videoWatchSummaries: {...state.videoWatchSummaries, videoId: summary},
      );
    } on Object {
      state = state.copyWith(error: '시청 현황을 불러오지 못했습니다.');
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
    } on Object {
      state = state.copyWith(error: '일정을 저장하지 못했습니다.');
      return false;
    }
  }

  Future<int> createDemoEvents() async {
    if (state.events.any((event) => event.memo.startsWith('테스트 일정 ·'))) {
      return 0;
    }
    var savedCount = 0;
    for (final source in _seedEvents()) {
      final event = LockerEvent(
        id: 'demo-${DateTime.now().microsecondsSinceEpoch}-$savedCount',
        title: source.title,
        start: source.start,
        end: source.end,
        place: source.place,
        kind: source.kind,
        memo: '테스트 일정 · ${source.memo}',
        court: source.court,
        uniformColors: source.uniformColors,
        capacity: source.capacity,
        targetTeam: source.targetTeam,
        createdBy: source.createdBy,
        isRecurring: false,
        responseEnabled: source.responseEnabled,
        responseDeadlineOverride: source.responseDeadline,
        pollOptions: source.pollOptions,
        visibility: source.visibility,
        opponents: source.opponents,
      );
      if (await saveEvent(event)) savedCount++;
    }
    return savedCount;
  }

  Future<bool> addAnnouncement({
    required String title,
    required String body,
    required bool pinned,
  }) async {
    try {
      final saved = await _repository?.addAnnouncement(
        title: title,
        body: body,
        pinned: pinned,
      );
      if (saved != null) {
        state = state.copyWith(announcements: [saved, ...state.announcements]);
      }
      return saved != null;
    } on Object {
      state = state.copyWith(error: '공지를 저장하지 못했습니다.');
      return false;
    }
  }

  Future<bool> updateAnnouncement({
    required AnnouncementItem announcement,
    required String title,
    required String body,
    required bool pinned,
  }) async {
    try {
      final saved = await _repository?.updateAnnouncement(
        id: announcement.id,
        title: title,
        body: body,
        pinned: pinned,
      );
      if (saved == null) return false;
      state = state.copyWith(
        announcements: state.announcements
            .map((item) => item.id == saved.id ? saved : item)
            .toList(),
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '공지를 수정하지 못했습니다.');
      return false;
    }
  }

  Future<bool> deleteAnnouncement(String id) async {
    try {
      await _repository?.deleteAnnouncement(id);
      state = state.copyWith(
        announcements: state.announcements
            .where((item) => item.id != id)
            .toList(),
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '공지를 삭제하지 못했습니다.');
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

  Future<void> toggleVideoLike(String id) async {
    final previousVideos = state.videos;
    final previousLikes = state.likedVideoIds;
    final liked = {...state.likedVideoIds};
    final wasLiked = liked.remove(id);
    if (!wasLiked) liked.add(id);
    final videos = state.videos
        .map(
          (video) => video.id == id
              ? video.copyWith(
                  likeCount: (video.likeCount + (wasLiked ? -1 : 1))
                      .clamp(0, 999999)
                      .toInt(),
                )
              : video,
        )
        .toList();
    state = state.copyWith(videos: videos, likedVideoIds: liked);
    try {
      await _repository?.setVideoLike(id, liked: !wasLiked);
    } on Object {
      state = state.copyWith(
        videos: previousVideos,
        likedVideoIds: previousLikes,
        error: '좋아요를 저장하지 못했습니다.',
      );
    }
  }

  Future<bool> addVideo(VideoItem video) async {
    try {
      final saved = await _repository?.addVideo(video) ?? video;
      final videos = [saved, ...state.videos];
      state = state.copyWith(videos: videos, clearError: true);
      return true;
    } on Object {
      state = state.copyWith(error: '영상 링크를 등록하지 못했습니다.');
      return false;
    }
  }

  Future<bool> updateVideo(VideoItem video) async {
    try {
      final saved = await _repository?.updateVideo(video) ?? video;
      state = state.copyWith(
        videos: state.videos
            .map((item) => item.id == saved.id ? saved : item)
            .toList(),
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '영상을 수정하지 못했습니다.');
      return false;
    }
  }

  Future<bool> deleteVideo(String id) async {
    try {
      await _repository?.deleteVideo(id);
      state = state.copyWith(
        videos: state.videos.where((item) => item.id != id).toList(),
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '영상을 삭제하지 못했습니다.');
      return false;
    }
  }

  Future<void> loadVideoComments(String videoId) async {
    if (_repository == null) return;
    try {
      final comments = await _repository.loadVideoComments(videoId);
      state = state.copyWith(
        videoComments: {...state.videoComments, videoId: comments},
        clearError: true,
      );
    } on Object {
      state = state.copyWith(error: '영상 코멘트를 불러오지 못했습니다.');
    }
  }

  Future<bool> addVideoComment({
    required String videoId,
    required int timestampSeconds,
    required String body,
  }) async {
    if (_repository == null) return false;
    try {
      final saved = await _repository.addVideoComment(
        videoId: videoId,
        timestampSeconds: timestampSeconds,
        body: body,
      );
      final comments = [
        ...state.videoComments[videoId] ?? const <VideoCommentItem>[],
        saved,
      ]..sort((a, b) => a.timestampSeconds.compareTo(b.timestampSeconds));
      state = state.copyWith(
        videoComments: {...state.videoComments, videoId: comments},
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '영상 코멘트를 저장하지 못했습니다.');
      return false;
    }
  }
}

List<VideoItem> _seedVideos() {
  final now = DateTime.now();
  return [
    for (final (index, code) in [
      'Db2nVhDz4Fq',
      'DajgzpRTc4e',
      'DZDMprWogCr',
      'DXPE0fsEwcm',
      'DTnGCB7E50t',
    ].indexed)
      VideoItem(
        id: 'instagram-$code',
        title: 'ENCBA REEL ${index + 1}',
        durationLabel: '',
        category: '하이라이트',
        url: 'https://www.instagram.com/reel/$code/',
        youtubeId: '',
        sourceType: 'instagram',
        uploadedAt: now.subtract(Duration(days: index)),
        uploader: 'ENCBA',
        accent: 0xFF00539B,
      ),
    VideoItem(
      id: 'review-01',
      title: '지역방어 로테이션 복기',
      durationLabel: '12:41',
      category: '복기',
      url: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
      youtubeId: 'jNQXAC9IVRw',
      uploadedAt: now.subtract(const Duration(days: 2, hours: 3)),
      uploader: '주장 이준호',
      accent: 0xFF0B2347,
      likeCount: 7,
    ),
    VideoItem(
      id: 'share-01',
      title: '가드가 보면 좋은 픽앤롤 읽기',
      durationLabel: '8:05',
      category: '공유',
      url: 'https://www.youtube.com/watch?v=M7lc1UVf-VE',
      youtubeId: 'M7lc1UVf-VE',
      uploadedAt: now.subtract(const Duration(days: 1, hours: 5)),
      uploader: '김민수',
      accent: 0xFF123A72,
      likeCount: 9,
    ),
  ];
}

List<MemberProfile> _seedMembers() => const [
  MemberProfile(
    name: '김민수',
    studentId: '22학번',
    generation: 41,
    status: 'YB',
    position: 'PG',
    teams: ['ENCBA', 'BEN'],
    note: '',
    phone: '010-1234-1001',
  ),
  MemberProfile(
    name: '이준호',
    studentId: '21학번',
    generation: 40,
    status: 'YB',
    position: 'SF',
    teams: ['ENCBA'],
    note: '',
    phone: '010-1234-1002',
  ),
];

List<LockerEvent> _seedEvents() {
  final now = DateTime.now();
  DateTime futureAt(int days, int hour, [int minute = 0]) =>
      DateTime(now.year, now.month, now.day + days, hour, minute);
  return [
    LockerEvent(
      id: 'training-01',
      title: '정기 훈련',
      start: futureAt(1, 18),
      end: futureAt(1, 20),
      place: '71동 종합체육관',
      court: 'A코트',
      kind: EventKind.training,
      memo: '10분 전까지 모여 스트레칭을 시작합니다. 개인 물병을 챙겨 주세요.',
      capacity: 24,
      attending: 18,
      isRecurring: true,
      createdBy: '주장 이준호',
    ),
    LockerEvent(
      id: 'ib-01',
      title: 'IB 1부',
      start: futureAt(3, 20),
      end: futureAt(3, 21),
      place: '71동 종합체육관',
      court: 'B코트',
      kind: EventKind.ibDivision1,
      memo: '경기 시작 40분 전 집합합니다. 학생증과 개인 물병을 지참해 주세요.',
      uniformColors: const ['검정'],
      attending: 9,
      createdBy: 'IB 운영 김민수',
    ),
    LockerEvent(
      id: 'ib-02',
      title: 'IB 2부',
      start: futureAt(5, 19),
      end: futureAt(5, 20),
      place: '71동 종합체육관',
      court: 'A코트',
      kind: EventKind.ibDivision2,
      memo: '경기 시작 30분 전 집합합니다.',
      uniformColors: const ['흰색'],
      attending: 8,
      createdBy: 'IB 운영 김민수',
    ),
    LockerEvent(
      id: 'morning-01',
      title: '아농',
      start: futureAt(2, 8),
      end: futureAt(2, 10),
      place: '71-1동 신체육관',
      kind: EventKind.morning,
      memo: '자율 게임입니다. 8명 이상 모이면 진행합니다.',
      capacity: 16,
      attending: 7,
    ),
    LockerEvent(
      id: 'pickup-01',
      title: '픽업게임',
      start: futureAt(7, 16),
      end: futureAt(7, 18),
      place: '71-1동 신체육관',
      kind: EventKind.pickup,
      memo: '팀은 현장에서 나눕니다.',
      uniformColors: const ['검정', '흰색'],
      attending: 10,
    ),
    LockerEvent(
      id: 'free-open-01',
      title: '자개',
      start: futureAt(6, 18),
      end: futureAt(6, 20),
      place: '71-1동 신체육관',
      kind: EventKind.freeOpen,
      memo: '자유개방 시간입니다. 먼저 온 사람이 공과 조끼를 준비해 주세요.',
      capacity: 20,
      attending: 7,
    ),
    LockerEvent(
      id: 'scrimmage-01',
      title: '연습 경기',
      start: futureAt(9, 18, 30),
      end: futureAt(9, 20, 30),
      place: '900동 기숙사체육관',
      kind: EventKind.scrimmage,
      memo: '경기 시작 30분 전까지 도착해 주세요.',
      uniformColors: const ['흰색'],
      attending: 11,
      opponents: const ['스티즈'],
      createdBy: '관리자 최재원',
    ),
    LockerEvent(
      id: 'threeway-01',
      title: '삼파전',
      start: futureAt(12, 14),
      end: futureAt(12, 18),
      place: '71동 종합체육관',
      court: '전체',
      kind: EventKind.threeWay,
      memo: '세 팀이 순환 경기로 진행합니다.',
      uniformColors: const ['검정', '흰색'],
      attending: 13,
      opponents: const ['농구부', '그래비티'],
      createdBy: '관리자 최재원',
    ),
  ];
}

final lockerControllerProvider =
    StateNotifierProvider<LockerController, LockerState>((ref) {
      ref.watch(authControllerProvider.select((state) => state.user?.id));
      return LockerController(
        SupabaseLockerRepository(Supabase.instance.client, LocalStore()),
      );
    });
