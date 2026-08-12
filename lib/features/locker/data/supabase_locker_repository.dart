import 'dart:convert';

import 'package:encba_locker/core/storage/local_store.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  String get _userId =>
      _client.auth.currentUser?.id ?? (throw StateError('로그인이 필요합니다.'));

  Future<LockerSnapshot> load() async {
    final now = DateTime.now();
    final todayStartsAt = DateTime(
      now.year,
      now.month,
      now.day,
    ).toUtc().toIso8601String();
    final cached = await _readCache();
    final eventFuture = _orFallback<({List<LockerEvent> events, bool hasMore})>(
      _loadEventPage(
        todayStartsAt: todayStartsAt,
        offset: 0,
        limit: eventPageSize,
        includeLocked: true,
      ),
      (
        events: cached?.events ?? const <LockerEvent>[],
        hasMore: cached?.hasMoreEvents ?? false,
      ),
      debugLabel: 'events',
    );
    final attendanceFuture = _orFallback<Map<String, String>>(
      _loadMyAttendance(),
      cached?.attendance ?? const <String, String>{},
    );
    final videosFuture = _orFallback<List<VideoItem>>(
      _loadVideos(),
      cached?.videos ?? const <VideoItem>[],
    );
    final likesFuture = _orFallback<Set<String>>(
      _loadLikedVideoIds(),
      cached?.likedVideoIds ?? const <String>{},
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
      fromCache: cached != null && identical(eventPage.events, cached.events),
    );
    try {
      await _cache(snapshot);
    } on Object {
      // 온라인 응답은 로컬 캐시 저장 실패와 무관하게 그대로 사용한다.
    }
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
    final rows = await _client
        .from('videos')
        .select('*,profiles!videos_uploaded_by_fkey(name,display_name)')
        .order('created_at', ascending: false)
        .order('id')
        .limit(videoPageSize);
    return rows
        .map<VideoItem>((row) => _videoFromRow(Map<String, dynamic>.from(row)))
        .toList(growable: false);
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
    final now = DateTime.now();
    return _loadEventPage(
      todayStartsAt: DateTime(
        now.year,
        now.month,
        now.day,
      ).toUtc().toIso8601String(),
      offset: offset,
      limit: eventPageSize,
      includeLocked: false,
    );
  }

  Future<({List<LockerEvent> events, bool hasMore})> _loadEventPage({
    required String todayStartsAt,
    required int offset,
    required int limit,
    required bool includeLocked,
  }) async {
    final normalFuture = _client
        .from('events')
        .select('*,places(name),profiles!events_created_by_fkey(name)')
        .gte('starts_at', todayStartsAt)
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
    final events =
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
    return (events: events, hasMore: normalRows.length == limit);
  }

  Future<T> _orFallback<T>(
    Future<T> future,
    T fallback, {
    String? debugLabel,
  }) async {
    try {
      return await future;
    } on Object catch (error) {
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
          return MemberProfile(
            id: map['directory_id'] as String,
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
            isActive: map['is_active'] as bool? ?? true,
            phone: map['phone'] as String? ?? '',
            jerseyNumber: map['jersey_number'] as int? ?? 0,
            leadershipRole: map['leadership_role'] as String? ?? 'member',
          );
        })
        .toList(growable: false);
  }

  Future<void> setMemberActive(String profileId, bool isActive) => _client.rpc(
    'set_member_account_active',
    params: {'requested_directory_id': profileId, 'requested_active': isActive},
  );

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
    },
  );

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
    final rows = await _client
        .from('announcements')
        .select(
          'id,title,body,pinned,published_at,profiles!announcements_created_by_fkey(name)',
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
        pinned: row['pinned'] as bool? ?? false,
      );
    }).toList();
  }

  Future<AnnouncementItem> addAnnouncement({
    required String title,
    required String body,
    required bool pinned,
  }) async {
    final row = await _client
        .from('announcements')
        .insert({
          'title': title,
          'body': body,
          'pinned': pinned,
          'created_by': _userId,
          'updated_by': _userId,
        })
        .select(
          'id,title,body,published_at,profiles!announcements_created_by_fkey(name,display_name)',
        )
        .single();
    final profile = row['profiles'] as Map?;
    return AnnouncementItem(
      id: row['id'] as String,
      title: row['title'] as String,
      body: row['body'] as String,
      author:
          profile?['display_name'] as String? ??
          profile?['name'] as String? ??
          '운영진',
      publishedAt: DateTime.parse(row['published_at'] as String).toLocal(),
      pinned: row['pinned'] as bool? ?? false,
    );
  }

  Future<AnnouncementItem> updateAnnouncement({
    required String id,
    required String title,
    required String body,
    required bool pinned,
  }) async {
    final row = await _client
        .from('announcements')
        .update({
          'title': title,
          'body': body,
          'pinned': pinned,
          'updated_by': _userId,
        })
        .eq('id', id)
        .select(
          'id,title,body,published_at,profiles!announcements_created_by_fkey(name,display_name)',
        )
        .single();
    final profile = row['profiles'] as Map?;
    return AnnouncementItem(
      id: row['id'] as String,
      title: row['title'] as String,
      body: row['body'] as String,
      author:
          profile?['display_name'] as String? ??
          profile?['name'] as String? ??
          '운영진',
      publishedAt: DateTime.parse(row['published_at'] as String).toLocal(),
      pinned: row['pinned'] as bool? ?? false,
    );
  }

  Future<void> deleteAnnouncement(String id) =>
      _client.from('announcements').delete().eq('id', id);

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

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  Future<List<OperationAssignment>> loadOperations() async {
    final rows = await _client.rpc('list_my_operation_assignments');
    return rows
        .map(
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
        .toList();
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

  Future<List<HomecomingContact>> loadHomecomingContacts() async {
    final rows = await _client
        .from('homecoming_contacts')
        .select(
          'id,source_row,senior_name,generation,home_or_office_phone,phone,'
          'contact_status,parking_required,parking_registered,follow_up_allowed,'
          'follow_up_on,notes,homecoming_campaigns!inner(is_active)',
        )
        .eq('homecoming_campaigns.is_active', true)
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
            homeOrOfficePhone: row['home_or_office_phone'] as String?,
            followUpAllowed: row['follow_up_allowed'] as bool?,
            followUpOn: row['follow_up_on'] == null
                ? null
                : DateTime.parse(row['follow_up_on'] as String),
            notes: row['notes'] as String?,
            sourceRow: row['source_row'] as int?,
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

  Future<void> importHomecomingContacts({
    required String campaignId,
    required String fileName,
    required List<Map<String, dynamic>> contacts,
  }) async {
    await _client
        .from('homecoming_campaigns')
        .update({'source_file_name': fileName})
        .eq('id', campaignId);
    await _client
        .from('homecoming_contacts')
        .delete()
        .eq('campaign_id', campaignId);
    for (var offset = 0; offset < contacts.length; offset += 100) {
      final end = (offset + 100).clamp(0, contacts.length);
      await _client
          .from('homecoming_contacts')
          .insert(
            contacts
                .sublist(offset, end)
                .map((row) => {...row, 'campaign_id': campaignId})
                .toList(),
          );
    }
  }

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
                profile?['display_name'] as String? ??
                profile?['name'] as String? ??
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
      'response_enabled': event.responseEnabled,
      'response_deadline': event.responseDeadline.toUtc().toIso8601String(),
      'recurrence_rule': event.isRecurring
          ? {'frequency': 'weekly', 'count': 12, 'editable_instances': true}
          : null,
      'poll_options': event.pollOptions,
      'visibility': event.visibility,
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
            .select('*,places(name),profiles!events_created_by_fkey(name)')
            .single();
      }
      payload['created_by'] = _userId;
      return _client
          .from('events')
          .insert(payload)
          .select('*,places(name),profiles!events_created_by_fkey(name)')
          .single();
    }

    late final Map<String, dynamic> row;
    try {
      row = await persist();
    } on PostgrestException catch (error) {
      final schemaCacheMissing =
          error.code == 'PGRST204' &&
          error.message.toLowerCase().contains('opponents');
      if (!schemaCacheMissing) rethrow;
      payload.remove('opponents');
      row = await persist();
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
          'youtube_id': video.youtubeId.isEmpty ? null : video.youtubeId,
          'source_type': video.sourceType,
          'quarter_1_url': video.quarterUrls.elementAtOrNull(0),
          'quarter_2_url': video.quarterUrls.elementAtOrNull(1),
          'quarter_3_url': video.quarterUrls.elementAtOrNull(2),
          'quarter_4_url': video.quarterUrls.elementAtOrNull(3),
          'duration_seconds': _durationToSeconds(video.durationLabel),
          'uploaded_by': _userId,
        })
        .select('*,profiles!videos_uploaded_by_fkey(name,display_name)')
        .single();
    return _videoFromRow(row);
  }

  Future<VideoItem> updateVideo(VideoItem video) async {
    final row = await _client
        .from('videos')
        .update({
          'title': video.title,
          'category': _videoCategoryToDatabase(video.category),
          'source_url': video.url,
          'youtube_id': video.youtubeId.isEmpty ? null : video.youtubeId,
          'source_type': video.sourceType,
          'quarter_1_url': video.quarterUrls.elementAtOrNull(0),
          'quarter_2_url': video.quarterUrls.elementAtOrNull(1),
          'quarter_3_url': video.quarterUrls.elementAtOrNull(2),
          'quarter_4_url': video.quarterUrls.elementAtOrNull(3),
          'duration_seconds': _durationToSeconds(video.durationLabel),
        })
        .eq('id', video.id)
        .select('*,profiles!videos_uploaded_by_fkey(name,display_name)')
        .single();
    return _videoFromRow(row);
  }

  Future<void> deleteVideo(String id) =>
      _client.from('videos').delete().eq('id', id);

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

  Future<void> recordVideoWatch({
    required String videoId,
    required int watchedSeconds,
    required int lastPositionSeconds,
    required bool completed,
  }) => _client.rpc(
    'record_video_watch',
    params: {
      'requested_video_id': videoId,
      'watched_delta_seconds': watchedSeconds,
      'requested_position_seconds': lastPositionSeconds,
      'requested_completed': completed,
    },
  );

  Future<List<VideoWatchSummary>> loadVideoWatchSummary(String videoId) async {
    final rows = await _client
        .from('video_watch_sessions')
        .select(
          'watched_seconds,last_position_seconds,completed,profiles(name,display_name)',
        )
        .eq('video_id', videoId)
        .order('watched_seconds', ascending: false);
    return rows.map((row) {
      final profile = row['profiles'] as Map?;
      return VideoWatchSummary(
        name:
            profile?['display_name'] as String? ??
            profile?['name'] as String? ??
            '부원',
        watchedSeconds: row['watched_seconds'] as int? ?? 0,
        lastPositionSeconds: row['last_position_seconds'] as int? ?? 0,
        completed: row['completed'] as bool? ?? false,
      );
    }).toList();
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
            profile?['display_name'] as String? ??
            profile?['name'] as String? ??
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
      uniformColors: (row['uniform_colors'] as List? ?? const [])
          .map((value) => _uniformFromDatabase(value as String))
          .whereType<String>()
          .toList(),
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
      pollOptions: List<String>.from(
        row['poll_options'] as List? ?? const ['참석', '불참', '미정'],
      ),
      visibility: row['visibility'] as String? ?? 'team',
      isLocked: row['locked'] as bool? ?? false,
      opponents:
          (row['opponents'] as List?)?.cast<String>() ??
          (row['opponent'] == null ? const [] : [row['opponent'] as String]),
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
      youtubeId: row['youtube_id'] as String? ?? '',
      uploadedAt: DateTime.parse(row['created_at'] as String).toLocal(),
      uploader:
          uploader?['display_name'] as String? ??
          uploader?['name'] as String? ??
          'ENCBA',
      accent: 0xFF00539B,
      likeCount: row['like_count'] as int? ?? 0,
      sourceType: row['source_type'] as String? ?? 'youtube',
      quarterUrls: [
        row['quarter_1_url'] as String?,
        row['quarter_2_url'] as String?,
        row['quarter_3_url'] as String?,
        row['quarter_4_url'] as String?,
      ],
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
