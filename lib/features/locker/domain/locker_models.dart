enum EventKind {
  training,
  morning,
  freeOpen,
  internal,
  pickup,
  ibDivision1,
  ibDivision2,
  ibFreshman,
  scrimmage,
  threeWay,
  external,
  operations,
  homecoming,
}

extension EventKindUi on EventKind {
  String get label => switch (this) {
    EventKind.training => '훈련',
    EventKind.morning => '아농',
    EventKind.freeOpen => '자개',
    EventKind.internal => '내부 경기',
    EventKind.pickup => '픽업게임',
    EventKind.ibDivision1 => 'IB 1부',
    EventKind.ibDivision2 => 'IB 2부',
    EventKind.ibFreshman => 'IB 신입생',
    EventKind.scrimmage => '연습 경기',
    EventKind.threeWay => '삼파전',
    EventKind.external => '외부 경기',
    EventKind.operations => 'IB 운영',
    EventKind.homecoming => '홈커밍',
  };

  bool get isMatch => const {
    EventKind.internal,
    EventKind.pickup,
    EventKind.ibDivision1,
    EventKind.ibDivision2,
    EventKind.ibFreshman,
    EventKind.scrimmage,
    EventKind.threeWay,
    EventKind.external,
  }.contains(this);

  bool get isBattle => const {
    EventKind.ibDivision1,
    EventKind.ibDivision2,
    EventKind.ibFreshman,
    EventKind.scrimmage,
    EventKind.threeWay,
    EventKind.external,
  }.contains(this);
}

class LockerEvent {
  const LockerEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.place,
    required this.kind,
    required this.memo,
    this.court,
    this.uniformColors = const [],
    this.capacity,
    this.attending = 0,
    this.targetTeam = '전체',
    this.createdBy = '운영진',
    this.updatedAt = '방금 전',
    this.isRecurring = false,
    this.responseEnabled = true,
    this.responseDeadlineOverride,
    this.pollOptions = const ['참석', '불참', '미정'],
    this.visibility = 'team',
    this.isLocked = false,
    this.opponents = const [],
    this.starterProfileIds = const [],
    this.starterNames = const [],
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String place;
  final String? court;
  final EventKind kind;
  final String memo;
  final List<String> uniformColors;
  final int? capacity;
  final int attending;
  final String targetTeam;
  final String createdBy;
  final String updatedAt;
  final bool isRecurring;
  final bool responseEnabled;
  final DateTime? responseDeadlineOverride;
  final List<String> pollOptions;
  final String visibility;
  final bool isLocked;
  final List<String> opponents;
  final List<String> starterProfileIds;
  final List<String> starterNames;

  bool get isBattle => kind.isBattle;

  String get fullPlace =>
      court == null || court!.isEmpty ? place : '$place · $court';

  Duration get responseBuffer =>
      kind.isMatch ? const Duration(hours: 3) : const Duration(hours: 1);

  DateTime get responseDeadline =>
      responseDeadlineOverride ?? start.subtract(responseBuffer);

  LockerEvent copyWith({
    int? attending,
    bool? isLocked,
    List<String>? starterProfileIds,
    List<String>? starterNames,
  }) => LockerEvent(
    id: id,
    title: title,
    start: start,
    end: end,
    place: place,
    kind: kind,
    memo: memo,
    court: court,
    uniformColors: uniformColors,
    capacity: capacity,
    attending: attending ?? this.attending,
    targetTeam: targetTeam,
    createdBy: createdBy,
    updatedAt: updatedAt,
    isRecurring: isRecurring,
    responseEnabled: responseEnabled,
    responseDeadlineOverride: responseDeadlineOverride,
    pollOptions: pollOptions,
    visibility: visibility,
    isLocked: isLocked ?? this.isLocked,
    opponents: opponents,
    starterProfileIds: starterProfileIds ?? this.starterProfileIds,
    starterNames: starterNames ?? this.starterNames,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'place': place,
    'court': court,
    'kind': kind.name,
    'memo': memo,
    'uniformColors': uniformColors,
    'capacity': capacity,
    'attending': attending,
    'targetTeam': targetTeam,
    'createdBy': createdBy,
    'updatedAt': updatedAt,
    'isRecurring': isRecurring,
    'responseEnabled': responseEnabled,
    'responseDeadline': responseDeadline.toIso8601String(),
    'pollOptions': pollOptions,
    'visibility': visibility,
    'isLocked': isLocked,
    'opponents': opponents,
    'starterProfileIds': starterProfileIds,
    'starterNames': starterNames,
  };

  factory LockerEvent.fromJson(Map<String, dynamic> json) => LockerEvent(
    id: json['id'] as String,
    title: json['title'] as String,
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    place: json['place'] as String,
    court: json['court'] as String?,
    kind: EventKind.values.byName(json['kind'] as String),
    memo: json['memo'] as String,
    uniformColors: List<String>.from(
      json['uniformColors'] as List? ??
          (json['uniformColor'] == null ? const [] : [json['uniformColor']]),
    ),
    capacity: json['capacity'] as int?,
    attending: json['attending'] as int? ?? 0,
    targetTeam: json['targetTeam'] as String? ?? '전체',
    createdBy: json['createdBy'] as String? ?? '운영진',
    updatedAt: json['updatedAt'] as String? ?? '방금 전',
    isRecurring: json['isRecurring'] as bool? ?? false,
    responseEnabled: json['responseEnabled'] as bool? ?? true,
    responseDeadlineOverride: json['responseDeadline'] == null
        ? null
        : DateTime.parse(json['responseDeadline'] as String),
    pollOptions: List<String>.from(
      json['pollOptions'] as List? ?? const ['참석', '불참', '미정'],
    ),
    visibility: json['visibility'] as String? ?? 'team',
    isLocked: json['isLocked'] as bool? ?? false,
    opponents: List<String>.from(json['opponents'] as List? ?? const []),
    starterProfileIds: List<String>.from(
      json['starterProfileIds'] as List? ?? const [],
    ),
    starterNames: List<String>.from(json['starterNames'] as List? ?? const []),
  );
}

class EventStrategy {
  const EventStrategy({
    required this.eventId,
    this.offense = '',
    this.defense = '',
    this.notes = '',
    this.updatedBy = '',
    this.updatedAt,
  });

  final String eventId;
  final String offense;
  final String defense;
  final String notes;
  final String updatedBy;
  final DateTime? updatedAt;

  bool get isEmpty =>
      offense.trim().isEmpty && defense.trim().isEmpty && notes.trim().isEmpty;
}

class MemberProfile {
  const MemberProfile({
    this.id,
    required this.name,
    required this.studentId,
    required this.generation,
    this.joinedYear,
    required this.status,
    required this.position,
    required this.teams,
    required this.note,
    this.badge,
    this.phone = '010-0000-0000',
    this.jerseyNumber = 0,
    this.isActive = true,
    this.leadershipRole = 'member',
    this.isReservationManager = false,
    this.department = '',
  });

  final String? id;
  final String name;
  final String studentId;
  final int generation;
  final int? joinedYear;
  final String status;
  final String position;
  final List<String> teams;
  final String note;
  final String? badge;
  final String phone;
  final int jerseyNumber;
  final bool isActive;
  final String leadershipRole;
  final bool isReservationManager;
  final String department;

  bool get canAdminister =>
      leadershipRole == 'admin' || leadershipRole == 'captain';

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

  MemberProfile copyWith({
    String? name,
    String? studentId,
    int? joinedYear,
    String? status,
    String? position,
    List<String>? teams,
    String? phone,
    int? jerseyNumber,
    bool? isActive,
    String? leadershipRole,
    bool? isReservationManager,
    String? department,
  }) => MemberProfile(
    id: id,
    name: name ?? this.name,
    studentId: studentId ?? this.studentId,
    generation: generation,
    joinedYear: joinedYear ?? this.joinedYear,
    status: status ?? this.status,
    position: position ?? this.position,
    teams: teams ?? this.teams,
    note: note,
    badge: badge,
    phone: phone ?? this.phone,
    jerseyNumber: jerseyNumber ?? this.jerseyNumber,
    isActive: isActive ?? this.isActive,
    leadershipRole: leadershipRole ?? this.leadershipRole,
    isReservationManager: isReservationManager ?? this.isReservationManager,
    department: department ?? this.department,
  );
}

class AnnouncementItem {
  const AnnouncementItem({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.publishedAt,
    this.pinned = false,
  });
  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime publishedAt;
  final bool pinned;
}

class AttendanceRates {
  const AttendanceRates({this.training = 0, this.morning = 0, this.game = 0});

  final int training;
  final int morning;
  final int game;
}

class OperationAssignment {
  const OperationAssignment({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.memo,
    this.assigneeId,
    this.assigneeName = '',
    this.isMine = true,
  });
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String memo;
  final String? assigneeId;
  final String assigneeName;
  final bool isMine;

  LockerEvent toPlannerEvent() => LockerEvent(
    id: 'operation-$id',
    title: title,
    start: start,
    end: end,
    place: location.isEmpty ? '장소 미정' : location,
    kind: EventKind.operations,
    memo: memo,
    targetTeam: '개인',
    createdBy: 'IB 운영표',
    responseEnabled: false,
  );
}

class AttendanceResponse {
  const AttendanceResponse({
    required this.profileId,
    required this.name,
    required this.choice,
    required this.respondedAt,
    this.absenceReason,
  });

  final String profileId;
  final String name;
  final String choice;
  final String? absenceReason;
  final DateTime respondedAt;
}

class OperationSwapRequest {
  const OperationSwapRequest({
    required this.id,
    required this.requesterAssignmentId,
    required this.targetAssignmentId,
    required this.incoming,
    required this.counterpartName,
    required this.requesterTitle,
    required this.requesterStartsAt,
    required this.targetTitle,
    required this.targetStartsAt,
    required this.status,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String requesterAssignmentId;
  final String targetAssignmentId;
  final bool incoming;
  final String counterpartName;
  final String requesterTitle;
  final DateTime requesterStartsAt;
  final String targetTitle;
  final DateTime targetStartsAt;
  final String status;
  final String message;
  final DateTime createdAt;
}

class HomecomingContact {
  const HomecomingContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    this.generation,
    this.parkingRequired,
    this.parkingRegistered = false,
    this.homeOrOfficePhone,
    this.followUpAllowed,
    this.followUpOn,
    this.notes,
    this.sourceRow,
  });
  final String id;
  final String name;
  final String phone;
  final String status;
  final int? generation;
  final bool? parkingRequired;
  final bool parkingRegistered;
  final String? homeOrOfficePhone;
  final bool? followUpAllowed;
  final DateTime? followUpOn;
  final String? notes;
  final int? sourceRow;

  bool get contacted => status == 'contacted' || status == 'confirmed';
  bool get handled => status != 'pending';
  HomecomingContact copyWith({
    String? status,
    bool? parkingRequired,
    bool? parkingRegistered,
    bool? followUpAllowed,
    DateTime? followUpOn,
    String? notes,
  }) => HomecomingContact(
    id: id,
    name: name,
    phone: phone,
    status: status ?? this.status,
    generation: generation,
    parkingRequired: parkingRequired ?? this.parkingRequired,
    parkingRegistered: parkingRegistered ?? this.parkingRegistered,
    homeOrOfficePhone: homeOrOfficePhone,
    followUpAllowed: followUpAllowed ?? this.followUpAllowed,
    followUpOn: followUpOn ?? this.followUpOn,
    notes: notes ?? this.notes,
    sourceRow: sourceRow,
  );
}

class HomecomingCampaign {
  const HomecomingCampaign({
    required this.id,
    required this.title,
    required this.academicYear,
    required this.term,
    required this.eventDate,
    required this.startsAt,
    required this.endsAt,
    required this.venue,
    required this.isActive,
    this.afterpartyNote = '회식 장소는 아직 정해지지 않았습니다.',
    this.sourceFileName,
  });

  final String id;
  final String title;
  final int academicYear;
  final int term;
  final DateTime eventDate;
  final String startsAt;
  final String endsAt;
  final String venue;
  final bool isActive;
  final String afterpartyNote;
  final String? sourceFileName;
}

class VideoWatchSummary {
  const VideoWatchSummary({
    required this.name,
    required this.watchedSeconds,
    required this.lastPositionSeconds,
    required this.completed,
  });

  final String name;
  final int watchedSeconds;
  final int lastPositionSeconds;
  final bool completed;
}

class EventRosterMember {
  const EventRosterMember({
    required this.profileId,
    required this.name,
    required this.status,
  });

  final String profileId;
  final String name;
  final String status;

  EventRosterMember copyWith({String? status}) => EventRosterMember(
    profileId: profileId,
    name: name,
    status: status ?? this.status,
  );
}

class AuditEntry {
  const AuditEntry({
    required this.table,
    required this.action,
    required this.actor,
    required this.createdAt,
  });
  final String table;
  final String action;
  final String actor;
  final DateTime createdAt;
}

class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.durationLabel,
    required this.category,
    required this.url,
    required this.youtubeId,
    required this.uploadedAt,
    required this.uploader,
    required this.accent,
    this.likeCount = 0,
    this.sourceType = 'youtube',
    this.quarterUrls = const [],
  });

  final String id;
  final String title;
  final String durationLabel;
  final String category;
  final String url;
  final String youtubeId;
  final DateTime uploadedAt;
  final String uploader;
  final int accent;
  final int likeCount;
  final String sourceType;
  final List<String?> quarterUrls;

  VideoItem copyWith({
    String? title,
    String? durationLabel,
    String? category,
    String? url,
    String? youtubeId,
    int? likeCount,
    String? sourceType,
    List<String?>? quarterUrls,
  }) => VideoItem(
    id: id,
    title: title ?? this.title,
    durationLabel: durationLabel ?? this.durationLabel,
    category: category ?? this.category,
    url: url ?? this.url,
    youtubeId: youtubeId ?? this.youtubeId,
    uploadedAt: uploadedAt,
    uploader: uploader,
    accent: accent,
    likeCount: likeCount ?? this.likeCount,
    sourceType: sourceType ?? this.sourceType,
    quarterUrls: quarterUrls ?? this.quarterUrls,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'durationLabel': durationLabel,
    'category': category,
    'url': url,
    'youtubeId': youtubeId,
    'uploadedAt': uploadedAt.toIso8601String(),
    'uploader': uploader,
    'accent': accent,
    'likeCount': likeCount,
    'sourceType': sourceType,
    'quarterUrls': quarterUrls,
  };

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
    id: json['id'] as String,
    title: json['title'] as String,
    durationLabel: json['durationLabel'] as String? ?? '',
    category: json['category'] as String,
    url: json['url'] as String,
    youtubeId: json['youtubeId'] as String? ?? '',
    uploadedAt: DateTime.parse(json['uploadedAt'] as String),
    uploader: json['uploader'] as String? ?? 'ENCBA',
    accent: json['accent'] as int? ?? 0xFF00539B,
    likeCount: json['likeCount'] as int? ?? 0,
    sourceType: json['sourceType'] as String? ?? 'youtube',
    quarterUrls: (json['quarterUrls'] as List? ?? const [])
        .map((value) => value as String?)
        .toList(),
  );
}

class VideoCommentItem {
  const VideoCommentItem({
    required this.id,
    required this.videoId,
    required this.timestampSeconds,
    required this.body,
    required this.author,
    required this.createdAt,
  });

  final int id;
  final String videoId;
  final int timestampSeconds;
  final String body;
  final String author;
  final DateTime createdAt;
}
