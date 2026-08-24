import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/locker/application/locker_state.dart';
import 'package:encba_locker/features/locker/data/supabase_locker_repository.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/services/notification_category_prefs.dart';
import 'package:encba_locker/features/locker/services/web_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:encba_locker/features/locker/application/locker_state.dart';

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
  RealtimeChannel? _operationAssignmentChannel;
  RealtimeChannel? _eventChannel;
  RealtimeChannel? _videoFeedChannel;
  final _notificationPrefs = NotificationCategoryPrefs();
  Timer? _undecidedReminderTimer;
  Future<void>? _loadInFlight;
  Future<void>? _homecomingContactsLoadInFlight;
  Future<void>? _auditEntriesLoadInFlight;
  final Map<String, int> _voteRevisions = {};
  final Map<String, Future<void>> _voteWriteTails = {};

  /// 멤버를 다시 읽을 때 화면에 걸려 있던 검색·필터를 그대로 다시 건다.
  /// 조건을 잃으면 수정 직후 목록이 통째로 갈아엎여 저장이 안 된 것처럼 보인다.
  String _memberQuery = '';
  String _memberMembership = 'ALL';
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
      // 관리자가 IB 운영표를 올리면 내 배정이 실시간으로 도착한다.
      // 재접속 없이 홈·일정·운영 화면에 바로 반영되게 한다.
      _operationAssignmentChannel ??= repository
          .subscribeToOperationAssignments((record) {
            unawaited(_mergeRealtimeOperations(repository, record));
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

  /// 항목별 알림 설정이 꺼져 있으면 브라우저 알림 자체를 띄우지 않는다.
  Future<void> _notifyIfEnabled(
    NotificationCategory category,
    String title,
    String body,
  ) async {
    if (!await _notificationPrefs.isEnabled(category)) return;
    await WebNotificationService().show(title, body);
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
      unreadNotifications: state.unreadNotifications + 1,
    );
    await _notifyIfEnabled(
      NotificationCategory.announcements,
      announcement.title,
      announcement.body,
    );
  }

  /// 새로 등록된(또는 시간이 바뀐) 내 운영 배정을 목록에 합친다.
  /// 서버에서 전체를 다시 읽어 오는 게 가장 단순하고 안전하다.
  Future<void> _mergeRealtimeOperations(
    SupabaseLockerRepository repository,
    Map<String, dynamic> record,
  ) async {
    final operations = await _orDefault(
      repository.loadOperations(),
      const <OperationAssignment>[],
    );
    state = state.copyWith(operations: operations);
    final title = record['title'] as String?;
    await _notifyIfEnabled(
      NotificationCategory.events,
      'IB 운영 일정이 등록됐습니다',
      title == null || title.isEmpty
          ? '일정 탭에서 배정을 확인해 주세요.'
          : '$title · 일정 탭에서 확인해 주세요.',
    );
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

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  /// 홈커밍 연락망은 전용 화면에 들어올 때만 불러와 초기 동기화를 가볍게 유지한다.
  Future<void> loadHomecomingContacts() {
    final inFlight = _homecomingContactsLoadInFlight;
    if (inFlight != null) return inFlight;
    if (_repository == null) return Future<void>.value();
    final next = _repository
        .loadHomecomingContacts()
        .then((contacts) {
          state = state.copyWith(
            homecomingContacts: contacts,
            clearError: true,
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'ENCBA homecoming contacts load failed: $error\n$stackTrace',
          );
          state = state.copyWith(error: '홈커밍 연락망을 불러오지 못했습니다.');
        });
    _homecomingContactsLoadInFlight = next;
    return next.whenComplete(() {
      if (identical(_homecomingContactsLoadInFlight, next)) {
        _homecomingContactsLoadInFlight = null;
      }
    });
  }

  /// 감사 로그는 감사 화면에서만 필요하므로 진입 시점까지 네트워크 요청을 미룬다.
  Future<void> loadAuditEntries() {
    final inFlight = _auditEntriesLoadInFlight;
    if (inFlight != null) return inFlight;
    if (_repository == null) return Future<void>.value();
    final next = _repository
        .loadAuditLogs()
        .then((entries) {
          state = state.copyWith(auditEntries: entries, clearError: true);
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('ENCBA audit log load failed: $error\n$stackTrace');
          state = state.copyWith(error: '수정 이력을 불러오지 못했습니다.');
        });
    _auditEntriesLoadInFlight = next;
    return next.whenComplete(() {
      if (identical(_auditEntriesLoadInFlight, next)) {
        _auditEntriesLoadInFlight = null;
      }
    });
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

  /// 구글 로그인 때 대조하는 가입 명단에 아직 계정이 없는 신규 인원을 추가한다.
  /// 성공하면 null, 실패하면 화면에 그대로 띄울 사유를 돌려준다.
  Future<String?> addMember(MemberProfile member) async {
    if (_repository == null) return '멤버를 등록할 수 없는 상태입니다.';
    try {
      await _repository.addAllowlistMember(member);
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA member add failed: $error\n$stackTrace');
      final message = _memberUpdateMessage(error, adding: true);
      state = state.copyWith(error: message);
      return message;
    }
    final members = await _orDefault(
      _repository.loadMembers(
        membership: _memberMembership,
        query: _memberQuery,
      ),
      state.members,
    );
    state = state.copyWith(members: members, clearError: true);
    return null;
  }

  String _memberUpdateMessage(Object error, {bool adding = false}) {
    final text = error is PostgrestException
        ? '${error.code ?? ''} ${error.message}'
        : error.toString();
    if (error is PostgrestException && error.code == '23505') {
      return '이미 등록된 이름입니다.';
    }
    if (text.contains('ENCBA_RESERVATION_ROLE_ADMIN_ONLY')) {
      return '체육관 예약자 지정은 관리자만 바꿀 수 있습니다.';
    }
    if (text.contains('ENCBA_DEPARTMENT_ADMIN_ONLY')) {
      return '학과는 관리자만 바꿀 수 있습니다.';
    }
    if (text.contains('ENCBA_ADMIN_OR_CAPTAIN_REQUIRED')) {
      return adding
          ? '관리자나 주장만 멤버를 등록할 수 있습니다.'
          : '관리자나 주장만 멤버 정보를 수정할 수 있습니다.';
    }
    if (text.contains('ENCBA_INVALID_MEMBER_PROFILE')) {
      return '학번·가입 연도·등번호·소속을 확인해 주세요.';
    }
    if (text.contains('PGRST202') ||
        text.contains('Could not find the function')) {
      return '서버에 최신 마이그레이션이 적용되지 않았습니다. supabase db push가 필요합니다.';
    }
    return adding ? '멤버를 등록하지 못했습니다.' : '멤버 정보를 수정하지 못했습니다.';
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

  Future<bool> assignHomecomingContact({
    required HomecomingContact contact,
    MemberProfile? member,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    final previous = state.homecomingContacts;
    final updated = contact.assignedTo(id: member?.id, name: member?.name);
    state = state.copyWith(
      homecomingContacts: previous
          .map((item) => item.id == contact.id ? updated : item)
          .toList(growable: false),
    );
    try {
      await repository.assignHomecomingContact(
        id: contact.id,
        assignedToId: member?.id,
        assignedToName: member?.name,
      );
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint(
        'ENCBA homecoming assignee update failed: $error\n$stackTrace',
      );
      state = state.copyWith(
        homecomingContacts: previous,
        error: '홈커밍 담당자를 저장하지 못했습니다.',
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

  Future<bool> deactivateHomecomingCampaign(String campaignId) async {
    try {
      await _repository?.deactivateHomecomingCampaign(campaignId);
      state = state.copyWith(
        clearHomecomingCampaign: true,
        homecomingContacts: const [],
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '홈커밍 캠페인을 다시 잠그지 못했습니다.');
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

  /// 관리자가 홈커밍 연락 보드에 선배를 한 명 직접 추가한다.
  Future<bool> addHomecomingContact({
    required String name,
    required String phone,
    int? generation,
    String? assignedToId,
    String? assignedToName,
  }) async {
    final campaign = state.homecomingCampaign;
    final repository = _repository;
    if (campaign == null || repository == null) return false;
    try {
      await repository.addHomecomingContact(
        campaignId: campaign.id,
        name: name,
        phone: phone,
        generation: generation,
        assignedToId: assignedToId,
        assignedToName: assignedToName,
      );
      final refreshed = await repository.loadHomecomingContacts();
      state = state.copyWith(homecomingContacts: refreshed, clearError: true);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA homecoming contact add failed: $error\n$stackTrace');
      state = state.copyWith(error: '선배 연락처를 추가하지 못했습니다.');
      return false;
    }
  }

  /// 관리자가 홈커밍 연락 보드에서 선배 카드를 삭제한다.
  Future<bool> deleteHomecomingContact(String id) async {
    final repository = _repository;
    if (repository == null) return false;
    final previous = state.homecomingContacts;
    state = state.copyWith(
      homecomingContacts: previous.where((item) => item.id != id).toList(),
    );
    try {
      await repository.deleteHomecomingContact(id);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA homecoming contact delete failed: $error\n$stackTrace');
      state = state.copyWith(
        homecomingContacts: previous,
        error: '선배 연락처를 삭제하지 못했습니다.',
      );
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

  /// 관리자용: 학기 전체 IB 운영 배정을 읽어 온다.
  Future<List<OperationAssignment>> loadAllOperations() async {
    final repository = _repository;
    if (repository == null) return const [];
    return _orDefault(
      repository.loadAllOperations(),
      const <OperationAssignment>[],
    );
  }

  /// 관리자가 전체 운영 배정을 수정한 뒤 내 일정과 교환 게시판을 새로 읽는다.
  Future<bool> updateOperationAssignment({
    required OperationAssignment assignment,
    required DateTime start,
    required DateTime end,
    required String title,
    required String location,
    required String memo,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      await repository.updateOperationAssignment(
        id: assignment.id,
        start: start,
        end: end,
        title: title,
        location: location,
        memo: memo,
      );
      await refreshOperationSwaps();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation update failed: $error\n$stackTrace');
      state = state.copyWith(error: '운영 일정을 수정하지 못했습니다.');
      return false;
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
    bool isUrgent = false,
    List<String> linkedEventIds = const [],
    String? imageBase64,
    String? imageName,
    List<String> pollOptions = const [],
    String pollQuestion = '',
  }) async {
    try {
      final saved = await _repository?.addAnnouncement(
        title: title,
        body: body,
        pinned: pinned,
        isUrgent: isUrgent,
        linkedEventIds: linkedEventIds,
        imageBase64: imageBase64,
        imageName: imageName,
        pollOptions: pollOptions,
        pollQuestion: pollQuestion,
      );
      if (saved != null) {
        // Realtime 구독이 같은 INSERT를 이 응답보다 먼저 받아 이미 추가해
        // 뒀을 수 있다. 그 경우 낙관적 추가를 또 하면 같은 공지가 두 번
        // 보인다.
        final alreadyMerged = state.announcements.any(
          (item) => item.id == saved.id,
        );
        if (!alreadyMerged) {
          state = state.copyWith(
            announcements: [saved, ...state.announcements],
          );
        }
      }
      return saved != null;
    } on Object catch (error) {
      state = state.copyWith(
        error: _announcementError(error, '공지를 저장하지 못했습니다.'),
      );
      return false;
    }
  }

  Future<bool> updateAnnouncement({
    required AnnouncementItem announcement,
    required String title,
    required String body,
    required bool pinned,
    bool? isUrgent,
    List<String> linkedEventIds = const [],
    String? imageBase64,
    String? imageName,
    bool removeImage = false,
    List<String> pollOptions = const [],
    String pollQuestion = '',
  }) async {
    try {
      final saved = await _repository?.updateAnnouncement(
        id: announcement.id,
        title: title,
        body: body,
        pinned: pinned,
        isUrgent: isUrgent ?? announcement.isUrgent,
        linkedEventIds: linkedEventIds,
        existingImageUrl: announcement.imageUrl,
        imageBase64: imageBase64,
        imageName: imageName,
        removeImage: removeImage,
        pollOptions: pollOptions,
        pollQuestion: pollQuestion,
      );
      if (saved == null) return false;
      state = state.copyWith(
        announcements: state.announcements
            .map((item) => item.id == saved.id ? saved : item)
            .toList(),
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      state = state.copyWith(
        error: _announcementError(error, '공지를 수정하지 못했습니다.'),
      );
      return false;
    }
  }

  Future<bool> deleteAnnouncement(String id) async {
    try {
      final imageUrl = state.announcements
          .where((item) => item.id == id)
          .firstOrNull
          ?.imageUrl;
      await _repository?.deleteAnnouncement(id, imageUrl: imageUrl);
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

  Future<bool> voteAnnouncement(
    AnnouncementItem announcement,
    int optionIndex,
  ) async {
    if (optionIndex < 0 || optionIndex >= announcement.pollOptions.length) {
      return false;
    }
    final previousOption = announcement.myPollOption;
    final counts = Map<int, int>.from(announcement.pollVotes);
    if (previousOption != null && previousOption != optionIndex) {
      final previousCount = counts[previousOption] ?? 0;
      if (previousCount <= 1) {
        counts.remove(previousOption);
      } else {
        counts[previousOption] = previousCount - 1;
      }
    }
    if (previousOption != optionIndex) {
      counts.update(optionIndex, (count) => count + 1, ifAbsent: () => 1);
    }
    final optimistic = announcement.copyWith(
      pollVotes: counts,
      myPollOption: optionIndex,
    );
    state = state.copyWith(
      announcements: state.announcements
          .map((item) => item.id == announcement.id ? optimistic : item)
          .toList(),
    );
    try {
      await _repository?.voteAnnouncement(announcement.id, optionIndex);
      state = state.copyWith(clearError: true);
      return true;
    } on Object {
      state = state.copyWith(
        announcements: state.announcements
            .map((item) => item.id == announcement.id ? announcement : item)
            .toList(),
        error: '공지 투표를 저장하지 못했습니다.',
      );
      return false;
    }
  }

  String _announcementError(Object error, String fallback) =>
      error is LockerRepositoryException ? error.message : fallback;

  /// 투표 현황 시트를 열 때만 부르는 온디맨드 조회라 다른 보조 데이터처럼
  /// 실패해도 전역 에러 상태를 건드리지 않고 빈 목록으로 조용히 넘어간다.
  Future<List<AnnouncementPollVoter>> loadAnnouncementPollVoters(
    String announcementId,
  ) async {
    final repository = _repository;
    if (repository == null) return const [];
    return _orDefault(
      repository.loadAnnouncementPollVoters(announcementId),
      const <AnnouncementPollVoter>[],
    );
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
    } on Object catch (error) {
      debugPrint('ENCBA video comment save failed: $error');
      // 디버그 빌드에서는 실제 서버 사유를 함께 보여준다.
      final detail = kDebugMode ? '\n(${error.toString()})' : '';
      state = state.copyWith(error: '영상 코멘트를 저장하지 못했습니다.$detail');
      return false;
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
