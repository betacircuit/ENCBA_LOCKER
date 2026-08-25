part of 'supabase_locker_repository.dart';

/// MembersApi - 리포지토리를 테이블·도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin MembersApi on RepoCore {
  @override
  SupabaseClient get _client;

  @override
  String get _userId;

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
}
