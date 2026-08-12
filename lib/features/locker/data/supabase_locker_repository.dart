import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LockerSnapshot {
  const LockerSnapshot({
    required this.events,
    required this.attendance,
    required this.videos,
    required this.likedVideoIds,
    this.fromCache = false,
  });

  final List<LockerEvent> events;
  final Map<String, AttendanceStatus> attendance;
  final List<VideoItem> videos;
  final Set<String> likedVideoIds;
  final bool fromCache;
}

class SupabaseLockerRepository {
  SupabaseLockerRepository(this._client, this._store);

  String get _cacheKey => 'encba.remote-snapshot.$_userId.v1';
  final SupabaseClient _client;
  final LocalStore _store;

  String get _userId =>
      _client.auth.currentUser?.id ?? (throw StateError('로그인이 필요합니다.'));

  Future<LockerSnapshot> load() async {
    try {
      final result = await Future.wait([
        _client
            .from('events')
            .select('*,places(name),profiles!events_created_by_fkey(name)')
            .gte('ends_at', DateTime.now().toUtc().toIso8601String())
            .isFilter('cancelled_at', null)
            .order('starts_at')
            .limit(300),
        _client
            .from('event_attendance')
            .select('event_id,status')
            .eq('profile_id', _userId),
        _client
            .from('videos')
            .select('*,profiles!videos_uploaded_by_fkey(name)')
            .order('created_at', ascending: false)
            .limit(200),
        _client
            .from('video_likes')
            .select('video_id')
            .eq('profile_id', _userId),
      ]);
      final events = (result[0] as List)
          .map((row) => _eventFromRow(Map<String, dynamic>.from(row as Map)))
          .toList();
      final attendance = {
        for (final row in result[1] as List)
          (row as Map)['event_id'] as String: AttendanceStatus.values.byName(
            row['status'] as String,
          ),
      };
      final videos = (result[2] as List)
          .map((row) => _videoFromRow(Map<String, dynamic>.from(row as Map)))
          .toList();
      final likes = {
        for (final row in result[3] as List) (row as Map)['video_id'] as String,
      };
      final snapshot = LockerSnapshot(
        events: events,
        attendance: attendance,
        videos: videos,
        likedVideoIds: likes,
      );
      try {
        await _cache(snapshot);
      } on Object {
        // 온라인 응답은 로컬 캐시 저장 실패와 무관하게 그대로 사용한다.
      }
      return snapshot;
    } on Object {
      final cached = await _readCache();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<MemberProfile>> loadMembers({
    String membership = 'YB',
    String query = '',
  }) async {
    var request = _client
        .from('profiles')
        .select(
          'name,student_year,generation,phone,position,membership_status,badge,profile_teams(teams(code))',
        )
        .eq('membership_status', membership.toLowerCase());
    final normalizedQuery = query.trim();
    if (normalizedQuery.isNotEmpty) {
      final studentYear = int.tryParse(
        normalizedQuery.replaceAll(RegExp(r'[^0-9]'), ''),
      );
      final filters = <String>[
        'name.ilike.%$normalizedQuery%',
        'position.ilike.%$normalizedQuery%',
        if (studentYear != null && studentYear <= 99)
          'student_year.eq.$studentYear',
      ];
      request = request.or(filters.join(','));
    }
    final rows = await request.order('generation', ascending: false).limit(100);
    return rows.map((row) {
      final map = Map<String, dynamic>.from(row);
      final teams = (map['profile_teams'] as List? ?? const [])
          .map((item) => (item as Map)['teams'])
          .whereType<Map>()
          .map((team) => team['code'] as String)
          .toList();
      return MemberProfile(
        name: map['name'] as String,
        studentId: '${map['student_year']}학번',
        generation: map['generation'] as int,
        status: (map['membership_status'] as String).toUpperCase(),
        position: map['position'] as String,
        teams: teams,
        note: '',
        badge: map['badge'] as String?,
        phone: map['phone'] as String? ?? '',
      );
    }).toList();
  }

  Future<List<AnnouncementItem>> loadAnnouncements() async {
    final rows = await _client
        .from('announcements')
        .select(
          'id,title,body,published_at,profiles!announcements_created_by_fkey(name)',
        )
        .order('pinned', ascending: false)
        .order('published_at', ascending: false)
        .limit(50);
    return rows.map((row) {
      final author = row['profiles'] as Map?;
      return AnnouncementItem(
        id: row['id'] as String,
        title: row['title'] as String,
        body: row['body'] as String,
        author: author?['name'] as String? ?? '운영진',
        publishedAt: DateTime.parse(row['published_at'] as String).toLocal(),
      );
    }).toList();
  }

  Future<List<OperationAssignment>> loadOperations() async {
    final rows = await _client
        .from('operation_assignments')
        .select('id,title,starts_at,ends_at,location,memo')
        .eq('profile_id', _userId)
        .gte(
          'ends_at',
          DateTime.now()
              .subtract(const Duration(days: 30))
              .toUtc()
              .toIso8601String(),
        )
        .order('starts_at')
        .limit(100);
    return rows
        .map(
          (row) => OperationAssignment(
            id: row['id'] as String,
            title: row['title'] as String,
            start: DateTime.parse(row['starts_at'] as String).toLocal(),
            end: DateTime.parse(row['ends_at'] as String).toLocal(),
            location: row['location'] as String? ?? '',
            memo: row['memo'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<List<HomecomingContact>> loadHomecomingContacts() async {
    final rows = await _client
        .from('homecoming_contacts')
        .select(
          'id,senior_name,generation,phone,contact_status,parking_required,parking_registered',
        )
        .order('generation', ascending: false)
        .limit(300);
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

  Future<void> updateHomecomingContacted(
    String id, {
    required bool contacted,
  }) => _client
      .from('homecoming_contacts')
      .update({
        'contact_status': contacted ? 'contacted' : 'pending',
        'last_contacted_at': contacted
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      })
      .eq('id', id);

  Future<void> vote(String eventId, AttendanceStatus status) async {
    await _client.from('event_attendance').upsert({
      'event_id': eventId,
      'profile_id': _userId,
      'status': status.name,
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'event_id,profile_id');
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
      'uniform_color': _uniformToDatabase(event.uniformColor),
      'memo': event.memo,
      'capacity': event.capacity,
      'response_enabled': event.responseEnabled,
      'response_deadline': event.responseDeadline.toUtc().toIso8601String(),
      'recurrence_rule': event.isRecurring
          ? {'frequency': 'weekly', 'count': 12, 'editable_instances': true}
          : null,
      'updated_by': _userId,
    };
    final isUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(event.id);
    late final Map<String, dynamic> row;
    if (isUuid) {
      row = await _client
          .from('events')
          .update(payload)
          .eq('id', event.id)
          .select('*,places(name),profiles!events_created_by_fkey(name)')
          .single();
    } else {
      payload['created_by'] = _userId;
      row = await _client
          .from('events')
          .insert(payload)
          .select('*,places(name),profiles!events_created_by_fkey(name)')
          .single();
    }
    return _eventFromRow(row);
  }

  Future<void> deleteEvent(String id) async {
    await _client.from('events').delete().eq('id', id);
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
    final row = await _client
        .from('videos')
        .insert({
          'title': video.title,
          'category': _videoCategoryToDatabase(video.category),
          'source_url': video.url,
          'youtube_id': video.youtubeId,
          'duration_seconds': _durationToSeconds(video.durationLabel),
          'uploaded_by': _userId,
        })
        .select('*,profiles!videos_uploaded_by_fkey(name)')
        .single();
    return _videoFromRow(row);
  }

  Future<List<VideoCommentItem>> loadVideoComments(String videoId) async {
    final rows = await _client
        .from('video_comments')
        .select(
          'id,video_id,timestamp_seconds,body,created_at,'
          'profiles!video_comments_profile_id_fkey(name)',
        )
        .eq('video_id', videoId)
        .order('timestamp_seconds')
        .order('created_at');
    return rows.map(_videoCommentFromRow).toList();
  }

  Future<VideoCommentItem> addVideoComment({
    required String videoId,
    required int timestampSeconds,
    required String body,
  }) async {
    final row = await _client
        .from('video_comments')
        .insert({
          'video_id': videoId,
          'profile_id': _userId,
          'timestamp_seconds': timestampSeconds,
          'body': body,
        })
        .select(
          'id,video_id,timestamp_seconds,body,created_at,'
          'profiles!video_comments_profile_id_fkey(name)',
        )
        .single();
    return _videoCommentFromRow(row);
  }

  VideoCommentItem _videoCommentFromRow(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map?;
    return VideoCommentItem(
      id: row['id'] as int,
      videoId: row['video_id'] as String,
      timestampSeconds: row['timestamp_seconds'] as int? ?? 0,
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
      uniformColor: _uniformFromDatabase(row['uniform_color'] as String?),
      capacity: row['capacity'] as int?,
      attending: row['attending_count'] as int? ?? 0,
      targetTeam: row['target_team'] as String? ?? '전체',
      createdBy: creator?['name'] as String? ?? '운영진',
      updatedAt: _relativeTime(DateTime.parse(row['updated_at'] as String)),
      isRecurring: row['recurrence_rule'] != null,
      responseEnabled: row['response_enabled'] as bool? ?? true,
      responseDeadlineOverride: DateTime.parse(
        row['response_deadline'] as String,
      ).toLocal(),
    );
  }

  VideoItem _videoFromRow(Map<String, dynamic> row) {
    final uploader = row['profiles'] as Map?;
    return VideoItem(
      id: row['id'] as String,
      title: row['title'] as String,
      durationLabel: _formatDuration(row['duration_seconds'] as int?),
      category: _videoCategoryFromDatabase(row['category'] as String),
      url: row['source_url'] as String,
      youtubeId: row['youtube_id'] as String,
      uploadedAt: DateTime.parse(row['created_at'] as String).toLocal(),
      uploader: uploader?['name'] as String? ?? 'ENCBA',
      accent: 0xFF00539B,
      likeCount: row['like_count'] as int? ?? 0,
    );
  }

  Future<void> _cache(LockerSnapshot snapshot) => _store.setString(
    _cacheKey,
    jsonEncode({
      'events': snapshot.events.map((event) => event.toJson()).toList(),
      'attendance': snapshot.attendance.map(
        (key, value) => MapEntry(key, value.name),
      ),
      'videos': snapshot.videos.map((video) => video.toJson()).toList(),
      'likes': snapshot.likedVideoIds.toList(),
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
        attendance: Map<String, dynamic>.from(json['attendance'] as Map).map(
          (key, value) =>
              MapEntry(key, AttendanceStatus.values.byName(value as String)),
        ),
        videos: (json['videos'] as List)
            .map(
              (item) =>
                  VideoItem.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(),
        likedVideoIds: Set<String>.from(json['likes'] as List),
        fromCache: true,
      );
    } on Object {
      return null;
    }
  }
}

String _kindToDatabase(EventKind kind) => switch (kind) {
  EventKind.ibDivision1 => 'ib_division_1',
  EventKind.ibDivision2 => 'ib_division_2',
  EventKind.threeWay => 'three_way',
  EventKind.operations => 'operation',
  _ => kind.name,
};

EventKind _kindFromDatabase(String kind) => switch (kind) {
  'ib_division_1' => EventKind.ibDivision1,
  'ib_division_2' => EventKind.ibDivision2,
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

int? _durationToSeconds(String value) {
  final parts = value.split(':').map(int.tryParse).toList();
  if (parts.length != 2 || parts.any((item) => item == null)) return null;
  return parts[0]! * 60 + parts[1]!;
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
