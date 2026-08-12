enum AttendanceStatus { attending, late, absent, undecided }

enum EventKind {
  training,
  morning,
  internal,
  ibDivision1,
  ibDivision2,
  scrimmage,
  threeWay,
  external,
  operations,
  homecoming,
}

extension EventKindUi on EventKind {
  String get label => switch (this) {
    EventKind.training => '정기 훈련',
    EventKind.morning => '아농',
    EventKind.internal => '내부 경기',
    EventKind.ibDivision1 => 'IB 1부',
    EventKind.ibDivision2 => 'IB 2부',
    EventKind.scrimmage => '연습 경기',
    EventKind.threeWay => '삼파전',
    EventKind.external => '외부 경기',
    EventKind.operations => 'IB 운영',
    EventKind.homecoming => '홈커밍',
  };

  bool get isMatch => const {
    EventKind.internal,
    EventKind.ibDivision1,
    EventKind.ibDivision2,
    EventKind.scrimmage,
    EventKind.threeWay,
    EventKind.external,
  }.contains(this);

  bool get isBattle => const {
    EventKind.ibDivision1,
    EventKind.ibDivision2,
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
    this.uniformColor,
    this.capacity,
    this.attending = 0,
    this.targetTeam = '전체',
    this.createdBy = '운영진',
    this.updatedAt = '방금 전',
    this.isRecurring = false,
    this.responseEnabled = true,
    this.responseDeadlineOverride,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String place;
  final String? court;
  final EventKind kind;
  final String memo;
  final String? uniformColor;
  final int? capacity;
  final int attending;
  final String targetTeam;
  final String createdBy;
  final String updatedAt;
  final bool isRecurring;
  final bool responseEnabled;
  final DateTime? responseDeadlineOverride;

  bool get isBattle => kind.isBattle;

  String get fullPlace =>
      court == null || court!.isEmpty ? place : '$place · $court';

  Duration get responseBuffer =>
      kind.isMatch ? const Duration(hours: 3) : const Duration(hours: 1);

  DateTime get responseDeadline =>
      responseDeadlineOverride ?? start.subtract(responseBuffer);

  LockerEvent copyWith({int? attending}) => LockerEvent(
    id: id,
    title: title,
    start: start,
    end: end,
    place: place,
    kind: kind,
    memo: memo,
    court: court,
    uniformColor: uniformColor,
    capacity: capacity,
    attending: attending ?? this.attending,
    targetTeam: targetTeam,
    createdBy: createdBy,
    updatedAt: updatedAt,
    isRecurring: isRecurring,
    responseEnabled: responseEnabled,
    responseDeadlineOverride: responseDeadlineOverride,
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
    'uniformColor': uniformColor,
    'capacity': capacity,
    'attending': attending,
    'targetTeam': targetTeam,
    'createdBy': createdBy,
    'updatedAt': updatedAt,
    'isRecurring': isRecurring,
    'responseEnabled': responseEnabled,
    'responseDeadline': responseDeadline.toIso8601String(),
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
    uniformColor: json['uniformColor'] as String?,
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
  );
}

class MemberProfile {
  const MemberProfile({
    required this.name,
    required this.studentId,
    required this.generation,
    required this.status,
    required this.position,
    required this.teams,
    required this.note,
    this.badge,
    this.phone = '010-0000-0000',
  });

  final String name;
  final String studentId;
  final int generation;
  final String status;
  final String position;
  final List<String> teams;
  final String note;
  final String? badge;
  final String phone;
}

class AnnouncementItem {
  const AnnouncementItem({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.publishedAt,
  });
  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime publishedAt;
}

class OperationAssignment {
  const OperationAssignment({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.memo,
  });
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String memo;
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
  });
  final String id;
  final String name;
  final String phone;
  final String status;
  final int? generation;
  final bool? parkingRequired;
  final bool parkingRegistered;

  bool get contacted => status == 'contacted' || status == 'confirmed';
  bool get handled => status != 'pending';
  HomecomingContact copyWith({String? status}) => HomecomingContact(
    id: id,
    name: name,
    phone: phone,
    status: status ?? this.status,
    generation: generation,
    parkingRequired: parkingRequired,
    parkingRegistered: parkingRegistered,
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

  VideoItem copyWith({int? likeCount}) => VideoItem(
    id: id,
    title: title,
    durationLabel: durationLabel,
    category: category,
    url: url,
    youtubeId: youtubeId,
    uploadedAt: uploadedAt,
    uploader: uploader,
    accent: accent,
    likeCount: likeCount ?? this.likeCount,
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
