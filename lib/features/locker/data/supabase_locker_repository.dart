import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _encbaUtcOffset = Duration(hours: 9);

/// Returns the UTC instant at which the current ENCBA business day started.
///
/// Schedules are operated in Korea even when a member opens the app while the
/// device is set to another time zone. Keeping this calculation independent of
/// the device locale also makes the server query boundary deterministic.
@visibleForTesting
DateTime encbaDayStartsAtUtc(DateTime now) {
  final koreaNow = now.toUtc().add(_encbaUtcOffset);
  return DateTime.utc(
    koreaNow.year,
    koreaNow.month,
    koreaNow.day,
  ).subtract(_encbaUtcOffset);
}

class LockerRepositoryException implements Exception {
  const LockerRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LockerSnapshot {
  const LockerSnapshot({
    required this.events,
    required this.attendance,
    required this.videos,
    required this.likedVideoIds,
    this.hasMoreEvents = false,
    this.fromCache = false,
  });

  final List<LockerEvent> events;
  final Map<String, String> attendance;
  final List<VideoItem> videos;
  final Set<String> likedVideoIds;
  final bool hasMoreEvents;
  final bool fromCache;
}

class SupabaseLockerRepository {
  SupabaseLockerRepository(this._client, this._store);

  String get _cacheKey => 'encba.remote-snapshot.$_userId.v2';
  final SupabaseClient _client;
  final LocalStore _store;
  static const int eventPageSize = 20;
  static const int videoPageSize = 30;
  static const _initialReadTimeout = Duration(seconds: 6);
  static const _announcementSelection =
      'id,title,body,pinned,is_urgent,published_at,image_url,poll_options,'
      'poll_question,'
      'profiles!announcements_created_by_fkey(name,display_name),'
      'announcement_event_links(event_id),'
      'announcement_poll_votes(profile_id,option_index)';
  static const _legacyAnnouncementSelection =
      'id,title,body,pinned,published_at,'
      'profiles!announcements_created_by_fkey(name,display_name),'
      'announcement_event_links(event_id)';
  static const _eventSelection =
      'id,title,starts_at,ends_at,place_label,court,kind,memo,'
      'uniform_colors,capacity,attending_count,target_team,updated_at,'
      'ob_participant_count,'
      'recurrence_rule,response_enabled,response_deadline,poll_options,'
      'visibility,opponent,opponents,map_reference,'
      'places(name),profiles!events_created_by_fkey(name)';
  static const _videoSelection =
      'id,title,category,source_url,youtube_id,source_type,'
      'quarter_1_url,quarter_2_url,quarter_3_url,quarter_4_url,'
      'audience_type,audience_values,duration_seconds,created_at,like_count,'
      'recorded_on,video_links(id,quarter_number,url,sort_order),'
      'profiles!videos_uploaded_by_fkey(name,display_name)';

  /// 링크 테이블 마이그레이션 전 서버에서도 영상 목록은 보여야 한다.
  static const _legacyVideoSelection =
      'id,title,category,source_url,youtube_id,source_type,'
      'quarter_1_url,quarter_2_url,quarter_3_url,quarter_4_url,'
      'audience_type,audience_values,duration_seconds,created_at,like_count,'
      'profiles!videos_uploaded_by_fkey(name,display_name)';

  String get _userId =>
      _client.auth.currentUser?.id ?? (throw StateError('로그인이 필요합니다.'));

  Future<LockerSnapshot?> loadCached() => _readCache();

  Future<LockerSnapshot> load({LockerSnapshot? fallback}) async {
    final todayStartsAt = encbaDayStartsAtUtc(DateTime.now()).toIso8601String();
    final cached = fallback ?? await _readCache();
    var usedFallback = false;
    void markFallback() => usedFallback = true;
    final eventFuture = _orFallback<({List<LockerEvent> events, bool hasMore})>(
      _loadEventPage(
        todayStartsAt: todayStartsAt,
        offset: 0,
        limit: eventPageSize,
        includeLocked: true,
      ).timeout(_initialReadTimeout),
      (
        events: cached?.events ?? const <LockerEvent>[],
        hasMore: cached?.hasMoreEvents ?? false,
      ),
      debugLabel: 'events',
      onFallback: markFallback,
    );
    final attendanceFuture = _orFallback<Map<String, String>>(
      _loadMyAttendance().timeout(_initialReadTimeout),
      cached?.attendance ?? const <String, String>{},
      onFallback: markFallback,
    );
    final videosFuture = _orFallback<List<VideoItem>>(
      _loadVideos().timeout(_initialReadTimeout),
      cached?.videos ?? const <VideoItem>[],
      debugLabel: 'videos',
      onFallback: markFallback,
    );
    final likesFuture = _orFallback<Set<String>>(
      _loadLikedVideoIds().timeout(_initialReadTimeout),
      cached?.likedVideoIds ?? const <String>{},
      onFallback: markFallback,
    );

    final eventPage = await eventFuture;
    final attendance = await attendanceFuture;
    final videos = await videosFuture;
    final likes = await likesFuture;
    final snapshot = LockerSnapshot(
      events: eventPage.events,
      attendance: attendance,
      videos: videos,
      likedVideoIds: likes,
      hasMoreEvents: eventPage.hasMore,
      fromCache: usedFallback,
    );
    unawaited(
      _cache(snapshot).catchError((Object _) {
        // 온라인 응답은 로컬 캐시 저장 실패와 무관하게 그대로 사용한다.
      }),
    );
    return snapshot;
  }

  Future<Map<String, String>> _loadMyAttendance() async {
    final rows = await _client
        .from('event_attendance')
        .select('event_id,choice')
        .eq('profile_id', _userId);
    return {
      for (final row in rows)
        row['event_id'] as String: row['choice'] as String,
    };
  }

  Future<List<VideoItem>> _loadVideos() async {
    final rows = await _selectVideos(
      (selection) => _client
          .from('videos')
          .select(selection)
          .order('created_at', ascending: false)
          .order('id')
          .limit(videoPageSize),
    );
    final videos = rows.map<VideoItem>(_videoFromRow).toList(growable: false);
    return _attachReviewPlayers(videos);
  }

  Future<VideoItem?> loadVideo(String id) async {
    final rows = await _selectVideos(
      (selection) =>
          _client.from('videos').select(selection).eq('id', id).limit(1),
    );
    if (rows.isEmpty) return null;
    final videos = await _attachReviewPlayers([_videoFromRow(rows.first)]);
    return videos.first;
  }

  /// 링크 테이블이 아직 없는 서버에서는 예전 컬럼만 골라 다시 물어본다.
  Future<List<Map<String, dynamic>>> _selectVideos(
    Future<List<Map<String, dynamic>>> Function(String selection) query,
  ) async {
    try {
      final rows = await query(_videoSelection);
      return rows.map(Map<String, dynamic>.from).toList(growable: false);
    } on PostgrestException catch (error) {
      if (!_isMissingVideoLinkFeature(error)) rethrow;
      debugPrint('Supabase video link migration pending: $error');
      final rows = await query(_legacyVideoSelection);
      return rows.map(Map<String, dynamic>.from).toList(growable: false);
    }
  }

  Future<Set<String>> _loadLikedVideoIds() async {
    final rows = await _client
        .from('video_likes')
        .select('video_id')
        .eq('profile_id', _userId);
    return {for (final row in rows) row['video_id'] as String};
  }

  Future<({List<LockerEvent> events, bool hasMore})> loadMoreEvents({
    required int offset,
  }) {
    return _loadEventPage(
      todayStartsAt: encbaDayStartsAtUtc(DateTime.now()).toIso8601String(),
      offset: offset,
      limit: eventPageSize,
      includeLocked: false,
    );
  }

  /// 공유 주소로 들어온 일정 하나를 초기 페이지와 무관하게 불러온다.
  Future<LockerEvent?> loadEvent(String id) async {
    final rows = await _client
        .from('events')
        .select(_eventSelection)
        .eq('id', id)
        .isFilter('cancelled_at', null)
        .limit(1);
    if (rows.isEmpty) return null;

    var event = _eventFromRow(Map<String, dynamic>.from(rows.first));
    final starterRows = await _orFallback<List<dynamic>>(
      _client.rpc(
        'list_event_starters',
        params: {
          'requested_event_ids': [id],
        },
      ),
      const <dynamic>[],
      debugLabel: 'event starters',
    );
    if (starterRows.isNotEmpty) {
      event = event.copyWith(
        starterProfileIds: starterRows
            .map(
              (raw) =>
                  Map<String, dynamic>.from(raw as Map)['directory_id']
                      as String,
            )
            .toList(growable: false),
        starterNames: starterRows
            .map(
              (raw) => Map<String, dynamic>.from(raw as Map)['name'] as String,
            )
            .toList(growable: false),
      );
    }
    return event;
  }

  Future<({List<LockerEvent> events, bool hasMore})> _loadEventPage({
    required String todayStartsAt,
    required int offset,
    required int limit,
    required bool includeLocked,
  }) async {
    final normalFuture = _client
        .from('events')
        .select(_eventSelection)
        .gte('ends_at', todayStartsAt)
        .isFilter('cancelled_at', null)
        .order('starts_at')
        .order('id')
        .range(offset, offset + limit - 1);
    final lockedFuture = includeLocked
        ? _orFallback<dynamic>(
            _client.rpc('list_locked_event_stubs'),
            const <dynamic>[],
          )
        : Future<dynamic>.value(const <dynamic>[]);
    final normalRows = await normalFuture;
    final lockedRows = await lockedFuture;
    var events =
        <LockerEvent>[
          ...normalRows.map(
            (row) => _eventFromRow(Map<String, dynamic>.from(row as Map)),
          ),
          ...(lockedRows as List).map(
            (row) => _eventFromRow(Map<String, dynamic>.from(row as Map)),
          ),
        ]..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
    final starterRows = events.isEmpty
        ? const <dynamic>[]
        : await _orFallback<List<dynamic>>(
            _client.rpc(
              'list_event_starters',
              params: {
                'requested_event_ids': events.map((event) => event.id).toList(),
              },
            ),
            const <dynamic>[],
            debugLabel: 'event starters',
          );
    if (starterRows.isNotEmpty) {
      final ids = <String, List<String>>{};
      final names = <String, List<String>>{};
      for (final raw in starterRows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final eventId = row['event_id'] as String;
        ids.putIfAbsent(eventId, () => []).add(row['directory_id'] as String);
        names.putIfAbsent(eventId, () => []).add(row['name'] as String);
      }
      events = events
          .map(
            (event) => event.copyWith(
              starterProfileIds: ids[event.id] ?? const [],
              starterNames: names[event.id] ?? const [],
            ),
          )
          .toList(growable: false);
    }
    return (events: events, hasMore: normalRows.length == limit);
  }

  Future<T> _orFallback<T>(
    Future<T> future,
    T fallback, {
    String? debugLabel,
    VoidCallback? onFallback,
  }) async {
    try {
      return await future;
    } on Object catch (error) {
      onFallback?.call();
      if (debugLabel != null) {
        debugPrint('Supabase $debugLabel load failed: $error');
      }
      return fallback;
    }
  }

  Future<List<MemberProfile>> loadMembers({
    String membership = 'ALL',
    String query = '',
  }) async {
    final rows = await _client.rpc(
      'list_member_directory',
      params: {
        'requested_status': membership == 'MILITARY' ? 'military' : 'all',
        'requested_query': query.trim(),
      },
    );
    return (rows as List<dynamic>)
        .map<MemberProfile>((row) {
          final map = Map<String, dynamic>.from(row);
          final directoryId = map['directory_id'] as String;
          // 아직 구글 계정으로 가입하지 않은 명단(allowlist) 전용 항목은
          // DB의 is_active 값(명단 등록 시 기본값)과 무관하게 항상 비활성으로
          // 취급한다. 실제로 로그인해 profiles 행이 생겨야 활성일 수 있다.
          final hasRegisteredAccount = !directoryId.startsWith('allowlist:');
          return MemberProfile(
            id: directoryId,
            name: map['name'] as String,
            studentId: map['student_year'] == null
                ? '학번 미등록'
                : '${map['student_year']}학번',
            generation: map['generation'] as int? ?? 1,
            joinedYear: map['joined_year'] as int?,
            status: (map['membership_status'] as String).toUpperCase(),
            position: map['position'] as String? ?? '미정',
            teams:
                (map['team_codes'] as List?)?.cast<String>() ?? const ['ENCBA'],
            note: '',
            badge: map['membership_status'] == 'military_leave' ? '군복무' : null,
            isActive:
                hasRegisteredAccount && (map['is_active'] as bool? ?? true),
            phone: map['phone'] as String? ?? '',
            jerseyNumber: map['jersey_number'] as int? ?? 0,
            leadershipRole: map['leadership_role'] as String? ?? 'member',
            isReservationManager:
                map['is_reservation_manager'] as bool? ?? false,
            department: map['department'] as String? ?? '',
            isFreshman: map['is_freshman'] as bool? ?? false,
            titles: (map['titles'] as List?)?.cast<String>() ?? const [],
            avatarUrl: _avatarPublicUrl(map['avatar_path'] as String?),
          );
        })
        .toList(growable: false);
  }

  /// avatars 버킷은 public이므로 경로만 있으면 공개 URL을 만들 수 있다.
  String? _avatarPublicUrl(String? path) => path == null || path.isEmpty
      ? null
      : _client.storage.from('avatars').getPublicUrl(path);

  /// 멤버 상세 공유 주소를 위해 검색·필터 상태와 무관하게 한 명을 찾는다.
  Future<MemberProfile?> loadMember(String id) async {
    final members = await loadMembers();
    for (final member in members) {
      if (member.id == id) return member;
    }
    return null;
  }

  Future<void> setMemberActive(String profileId, bool isActive) => _client.rpc(
    'set_member_account_active',
    params: {'requested_directory_id': profileId, 'requested_active': isActive},
  );

  /// 멤버 수정은 한 번의 RPC로 끝낸다. 예전처럼 여러 함수를 이어 부르면
  /// 중간에서 실패했을 때 앞부분만 커밋된 채로 남는다.
  Future<void> updateMember(MemberProfile member) => _client.rpc(
    'admin_update_member',
    params: {
      'requested_directory_id': member.id,
      'requested_name': member.name,
      'requested_student_year': int.tryParse(
        member.studentId.replaceAll(RegExp(r'[^0-9]'), ''),
      ),
      'requested_joined_year': member.joinedYear,
      'requested_phone': member.phone,
      'requested_position': member.position,
      'requested_jersey_number': member.jerseyNumber,
      'requested_membership_status': member.status.toLowerCase(),
      'requested_team_codes': member.teams,
      'requested_leadership_role': member.leadershipRole,
      'requested_active': member.isActive,
      'requested_department': member.department,
      'requested_reservation_manager': member.isReservationManager,
      'requested_freshman': member.isFreshman,
      'requested_titles': member.titles,
    },
  );

  /// 구글 로그인 대조용 가입 명단에 아직 아무 계정도 없는 신규 인원을 만든다.
  Future<void> addAllowlistMember(MemberProfile member) => _client.rpc(
    'admin_add_allowlist_member',
    params: {
      'requested_name': member.name,
      'requested_student_year': int.tryParse(
        member.studentId.replaceAll(RegExp(r'[^0-9]'), ''),
      ),
      'requested_joined_year': member.joinedYear,
      'requested_phone': member.phone,
      'requested_position': member.position,
      'requested_jersey_number': member.jerseyNumber,
      'requested_membership_status': member.status.toLowerCase(),
      'requested_team_codes': member.teams,
      'requested_leadership_role': member.leadershipRole,
      'requested_department': member.department,
      'requested_reservation_manager': member.isReservationManager,
      'requested_freshman': member.isFreshman,
      'requested_titles': member.titles,
      'requested_active': member.isActive,
    },
  );

  Future<List<AttendanceReportRow>> loadAttendanceReport({
    required DateTime from,
    required DateTime to,
    required bool freshmenOnly,
  }) async {
    final rows = await _client.rpc(
      'get_attendance_report',
      params: {
        'requested_from': from.toUtc().toIso8601String(),
        'requested_to': to.toUtc().toIso8601String(),
        'requested_freshmen_only': freshmenOnly,
      },
    );
    return (rows as List<dynamic>)
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          return AttendanceReportRow(
            directoryId: row['directory_id'] as String,
            memberName: row['member_name'] as String,
            studentYear: _databaseInt(row['student_year']),
            isFreshman: row['is_freshman'] as bool? ?? false,
            eventId: row['event_id'] as String,
            eventTitle: row['event_title'] as String,
            eventStart: DateTime.parse(row['event_start'] as String).toLocal(),
            eventKind: row['event_kind'] as String,
            choice: row['choice'] as String?,
            absenceReason: row['absence_reason'] as String?,
          );
        })
        .toList(growable: false);
  }

  Future<DateTime> loadServerTime() async {
    final value = await _client.rpc('get_server_time');
    return DateTime.parse(value as String).toLocal();
  }

  Future<AttendanceRates> loadAttendanceRates() async {
    final rows = await _client.rpc('get_my_attendance_rates');
    if ((rows as List).isEmpty) return const AttendanceRates();
    final row = Map<String, dynamic>.from(rows.first as Map);
    return AttendanceRates(
      training: row['training_rate'] as int? ?? 0,
      morning: row['morning_rate'] as int? ?? 0,
      game: row['game_rate'] as int? ?? 0,
    );
  }

  Future<List<AnnouncementItem>> loadAnnouncements() async {
    final rows = await _selectAnnouncementRows(
      (selection) => _client
          .from('announcements')
          .select(selection)
          .order('pinned', ascending: false)
          .order('published_at', ascending: false)
          .limit(50),
    );
    return rows.map(_announcementFromRow).toList();
  }

  Future<AnnouncementItem?> loadAnnouncement(String id) async {
    final rows = await _selectAnnouncementRows(
      (selection) =>
          _client.from('announcements').select(selection).eq('id', id).limit(1),
    );
    if (rows.isEmpty) return null;
    return _announcementFromRow(rows.first);
  }

  Future<AnnouncementItem> addAnnouncement({
    required String title,
    required String body,
    required bool pinned,
    required bool isUrgent,
    List<String> linkedEventIds = const [],
    String? imageBase64,
    String? imageName,
    List<String> pollOptions = const [],
    String pollQuestion = '',
  }) async {
    String? uploadedPath;
    String? imageUrl;
    if (imageBase64 != null) {
      final uploaded = await _uploadAnnouncementImage(imageBase64, imageName);
      uploadedPath = uploaded.path;
      imageUrl = uploaded.url;
    }
    final payload = <String, dynamic>{
      'title': title,
      'body': body,
      'pinned': pinned,
      'is_urgent': isUrgent,
      'image_url': imageUrl,
      'poll_options': pollOptions,
      'poll_question': pollQuestion,
      'created_by': _userId,
      'updated_by': _userId,
    };
    final Map<String, dynamic> row;
    try {
      row = await _writeAnnouncement(
        () => _client
            .from('announcements')
            .insert(payload)
            .select(_announcementSelection)
            .single(),
        () => _client
            .from('announcements')
            .insert(
              Map<String, dynamic>.from(payload)
                ..remove('is_urgent')
                ..remove('image_url')
                ..remove('poll_options')
                ..remove('poll_question'),
            )
            .select(_legacyAnnouncementSelection)
            .single(),
        requiresCurrentSchema:
            imageBase64 != null ||
            pollOptions.isNotEmpty ||
            pollQuestion.trim().isNotEmpty,
      );
    } on Object {
      if (uploadedPath != null) {
        await _tryRemoveUploadedAnnouncementImage(uploadedPath);
      }
      rethrow;
    }
    final saved = _announcementFromRow(
      Map<String, dynamic>.from(row)
        ..['announcement_event_links'] = [
          for (final eventId in linkedEventIds) {'event_id': eventId},
        ],
    );
    await _replaceAnnouncementEvents(
      announcementId: saved.id,
      eventIds: linkedEventIds,
    );
    return saved;
  }

  Future<AnnouncementItem> updateAnnouncement({
    required String id,
    required String title,
    required String body,
    required bool pinned,
    required bool isUrgent,
    List<String> linkedEventIds = const [],
    String? existingImageUrl,
    String? imageBase64,
    String? imageName,
    bool removeImage = false,
    List<String> pollOptions = const [],
    String pollQuestion = '',
  }) async {
    String? uploadedPath;
    var imageUrl = removeImage ? null : existingImageUrl;
    if (imageBase64 != null) {
      final uploaded = await _uploadAnnouncementImage(imageBase64, imageName);
      uploadedPath = uploaded.path;
      imageUrl = uploaded.url;
    }
    final payload = <String, dynamic>{
      'title': title,
      'body': body,
      'pinned': pinned,
      'is_urgent': isUrgent,
      'image_url': imageUrl,
      'poll_options': pollOptions,
      'poll_question': pollQuestion,
      'updated_by': _userId,
    };
    final Map<String, dynamic> row;
    try {
      row = await _writeAnnouncement(
        () => _client
            .from('announcements')
            .update(payload)
            .eq('id', id)
            .select(_announcementSelection)
            .single(),
        () => _client
            .from('announcements')
            .update(
              Map<String, dynamic>.from(payload)
                ..remove('is_urgent')
                ..remove('image_url')
                ..remove('poll_options')
                ..remove('poll_question'),
            )
            .eq('id', id)
            .select(_legacyAnnouncementSelection)
            .single(),
        requiresCurrentSchema:
            existingImageUrl != null ||
            imageBase64 != null ||
            removeImage ||
            pollOptions.isNotEmpty ||
            pollQuestion.trim().isNotEmpty,
      );
    } on Object {
      if (uploadedPath != null) {
        await _tryRemoveUploadedAnnouncementImage(uploadedPath);
      }
      rethrow;
    }
    final saved = _announcementFromRow(
      Map<String, dynamic>.from(row)
        ..['announcement_event_links'] = [
          for (final eventId in linkedEventIds) {'event_id': eventId},
        ],
    );
    await _replaceAnnouncementEvents(
      announcementId: saved.id,
      eventIds: linkedEventIds,
    );
    if ((removeImage || imageBase64 != null) && existingImageUrl != null) {
      await _tryRemoveAnnouncementImage(existingImageUrl);
    }
    return saved;
  }

  Future<List<Map<String, dynamic>>> _selectAnnouncementRows(
    Future<List<Map<String, dynamic>>> Function(String selection) query,
  ) async {
    try {
      return await query(_announcementSelection);
    } on PostgrestException catch (error) {
      if (!_isMissingAnnouncementFeature(error)) rethrow;
      return query(_legacyAnnouncementSelection);
    }
  }

  Future<Map<String, dynamic>> _writeAnnouncement(
    Future<Map<String, dynamic>> Function() current,
    Future<Map<String, dynamic>> Function() legacy, {
    bool requiresCurrentSchema = false,
  }) async {
    try {
      return await current();
    } on PostgrestException catch (error) {
      if (!_isMissingAnnouncementFeature(error)) rethrow;
      if (requiresCurrentSchema) {
        throw const LockerRepositoryException(
          '서버에 공지 사진·투표 마이그레이션을 먼저 적용해 주세요.',
        );
      }
      return legacy();
    }
  }

  AnnouncementItem _announcementFromRow(Map<String, dynamic> row) {
    final author = row['profiles'] as Map?;
    final votes = (row['announcement_poll_votes'] as List? ?? const [])
        .cast<Map>();
    final counts = <int, int>{};
    int? myPollOption;
    for (final vote in votes) {
      final option = vote['option_index'] as int?;
      if (option == null) continue;
      counts.update(option, (count) => count + 1, ifAbsent: () => 1);
      if (vote['profile_id'] == _client.auth.currentUser?.id) {
        myPollOption = option;
      }
    }
    return AnnouncementItem(
      id: row['id'] as String,
      title: row['title'] as String,
      body: row['body'] as String,
      author:
          author?['name'] as String? ??
          author?['display_name'] as String? ??
          '운영진',
      publishedAt: DateTime.parse(row['published_at'] as String).toLocal(),
      pinned: row['pinned'] as bool? ?? false,
      isUrgent: row['is_urgent'] as bool? ?? false,
      linkedEventIds: (row['announcement_event_links'] as List? ?? const [])
          .map((item) => (item as Map)['event_id'] as String)
          .toList(growable: false),
      imageUrl: row['image_url'] as String?,
      pollOptions: (row['poll_options'] as List?)?.cast<String>() ?? const [],
      pollQuestion: row['poll_question'] as String? ?? '',
      pollVotes: counts,
      myPollOption: myPollOption,
    );
  }

  Future<({String path, String url})> _uploadAnnouncementImage(
    String imageBase64,
    String? imageName,
  ) async {
    final lowerName = imageName?.toLowerCase() ?? '';
    final extension = lowerName.endsWith('.png')
        ? 'png'
        : lowerName.endsWith('.webp')
        ? 'webp'
        : 'jpg';
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '$_userId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _client.storage
        .from('announcement-media')
        .uploadBinary(
          path,
          base64Decode(imageBase64),
          fileOptions: FileOptions(contentType: contentType),
        );
    return (
      path: path,
      url: _client.storage.from('announcement-media').getPublicUrl(path),
    );
  }

  Future<void> _removeAnnouncementImage(String imageUrl) async {
    const marker = '/object/public/announcement-media/';
    final index = imageUrl.indexOf(marker);
    if (index < 0) return;
    final path = Uri.decodeComponent(imageUrl.substring(index + marker.length));
    if (path.isNotEmpty) {
      await _client.storage.from('announcement-media').remove([path]);
    }
  }

  Future<void> _tryRemoveAnnouncementImage(String imageUrl) async {
    try {
      await _removeAnnouncementImage(imageUrl);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'ENCBA announcement image cleanup failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _tryRemoveUploadedAnnouncementImage(String path) async {
    try {
      await _client.storage.from('announcement-media').remove([path]);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'ENCBA uploaded announcement cleanup failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _replaceAnnouncementEvents({
    required String announcementId,
    required List<String> eventIds,
  }) => _client.rpc(
    'replace_announcement_events',
    params: {
      'requested_announcement_id': announcementId,
      'requested_event_ids': eventIds,
    },
  );

  Future<void> deleteAnnouncement(String id, {String? imageUrl}) async {
    await _client.from('announcements').delete().eq('id', id);
    if (imageUrl != null) await _tryRemoveAnnouncementImage(imageUrl);
  }

  Future<void> voteAnnouncement(String announcementId, int optionIndex) =>
      _client.from('announcement_poll_votes').upsert({
        'announcement_id': announcementId,
        'profile_id': _userId,
        'option_index': optionIndex,
        'voted_at': DateTime.now().toUtc().toIso8601String(),
      });

  /// 공지 투표 항목별로 "누가" 골랐는지 개별 응답자를 읽는다. 집계 카운트만
  /// 담는 `_announcementSelection`과 달리 투표 현황 화면 전용으로 필요할
  /// 때만 부른다. `announcement_poll_votes_read` 정책이 이미 전체 인증
  /// 사용자에게 열려 있어 별도 RPC 없이 다른 조인 select들과 같은 방식으로
  /// 읽는다.
  Future<List<AnnouncementPollVoter>> loadAnnouncementPollVoters(
    String announcementId,
  ) async {
    final rows = await _client
        .from('announcement_poll_votes')
        .select('profile_id,option_index,profiles(name,display_name)')
        .eq('announcement_id', announcementId);
    return (rows as List)
        .map((row) {
          final map = Map<String, dynamic>.from(row as Map);
          final profile = map['profiles'] as Map?;
          return AnnouncementPollVoter(
            profileId: map['profile_id'] as String,
            name:
                profile?['name'] as String? ??
                profile?['display_name'] as String? ??
                '알 수 없음',
            optionIndex: map['option_index'] as int,
          );
        })
        .toList(growable: false);
  }

  RealtimeChannel subscribeToAnnouncements(
    void Function(Map<String, dynamic> record) onInsert,
  ) => _client
      .channel('encba-announcements')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'announcements',
        callback: (payload) => onInsert(payload.newRecord),
      )
      .subscribe();

  RealtimeChannel subscribeToEvents(
    void Function(Map<String, dynamic> record) onInsert,
  ) => _client
      .channel('encba-events')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'events',
        callback: (payload) => onInsert(payload.newRecord),
      )
      .subscribe();

  RealtimeChannel subscribeToVideos(
    void Function(Map<String, dynamic> record) onInsert,
  ) => _client
      .channel('encba-videos-feed')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'videos',
        callback: (payload) => onInsert(payload.newRecord),
      )
      .subscribe();

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  Future<List<OperationAssignment>> loadOperations() async {
    final rows = await _client.rpc('list_my_operation_assignments');
    return (rows as List<dynamic>)
        .map<OperationAssignment>(
          (row) => OperationAssignment(
            id: row['id'] as String,
            title: row['title'] as String,
            start: DateTime.parse(row['starts_at'] as String).toLocal(),
            end: DateTime.parse(row['ends_at'] as String).toLocal(),
            location: row['location'] as String? ?? '',
            memo: row['memo'] as String? ?? '',
            assigneeId: _userId,
            isMine: true,
          ),
        )
        .toList(growable: false);
  }

  Future<List<OperationAssignment>> loadOperationExchangeBoard() async {
    final rows = await _client.rpc('list_operation_exchange_board');
    return (rows as List<dynamic>)
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          return OperationAssignment(
            id: row['id'] as String,
            title: row['title'] as String,
            start: DateTime.parse(row['starts_at'] as String).toLocal(),
            end: DateTime.parse(row['ends_at'] as String).toLocal(),
            location: row['location'] as String? ?? '',
            memo: row['memo'] as String? ?? '',
            assigneeId: row['assignee_id'] as String?,
            assigneeName: row['assignee_name'] as String? ?? '',
            isMine: row['is_mine'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }

  Future<List<OperationSwapRequest>> loadOperationSwapRequests() async {
    final rows = await _client.rpc('list_my_operation_swap_requests');
    return (rows as List<dynamic>)
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          return OperationSwapRequest(
            id: row['id'] as String,
            requesterAssignmentId: row['requester_assignment_id'] as String,
            targetAssignmentId: row['target_assignment_id'] as String,
            incoming: row['direction'] == 'incoming',
            counterpartName: row['counterpart_name'] as String,
            requesterTitle: row['requester_title'] as String,
            requesterStartsAt: DateTime.parse(
              row['requester_starts_at'] as String,
            ).toLocal(),
            targetTitle: row['target_title'] as String,
            targetStartsAt: DateTime.parse(
              row['target_starts_at'] as String,
            ).toLocal(),
            status: row['status'] as String,
            message: row['message'] as String? ?? '',
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          );
        })
        .toList(growable: false);
  }

  Future<void> createOperationSwapRequest({
    required String ownAssignmentId,
    required String targetAssignmentId,
    required String message,
  }) => _client.rpc(
    'create_operation_swap_request',
    params: {
      'requested_own_assignment': ownAssignmentId,
      'requested_target_assignment': targetAssignmentId,
      'requested_message': message,
    },
  );

  Future<void> respondOperationSwapRequest({
    required String requestId,
    required bool accept,
  }) => _client.rpc(
    'respond_operation_swap_request',
    params: {'requested_swap_id': requestId, 'requested_accept': accept},
  );

  /// 내 IB 운영 배정이 새로 등록되거나 바뀌면 알려 준다. 관리자가 학기 초
  /// 엑셀을 올리는 즉시, 재접속 없이 내 일정에 반영되게 하기 위한 구독이다.
  /// RLS 정책이 내 배정만 보내 주므로 필터만으로 충분하다.
  RealtimeChannel subscribeToOperationAssignments(
    void Function(Map<String, dynamic> record) onChange,
  ) => _client
      .channel('encba-operation-assignments-$_userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'operation_assignments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'assignee_id',
          value: _userId,
        ),
        callback: (payload) => onChange(payload.newRecord),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'operation_assignments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'assignee_id',
          value: _userId,
        ),
        callback: (payload) => onChange(payload.newRecord),
      )
      .subscribe();

  RealtimeChannel subscribeToOperationSwapRequests(
    void Function(Map<String, dynamic> record) onInsert,
  ) => _client
      .channel('encba-operation-swaps-$_userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'operation_swap_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'target_id',
          value: _userId,
        ),
        callback: (payload) => onInsert(payload.newRecord),
      )
      .subscribe();

  Future<({int imported, int unmatched})> importOperations({
    required String fileName,
    required int academicYear,
    required int term,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final result = await _client.rpc(
      'import_ib_operation_assignments',
      params: {
        'requested_file_name': fileName,
        'requested_academic_year': academicYear,
        'requested_term': term,
        'requested_assignments': assignments,
      },
    );
    final map = Map<String, dynamic>.from(result as Map);
    return (
      imported: map['imported'] as int? ?? 0,
      unmatched: map['unmatched'] as int? ?? 0,
    );
  }

  /// 관리자가 학기 전체 IB 운영 배정을 볼 때 쓴다. RLS가 부원에게는
  /// 자기 배정만, 관리자에게는 전체를 허용하므로 화면에서 권한을 가린다.
  Future<List<OperationAssignment>> loadAllOperations() async {
    final rows = await _client
        .from('operation_assignments')
        .select(
          'id,title,starts_at,ends_at,location,memo,assignee_name,'
          'profiles!operation_assignments_profile_id_fkey(name,display_name)',
        )
        .order('starts_at')
        .limit(500);
    return (rows as List<dynamic>)
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          final profile = row['profiles'] as Map?;
          return OperationAssignment(
            id: row['id'] as String,
            title: row['title'] as String,
            start: DateTime.parse(row['starts_at'] as String).toLocal(),
            end: DateTime.parse(row['ends_at'] as String).toLocal(),
            location: row['location'] as String? ?? '',
            memo: row['memo'] as String? ?? '',
            assigneeId: null,
            assigneeName:
                row['assignee_name'] as String? ??
                profile?['name'] as String? ??
                profile?['display_name'] as String? ??
                '미지정',
            isMine: false,
          );
        })
        .toList(growable: false);
  }

  /// 관리자가 전체 운영 배정의 시간·장소·메모를 고친다.
  Future<void> updateOperationAssignment({
    required String id,
    required DateTime start,
    required DateTime end,
    required String title,
    required String location,
    required String memo,
  }) => _client
      .from('operation_assignments')
      .update({
        'title': title,
        'starts_at': start.toUtc().toIso8601String(),
        'ends_at': end.toUtc().toIso8601String(),
        'location': location.trim().isEmpty ? null : location.trim(),
        'memo': memo.trim().isEmpty ? null : memo.trim(),
      })
      .eq('id', id);

  Future<List<HomecomingContact>> loadHomecomingContacts() async {
    final rows = await _client
        .from('homecoming_contacts')
        .select(
          'id,source_row,senior_name,generation,home_or_office_phone,phone,'
          'contact_status,parking_required,parking_registered,follow_up_allowed,'
          'follow_up_on,notes,assigned_to,assigned_to_name,'
          'homecoming_campaigns!inner(is_active)',
        )
        .eq('homecoming_campaigns.is_active', true)
        .order('generation', ascending: false, nullsFirst: false)
        .limit(1000);
    return rows
        .map(
          (row) => HomecomingContact(
            id: row['id'] as String,
            name: row['senior_name'] as String,
            phone: row['phone'] as String,
            status: row['contact_status'] as String,
            generation: row['generation'] as int?,
            parkingRequired: row['parking_required'] as bool?,
            parkingRegistered: row['parking_registered'] as bool? ?? false,
            homeOrOfficePhone: row['home_or_office_phone'] as String?,
            followUpAllowed: row['follow_up_allowed'] as bool?,
            followUpOn: row['follow_up_on'] == null
                ? null
                : DateTime.parse(row['follow_up_on'] as String),
            notes: row['notes'] as String?,
            sourceRow: row['source_row'] as int?,
            assignedToId: row['assigned_to'] as String?,
            assignedToName: row['assigned_to_name'] as String?,
          ),
        )
        .toList();
  }

  Future<List<AuditEntry>> loadAuditLogs() async {
    final rows = await _client
        .from('audit_logs')
        .select(
          'entity_table,action,created_at,profiles!audit_logs_actor_id_fkey(name)',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map((row) {
      final actor = row['profiles'] as Map?;
      return AuditEntry(
        table: row['entity_table'] as String,
        action: row['action'] as String,
        actor: actor?['name'] as String? ?? '시스템',
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }).toList();
  }

  Future<void> updateHomecomingContact(HomecomingContact contact) => _client
      .from('homecoming_contacts')
      .update({
        'contact_status': contact.status,
        'parking_required': contact.parkingRequired,
        'parking_registered': contact.parkingRegistered,
        'follow_up_allowed': contact.followUpAllowed,
        'follow_up_on': contact.followUpOn?.toIso8601String().split('T').first,
        'notes': contact.notes,
        'last_contacted_at': contact.handled
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      })
      .eq('id', contact.id);

  Future<void> assignHomecomingContact({
    required String id,
    String? assignedToId,
    String? assignedToName,
  }) => _client
      .from('homecoming_contacts')
      .update({'assigned_to': assignedToId, 'assigned_to_name': assignedToName})
      .eq('id', id);

  Future<HomecomingCampaign?> loadActiveHomecomingCampaign() async {
    final rows = await _client
        .from('homecoming_campaigns')
        .select()
        .eq('is_active', true)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return HomecomingCampaign(
      id: row['id'] as String,
      title: row['title'] as String,
      academicYear: row['academic_year'] as int,
      term: row['term'] as int,
      eventDate: DateTime.parse(row['event_date'] as String),
      startsAt: row['starts_at'] as String,
      endsAt: row['ends_at'] as String,
      venue: row['venue'] as String,
      isActive: row['is_active'] as bool,
      afterpartyNote: row['afterparty_note'] as String,
      sourceFileName: row['source_file_name'] as String?,
    );
  }

  Future<HomecomingCampaign> activateHomecomingCampaign({
    required int academicYear,
    required int term,
    required DateTime eventDate,
    required String startsAt,
    required String endsAt,
    required String venue,
  }) async {
    await _client
        .from('homecoming_campaigns')
        .update({'is_active': false})
        .eq('is_active', true);
    await _client
        .from('homecoming_campaigns')
        .upsert({
          'academic_year': academicYear,
          'term': term,
          'title': '$academicYear-$term 홈커밍',
          'event_date': eventDate.toIso8601String().split('T').first,
          'starts_at': startsAt,
          'ends_at': endsAt,
          'venue': venue,
          'is_active': true,
          'created_by': _userId,
        }, onConflict: 'academic_year,term')
        .select()
        .single();
    return (await loadActiveHomecomingCampaign())!;
  }

  Future<void> deactivateHomecomingCampaign(String campaignId) => _client
      .from('homecoming_campaigns')
      .update({'is_active': false})
      .eq('id', campaignId);

  Future<void> importHomecomingContacts({
    required String campaignId,
    required String fileName,
    required List<Map<String, dynamic>> contacts,
  }) => _client.rpc(
    'import_homecoming_contacts',
    params: {
      'requested_campaign_id': campaignId,
      'requested_file_name': fileName,
      'requested_contacts': contacts,
    },
  );

  /// 관리자가 연락 보드에서 선배를 한 명 직접 추가한다. 엑셀 가져오기 없이
  /// 빠진 선배를 보충할 때 쓴다. RLS가 관리자에게만 insert를 허용한다.
  Future<void> addHomecomingContact({
    required String campaignId,
    required String name,
    required String phone,
    int? generation,
    String? assignedToId,
    String? assignedToName,
  }) => _client.from('homecoming_contacts').insert({
    'campaign_id': campaignId,
    'senior_name': name,
    'phone': phone,
    'generation': generation,
    'assigned_to': assignedToId,
    'assigned_to_name': assignedToName,
  });

  Future<void> deleteHomecomingContact(String id) =>
      _client.from('homecoming_contacts').delete().eq('id', id);

  Future<void> vote(
    String eventId,
    String choice, {
    String? absenceReason,
  }) async {
    await _client.from('event_attendance').upsert({
      'event_id': eventId,
      'profile_id': _userId,
      'choice': choice,
      'absence_reason': absenceReason,
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'event_id,profile_id');
  }

  Future<List<AttendanceResponse>> loadEventAttendance(String eventId) async {
    final rows = await _client
        .from('event_attendance')
        .select(
          'profile_id,choice,absence_reason,responded_at,'
          'profiles!event_attendance_profile_id_fkey(name,display_name)',
        )
        .eq('event_id', eventId)
        .order('responded_at', ascending: false);
    return rows
        .map((raw) {
          final row = Map<String, dynamic>.from(raw);
          final profile = row['profiles'] as Map?;
          return AttendanceResponse(
            profileId: row['profile_id'] as String,
            name:
                profile?['name'] as String? ??
                profile?['display_name'] as String? ??
                '부원',
            choice: row['choice'] as String,
            absenceReason: row['absence_reason'] as String?,
            respondedAt: DateTime.parse(
              row['responded_at'] as String,
            ).toLocal(),
          );
        })
        .toList(growable: false);
  }

  Future<LockerEvent> saveEvent(LockerEvent event) async {
    final payload = <String, dynamic>{
      'title': event.title,
      'kind': _kindToDatabase(event.kind),
      'starts_at': event.start.toUtc().toIso8601String(),
      'ends_at': event.end.toUtc().toIso8601String(),
      'place_label': event.place,
      'court': event.court,
      'target_team': event.targetTeam,
      'opponent': event.opponents.isEmpty ? null : event.opponents.join(' · '),
      'opponents': event.opponents,
      'uniform_colors': event.uniformColors
          .map(_uniformToDatabase)
          .whereType<String>()
          .toList(),
      'memo': event.memo,
      'capacity': event.capacity,
      'ob_participant_count': event.obParticipantCount,
      'response_enabled': event.responseEnabled,
      'response_deadline': event.responseDeadline.toUtc().toIso8601String(),
      'recurrence_rule': event.isRecurring
          ? {'frequency': 'weekly', 'count': 12, 'editable_instances': true}
          : null,
      'poll_options': event.pollOptions,
      'visibility': event.visibility,
      'map_reference': event.mapReference?.trim().isEmpty == true
          ? null
          : event.mapReference?.trim(),
      'updated_by': _userId,
    };
    final isUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(event.id);
    Future<Map<String, dynamic>> persist() async {
      if (isUuid) {
        return _client
            .from('events')
            .update(payload)
            .eq('id', event.id)
            .select(_eventSelection)
            .single();
      }
      payload['created_by'] = _userId;
      return _client
          .from('events')
          .insert(payload)
          .select(_eventSelection)
          .single();
    }

    late final Map<String, dynamic> row;
    try {
      row = await persist();
    } on PostgrestException catch (error) {
      final missingColumn = error.message.toLowerCase();
      final schemaCacheMissing =
          error.code == 'PGRST204' &&
          (missingColumn.contains('opponents') ||
              missingColumn.contains('map_reference'));
      if (!schemaCacheMissing) {
        throw LockerRepositoryException(_friendlyPostgrestMessage(error));
      }
      payload.remove('opponents');
      payload.remove('map_reference');
      try {
        row = await persist();
      } on PostgrestException catch (fallbackError) {
        throw LockerRepositoryException(
          _friendlyPostgrestMessage(fallbackError),
        );
      }
    }
    final saved = _eventFromRow(row).copyWith(
      starterProfileIds: event.starterProfileIds,
      starterNames: event.starterNames,
    );
    if (isUuid || event.starterProfileIds.isNotEmpty) {
      try {
        await _client.rpc(
          'replace_event_starters',
          params: {
            'requested_event_id': saved.id,
            'requested_directory_ids': event.starterProfileIds,
          },
        );
      } on PostgrestException catch (error) {
        throw LockerRepositoryException(
          '일정은 저장됐지만 주전 명단을 저장하지 못했습니다: ${_friendlyPostgrestMessage(error)}',
        );
      }
    }
    return saved;
  }

  Future<void> deleteEvent(String id) async {
    await _client.from('events').delete().eq('id', id);
  }

  Future<EventStrategy> loadEventStrategy(String eventId) async {
    final rows = await _client
        .from('event_strategies')
        .select(
          'event_id,offense,defense,notes,updated_at,profiles!event_strategies_updated_by_fkey(name,display_name)',
        )
        .eq('event_id', eventId)
        .limit(1);
    if (rows.isEmpty) return EventStrategy(eventId: eventId);
    final row = Map<String, dynamic>.from(rows.first);
    final profile = row['profiles'] as Map?;
    return EventStrategy(
      eventId: eventId,
      offense: row['offense'] as String? ?? '',
      defense: row['defense'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
      updatedBy:
          profile?['name'] as String? ??
          profile?['display_name'] as String? ??
          '',
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }

  Future<EventStrategy> saveEventStrategy(EventStrategy strategy) async {
    final row = await _client
        .from('event_strategies')
        .upsert({
          'event_id': strategy.eventId,
          'offense': strategy.offense.trim(),
          'defense': strategy.defense.trim(),
          'notes': strategy.notes.trim(),
          'updated_by': _userId,
        }, onConflict: 'event_id')
        .select(
          'event_id,offense,defense,notes,updated_at,profiles!event_strategies_updated_by_fkey(name,display_name)',
        )
        .single();
    final profile = row['profiles'] as Map?;
    return EventStrategy(
      eventId: row['event_id'] as String,
      offense: row['offense'] as String? ?? '',
      defense: row['defense'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
      updatedBy:
          profile?['name'] as String? ??
          profile?['display_name'] as String? ??
          '',
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }

  Future<void> setVideoLike(String videoId, {required bool liked}) async {
    if (liked) {
      try {
        await _client.from('video_likes').insert({
          'video_id': videoId,
          'profile_id': _userId,
        });
      } on PostgrestException catch (error) {
        if (error.code != '23505') rethrow;
      }
    } else {
      await _client
          .from('video_likes')
          .delete()
          .eq('video_id', videoId)
          .eq('profile_id', _userId);
    }
  }

  Future<VideoItem> addVideo(VideoItem video) async {
    final payload = _videoPayload(video)..['uploaded_by'] = _userId;
    final row = await _writeVideo(
      (values) => _client.from('videos').insert(values).select('id').single(),
      payload,
    );
    final id = row['id'] as String;
    await _syncVideoLinks(id, video.links);
    if (video.category == '복기') {
      await _syncReviewPlayers(id, video.reviewPlayers);
    }
    // 다시 읽지 못하더라도 서버가 매긴 id는 반드시 들고 나가야 상세 화면과
    // 이후 수정이 같은 영상을 가리킨다.
    return await loadVideo(id) ?? video.copyWith(id: id);
  }

  Future<VideoItem> updateVideo(VideoItem video) async {
    await _writeVideo(
      (values) => _client
          .from('videos')
          .update(values)
          .eq('id', video.id)
          .select('id')
          .single(),
      _videoPayload(video),
    );
    await _syncVideoLinks(video.id, video.links);
    if (video.category == '복기') {
      await _syncReviewPlayers(video.id, video.reviewPlayers);
    }
    return await loadVideo(video.id) ?? video;
  }

  Map<String, dynamic> _videoPayload(VideoItem video) => {
    'title': video.title,
    'category': _videoCategoryToDatabase(video.category),
    'source_url': video.url,
    'youtube_id': video.youtubeId.isEmpty ? null : video.youtubeId,
    'source_type': video.sourceType,
    // 예전 앱과 예전 서버를 위해 앞 네 쿼터는 컬럼에도 그대로 남긴다.
    'quarter_1_url': video.quarterUrls.elementAtOrNull(0),
    'quarter_2_url': video.quarterUrls.elementAtOrNull(1),
    'quarter_3_url': video.quarterUrls.elementAtOrNull(2),
    'quarter_4_url': video.quarterUrls.elementAtOrNull(3),
    'audience_type': video.audienceType,
    'audience_values': video.audienceValues,
    'duration_seconds': _durationToSeconds(video.durationLabel),
    'recorded_on': video.recordedOn == null
        ? null
        : _dateOnly(video.recordedOn!),
  };

  /// recorded_on이 없는 서버에서는 그 값만 빼고 다시 저장한다.
  Future<Map<String, dynamic>> _writeVideo(
    Future<Map<String, dynamic>> Function(Map<String, dynamic> values) write,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await write(payload);
    } on PostgrestException catch (error) {
      if (!_isMissingVideoLinkFeature(error)) rethrow;
      debugPrint('Supabase video link migration pending: $error');
      return write(Map<String, dynamic>.from(payload)..remove('recorded_on'));
    }
  }

  Future<void> _syncVideoLinks(String videoId, List<VideoLink> links) async {
    try {
      await _client.rpc(
        'set_video_links',
        params: {
          'requested_video_id': videoId,
          'requested_links': [
            for (final link in links)
              {'quarter': link.quarterNumber, 'url': link.url},
          ],
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingVideoLinkFeature(error)) rethrow;
      debugPrint('Supabase video link migration pending: $error');
    }
  }

  Future<void> deleteVideo(String id) =>
      _client.from('videos').delete().eq('id', id);

  static const _commentSelection =
      'id,video_id,quarter_number,link_id,timestamp_seconds,'
      'end_timestamp_seconds,body,created_at,'
      'profiles!video_comments_profile_id_fkey(name)';
  static const _commentSelectionWithoutRange =
      'id,video_id,quarter_number,link_id,timestamp_seconds,body,created_at,'
      'profiles!video_comments_profile_id_fkey(name)';
  static const _legacyCommentSelection =
      'id,video_id,quarter_number,timestamp_seconds,body,created_at,'
      'profiles!video_comments_profile_id_fkey(name)';

  Future<List<VideoCommentItem>> loadVideoComments(String videoId) async {
    Future<List<Map<String, dynamic>>> query(String selection) async {
      final rows = await _client
          .from('video_comments')
          .select(selection)
          .eq('video_id', videoId)
          .order('timestamp_seconds')
          .order('created_at');
      return rows.map(Map<String, dynamic>.from).toList(growable: false);
    }

    Future<List<Map<String, dynamic>>> queryWithoutRange() async {
      try {
        return await query(_commentSelectionWithoutRange);
      } on PostgrestException catch (error) {
        if (!_isMissingVideoLinkFeature(error)) rethrow;
        return query(_legacyCommentSelection);
      }
    }

    List<Map<String, dynamic>> rows;
    try {
      rows = await query(_commentSelection);
    } on PostgrestException catch (error) {
      if (_isMissingVideoCommentRangeFeature(error)) {
        rows = await queryWithoutRange();
      } else if (_isMissingVideoLinkFeature(error)) {
        rows = await query(_legacyCommentSelection);
      } else {
        rethrow;
      }
    }
    final comments = rows.map(_videoCommentFromRow).toList(growable: false);
    return _attachCommentTargets(videoId, comments);
  }

  Future<VideoCommentItem> addVideoComment({
    required String videoId,
    required int? quarterNumber,
    required int? linkId,
    required int timestampSeconds,
    int? endTimestampSeconds,
    required String body,
    List<VideoTaggedMember> targetPlayers = const [],
  }) async {
    // 값이 없는 컬럼은 아예 보내지 않는다. 릴스(하이라이트)처럼 쿼터·링크가
    // 없는 댓글에서 명시적 null이 원인일 수 있는 저장 실패를 줄인다.
    final payload = <String, dynamic>{
      'video_id': videoId,
      'profile_id': _userId,
      'quarter_number': quarterNumber,
      'link_id': linkId,
      'timestamp_seconds': timestampSeconds,
      'end_timestamp_seconds': endTimestampSeconds,
      'body': body,
    };
    Future<Map<String, dynamic>> insert(
      Map<String, dynamic> insertPayload,
      String selection,
    ) => _client
        .from('video_comments')
        .insert(insertPayload)
        .select(selection)
        .single();

    Future<Map<String, dynamic>> insertWithoutRange() async {
      final fallbackPayload = Map<String, dynamic>.from(payload)
        ..remove('end_timestamp_seconds');
      try {
        return await insert(fallbackPayload, _commentSelectionWithoutRange);
      } on PostgrestException catch (error) {
        if (!_isMissingVideoLinkFeature(error)) rethrow;
        fallbackPayload.remove('link_id');
        return insert(fallbackPayload, _legacyCommentSelection);
      }
    }

    Map<String, dynamic> row;
    try {
      row = await insert(payload, _commentSelection);
    } on PostgrestException catch (error) {
      if (_isMissingVideoCommentRangeFeature(error)) {
        row = await insertWithoutRange();
      } else if (_isMissingVideoLinkFeature(error)) {
        row = await insert(
          Map<String, dynamic>.from(payload)
            ..remove('end_timestamp_seconds')
            ..remove('link_id'),
          _legacyCommentSelection,
        );
      } else {
        rethrow;
      }
    }
    final saved = _videoCommentFromRow(Map<String, dynamic>.from(row));
    await _syncCommentTargets(saved.id, targetPlayers);
    return VideoCommentItem(
      id: saved.id,
      videoId: saved.videoId,
      timestampSeconds: saved.timestampSeconds,
      body: saved.body,
      author: saved.author,
      createdAt: saved.createdAt,
      quarterNumber: saved.quarterNumber,
      linkId: saved.linkId ?? linkId,
      endTimestampSeconds: saved.endTimestampSeconds ?? endTimestampSeconds,
      targetPlayers: targetPlayers,
    );
  }

  Future<List<VideoItem>> _attachReviewPlayers(List<VideoItem> videos) async {
    final reviewIds = videos
        .where((video) => video.category == '복기')
        .map((video) => video.id)
        .toList(growable: false);
    if (reviewIds.isEmpty) return videos;
    final rows = await _orFallback<dynamic>(
      _client.rpc(
        'list_video_review_players',
        params: {'requested_video_ids': reviewIds},
      ),
      const <dynamic>[],
      debugLabel: 'video review players',
    );
    final playersByVideo = <String, List<VideoTaggedMember>>{};
    for (final raw in rows as List<dynamic>) {
      final row = Map<String, dynamic>.from(raw as Map);
      playersByVideo
          .putIfAbsent(row['video_id'] as String, () => [])
          .add(
            VideoTaggedMember(
              directoryId: row['directory_id'] as String,
              name: row['name'] as String,
              studentYear: _databaseInt(row['student_year']),
              jerseyNumber: _databaseInt(row['jersey_number']),
            ),
          );
    }
    return videos
        .map(
          (video) => video.copyWith(
            reviewPlayers:
                playersByVideo[video.id] ?? const <VideoTaggedMember>[],
          ),
        )
        .toList(growable: false);
  }

  Future<List<VideoCommentItem>> _attachCommentTargets(
    String videoId,
    List<VideoCommentItem> comments,
  ) async {
    if (comments.isEmpty) return comments;
    final rows = await _orFallback<dynamic>(
      _client.rpc(
        'list_video_comment_targets',
        params: {'requested_video_id': videoId},
      ),
      const <dynamic>[],
      debugLabel: 'video comment targets',
    );
    final targetsByComment = <int, List<VideoTaggedMember>>{};
    for (final raw in rows as List<dynamic>) {
      final row = Map<String, dynamic>.from(raw as Map);
      targetsByComment
          .putIfAbsent((row['comment_id'] as num).toInt(), () => [])
          .add(
            VideoTaggedMember(
              directoryId: row['directory_id'] as String,
              name: row['name'] as String,
              studentYear: _databaseInt(row['student_year']),
              jerseyNumber: _databaseInt(row['jersey_number']),
            ),
          );
    }
    return comments
        .map(
          (comment) => VideoCommentItem(
            id: comment.id,
            videoId: comment.videoId,
            timestampSeconds: comment.timestampSeconds,
            body: comment.body,
            author: comment.author,
            createdAt: comment.createdAt,
            quarterNumber: comment.quarterNumber,
            linkId: comment.linkId,
            endTimestampSeconds: comment.endTimestampSeconds,
            targetPlayers:
                targetsByComment[comment.id] ?? const <VideoTaggedMember>[],
          ),
        )
        .toList(growable: false);
  }

  Future<void> _syncReviewPlayers(
    String videoId,
    List<VideoTaggedMember> players,
  ) async {
    try {
      await _client.rpc(
        'set_video_review_players',
        params: {
          'requested_video_id': videoId,
          'requested_directory_ids': players
              .map((player) => player.directoryId)
              .toList(growable: false),
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingVideoPlayerFeature(error)) rethrow;
      debugPrint('Supabase video review player migration pending: $error');
    }
  }

  Future<void> _syncCommentTargets(
    int commentId,
    List<VideoTaggedMember> players,
  ) async {
    try {
      await _client.rpc(
        'set_video_comment_targets',
        params: {
          'requested_comment_id': commentId,
          'requested_directory_ids': players
              .map((player) => player.directoryId)
              .toList(growable: false),
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingVideoPlayerFeature(error)) rethrow;
      debugPrint('Supabase video comment target migration pending: $error');
    }
  }

  Future<void> applyExternalEvent(String eventId) =>
      _client.from('event_roster').upsert({
        'event_id': eventId,
        'profile_id': _userId,
        'status': 'applied',
      }, onConflict: 'event_id,profile_id');

  Future<List<EventRosterMember>> loadEventRoster(String eventId) async {
    final rows = await _client
        .from('event_roster')
        .select('profile_id,status,profiles(name,display_name)')
        .eq('event_id', eventId)
        .order('created_at');
    return rows.map((row) {
      final profile = row['profiles'] as Map?;
      return EventRosterMember(
        profileId: row['profile_id'] as String,
        name:
            profile?['name'] as String? ??
            profile?['display_name'] as String? ??
            '부원',
        status: row['status'] as String,
      );
    }).toList();
  }

  Future<void> setEventRosterStatus({
    required String eventId,
    required String profileId,
    required String status,
  }) => _client
      .from('event_roster')
      .update({'status': status, 'updated_by': _userId})
      .eq('event_id', eventId)
      .eq('profile_id', profileId);

  VideoCommentItem _videoCommentFromRow(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map?;
    return VideoCommentItem(
      id: row['id'] as int,
      videoId: row['video_id'] as String,
      quarterNumber: row['quarter_number'] as int?,
      linkId: _databaseInt(row['link_id']),
      timestampSeconds: row['timestamp_seconds'] as int? ?? 0,
      endTimestampSeconds: _databaseInt(row['end_timestamp_seconds']),
      body: row['body'] as String,
      author: profile?['name'] as String? ?? 'ENCBA',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  LockerEvent _eventFromRow(Map<String, dynamic> row) {
    final place = row['places'] as Map?;
    final creator = row['profiles'] as Map?;
    return LockerEvent(
      id: row['id'] as String,
      title: row['title'] as String,
      start: DateTime.parse(row['starts_at'] as String).toLocal(),
      end: DateTime.parse(row['ends_at'] as String).toLocal(),
      place:
          place?['name'] as String? ?? row['place_label'] as String? ?? '장소 미정',
      court: row['court'] as String?,
      kind: _kindFromDatabase(row['kind'] as String),
      memo: row['memo'] as String,
      uniformColors: (row['uniform_colors'] as List? ?? const [])
          .map((value) => _uniformFromDatabase(value as String))
          .whereType<String>()
          .toList(),
      capacity: _databaseInt(row['capacity']),
      obParticipantCount: _databaseInt(row['ob_participant_count']) ?? 0,
      attending: _databaseInt(row['attending_count']) ?? 0,
      targetTeam: row['target_team'] as String? ?? '전체',
      createdBy: creator?['name'] as String? ?? '운영진',
      updatedAt: _relativeTime(DateTime.parse(row['updated_at'] as String)),
      isRecurring: row['recurrence_rule'] != null,
      responseEnabled: row['response_enabled'] as bool? ?? true,
      responseDeadlineOverride: DateTime.parse(
        row['response_deadline'] as String,
      ).toLocal(),
      pollOptions: List<String>.from(
        row['poll_options'] as List? ?? const ['참석', '불참', '미정'],
      ),
      visibility: row['visibility'] as String? ?? 'team',
      isLocked: row['locked'] as bool? ?? false,
      opponents:
          (row['opponents'] as List?)?.cast<String>() ??
          (row['opponent'] == null ? const [] : [row['opponent'] as String]),
      mapReference: row['map_reference'] as String?,
    );
  }

  /// 링크 테이블 값을 우선 쓰고, 아직 없는 서버에서는 쿼터 컬럼으로 되돌아간다.
  List<VideoLink> _videoLinksFromRow(Map<String, dynamic> row) {
    final rows = row['video_links'] as List?;
    if (rows != null) {
      final links = rows.map((raw) {
        final link = Map<String, dynamic>.from(raw as Map);
        return (
          sort: _databaseInt(link['sort_order']) ?? 0,
          link: VideoLink(
            id: _databaseInt(link['id']),
            quarterNumber: _databaseInt(link['quarter_number']),
            url: link['url'] as String,
          ),
        );
      }).toList()..sort((a, b) => a.sort.compareTo(b.sort));
      return sortedVideoLinks(links.map((entry) => entry.link));
    }
    return [
      for (final (index, key) in const [
        'quarter_1_url',
        'quarter_2_url',
        'quarter_3_url',
        'quarter_4_url',
      ].indexed)
        if (row[key] is String && (row[key] as String).isNotEmpty)
          VideoLink(url: row[key] as String, quarterNumber: index + 1),
    ];
  }

  VideoItem _videoFromRow(Map<String, dynamic> row) {
    final uploader = row['profiles'] as Map?;
    return VideoItem(
      id: row['id'] as String,
      title: row['title'] as String,
      durationLabel: _formatDuration(_databaseInt(row['duration_seconds'])),
      category: _videoCategoryFromDatabase(row['category'] as String),
      url: row['source_url'] as String,
      youtubeId: row['youtube_id'] as String? ?? '',
      uploadedAt: DateTime.parse(row['created_at'] as String).toLocal(),
      uploader:
          uploader?['name'] as String? ??
          uploader?['display_name'] as String? ??
          'ENCBA',
      accent: 0xFF00539B,
      likeCount: _databaseInt(row['like_count']) ?? 0,
      sourceType: row['source_type'] as String? ?? 'youtube',
      links: _videoLinksFromRow(row),
      recordedOn: row['recorded_on'] == null
          ? null
          : DateTime.parse(row['recorded_on'] as String),
      audienceType: row['audience_type'] as String? ?? 'all',
      audienceValues: List<String>.from(
        row['audience_values'] as List? ?? const [],
      ),
    );
  }

  Future<void> _cache(LockerSnapshot snapshot) => _store.setString(
    _cacheKey,
    jsonEncode({
      'events': snapshot.events.map((event) => event.toJson()).toList(),
      'attendance': snapshot.attendance.map(
        (key, value) => MapEntry(key, value),
      ),
      'videos': snapshot.videos.map((video) => video.toJson()).toList(),
      'likes': snapshot.likedVideoIds.toList(),
      'hasMoreEvents': snapshot.hasMoreEvents,
    }),
  );

  Future<LockerSnapshot?> _readCache() async {
    final raw = await _store.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return LockerSnapshot(
        events: (json['events'] as List)
            .map(
              (item) =>
                  LockerEvent.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(),
        attendance: Map<String, dynamic>.from(
          json['attendance'] as Map,
        ).map((key, value) => MapEntry(key, value as String)),
        videos: (json['videos'] as List)
            .map(
              (item) =>
                  VideoItem.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(),
        likedVideoIds: Set<String>.from(json['likes'] as List),
        hasMoreEvents: json['hasMoreEvents'] as bool? ?? false,
        fromCache: true,
      );
    } on Object {
      return null;
    }
  }
}

String _kindToDatabase(EventKind kind) => switch (kind) {
  EventKind.freeOpen => 'free_open',
  EventKind.ibDivision1 => 'ib_division_1',
  EventKind.ibDivision2 => 'ib_division_2',
  EventKind.ibFreshman => 'ib_freshman',
  EventKind.threeWay => 'three_way',
  EventKind.operations => 'operation',
  _ => kind.name,
};

EventKind _kindFromDatabase(String kind) => switch (kind) {
  'free_open' => EventKind.freeOpen,
  'ib_division_1' => EventKind.ibDivision1,
  'ib_division_2' => EventKind.ibDivision2,
  'ib_freshman' => EventKind.ibFreshman,
  'three_way' => EventKind.threeWay,
  'operation' => EventKind.operations,
  _ => EventKind.values.byName(kind),
};

String? _uniformToDatabase(String? value) => switch (value) {
  '검정' || '검' => '검',
  '흰색' || '흰' => '흰',
  _ => null,
};

String? _uniformFromDatabase(String? value) => switch (value) {
  '검' => '검정',
  '흰' => '흰색',
  _ => null,
};

String _videoCategoryToDatabase(String category) => switch (category) {
  '하이라이트' => 'highlight',
  '복기' => 'review',
  _ => 'shared',
};

String _videoCategoryFromDatabase(String category) => switch (category) {
  'highlight' => '하이라이트',
  'review' => '복기',
  _ => '공유',
};

int? _databaseInt(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text),
  _ => null,
};

int? _durationToSeconds(String value) {
  final parts = value.split(':').map(int.tryParse).toList();
  if (parts.length != 2 || parts.any((item) => item == null)) return null;
  return parts[0]! * 60 + parts[1]!;
}

bool _isMissingVideoPlayerFeature(PostgrestException error) =>
    error.code == 'PGRST202' || error.code == '42883';

bool _isMissingVideoCommentRangeFeature(PostgrestException error) {
  if (error.code != 'PGRST204' && error.code != '42703') return false;
  final context = '${error.message} ${error.details ?? ''}'.toLowerCase();
  return context.contains('end_timestamp_seconds');
}

bool _isMissingAnnouncementFeature(PostgrestException error) {
  if (!const {'PGRST200', 'PGRST204', '42703'}.contains(error.code)) {
    return false;
  }
  final context = '${error.message} ${error.details ?? ''}'.toLowerCase();
  return context.contains('is_urgent') ||
      context.contains('image_url') ||
      context.contains('poll_options') ||
      context.contains('poll_question') ||
      context.contains('announcement_poll_votes');
}

/// 링크 테이블·recorded_on 마이그레이션이 아직 안 올라간 서버의 응답들.
/// PGRST200은 없는 관계, PGRST204는 스키마 캐시에 없는 컬럼,
/// 42703은 없는 컬럼, PGRST202/42883은 없는 함수다.
bool _isMissingVideoLinkFeature(PostgrestException error) => const {
  'PGRST200',
  'PGRST204',
  'PGRST202',
  '42703',
  '42883',
}.contains(error.code);

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _friendlyPostgrestMessage(PostgrestException error) {
  final detail = [
    error.message.trim(),
    if (error.details?.toString().trim().isNotEmpty == true)
      error.details.toString().trim(),
    if (error.hint?.trim().isNotEmpty == true) error.hint!.trim(),
  ].where((value) => value.isNotEmpty).join(' / ');

  return switch (error.code) {
    '42501' => '일정 등록 권한이 없거나 로그인 세션이 만료되었습니다.',
    '23503' => '선택한 장소·멤버·연결 데이터가 서버에 없습니다.',
    '23505' => '이미 등록된 일정과 중복됩니다.',
    '23514' => '일정 유형에 필요한 값이 빠졌거나 입력 형식이 맞지 않습니다.',
    '22023' => detail.isEmpty ? '입력값을 확인해 주세요.' : detail,
    'PGRST202' || 'PGRST204' => '서버 DB가 최신 앱 구조와 맞지 않습니다. DB 마이그레이션을 적용해 주세요.',
    _ => '서버가 일정 저장 요청을 처리하지 못했습니다. 잠시 뒤 다시 시도해 주세요.',
  };
}

String _formatDuration(int? seconds) {
  if (seconds == null) return '';
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _relativeTime(DateTime value) {
  final elapsed = DateTime.now().difference(value.toLocal());
  if (elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  if (elapsed.inDays < 1) return '${elapsed.inHours}시간 전';
  return '${elapsed.inDays}일 전';
}
