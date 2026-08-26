part of 'supabase_locker_repository.dart';

/// OperationsApi - 리포지토리를 테이블·도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin OperationsApi on RepoCore {
  @override
  SupabaseClient get _client;

  @override
  String get _userId;

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

  /// IB 운영 배정이 새로 등록되거나 바뀌면 알려 준다. 읽기 정책상 모든
  /// 부원이 전체 배정을 볼 수 있으므로 공용 플래너도 재접속 없이 갱신한다.
  RealtimeChannel subscribeToOperationAssignments(
    void Function(Map<String, dynamic> record) onChange,
  ) => _client
      .channel('encba-operation-assignments-$_userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'operation_assignments',
        callback: (payload) => onChange(payload.newRecord),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'operation_assignments',
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
    final assignments = (rows as List<dynamic>)
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
    assignments.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
    return assignments;
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
}
