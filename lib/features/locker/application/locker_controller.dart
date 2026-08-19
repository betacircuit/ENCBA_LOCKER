import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/locker/data/supabase_locker_repository.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/services/notification_category_prefs.dart';
import 'package:encba_locker/features/locker/services/web_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LockerUiState {
  const LockerUiState({
    this.isReady = false,
    this.gameSegment = 1,
    this.gameSubSegment = 0,
    this.videoSegment = 0,
    this.memberSegment = 0,
    this.unreadNotifications = 0,
    this.isOfflineCache = false,
    this.error,
  });

  final bool isReady;
  final int gameSegment;
  final int gameSubSegment;
  final int videoSegment;
  final int memberSegment;
  final int unreadNotifications;
  final bool isOfflineCache;
  final String? error;
}

class LockerEventsState {
  const LockerEventsState({
    this.attendance = const {},
    this.events = const [],
    this.eventRosters = const {},
    this.eventAttendance = const {},
    this.eventStrategies = const {},
    this.attendanceRates = const AttendanceRates(),
    this.hasMoreEvents = false,
    this.isLoadingMoreEvents = false,
  });

  final Map<String, String> attendance;
  final List<LockerEvent> events;
  final Map<String, List<EventRosterMember>> eventRosters;
  final Map<String, List<AttendanceResponse>> eventAttendance;
  final Map<String, EventStrategy> eventStrategies;
  final AttendanceRates attendanceRates;
  final bool hasMoreEvents;
  final bool isLoadingMoreEvents;

  List<LockerEvent> plannerEventsWith(LockerOperationsState operationsState) {
    final merged = <LockerEvent>[
      ...events,
      ...operationsState.operations.map(
        (assignment) => assignment.toPlannerEvent(),
      ),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return merged;
  }
}

class LockerVideosState {
  const LockerVideosState({
    this.videos = const [],
    this.likedVideoIds = const {},
    this.videoComments = const {},
  });

  final List<VideoItem> videos;
  final Set<String> likedVideoIds;
  final Map<String, List<VideoCommentItem>> videoComments;
}

class LockerMembersState {
  const LockerMembersState({this.members = const []});

  final List<MemberProfile> members;
}

class LockerOperationsState {
  const LockerOperationsState({
    this.announcements = const [],
    this.operations = const [],
    this.homecomingContacts = const [],
    this.homecomingCampaign,
    this.operationExchangeBoard = const [],
    this.operationSwapRequests = const [],
    this.auditEntries = const [],
  });

  final List<AnnouncementItem> announcements;
  final List<OperationAssignment> operations;
  final List<HomecomingContact> homecomingContacts;
  final HomecomingCampaign? homecomingCampaign;
  final List<OperationAssignment> operationExchangeBoard;
  final List<OperationSwapRequest> operationSwapRequests;
  final List<AuditEntry> auditEntries;
}

class LockerState {
  LockerState({
    bool isReady = false,
    int gameSegment = 1,
    int gameSubSegment = 0,
    int videoSegment = 0,
    int memberSegment = 0,
    int unreadNotifications = 0,
    Map<String, String> attendance = const {},
    List<LockerEvent> events = const [],
    List<VideoItem> videos = const [],
    Set<String> likedVideoIds = const {},
    Map<String, List<VideoCommentItem>> videoComments = const {},
    List<MemberProfile> members = const [],
    List<AnnouncementItem> announcements = const [],
    List<OperationAssignment> operations = const [],
    List<HomecomingContact> homecomingContacts = const [],
    HomecomingCampaign? homecomingCampaign,
    Map<String, List<EventRosterMember>> eventRosters = const {},
    Map<String, List<AttendanceResponse>> eventAttendance = const {},
    Map<String, EventStrategy> eventStrategies = const {},
    List<OperationAssignment> operationExchangeBoard = const [],
    List<OperationSwapRequest> operationSwapRequests = const [],
    List<AuditEntry> auditEntries = const [],
    AttendanceRates attendanceRates = const AttendanceRates(),
    bool hasMoreEvents = false,
    bool isLoadingMoreEvents = false,
    bool isOfflineCache = false,
    String? error,
  }) : ui = LockerUiState(
         isReady: isReady,
         gameSegment: gameSegment,
         gameSubSegment: gameSubSegment,
         videoSegment: videoSegment,
         memberSegment: memberSegment,
         unreadNotifications: unreadNotifications,
         isOfflineCache: isOfflineCache,
         error: error,
       ),
       eventsState = LockerEventsState(
         attendance: attendance,
         events: events,
         eventRosters: eventRosters,
         eventAttendance: eventAttendance,
         eventStrategies: eventStrategies,
         attendanceRates: attendanceRates,
         hasMoreEvents: hasMoreEvents,
         isLoadingMoreEvents: isLoadingMoreEvents,
       ),
       videosState = LockerVideosState(
         videos: videos,
         likedVideoIds: likedVideoIds,
         videoComments: videoComments,
       ),
       membersState = LockerMembersState(members: members),
       operationsState = LockerOperationsState(
         announcements: announcements,
         operations: operations,
         homecomingContacts: homecomingContacts,
         homecomingCampaign: homecomingCampaign,
         operationExchangeBoard: operationExchangeBoard,
         operationSwapRequests: operationSwapRequests,
         auditEntries: auditEntries,
       );

  LockerState._({
    required this.ui,
    required this.eventsState,
    required this.videosState,
    required this.membersState,
    required this.operationsState,
  });

  final LockerUiState ui;
  final LockerEventsState eventsState;
  final LockerVideosState videosState;
  final LockerMembersState membersState;
  final LockerOperationsState operationsState;

  bool get isReady => ui.isReady;
  int get gameSegment => ui.gameSegment;
  int get gameSubSegment => ui.gameSubSegment;
  int get videoSegment => ui.videoSegment;
  int get memberSegment => ui.memberSegment;
  int get unreadNotifications => ui.unreadNotifications;
  bool get isOfflineCache => ui.isOfflineCache;
  String? get error => ui.error;
  Map<String, String> get attendance => eventsState.attendance;
  List<LockerEvent> get events => eventsState.events;
  Map<String, List<EventRosterMember>> get eventRosters =>
      eventsState.eventRosters;
  Map<String, List<AttendanceResponse>> get eventAttendance =>
      eventsState.eventAttendance;
  Map<String, EventStrategy> get eventStrategies => eventsState.eventStrategies;
  AttendanceRates get attendanceRates => eventsState.attendanceRates;
  bool get hasMoreEvents => eventsState.hasMoreEvents;
  bool get isLoadingMoreEvents => eventsState.isLoadingMoreEvents;
  List<VideoItem> get videos => videosState.videos;
  Set<String> get likedVideoIds => videosState.likedVideoIds;
  Map<String, List<VideoCommentItem>> get videoComments =>
      videosState.videoComments;
  List<MemberProfile> get members => membersState.members;
  List<AnnouncementItem> get announcements => operationsState.announcements;
  List<OperationAssignment> get operations => operationsState.operations;
  List<HomecomingContact> get homecomingContacts =>
      operationsState.homecomingContacts;
  HomecomingCampaign? get homecomingCampaign =>
      operationsState.homecomingCampaign;
  List<OperationAssignment> get operationExchangeBoard =>
      operationsState.operationExchangeBoard;
  List<OperationSwapRequest> get operationSwapRequests =>
      operationsState.operationSwapRequests;
  List<AuditEntry> get auditEntries => operationsState.auditEntries;

  List<LockerEvent> get plannerEvents =>
      eventsState.plannerEventsWith(operationsState);

  LockerState copyWith({
    bool? isReady,
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
    Map<String, List<EventRosterMember>>? eventRosters,
    Map<String, List<AttendanceResponse>>? eventAttendance,
    Map<String, EventStrategy>? eventStrategies,
    List<OperationAssignment>? operationExchangeBoard,
    List<OperationSwapRequest>? operationSwapRequests,
    List<AuditEntry>? auditEntries,
    AttendanceRates? attendanceRates,
    bool? hasMoreEvents,
    bool? isLoadingMoreEvents,
    bool? isOfflineCache,
    String? error,
    bool clearError = false,
  }) {
    final uiChanged =
        isReady != null ||
        gameSegment != null ||
        gameSubSegment != null ||
        videoSegment != null ||
        memberSegment != null ||
        unreadNotifications != null ||
        isOfflineCache != null ||
        error != null ||
        clearError;
    final eventsChanged =
        attendance != null ||
        events != null ||
        eventRosters != null ||
        eventAttendance != null ||
        eventStrategies != null ||
        attendanceRates != null ||
        hasMoreEvents != null ||
        isLoadingMoreEvents != null;
    final videosChanged =
        videos != null || likedVideoIds != null || videoComments != null;
    final membersChanged = members != null;
    final operationsChanged =
        announcements != null ||
        operations != null ||
        homecomingContacts != null ||
        homecomingCampaign != null ||
        clearHomecomingCampaign ||
        operationExchangeBoard != null ||
        operationSwapRequests != null ||
        auditEntries != null;

    return LockerState._(
      ui: uiChanged
          ? LockerUiState(
              isReady: isReady ?? this.isReady,
              gameSegment: gameSegment ?? this.gameSegment,
              gameSubSegment: gameSubSegment ?? this.gameSubSegment,
              videoSegment: videoSegment ?? this.videoSegment,
              memberSegment: memberSegment ?? this.memberSegment,
              unreadNotifications:
                  unreadNotifications ?? this.unreadNotifications,
              isOfflineCache: isOfflineCache ?? this.isOfflineCache,
              error: clearError ? null : error ?? this.error,
            )
          : ui,
      eventsState: eventsChanged
          ? LockerEventsState(
              attendance: attendance ?? this.attendance,
              events: events ?? this.events,
              eventRosters: eventRosters ?? this.eventRosters,
              eventAttendance: eventAttendance ?? this.eventAttendance,
              eventStrategies: eventStrategies ?? this.eventStrategies,
              attendanceRates: attendanceRates ?? this.attendanceRates,
              hasMoreEvents: hasMoreEvents ?? this.hasMoreEvents,
              isLoadingMoreEvents:
                  isLoadingMoreEvents ?? this.isLoadingMoreEvents,
            )
          : eventsState,
      videosState: videosChanged
          ? LockerVideosState(
              videos: videos ?? this.videos,
              likedVideoIds: likedVideoIds ?? this.likedVideoIds,
              videoComments: videoComments ?? this.videoComments,
            )
          : videosState,
      membersState: membersChanged
          ? LockerMembersState(members: members)
          : membersState,
      operationsState: operationsChanged
          ? LockerOperationsState(
              announcements: announcements ?? this.announcements,
              operations: operations ?? this.operations,
              homecomingContacts: homecomingContacts ?? this.homecomingContacts,
              homecomingCampaign: clearHomecomingCampaign
                  ? null
                  : homecomingCampaign ?? this.homecomingCampaign,
              operationExchangeBoard:
                  operationExchangeBoard ?? this.operationExchangeBoard,
              operationSwapRequests:
                  operationSwapRequests ?? this.operationSwapRequests,
              auditEntries: auditEntries ?? this.auditEntries,
            )
          : operationsState,
    );
  }
}

class LockerController extends StateNotifier<LockerState> {
  LockerController(this._repository) : super(LockerState()) {
    _load();
  }

  LockerController.seeded({LockerState? initialState})
    : _repository = null,
      super(
        initialState ??
            LockerState(
              isReady: true,
              events: _seedEvents(),
              videos: _seedVideos(),
              members: _seedMembers(),
            ),
      );

  final SupabaseLockerRepository? _repository;
  RealtimeChannel? _announcementChannel;
  RealtimeChannel? _operationSwapChannel;
  RealtimeChannel? _eventChannel;
  RealtimeChannel? _videoFeedChannel;
  final _notificationPrefs = NotificationCategoryPrefs();
  Timer? _undecidedReminderTimer;
  Future<void>? _loadInFlight;
  final Map<String, int> _voteRevisions = {};
  final Map<String, Future<void>> _voteWriteTails = {};

  /// 멤버를 다시 읽을 때 화면에 걸려 있던 검색·필터를 그대로 다시 건다.
  /// 조건을 잃으면 수정 직후 목록이 통째로 갈아엎여 저장이 안 된 것처럼 보인다.
  String _memberQuery = '';
  String _memberMembership = 'ALL';
  static const _reminderStoreKey = 'encba.undecided-reminders.v1';

  Future<void> _load() {
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final next = _performLoad();
    _loadInFlight = next;
    return next.whenComplete(() {
      if (identical(_loadInFlight, next)) _loadInFlight = null;
    });
  }

  Future<void> _performLoad() async {
    final repository = _repository!;
    try {
      final cached = await repository.loadCached();
      if (cached != null) _applySnapshot(cached);
      final snapshot = await repository.load(fallback: cached);
      _applySnapshot(snapshot);

      final membersFuture = _orDefault(
        repository.loadMembers(),
        const <MemberProfile>[],
      );
      final announcementsFuture = _orDefault(
        repository.loadAnnouncements(),
        const <AnnouncementItem>[],
      );
      final operationsFuture = _orDefault(
        repository.loadOperations(),
        const <OperationAssignment>[],
      );
      final contactsFuture = _orDefault(
        repository.loadHomecomingContacts(),
        const <HomecomingContact>[],
      );
      final auditFuture = _orDefault(
        repository.loadAuditLogs(),
        const <AuditEntry>[],
      );
      final campaignFuture = _orDefault<HomecomingCampaign?>(
        repository.loadActiveHomecomingCampaign(),
        null,
      );
      final ratesFuture = _orDefault(
        repository.loadAttendanceRates(),
        const AttendanceRates(),
      );
      final exchangeBoardFuture = _orDefault(
        repository.loadOperationExchangeBoard(),
        const <OperationAssignment>[],
      );
      final swapRequestsFuture = _orDefault(
        repository.loadOperationSwapRequests(),
        const <OperationSwapRequest>[],
      );
      state = state.copyWith(
        members: await membersFuture,
        announcements: await announcementsFuture,
        operations: await operationsFuture,
        homecomingContacts: await contactsFuture,
        auditEntries: await auditFuture,
        homecomingCampaign: await campaignFuture,
        attendanceRates: await ratesFuture,
        operationExchangeBoard: await exchangeBoardFuture,
        operationSwapRequests: await swapRequestsFuture,
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
          _notifyIfEnabled(
            NotificationCategory.announcements,
            announcement.title,
            announcement.body,
          ),
        );
      });
      _eventChannel ??= repository.subscribeToEvents((record) {
        state = state.copyWith(
          unreadNotifications: state.unreadNotifications + 1,
        );
        unawaited(
          _notifyIfEnabled(
            NotificationCategory.events,
            '새 일정이 등록됐습니다',
            (record['title'] as String?) ?? '일정 탭에서 확인해 주세요.',
          ),
        );
      });
      _videoFeedChannel ??= repository.subscribeToVideos((record) {
        state = state.copyWith(
          unreadNotifications: state.unreadNotifications + 1,
        );
        final category = record['category'] as String? ?? '영상';
        unawaited(
          _notifyIfEnabled(
            NotificationCategory.videos,
            '새 $category 영상이 올라왔습니다',
            (record['title'] as String?) ?? '영상 탭에서 확인해 주세요.',
          ),
        );
      });
      _operationSwapChannel ??= repository.subscribeToOperationSwapRequests((
        record,
      ) {
        state = state.copyWith(
          unreadNotifications: state.unreadNotifications + 1,
        );
        unawaited(
          WebNotificationService().show(
            'IB 운영 교환 신청이 왔습니다',
            'PERSONAL의 IB 운영 일정에서 요청을 확인해 주세요.',
          ),
        );
        unawaited(refreshOperationSwaps());
      });
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA data sync failed: $error\n$stackTrace');
      state = state.copyWith(isReady: true, error: '서버 데이터를 불러오지 못했습니다.');
    }
  }

  /// 항목별 알림 설정이 꺼져 있으면 브라우저 알림 자체를 띄우지 않는다.
  Future<void> _notifyIfEnabled(
    NotificationCategory category,
    String title,
    String body,
  ) async {
    if (!await _notificationPrefs.isEnabled(category)) return;
    await WebNotificationService().show(title, body);
  }

  void _applySnapshot(LockerSnapshot snapshot) {
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
  }

  @override
  void dispose() {
    _undecidedReminderTimer?.cancel();
    final channel = _announcementChannel;
    if (channel != null) _repository?.unsubscribe(channel);
    final operationSwapChannel = _operationSwapChannel;
    if (operationSwapChannel != null) {
      _repository?.unsubscribe(operationSwapChannel);
    }
    final eventChannel = _eventChannel;
    if (eventChannel != null) _repository?.unsubscribe(eventChannel);
    final videoFeedChannel = _videoFeedChannel;
    if (videoFeedChannel != null) _repository?.unsubscribe(videoFeedChannel);
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

  void selectGameSegment(int index) =>
      state = state.copyWith(gameSegment: index, gameSubSegment: 0);
  void selectGameSubSegment(int index) =>
      state = state.copyWith(gameSubSegment: index);
  void selectVideoSegment(int index) =>
      state = state.copyWith(videoSegment: index);
  void selectMemberSegment(int index) => _selectMemberSegment(index);

  Future<void> reload() => _load();

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

  void readNotifications() => state = state.copyWith(unreadNotifications: 0);
  void refreshUndecidedReminders() => unawaited(_scheduleUndecidedReminder());

  Future<void> _selectMemberSegment(int index) async {
    state = state.copyWith(memberSegment: index);
    if (_repository == null) return;
    _memberMembership = index == 0 ? 'ALL' : 'MILITARY';
    try {
      final members = await _repository.loadMembers(
        membership: _memberMembership,
        query: _memberQuery,
      );
      state = state.copyWith(members: members, clearError: true);
    } on Object {
      state = state.copyWith(error: '멤버 정보를 불러오지 못했습니다.');
    }
  }

  Future<void> searchMembers(String query) async {
    if (_repository == null) return;
    _memberQuery = query;
    try {
      final members = await _repository.loadMembers(
        membership: _memberMembership,
        query: query,
      );
      state = state.copyWith(members: members, clearError: true);
    } on Object {
      state = state.copyWith(error: '멤버 검색에 실패했습니다.');
    }
  }

  /// 엑셀 배정을 보내기 전 계정 등록·활성 상태를 확인할 때는 현재 화면의
  /// 검색어나 군휴학 필터와 무관한 전체 명단이 필요하다.
  Future<List<MemberProfile>> loadAllMembersForAccountCheck() async {
    final repository = _repository;
    if (repository == null) return state.members;
    return _orDefault(repository.loadMembers(membership: 'ALL'), state.members);
  }

  /// 검색 결과에서 빠진 멤버도 상세 주소의 ID로 읽어 현재 상태에 합친다.
  Future<bool> ensureMember(String id) async {
    if (state.members.any((member) => member.id == id)) return true;
    final repository = _repository;
    if (repository == null) return false;
    final member = await repository.loadMember(id);
    if (member == null) return false;
    state = state.copyWith(
      members: [...state.members.where((item) => item.id != member.id), member],
      clearError: true,
    );
    return true;
  }

  /// 공지 목록의 로드 범위와 무관하게 공유 주소의 공지를 상태에 합친다.
  Future<bool> ensureAnnouncement(String id) async {
    if (state.announcements.any((notice) => notice.id == id)) return true;
    final repository = _repository;
    if (repository == null) return false;
    final notice = await repository.loadAnnouncement(id);
    if (notice == null) return false;
    state = state.copyWith(
      announcements: [
        notice,
        ...state.announcements.where((item) => item.id != notice.id),
      ],
      clearError: true,
    );
    return true;
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

  /// 성공하면 null, 실패하면 화면에 그대로 띄울 사유를 돌려준다.
  /// 예전에는 실패 사유를 삼키고 '수정하지 못했습니다'만 보여줘서
  /// 어디가 막혔는지 알 수 없었다.
  Future<String?> updateMember(MemberProfile member) async {
    if (_repository == null || member.id == null) {
      return '멤버 정보를 수정할 수 없는 상태입니다.';
    }
    try {
      await _repository.updateMember(member);
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA member update failed: $error\n$stackTrace');
      final message = _memberUpdateMessage(error);
      state = state.copyWith(error: message);
      return message;
    }
    // 서버가 이름 공백을 다듬거나 뱃지를 다시 계산하므로 저장된 값을 다시 읽는다.
    // 재조회가 실패해도 방금 저장한 값은 화면에 남겨 둔다.
    final members = await _orDefault(
      _repository.loadMembers(
        membership: _memberMembership,
        query: _memberQuery,
      ),
      state.members
          .map((item) => item.id == member.id ? member : item)
          .toList(growable: false),
    );
    // 검색 조건 때문에 방금 고친 멤버가 목록에서 빠지면 상세 화면이 빈 채로
    // 남는다. 조건과 무관하게 그 한 명은 붙여 둔다.
    final refreshed = members.any((item) => item.id == member.id)
        ? members
        : [...members, member];
    state = state.copyWith(members: refreshed, clearError: true);
    return null;
  }

  String _memberUpdateMessage(Object error) {
    final text = error is PostgrestException
        ? '${error.code ?? ''} ${error.message}'
        : error.toString();
    if (text.contains('ENCBA_RESERVATION_ROLE_ADMIN_ONLY')) {
      return '체육관 예약자 지정은 관리자만 바꿀 수 있습니다.';
    }
    if (text.contains('ENCBA_DEPARTMENT_ADMIN_ONLY')) {
      return '학과는 관리자만 바꿀 수 있습니다.';
    }
    if (text.contains('ENCBA_ADMIN_OR_CAPTAIN_REQUIRED')) {
      return '관리자나 주장만 멤버 정보를 수정할 수 있습니다.';
    }
    if (text.contains('ENCBA_INVALID_MEMBER_PROFILE')) {
      return '학번·가입 연도·등번호·소속을 확인해 주세요.';
    }
    if (text.contains('PGRST202') ||
        text.contains('Could not find the function')) {
      return '서버에 최신 마이그레이션이 적용되지 않았습니다. supabase db push가 필요합니다.';
    }
    return '멤버 정보를 수정하지 못했습니다.';
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
      final board = await repository.loadOperationExchangeBoard();
      state = state.copyWith(
        operations: operations,
        operationExchangeBoard: board,
        clearError: true,
      );
      return result;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation import failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영표를 가져오지 못했습니다.');
      return null;
    }
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

  Future<void> refreshOperationSwaps() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final operationsFuture = repository.loadOperations();
      final boardFuture = repository.loadOperationExchangeBoard();
      final requestsFuture = repository.loadOperationSwapRequests();
      state = state.copyWith(
        operations: await operationsFuture,
        operationExchangeBoard: await boardFuture,
        operationSwapRequests: await requestsFuture,
        clearError: true,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation swap refresh failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영 교환 정보를 불러오지 못했습니다.');
    }
  }

  Future<bool> requestOperationSwap({
    required String ownAssignmentId,
    required String targetAssignmentId,
    required String message,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      await repository.createOperationSwapRequest(
        ownAssignmentId: ownAssignmentId,
        targetAssignmentId: targetAssignmentId,
        message: message,
      );
      await refreshOperationSwaps();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation swap request failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영 교환 신청을 보내지 못했습니다.');
      return false;
    }
  }

  Future<bool> respondOperationSwap({
    required String requestId,
    required bool accept,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      await repository.respondOperationSwapRequest(
        requestId: requestId,
        accept: accept,
      );
      await refreshOperationSwaps();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation swap response failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영 교환 응답을 저장하지 못했습니다.');
      return false;
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
      state = state.copyWith(error: '일정을 저장하지 못했습니다: $error');
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

  Future<DateTime> serverNow() async {
    try {
      return await _repository?.loadServerTime() ?? DateTime.now();
    } on Object {
      return DateTime.now();
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

  Future<bool> addAnnouncement({
    required String title,
    required String body,
    required bool pinned,
    List<String> linkedEventIds = const [],
  }) async {
    try {
      final saved = await _repository?.addAnnouncement(
        title: title,
        body: body,
        pinned: pinned,
        linkedEventIds: linkedEventIds,
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
    List<String> linkedEventIds = const [],
  }) async {
    try {
      final saved = await _repository?.updateAnnouncement(
        id: announcement.id,
        title: title,
        body: body,
        pinned: pinned,
        linkedEventIds: linkedEventIds,
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

  void upsertVideoFromRealtime(VideoItem video) {
    final next = [...state.videos];
    final index = next.indexWhere((item) => item.id == video.id);
    if (index == -1) {
      next.add(video);
    } else {
      next[index] = video;
    }
    next.sort((a, b) {
      final byTime = b.uploadedAt.compareTo(a.uploadedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    state = state.copyWith(videos: next, clearError: true);
  }

  void removeVideoFromRealtime(String id) {
    if (!state.videos.any((video) => video.id == id)) return;
    state = state.copyWith(
      videos: state.videos.where((video) => video.id != id).toList(),
      likedVideoIds: {...state.likedVideoIds}..remove(id),
      clearError: true,
    );
  }

  Future<void> refreshVideo(String id) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final video = await repository.loadVideo(id);
      if (video == null) {
        removeVideoFromRealtime(id);
      } else {
        upsertVideoFromRealtime(video);
      }
    } on Object catch (error) {
      debugPrint('ENCBA video refresh failed: $error');
    }
  }

  /// 초기 영상 페이지에 없는 항목도 공유 주소의 ID로 읽어 현재 상태에 합친다.
  Future<bool> ensureVideo(String id) async {
    if (state.videos.any((video) => video.id == id)) return true;
    final repository = _repository;
    if (repository == null) return false;
    final video = await repository.loadVideo(id);
    if (video == null) return false;
    upsertVideoFromRealtime(video);
    return true;
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
    required int? quarterNumber,
    required int? linkId,
    required int timestampSeconds,
    required String body,
    List<VideoTaggedMember> targetPlayers = const [],
  }) async {
    if (_repository == null) return false;
    try {
      final saved = await _repository.addVideoComment(
        videoId: videoId,
        quarterNumber: quarterNumber,
        linkId: linkId,
        timestampSeconds: timestampSeconds,
        body: body,
        targetPlayers: targetPlayers,
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
      opponents: const ['서울대 농구부', '그래비티'],
      createdBy: '관리자 최재원',
    ),
  ];
}

final lockerControllerProvider =
    StateNotifierProvider<LockerController, LockerState>((ref) {
      ref.watch(authControllerProvider.select((state) => state.user?.id));
      ref.watch(
        authControllerProvider.select((state) => state.sessionRevision),
      );
      return LockerController(
        SupabaseLockerRepository(Supabase.instance.client, LocalStore()),
      );
    });
