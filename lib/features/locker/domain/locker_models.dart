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
    this.mapReference,
    this.obParticipantCount = 0,
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
  final String? mapReference;
  final int obParticipantCount;

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
    String? mapReference,
    int? obParticipantCount,
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
    mapReference: mapReference ?? this.mapReference,
    obParticipantCount: obParticipantCount ?? this.obParticipantCount,
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
    'mapReference': mapReference,
    'obParticipantCount': obParticipantCount,
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
    mapReference: json['mapReference'] as String?,
    obParticipantCount: (json['obParticipantCount'] as num?)?.toInt() ?? 0,
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
    this.isFreshman = false,
    this.titles = const [],
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
  final bool isFreshman;
  /// 관리자/주장/매니저 권한과는 무관한 표시용 직책(부서장, BEN 감독 등).
  final List<String> titles;

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
    bool? isFreshman,
    List<String>? titles,
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
    isFreshman: isFreshman ?? this.isFreshman,
    titles: titles ?? this.titles,
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
    this.linkedEventIds = const [],
  });
  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime publishedAt;
  final bool pinned;
  final List<String> linkedEventIds;
}

class AttendanceReportRow {
  const AttendanceReportRow({
    required this.directoryId,
    required this.memberName,
    required this.studentYear,
    required this.isFreshman,
    required this.eventId,
    required this.eventTitle,
    required this.eventStart,
    required this.eventKind,
    required this.choice,
    required this.absenceReason,
  });

  final String directoryId;
  final String memberName;
  final int? studentYear;
  final bool isFreshman;
  final String eventId;
  final String eventTitle;
  final DateTime eventStart;
  final String eventKind;
  final String? choice;
  final String? absenceReason;
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

class VideoTaggedMember {
  const VideoTaggedMember({
    required this.directoryId,
    required this.name,
    this.studentYear,
    this.jerseyNumber,
  });

  final String directoryId;
  final String name;
  final int? studentYear;
  final int? jerseyNumber;

  /// 선택 목록에 그대로 쓰는 표기.
  /// 등번호는 미등록이면 0으로 들어오므로 그때는 이름만 남긴다.
  String get label => jerseyNumber == null || jerseyNumber == 0
      ? name
      : '$name ($jerseyNumber)';

  Map<String, dynamic> toJson() => {
    'directoryId': directoryId,
    'name': name,
    'studentYear': studentYear,
    'jerseyNumber': jerseyNumber,
  };

  factory VideoTaggedMember.fromJson(Map<String, dynamic> json) =>
      VideoTaggedMember(
        directoryId: json['directoryId'] as String,
        name: json['name'] as String,
        studentYear: (json['studentYear'] as num?)?.toInt(),
        jerseyNumber: (json['jerseyNumber'] as num?)?.toInt(),
      );
}

/// 학번이 높은(최근) 부원부터, 같은 학번이면 이름 순으로 세운다.
int compareTaggedMembers(VideoTaggedMember a, VideoTaggedMember b) {
  final left = a.studentYear ?? -1;
  final right = b.studentYear ?? -1;
  final byYear = right.compareTo(left);
  return byYear != 0 ? byYear : a.name.compareTo(b.name);
}

/// 복기 영상에 붙는 링크 하나. [quarterNumber]가 null이면 쿼터 미정이다.
class VideoLink {
  const VideoLink({required this.url, this.quarterNumber, this.id});

  final String url;
  final int? quarterNumber;

  /// 서버가 매긴 링크 id. 코멘트를 이 링크에 묶는 데 쓴다.
  /// 아직 저장하지 않은 링크는 null이다.
  final int? id;

  String get label => quarterNumber == null ? '쿼터 미정' : '$quarterNumber쿼터';

  VideoLink copyWith({int? id, int? quarterNumber, String? url}) => VideoLink(
    url: url ?? this.url,
    quarterNumber: quarterNumber ?? this.quarterNumber,
    id: id ?? this.id,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'quarterNumber': quarterNumber,
    'id': id,
  };

  factory VideoLink.fromJson(Map<String, dynamic> json) => VideoLink(
    url: json['url'] as String,
    quarterNumber: (json['quarterNumber'] as num?)?.toInt(),
    id: (json['id'] as num?)?.toInt(),
  );
}

/// 쿼터가 정해진 링크를 먼저 번호순으로, 쿼터 미정은 뒤에 등록 순으로 세운다.
/// 같은 자리끼리는 들어온 순서를 지켜야 "미정 1, 미정 2" 번호가 흔들리지 않는다.
List<VideoLink> sortedVideoLinks(Iterable<VideoLink> links) {
  final indexed = links.indexed.toList()
    ..sort((a, b) {
      final left = a.$2.quarterNumber;
      final right = b.$2.quarterNumber;
      if (left != right) {
        if (left == null) return 1;
        if (right == null) return -1;
        final byQuarter = left.compareTo(right);
        if (byQuarter != 0) return byQuarter;
      }
      return a.$1.compareTo(b.$1);
    });
  return [for (final entry in indexed) entry.$2];
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
    this.links = const [],
    this.recordedOn,
    this.audienceType = 'all',
    this.audienceValues = const [],
    this.reviewPlayers = const [],
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

  /// 복기 영상의 쿼터별·쿼터 미정 링크. 다른 분류에서는 비어 있다.
  final List<VideoLink> links;

  /// 경기가 열린 날. 업로드 날짜와 다를 수 있어 따로 받는다.
  final DateTime? recordedOn;
  final String audienceType;
  final List<String> audienceValues;
  final List<VideoTaggedMember> reviewPlayers;

  /// 예전 quarter_1..4 컬럼과 맞물리는 앞 네 쿼터의 링크.
  List<String?> get quarterUrls => [
    for (var quarter = 1; quarter <= 4; quarter++)
      links
          .where((link) => link.quarterNumber == quarter)
          .map((link) => link.url)
          .firstOrNull,
  ];

  VideoItem copyWith({
    String? id,
    String? title,
    String? durationLabel,
    String? category,
    String? url,
    String? youtubeId,
    int? likeCount,
    String? sourceType,
    List<VideoLink>? links,
    DateTime? recordedOn,
    bool clearRecordedOn = false,
    String? audienceType,
    List<String>? audienceValues,
    List<VideoTaggedMember>? reviewPlayers,
    DateTime? uploadedAt,
    String? uploader,
  }) => VideoItem(
    id: id ?? this.id,
    title: title ?? this.title,
    durationLabel: durationLabel ?? this.durationLabel,
    category: category ?? this.category,
    url: url ?? this.url,
    youtubeId: youtubeId ?? this.youtubeId,
    uploadedAt: uploadedAt ?? this.uploadedAt,
    uploader: uploader ?? this.uploader,
    accent: accent,
    likeCount: likeCount ?? this.likeCount,
    sourceType: sourceType ?? this.sourceType,
    links: links ?? this.links,
    recordedOn: clearRecordedOn ? null : recordedOn ?? this.recordedOn,
    audienceType: audienceType ?? this.audienceType,
    audienceValues: audienceValues ?? this.audienceValues,
    reviewPlayers: reviewPlayers ?? this.reviewPlayers,
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
    'links': links.map((link) => link.toJson()).toList(),
    'recordedOn': recordedOn?.toIso8601String(),
    'audienceType': audienceType,
    'audienceValues': audienceValues,
    'reviewPlayers': reviewPlayers.map((member) => member.toJson()).toList(),
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
    links: json['links'] == null
        // 링크 테이블이 생기기 전에 저장된 캐시는 쿼터 배열만 갖고 있다.
        ? [
            for (final (index, value)
                in (json['quarterUrls'] as List? ?? const []).indexed)
              if (value is String && value.isNotEmpty)
                VideoLink(url: value, quarterNumber: index + 1),
          ]
        : (json['links'] as List)
              .map(
                (value) =>
                    VideoLink.fromJson(Map<String, dynamic>.from(value as Map)),
              )
              .toList(),
    recordedOn: json['recordedOn'] == null
        ? null
        : DateTime.parse(json['recordedOn'] as String),
    audienceType: json['audienceType'] as String? ?? 'all',
    audienceValues: List<String>.from(
      json['audienceValues'] as List? ?? const [],
    ),
    reviewPlayers: (json['reviewPlayers'] as List? ?? const [])
        .map(
          (value) => VideoTaggedMember.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
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
    this.quarterNumber,
    this.linkId,
    this.targetPlayers = const [],
  });

  final int id;
  final String videoId;
  final int timestampSeconds;
  final String body;
  final String author;
  final DateTime createdAt;
  final int? quarterNumber;

  /// 코멘트가 달린 링크. 쿼터 미정 링크가 여러 개일 수 있어 쿼터 번호만으로는
  /// 어느 영상의 코멘트인지 가려지지 않는다.
  final int? linkId;
  final List<VideoTaggedMember> targetPlayers;
}
