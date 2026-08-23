class PendingGoogleRegistration {
  const PendingGoogleRegistration({
    required this.email,
    this.suggestedName = '',
  });

  final String email;
  final String suggestedName;
}

bool isSnuSchoolEmail(String email) {
  final separator = email.lastIndexOf('@');
  if (separator < 1 || separator == email.length - 1) return false;
  final domain = email.substring(separator + 1).toLowerCase();
  return domain == 'snu.ac.kr' || domain.endsWith('.snu.ac.kr');
}

class UserProfile {
  const UserProfile({
    this.id,
    required this.email,
    required this.name,
    this.displayName,
    required this.studentId,
    required this.generation,
    this.joinedYear,
    required this.phone,
    required this.position,
    required this.jerseyNumber,
    required this.status,
    required this.teams,
    this.badge,
    this.photoBase64,
    this.avatarUrl,
    this.isAdmin = false,
    this.isScheduleManager = false,
    this.isActive = true,
    this.leadershipRole = 'member',
    this.isReservationManager = false,
  });

  final String? id;
  final String email;
  final String name;
  final String? displayName;
  final String studentId;
  final int generation;
  final int? joinedYear;
  final String phone;
  final String position;
  final int jerseyNumber;
  final String status;
  final List<String> teams;
  final String? badge;
  final String? photoBase64;
  final String? avatarUrl;
  final bool isAdmin;
  final bool isScheduleManager;
  final bool isActive;
  final String leadershipRole;
  final bool isReservationManager;

  UserProfile copyWith({
    String? id,
    String? name,
    String? displayName,
    String? studentId,
    int? generation,
    int? joinedYear,
    String? phone,
    String? position,
    int? jerseyNumber,
    String? status,
    List<String>? teams,
    String? badge,
    String? photoBase64,
    bool clearPhoto = false,
    String? avatarUrl,
    bool clearAvatar = false,
    bool? isAdmin,
    bool? isScheduleManager,
    bool? isActive,
    String? leadershipRole,
    bool? isReservationManager,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      studentId: studentId ?? this.studentId,
      generation: generation ?? this.generation,
      joinedYear: joinedYear ?? this.joinedYear,
      phone: phone ?? this.phone,
      position: position ?? this.position,
      jerseyNumber: jerseyNumber ?? this.jerseyNumber,
      status: status ?? this.status,
      teams: teams ?? this.teams,
      badge: badge ?? this.badge,
      photoBase64: clearPhoto ? null : photoBase64 ?? this.photoBase64,
      avatarUrl: clearAvatar ? null : avatarUrl ?? this.avatarUrl,
      isAdmin: isAdmin ?? this.isAdmin,
      isScheduleManager: isScheduleManager ?? this.isScheduleManager,
      isActive: isActive ?? this.isActive,
      leadershipRole: leadershipRole ?? this.leadershipRole,
      isReservationManager: isReservationManager ?? this.isReservationManager,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'displayName': displayName,
    'studentId': studentId,
    'generation': generation,
    'joinedYear': joinedYear,
    'phone': phone,
    'position': position,
    'jerseyNumber': jerseyNumber,
    'status': status,
    'teams': teams,
    'badge': badge,
    'photoBase64': photoBase64,
    'avatarUrl': avatarUrl,
    'isAdmin': isAdmin,
    'isScheduleManager': isScheduleManager,
    'isActive': isActive,
    'leadershipRole': leadershipRole,
    'isReservationManager': isReservationManager,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String?,
    email: json['email'] as String,
    name: json['name'] as String,
    displayName: json['displayName'] as String?,
    studentId: json['studentId'] as String,
    generation: json['generation'] as int,
    joinedYear: json['joinedYear'] as int?,
    phone: json['phone'] as String,
    position: json['position'] as String,
    jerseyNumber: json['jerseyNumber'] as int? ?? 0,
    status: json['status'] as String,
    teams: List<String>.from(json['teams'] as List),
    badge: json['badge'] as String?,
    photoBase64: json['photoBase64'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    isAdmin: json['isAdmin'] as bool? ?? false,
    isScheduleManager: json['isScheduleManager'] as bool? ?? false,
    isActive: json['isActive'] as bool? ?? true,
    leadershipRole: json['leadershipRole'] as String? ?? 'member',
    isReservationManager: json['isReservationManager'] as bool? ?? false,
  );

  /// leadership_role='admin'인데 is_admin 플래그가 꺼진 계정이 있었다.
  /// 화면은 leadership_role 기준으로 관리자 뱃지를 보여주므로, 두 값 중
  /// 하나라도 관리자면 관리자로 취급해 서버·클라이언트 판정을 맞춘다.
  factory UserProfile.fromSupabase(Map<String, dynamic> row) {
    final leadershipRole =
        row['leadership_role'] as String? ??
        ((row['is_admin'] as bool? ?? false) ? 'admin' : 'member');
    return UserProfile(
      id: row['id'] as String,
      email: row['email'] as String,
      name: row['name'] as String,
      displayName: row['display_name'] as String?,
      studentId: '${row['student_year']}학번',
      generation: row['generation'] as int,
      joinedYear: row['joined_year'] as int?,
      phone: row['phone'] as String? ?? '',
      position: row['position'] as String? ?? '미정',
      jerseyNumber: row['jersey_number'] as int? ?? 0,
      status: (row['membership_status'] as String? ?? 'yb').toUpperCase(),
      teams: (row['teams'] as List?)?.cast<String>() ?? const ['ENCBA'],
      badge: row['badge'] as String?,
      photoBase64: row['photo_base64'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      isAdmin: (row['is_admin'] as bool? ?? false) || leadershipRole == 'admin',
      isScheduleManager: row['is_schedule_manager'] as bool? ?? false,
      isActive: row['is_active'] as bool? ?? true,
      leadershipRole: leadershipRole,
      isReservationManager: row['is_reservation_manager'] as bool? ?? false,
    );
  }

  /// 다른 부원에게 노출되는 이름은 가입 명단에서 확인한 실명만 사용한다.
  String get visibleName => name;

  bool get canAdminister => isAdmin || leadershipRole == 'captain';

  /// 하이라이트(릴스) 등록은 매니저 전용이었지만, 관리자·주장도 올릴 수
  /// 있게 열었다. 운영진이 하이라이트를 대신 등록하는 일이 잦기 때문이다.
  bool get canManageHighlights =>
      leadershipRole == 'manager' ||
      leadershipRole == 'captain' ||
      isAdmin;

  String? get leadershipLabel => switch (leadershipRole) {
    'admin' => '관리자',
    'captain' => '주장',
    'manager' => '매니저',
    _ => null,
  };

  String get teamLabel {
    final hasEncba = teams.contains('ENCBA');
    final hasBen = teams.contains('BEN');
    if (hasEncba && hasBen) return 'ENCBA & BEN';
    return teams.join(' & ');
  }
}
