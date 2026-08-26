part of 'supabase_locker_repository.dart';

/// EventsApi - 리포지토리를 테이블·도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin EventsApi on RepoCore {
  @override
  SupabaseClient get _client;

  @override
  String get _userId;

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

  Future<List<LockerEvent>> _loadPastEvents({
    required String todayStartsAt,
  }) async {
    const pageSize = 500;
    final events = <LockerEvent>[];
    for (var offset = 0; ; offset += pageSize) {
      final rows = await _client
          .from('events')
          .select(_eventSelection)
          .lt('ends_at', todayStartsAt)
          .order('starts_at')
          .order('id')
          .range(offset, offset + pageSize - 1);
      events.addAll(
        rows.map((row) => _eventFromRow(Map<String, dynamic>.from(row as Map))),
      );
      if (rows.length < pageSize) break;
    }
    return events;
  }

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

  Future<LockerEvent> cancelEvent(String id, String reason) async {
    final row = await _client
        .from('events')
        .update({
          'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          'cancellation_reason': reason.trim(),
          'updated_by': _userId,
        })
        .eq('id', id)
        .select(_eventSelection)
        .single();
    return _eventFromRow(Map<String, dynamic>.from(row));
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
      cancelledAt: row['cancelled_at'] == null
          ? null
          : DateTime.parse(row['cancelled_at'] as String).toLocal(),
      cancellationReason: row['cancellation_reason'] as String?,
    );
  }
}
