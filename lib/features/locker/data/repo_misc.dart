part of 'supabase_locker_repository.dart';

/// MiscApi - 리포지토리를 테이블·도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin MiscApi on RepoCore {
  @override
  SupabaseClient get _client;

  @override
  String get _userId;

  Future<DateTime> loadServerTime() async {
    final value = await _client.rpc('get_server_time');
    return DateTime.parse(value as String).toLocal();
  }

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  /// 오류 제보를 저장한다. 메일 설정에 기대지 않고 앱 안에서 관리자가 읽는다.
  Future<void> submitErrorReport({
    required String body,
    String? studentId,
    String? email,
    String? environment,
  }) => _client.from('error_reports').insert({
    'profile_id': _userId,
    'body': body,
    'student_id': studentId,
    'email': email,
    'environment': environment,
  });

  Future<List<ErrorReportItem>> loadErrorReports() async {
    final rows = await _client
        .from('error_reports')
        .select(
          'id,body,student_id,email,environment,is_read,created_at,'
          'profiles!error_reports_profile_id_fkey(name)',
        )
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map((row) {
      final reporter = row['profiles'] as Map?;
      return ErrorReportItem(
        id: row['id'].toString(),
        body: row['body'] as String? ?? '',
        reporter: reporter?['name'] as String? ?? '알 수 없음',
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        isRead: row['is_read'] as bool? ?? false,
        studentId: row['student_id'] as String?,
        email: row['email'] as String?,
        environment: row['environment'] as String?,
      );
    }).toList();
  }

  Future<void> setErrorReportRead(String id, {required bool isRead}) => _client
      .from('error_reports')
      .update({'is_read': isRead})
      .eq('id', id);

  Future<void> deleteErrorReport(String id) =>
      _client.from('error_reports').delete().eq('id', id);

  /// 내가 앱 수요조사에 별을 눌렀는지. 정책상 자기 행만 읽힌다.
  Future<bool> loadAppDemandVote() async {
    final userId = _userId;
    final rows = await _client
        .from('app_demand_votes')
        .select('profile_id')
        .eq('profile_id', userId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<void> addAppDemandVote() =>
      _client.from('app_demand_votes').upsert({'profile_id': _userId});

  Future<void> removeAppDemandVote() =>
      _client.from('app_demand_votes').delete().eq('profile_id', _userId);

  /// 별 토글. true면 지금 눌린 상태.
  Future<bool> toggleAppDemand() async {
    if (await loadAppDemandVote()) {
      await removeAppDemandVote();
      return false;
    }
    await addAppDemandVote();
    return true;
  }

  /// 관리자 전용: 서버에 남은 알림 기록 전체.
  Future<List<NotificationLogEntry>> loadNotificationLog({
    int limit = 200,
  }) async {
    final rows = await _client.rpc(
      'list_notification_log',
      params: {'requested_limit': limit},
    );
    return (rows as List<dynamic>)
        .map(
          (raw) =>
              NotificationLogEntry.fromRow(Map<String, dynamic>.from(raw as Map)),
        )
        .toList(growable: false);
  }

  /// 나에게 온 서버 알림. 기기 기록에 없는 것만 합치려고 시각으로 자른다.
  Future<List<NotificationLogEntry>> loadMyNotifications({
    DateTime? since,
  }) async {
    final rows = await _client.rpc(
      'list_my_notifications',
      params: {'requested_since': since?.toUtc().toIso8601String()},
    );
    return (rows as List<dynamic>)
        .map(
          (raw) => NotificationLogEntry.fromRow({
            ...Map<String, dynamic>.from(raw as Map),
            'recipient_name': '나',
          }),
        )
        .toList(growable: false);
  }

  /// 수요 합계. 관리자만 목록을 읽을 수 있다.
  Future<int> loadAppDemandCount() async {
    final rows = await _client.from('app_demand_votes').select('profile_id');
    return (rows as List).length;
  }

  /// 관리자 전용: 이 일정에 아직 응답하지 않은 사람에게 푸시를 일괄 발송한다.
  /// send-push 엣지 함수가 호출자 JWT로 관리자 권한을 확인한다.
  /// 반환값은 발송 대상(구독) 수다.
  Future<int> remindEventNonresponders(String eventId) async {
    final response = await _client.functions.invoke(
      'send-push',
      body: {'kind': 'response_reminder', 'event_id': eventId},
    );
    final data = response.data;
    if (data is Map && data['targets'] is num) {
      return (data['targets'] as num).toInt();
    }
    return 0;
  }
}
