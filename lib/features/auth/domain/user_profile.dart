class UserProfile {
  const UserProfile({
    this.id,
    required this.email,
    required this.name,
    required this.studentId,
    required this.generation,
    required this.phone,
    required this.position,
    required this.jerseyNumber,
    required this.status,
    required this.teams,
    this.badge,
    this.photoBase64,
    this.isAdmin = false,
  });

  final String? id;
  final String email;
  final String name;
  final String studentId;
  final int generation;
  final String phone;
  final String position;
  final int jerseyNumber;
  final String status;
  final List<String> teams;
  final String? badge;
  final String? photoBase64;
  final bool isAdmin;

  UserProfile copyWith({
    String? id,
    String? name,
    String? studentId,
    int? generation,
    String? phone,
    String? position,
    int? jerseyNumber,
    String? status,
    List<String>? teams,
    String? badge,
    String? photoBase64,
    bool clearPhoto = false,
    bool? isAdmin,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email,
      name: name ?? this.name,
      studentId: studentId ?? this.studentId,
      generation: generation ?? this.generation,
      phone: phone ?? this.phone,
      position: position ?? this.position,
      jerseyNumber: jerseyNumber ?? this.jerseyNumber,
      status: status ?? this.status,
      teams: teams ?? this.teams,
      badge: badge ?? this.badge,
      photoBase64: clearPhoto ? null : photoBase64 ?? this.photoBase64,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'studentId': studentId,
    'generation': generation,
    'phone': phone,
    'position': position,
    'jerseyNumber': jerseyNumber,
    'status': status,
    'teams': teams,
    'badge': badge,
    'photoBase64': photoBase64,
    'isAdmin': isAdmin,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String?,
    email: json['email'] as String,
    name: json['name'] as String,
    studentId: json['studentId'] as String,
    generation: json['generation'] as int,
    phone: json['phone'] as String,
    position: json['position'] as String,
    jerseyNumber: json['jerseyNumber'] as int? ?? 0,
    status: json['status'] as String,
    teams: List<String>.from(json['teams'] as List),
    badge: json['badge'] as String?,
    photoBase64: json['photoBase64'] as String?,
    isAdmin: json['isAdmin'] as bool? ?? false,
  );

  factory UserProfile.fromSupabase(Map<String, dynamic> row) => UserProfile(
    id: row['id'] as String,
    email: row['email'] as String,
    name: row['name'] as String,
    studentId: '${row['student_year']}학번',
    generation: row['generation'] as int,
    phone: row['phone'] as String? ?? '',
    position: row['position'] as String? ?? '미정',
    jerseyNumber: row['jersey_number'] as int? ?? 0,
    status: (row['membership_status'] as String? ?? 'yb').toUpperCase(),
    teams: (row['teams'] as List?)?.cast<String>() ?? const ['ENCBA'],
    badge: row['badge'] as String?,
    photoBase64: row['photo_base64'] as String?,
    isAdmin: row['is_admin'] as bool? ?? false,
  );
}
