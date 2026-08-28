import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/locker/application/locker_state.dart';
import 'package:encba_locker/features/locker/data/supabase_locker_repository.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/services/notification_category_prefs.dart';
import 'package:encba_locker/features/locker/services/notification_history_service.dart';
import 'package:encba_locker/features/locker/services/web_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:encba_locker/features/locker/application/locker_state.dart';
part 'controller_notifications.dart';
part 'controller_reminders.dart';
part 'controller_demand.dart';
part 'controller_reports.dart';
part 'controller_homecoming.dart';
part 'controller_operations.dart';
part 'controller_events.dart';
part 'controller_members.dart';
part 'controller_announcements.dart';
part 'controller_videos.dart';

/// 모든 도메인 파트가 의존하는 내부 상태 접근자.
mixin ControllerCore on StateNotifier<LockerState> {
  RealtimeChannel? _announcementChannel;
  RealtimeChannel? _operationSwapChannel;
  RealtimeChannel? _operationAssignmentChannel;
  RealtimeChannel? _eventChannel;
  RealtimeChannel? _videoFeedChannel;
  RealtimeChannel? _activationRequestChannel;
  Timer? _undecidedReminderTimer;
  Future<void>? _loadInFlight;
  String _memberMembership = 'ALL';

  SupabaseLockerRepository? get _repository;

  NotificationCategoryPrefs get _notificationPrefs;

  NotificationHistoryService get _notificationHistory;

  Future<void>? get _homecomingContactsLoadInFlight;

  set _homecomingContactsLoadInFlight(Future<void>? value);

  Future<void>? get _auditEntriesLoadInFlight;

  set _auditEntriesLoadInFlight(Future<void>? value);

  Map<String, int> get _voteRevisions;

  Map<String, Future<void>> get _voteWriteTails;

  String get _memberQuery;

  set _memberQuery(String value);

  Future<T> _orDefault<T>(Future<T> future, T fallback) async {
    try {
      return await future;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA secondary sync failed: $error\n$stackTrace');
      return fallback;
    }
  }

  /// 파트 간 호출 계약. 구현은 RemindersApi/본체가 제공한다.
  Future<void> _scheduleUndecidedReminder();

  Future<DateTime> serverNow();
}

class LockerController extends StateNotifier<LockerState>
    with
        ControllerCore,
        NotificationsApi,
        RemindersApi,
        DemandApi,
        ReportsApi,
        HomecomingApi,
        OperationsApi,
        EventsApi,
        MembersApi,
        AnnouncementsApi,
        VideosApi {
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

  @override
  final SupabaseLockerRepository? _repository;

  @override
  final _notificationPrefs = NotificationCategoryPrefs();
  @override
  final _notificationHistory = NotificationHistoryService();

  @override
  Future<void>? _homecomingContactsLoadInFlight;
  @override
  Future<void>? _auditEntriesLoadInFlight;
  @override
  final Map<String, int> _voteRevisions = {};
  @override
  final Map<String, Future<void>> _voteWriteTails = {};

  /// 멤버를 다시 읽을 때 화면에 걸려 있던 검색·필터를 그대로 다시 건다.
  /// 조건을 잃으면 수정 직후 목록이 통째로 갈아엎여 저장이 안 된 것처럼 보인다.
  @override
  String _memberQuery = '';

  static const _reminderStoreKey = 'encba.undecided-reminders.v1';
  static const _initialSyncTimeout = Duration(seconds: 6);

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
    // 로그아웃 상태에서도 auth 상태 변화(세션 복원 시도, 로그아웃 등)마다
    // 이 컨트롤러가 다시 만들어져 곧장 동기화를 시도한다. 로그인 전에는
    // 서버 호출이 전부 "로그인이 필요합니다" 에러로 실패할 뿐이므로 미리
    // 걸러서 불필요한 요청과 콘솔 에러 로그를 없앤다.
    if (Supabase.instance.client.auth.currentUser == null) {
      state = state.copyWith(isReady: true, isSyncing: false);
      return;
    }
    try {
      final cached = await repository.loadCached();
      if (cached != null) {
        _applySnapshot(cached, isSyncing: true);
      } else {
        // 로컬 저장소 확인이 끝나면 네트워크를 기다리지 않고 셸부터 연다.
        state = state.copyWith(
          isReady: true,
          isSyncing: true,
          isOfflineCache: false,
          clearError: true,
        );
      }
      final snapshot = await repository.load(fallback: cached);
      _applySnapshot(snapshot, isSyncing: false);

      final membersFuture = _orDefault(
        repository.loadMembers().timeout(_initialSyncTimeout),
        state.members,
      );
      final announcementsFuture = _orDefault(
        repository.loadAnnouncements().timeout(_initialSyncTimeout),
        state.announcements,
      );
      final operationsFuture = _orDefault(
        repository.loadOperations().timeout(_initialSyncTimeout),
        state.operations,
      );
      final allOperationsFuture = _orDefault(
        repository.loadAllOperations().timeout(_initialSyncTimeout),
        state.allOperations,
      );
      final campaignFuture = _orDefault<HomecomingCampaign?>(
        repository.loadActiveHomecomingCampaign().timeout(_initialSyncTimeout),
        state.homecomingCampaign,
      );
      final ratesFuture = _orDefault(
        repository.loadAttendanceRates().timeout(_initialSyncTimeout),
        state.attendanceRates,
      );
      final exchangeBoardFuture = _orDefault(
        repository.loadOperationExchangeBoard().timeout(_initialSyncTimeout),
        state.operationExchangeBoard,
      );
      final swapRequestsFuture = _orDefault(
        repository.loadOperationSwapRequests().timeout(_initialSyncTimeout),
        state.operationSwapRequests,
      );
      state = state.copyWith(
        members: await membersFuture,
        announcements: await announcementsFuture,
        operations: await operationsFuture,
        allOperations: await allOperationsFuture,
        homecomingCampaign: await campaignFuture,
        attendanceRates: await ratesFuture,
        operationExchangeBoard: await exchangeBoardFuture,
        operationSwapRequests: await swapRequestsFuture,
      );
      unawaited(_scheduleUndecidedReminder());
      _announcementChannel ??= repository.subscribeToAnnouncements((record) {
        unawaited(_mergeRealtimeAnnouncement(repository, record));
      });
      _eventChannel ??= repository.subscribeToEvents((record) {
        final id = record['id'] as String?;
        unawaited(
          _notifyIfEnabled(
            NotificationCategory.events,
            '새 일정이 등록됐습니다',
            (record['title'] as String?) ?? '일정 탭에서 확인해 주세요.',
            route: id == null
                ? null
                : '/schedule/${Uri.encodeComponent(id)}',
          ),
        );
      });
      _videoFeedChannel ??= repository.subscribeToVideos((record) {
        final id = record['id'] as String?;
        final category = record['category'] as String? ?? '영상';
        unawaited(
          _notifyIfEnabled(
            NotificationCategory.videos,
            '새 $category 영상이 올라왔습니다',
            (record['title'] as String?) ?? '영상 탭에서 확인해 주세요.',
            route: id == null ? null : '/videos/${Uri.encodeComponent(id)}',
          ),
        );
      });
      _operationSwapChannel ??= repository.subscribeToOperationSwapRequests((
        record,
      ) {
        unawaited(
          _notify(
            'IB 운영 교환 신청이 왔습니다',
            'PERSONAL의 IB 운영 일정에서 요청을 확인해 주세요.',
            category: NotificationCategory.events,
            route: '/operations',
          ),
        );
        unawaited(refreshOperationSwaps());
      });
      // 관리자가 IB 운영표를 올리면 내 배정이 실시간으로 도착한다.
      // 재접속 없이 홈·일정·운영 화면에 바로 반영되게 한다.
      _operationAssignmentChannel ??= repository
          .subscribeToOperationAssignments((record) {
            unawaited(_mergeRealtimeOperations(repository, record));
          });
      // 계정 활성화 요청은 관리자에게만 읽기가 열려 있어, 부원 계정에서는
      // 이 구독으로 아무것도 오지 않는다.
      unawaited(refreshActivationRequests());
      _activationRequestChannel ??= repository
          .subscribeToAccountActivationRequests((record) {
            final name =
                (record['requester_name'] as String?)?.trim().isNotEmpty == true
                ? (record['requester_name'] as String).trim()
                : (record['requester_email'] as String? ?? '한 부원');
            unawaited(
              _notify(
                '계정 활성화 요청',
                '$name님이 계정 활성화를 요청했어요.',
                route: '/profile',
              ),
            );
            unawaited(refreshActivationRequests());
          });
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA data sync failed: $error\n$stackTrace');
      state = state.copyWith(
        isReady: true,
        isSyncing: false,
        isOfflineCache: true,
        error: '서버 데이터를 불러오지 못했습니다.',
      );
    }
  }

  Future<void> _mergeRealtimeAnnouncement(
    SupabaseLockerRepository repository,
    Map<String, dynamic> record,
  ) async {
    final id = record['id'] as String?;
    if (id == null || state.announcements.any((item) => item.id == id)) return;
    final loaded = await _orDefault(repository.loadAnnouncement(id), null);
    final announcement =
        loaded ??
        AnnouncementItem(
          id: id,
          title: record['title'] as String? ?? '새 공지',
          body: record['body'] as String? ?? '',
          author: '운영진',
          publishedAt:
              DateTime.tryParse(
                record['published_at'] as String? ?? '',
              )?.toLocal() ??
              DateTime.now(),
          pinned: record['pinned'] as bool? ?? false,
          isUrgent: record['is_urgent'] as bool? ?? false,
          imageUrl: record['image_url'] as String?,
          pollOptions:
              (record['poll_options'] as List?)?.cast<String>() ?? const [],
          pollQuestion: record['poll_question'] as String? ?? '',
        );
    if (state.announcements.any((item) => item.id == id)) return;
    state = state.copyWith(
      announcements: [announcement, ...state.announcements],
    );
    await _notifyIfEnabled(
      NotificationCategory.announcements,
      announcement.title,
      announcement.body,
      route: '/announcements/${Uri.encodeComponent(announcement.id)}',
      occurredAt: announcement.publishedAt,
    );
  }

  /// 새로 등록된(또는 시간이 바뀐) 운영 배정을 개인·공용 목록에 합친다.
  /// 서버에서 전체를 다시 읽어 오는 게 가장 단순하고 안전하다.
  Future<void> _mergeRealtimeOperations(
    SupabaseLockerRepository repository,
    Map<String, dynamic> record,
  ) async {
    final operations = await _orDefault(
      repository.loadOperations(),
      const <OperationAssignment>[],
    );
    final allOperations = await _orDefault(
      repository.loadAllOperations(),
      state.allOperations,
    );
    state = state.copyWith(
      operations: operations,
      allOperations: allOperations,
    );
    final title = record['title'] as String?;
    if (record['profile_id'] == Supabase.instance.client.auth.currentUser?.id) {
      await _notifyIfEnabled(
        NotificationCategory.events,
        'IB 운영 일정이 등록됐습니다',
        title == null || title.isEmpty
            ? '일정 탭에서 배정을 확인해 주세요.'
            : '$title · 일정 탭에서 확인해 주세요.',
        route: '/operations',
      );
    }
  }

  void _applySnapshot(LockerSnapshot snapshot, {required bool isSyncing}) {
    state = state.copyWith(
      isReady: true,
      events: snapshot.events,
      attendance: snapshot.attendance,
      videos: snapshot.videos,
      likedVideoIds: snapshot.likedVideoIds,
      hasMoreEvents: snapshot.hasMoreEvents,
      isOfflineCache: snapshot.fromCache,
      isSyncing: isSyncing,
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
    final operationAssignmentChannel = _operationAssignmentChannel;
    if (operationAssignmentChannel != null) {
      _repository?.unsubscribe(operationAssignmentChannel);
    }
    final eventChannel = _eventChannel;
    if (eventChannel != null) _repository?.unsubscribe(eventChannel);
    final videoFeedChannel = _videoFeedChannel;
    if (videoFeedChannel != null) _repository?.unsubscribe(videoFeedChannel);
    final activationChannel = _activationRequestChannel;
    if (activationChannel != null) _repository?.unsubscribe(activationChannel);
    super.dispose();
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  void selectGameSegment(int index) =>
      state = state.copyWith(gameSegment: index, gameSubSegment: 0);
  void selectGameSubSegment(int index) =>
      state = state.copyWith(gameSubSegment: index);

  void selectMemberSegment(int index) => _selectMemberSegment(index);

  Future<void> reload() => _load();

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

  @override
  Future<DateTime> serverNow() async {
    try {
      return await _repository?.loadServerTime() ?? DateTime.now();
    } on Object {
      return DateTime.now();
    }
  }
}

List<VideoItem> _seedVideos() {
  final now = DateTime.now();
  return [
    for (final (index, reel) in defaultReelTitlesByShortcode.entries.indexed)
      VideoItem(
        id: 'instagram-${reel.key}',
        title: reel.value,
        durationLabel: '',
        category: '하이라이트',
        url: 'https://www.instagram.com/reel/${reel.key}/',
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
  ];
}

@visibleForTesting
const defaultReelTitlesByShortcode = {
  'Db2nVhDz4Fq': 'Kusf 하이라이트 - 진격의 엔크바',
  'DajgzpRTc4e': '엔크바 1학기 외부대회 하이라이트',
  'DZDMprWogCr': '살짝 꼬니까 다 들어가네?',
  'DXPE0fsEwcm': '서울대 대표 농친자들, 엔크바의 귀염뽀짝한 24시간',
  'DTnGCB7E50t': '2025 The Process 엔크바 하이라이트',
};

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
