import 'package:encba_locker/features/locker/domain/locker_models.dart';

class LockerUiState {
  const LockerUiState({
    this.isReady = false,
    this.gameSegment = 1,
    this.gameSubSegment = 0,
    this.videoSegment = 0,
    this.memberSegment = 0,
    this.unreadNotifications = 0,
    this.isOfflineCache = false,
    this.isSyncing = false,
    this.error,
  });

  final bool isReady;
  final int gameSegment;
  final int gameSubSegment;
  final int videoSegment;
  final int memberSegment;
  final int unreadNotifications;
  final bool isOfflineCache;
  final bool isSyncing;
  final String? error;
}

class LockerEventsState {
  const LockerEventsState({
    this.attendance = const {},
    this.events = const [],
    this.eventRosters = const {},
    this.eventAttendance = const {},
    this.eventStrategies = const {},
    this.attendanceRates = const AttendanceRates(),
    this.hasMoreEvents = false,
    this.isLoadingMoreEvents = false,
  });

  final Map<String, String> attendance;
  final List<LockerEvent> events;
  final Map<String, List<EventRosterMember>> eventRosters;
  final Map<String, List<AttendanceResponse>> eventAttendance;
  final Map<String, EventStrategy> eventStrategies;
  final AttendanceRates attendanceRates;
  final bool hasMoreEvents;
  final bool isLoadingMoreEvents;

  List<LockerEvent> plannerEventsWith(LockerOperationsState operationsState) {
    final visibleOperations = operationsState.allOperations.isNotEmpty
        ? operationsState.allOperations
        : operationsState.operations;
    final merged = <LockerEvent>[
      ...events,
      ...visibleOperations.map((assignment) => assignment.toPlannerEvent()),
      if (operationsState.homecomingCampaign case final campaign?)
        campaign.toPlannerEvent(),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return merged;
  }
}

class LockerVideosState {
  const LockerVideosState({
    this.videos = const [],
    this.likedVideoIds = const {},
    this.videoComments = const {},
  });

  final List<VideoItem> videos;
  final Set<String> likedVideoIds;
  final Map<String, List<VideoCommentItem>> videoComments;
}

class LockerMembersState {
  const LockerMembersState({this.members = const []});

  final List<MemberProfile> members;
}

class LockerOperationsState {
  const LockerOperationsState({
    this.announcements = const [],
    this.operations = const [],
    this.allOperations = const [],
    this.homecomingContacts = const [],
    this.homecomingCampaign,
    this.operationExchangeBoard = const [],
    this.operationSwapRequests = const [],
    this.auditEntries = const [],
    this.errorReports = const [],
  });

  final List<AnnouncementItem> announcements;
  final List<OperationAssignment> operations;
  final List<OperationAssignment> allOperations;
  final List<HomecomingContact> homecomingContacts;
  final HomecomingCampaign? homecomingCampaign;
  final List<OperationAssignment> operationExchangeBoard;
  final List<OperationSwapRequest> operationSwapRequests;
  final List<AuditEntry> auditEntries;

  /// 관리자만 읽는 오류 제보 목록.
  final List<ErrorReportItem> errorReports;
}

class LockerState {
  LockerState({
    bool isReady = false,
    int gameSegment = 1,
    int gameSubSegment = 0,
    int videoSegment = 0,
    int memberSegment = 0,
    int unreadNotifications = 0,
    Map<String, String> attendance = const {},
    List<LockerEvent> events = const [],
    List<VideoItem> videos = const [],
    Set<String> likedVideoIds = const {},
    Map<String, List<VideoCommentItem>> videoComments = const {},
    List<MemberProfile> members = const [],
    List<AnnouncementItem> announcements = const [],
    List<OperationAssignment> operations = const [],
    List<OperationAssignment> allOperations = const [],
    List<HomecomingContact> homecomingContacts = const [],
    HomecomingCampaign? homecomingCampaign,
    Map<String, List<EventRosterMember>> eventRosters = const {},
    Map<String, List<AttendanceResponse>> eventAttendance = const {},
    Map<String, EventStrategy> eventStrategies = const {},
    List<OperationAssignment> operationExchangeBoard = const [],
    List<OperationSwapRequest> operationSwapRequests = const [],
    List<AuditEntry> auditEntries = const [],
    List<ErrorReportItem> errorReports = const [],
    AttendanceRates attendanceRates = const AttendanceRates(),
    bool hasMoreEvents = false,
    bool isLoadingMoreEvents = false,
    bool isOfflineCache = false,
    bool isSyncing = false,
    String? error,
  }) : ui = LockerUiState(
         isReady: isReady,
         gameSegment: gameSegment,
         gameSubSegment: gameSubSegment,
         videoSegment: videoSegment,
         memberSegment: memberSegment,
         unreadNotifications: unreadNotifications,
         isOfflineCache: isOfflineCache,
         isSyncing: isSyncing,
         error: error,
       ),
       eventsState = LockerEventsState(
         attendance: attendance,
         events: events,
         eventRosters: eventRosters,
         eventAttendance: eventAttendance,
         eventStrategies: eventStrategies,
         attendanceRates: attendanceRates,
         hasMoreEvents: hasMoreEvents,
         isLoadingMoreEvents: isLoadingMoreEvents,
       ),
       videosState = LockerVideosState(
         videos: videos,
         likedVideoIds: likedVideoIds,
         videoComments: videoComments,
       ),
       membersState = LockerMembersState(members: members),
       operationsState = LockerOperationsState(
         announcements: announcements,
         operations: operations,
         allOperations: allOperations,
         homecomingContacts: homecomingContacts,
         homecomingCampaign: homecomingCampaign,
         operationExchangeBoard: operationExchangeBoard,
         operationSwapRequests: operationSwapRequests,
         auditEntries: auditEntries,
         errorReports: errorReports,
       );

  LockerState._({
    required this.ui,
    required this.eventsState,
    required this.videosState,
    required this.membersState,
    required this.operationsState,
  });

  final LockerUiState ui;
  final LockerEventsState eventsState;
  final LockerVideosState videosState;
  final LockerMembersState membersState;
  final LockerOperationsState operationsState;

  bool get isReady => ui.isReady;
  int get gameSegment => ui.gameSegment;
  int get gameSubSegment => ui.gameSubSegment;
  int get videoSegment => ui.videoSegment;
  int get memberSegment => ui.memberSegment;
  int get unreadNotifications => ui.unreadNotifications;
  bool get isOfflineCache => ui.isOfflineCache;
  bool get isSyncing => ui.isSyncing;
  String? get error => ui.error;
  Map<String, String> get attendance => eventsState.attendance;
  List<LockerEvent> get events => eventsState.events;
  Map<String, List<EventRosterMember>> get eventRosters =>
      eventsState.eventRosters;
  Map<String, List<AttendanceResponse>> get eventAttendance =>
      eventsState.eventAttendance;
  Map<String, EventStrategy> get eventStrategies => eventsState.eventStrategies;
  AttendanceRates get attendanceRates => eventsState.attendanceRates;
  bool get hasMoreEvents => eventsState.hasMoreEvents;
  bool get isLoadingMoreEvents => eventsState.isLoadingMoreEvents;
  List<VideoItem> get videos => videosState.videos;
  Set<String> get likedVideoIds => videosState.likedVideoIds;
  Map<String, List<VideoCommentItem>> get videoComments =>
      videosState.videoComments;
  List<MemberProfile> get members => membersState.members;
  List<AnnouncementItem> get announcements => operationsState.announcements;
  List<OperationAssignment> get operations => operationsState.operations;
  List<OperationAssignment> get allOperations => operationsState.allOperations;
  List<HomecomingContact> get homecomingContacts =>
      operationsState.homecomingContacts;
  HomecomingCampaign? get homecomingCampaign =>
      operationsState.homecomingCampaign;
  List<OperationAssignment> get operationExchangeBoard =>
      operationsState.operationExchangeBoard;
  List<OperationSwapRequest> get operationSwapRequests =>
      operationsState.operationSwapRequests;
  List<AuditEntry> get auditEntries => operationsState.auditEntries;
  List<ErrorReportItem> get errorReports => operationsState.errorReports;

  List<LockerEvent> get plannerEvents =>
      eventsState.plannerEventsWith(operationsState);

  LockerState copyWith({
    bool? isReady,
    int? gameSegment,
    int? gameSubSegment,
    int? videoSegment,
    int? memberSegment,
    int? unreadNotifications,
    Map<String, String>? attendance,
    List<LockerEvent>? events,
    List<VideoItem>? videos,
    Set<String>? likedVideoIds,
    Map<String, List<VideoCommentItem>>? videoComments,
    List<MemberProfile>? members,
    List<AnnouncementItem>? announcements,
    List<OperationAssignment>? operations,
    List<OperationAssignment>? allOperations,
    List<HomecomingContact>? homecomingContacts,
    HomecomingCampaign? homecomingCampaign,
    bool clearHomecomingCampaign = false,
    Map<String, List<EventRosterMember>>? eventRosters,
    Map<String, List<AttendanceResponse>>? eventAttendance,
    Map<String, EventStrategy>? eventStrategies,
    List<OperationAssignment>? operationExchangeBoard,
    List<OperationSwapRequest>? operationSwapRequests,
    List<AuditEntry>? auditEntries,
    List<ErrorReportItem>? errorReports,
    AttendanceRates? attendanceRates,
    bool? hasMoreEvents,
    bool? isLoadingMoreEvents,
    bool? isOfflineCache,
    bool? isSyncing,
    String? error,
    bool clearError = false,
  }) {
    final uiChanged =
        isReady != null ||
        gameSegment != null ||
        gameSubSegment != null ||
        videoSegment != null ||
        memberSegment != null ||
        unreadNotifications != null ||
        isOfflineCache != null ||
        isSyncing != null ||
        error != null ||
        clearError;
    final eventsChanged =
        attendance != null ||
        events != null ||
        eventRosters != null ||
        eventAttendance != null ||
        eventStrategies != null ||
        attendanceRates != null ||
        hasMoreEvents != null ||
        isLoadingMoreEvents != null;
    final videosChanged =
        videos != null || likedVideoIds != null || videoComments != null;
    final membersChanged = members != null;
    final operationsChanged =
        announcements != null ||
        operations != null ||
        allOperations != null ||
        homecomingContacts != null ||
        homecomingCampaign != null ||
        clearHomecomingCampaign ||
        operationExchangeBoard != null ||
        operationSwapRequests != null ||
        auditEntries != null ||
        errorReports != null;

    return LockerState._(
      ui: uiChanged
          ? LockerUiState(
              isReady: isReady ?? this.isReady,
              gameSegment: gameSegment ?? this.gameSegment,
              gameSubSegment: gameSubSegment ?? this.gameSubSegment,
              videoSegment: videoSegment ?? this.videoSegment,
              memberSegment: memberSegment ?? this.memberSegment,
              unreadNotifications:
                  unreadNotifications ?? this.unreadNotifications,
              isOfflineCache: isOfflineCache ?? this.isOfflineCache,
              isSyncing: isSyncing ?? this.isSyncing,
              error: clearError ? null : error ?? this.error,
            )
          : ui,
      eventsState: eventsChanged
          ? LockerEventsState(
              attendance: attendance ?? this.attendance,
              events: events ?? this.events,
              eventRosters: eventRosters ?? this.eventRosters,
              eventAttendance: eventAttendance ?? this.eventAttendance,
              eventStrategies: eventStrategies ?? this.eventStrategies,
              attendanceRates: attendanceRates ?? this.attendanceRates,
              hasMoreEvents: hasMoreEvents ?? this.hasMoreEvents,
              isLoadingMoreEvents:
                  isLoadingMoreEvents ?? this.isLoadingMoreEvents,
            )
          : eventsState,
      videosState: videosChanged
          ? LockerVideosState(
              videos: videos ?? this.videos,
              likedVideoIds: likedVideoIds ?? this.likedVideoIds,
              videoComments: videoComments ?? this.videoComments,
            )
          : videosState,
      membersState: membersChanged
          ? LockerMembersState(members: members)
          : membersState,
      operationsState: operationsChanged
          ? LockerOperationsState(
              announcements: announcements ?? this.announcements,
              operations: operations ?? this.operations,
              allOperations: allOperations ?? this.allOperations,
              homecomingContacts: homecomingContacts ?? this.homecomingContacts,
              homecomingCampaign: clearHomecomingCampaign
                  ? null
                  : homecomingCampaign ?? this.homecomingCampaign,
              operationExchangeBoard:
                  operationExchangeBoard ?? this.operationExchangeBoard,
              operationSwapRequests:
                  operationSwapRequests ?? this.operationSwapRequests,
              auditEntries: auditEntries ?? this.auditEntries,
              errorReports: errorReports ?? this.errorReports,
            )
          : operationsState,
    );
  }
}
