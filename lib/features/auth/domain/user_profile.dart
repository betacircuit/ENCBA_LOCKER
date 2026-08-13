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
    isAdmin: json['isAdmin'] as bool? ?? false,
    isScheduleManager: json['isScheduleManager'] as bool? ?? false,
    isActive: json['isActive'] as bool? ?? true,
    leadershipRole: json['leadershipRole'] as String? ?? 'member',
    isReservationManager: json['isReservationManager'] as bool? ?? false,
  );

  factory UserProfile.fromSupabase(Map<String, dynamic> row) => UserProfile(
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
    isAdmin: row['is_admin'] as bool? ?? false,
    isScheduleManager: row['is_schedule_manager'] as bool? ?? false,
    isActive: row['is_active'] as bool? ?? true,
    leadershipRole:
        row['leadership_role'] as String? ??
        ((row['is_admin'] as bool? ?? false) ? 'admin' : 'member'),
    isReservationManager: row['is_reservation_manager'] as bool? ?? false,
  );

  String get visibleName =>
      (displayName?.trim().isNotEmpty ?? false) ? displayName!.trim() : name;

  bool get canAdminister => isAdmin || leadershipRole == 'captain';

  bool get canManageHighlights => leadershipRole == 'manager';

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
