import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
part 'repo_members.dart';
part 'repo_events.dart';
part 'repo_videos.dart';
part 'repo_content.dart';
part 'repo_operations.dart';
part 'repo_homecoming.dart';
part 'repo_misc.dart';

const int eventPageSize = 20;
const int videoPageSize = 30;
const _initialReadTimeout = Duration(seconds: 6);
const _announcementSelection =
      'id,title,body,pinned,is_urgent,published_at,image_url,poll_options,'
      'poll_question,'
      'profiles!announcements_created_by_fkey(name,display_name),'
      'announcement_event_links(event_id),'
      'announcement_poll_votes(profile_id,option_index)';
const _legacyAnnouncementSelection =
      'id,title,body,pinned,published_at,'
      'profiles!announcements_created_by_fkey(name,display_name),'
      'announcement_event_links(event_id)';
const _eventSelection =
      'id,title,starts_at,ends_at,place_label,court,kind,memo,'
      'uniform_colors,capacity,attending_count,target_team,updated_at,'
      'ob_participant_count,'
      'recurrence_rule,response_enabled,response_deadline,poll_options,'
      'visibility,opponent,opponents,map_reference,'
      'places(name),profiles!events_created_by_fkey(name)';
const _videoSelection =
      'id,title,category,source_url,youtube_id,source_type,'
      'quarter_1_url,quarter_2_url,quarter_3_url,quarter_4_url,'
      'audience_type,audience_values,duration_seconds,created_at,like_count,'
      'recorded_on,video_links(id,quarter_number,url,sort_order),'
      'profiles!videos_uploaded_by_fkey(name,display_name)';
const _legacyVideoSelection =
      'id,title,category,source_url,youtube_id,source_type,'
      'quarter_1_url,quarter_2_url,quarter_3_url,quarter_4_url,'
      'audience_type,audience_values,duration_seconds,created_at,like_count,'
      'profiles!videos_uploaded_by_fkey(name,display_name)';

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


/// 모든 도메인 파트가 의존하는 공통 접근자와 공유 헬퍼.
mixin RepoCore {
  SupabaseClient get _client;

  LocalStore get _store;

  String get _userId;

  String get _cacheKey => 'encba.remote-snapshot.$_userId.v2';

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

  /// avatars 버킷은 public이므로 경로만 있으면 공개 URL을 만들 수 있다.
  String? _avatarPublicUrl(String? path) => path == null || path.isEmpty
      ? null
      : _client.storage.from('avatars').getPublicUrl(path);

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

class SupabaseLockerRepository with RepoCore, MembersApi, EventsApi, VideosApi, ContentApi, OperationsApi, HomecomingApi, MiscApi {
  @override
  final SupabaseClient _client;

  @override
  final LocalStore _store;

  SupabaseLockerRepository(this._client, this._store);

  @override
  String get _userId => _client.auth.currentUser?.id ?? (throw StateError('로그인이 필요합니다.'));

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
