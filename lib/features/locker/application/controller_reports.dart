part of 'locker_controller.dart';

/// ReportsApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin ReportsApi on StateNotifier<LockerState>, ControllerCore {
/// 감사 로그는 감사 화면에서만 필요하므로 진입 시점까지 네트워크 요청을 미룬다.
  Future<void> loadAuditEntries() {
    final inFlight = _auditEntriesLoadInFlight;
    if (inFlight != null) return inFlight;
    if (_repository == null) return Future<void>.value();
    final next = _repository
        .loadAuditLogs()
        .then((entries) {
          state = state.copyWith(auditEntries: entries, clearError: true);
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('ENCBA audit log load failed: $error\n$stackTrace');
          state = state.copyWith(error: '수정 이력을 불러오지 못했습니다.');
        });
    _auditEntriesLoadInFlight = next;
    return next.whenComplete(() {
      if (identical(_auditEntriesLoadInFlight, next)) {
        _auditEntriesLoadInFlight = null;
      }
    });
  }

/// 오류 제보를 서버에 남긴다. 실패하면 화면이 대체 경로를 안내하도록
  /// 예외를 그대로 올린다.
  Future<void> submitErrorReport({
    required String body,
    String? studentId,
    String? email,
    String? environment,
  }) async {
    final repository = _repository;
    if (repository == null) return;
    await repository.submitErrorReport(
      body: body,
      studentId: studentId,
      email: email,
      environment: environment,
    );
  }

/// 오류 제보는 관리자 화면에서만 필요해 진입 시점에 읽는다.
  Future<void> loadErrorReports() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final reports = await repository.loadErrorReports();
      state = state.copyWith(errorReports: reports, clearError: true);
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA error report load failed: $error\n$stackTrace');
      state = state.copyWith(error: '오류 제보를 불러오지 못했습니다.');
    }
  }

/// 읽음 표시는 눌린 즉시 반영하고, 실패하면 이전 값으로 되돌린다.
  Future<void> setErrorReportRead(String id, {required bool isRead}) async {
    final repository = _repository;
    if (repository == null) return;
    final previous = state.errorReports;
    state = state.copyWith(
      errorReports: [
        for (final report in previous)
          report.id == id ? report.copyWith(isRead: isRead) : report,
      ],
    );
    try {
      await repository.setErrorReportRead(id, isRead: isRead);
    } on Object {
      state = state.copyWith(
        errorReports: previous,
        error: '읽음 표시를 저장하지 못했습니다.',
      );
    }
  }

Future<void> deleteErrorReport(String id) async {
    final repository = _repository;
    if (repository == null) return;
    final previous = state.errorReports;
    state = state.copyWith(
      errorReports: previous.where((report) => report.id != id).toList(),
    );
    try {
      await repository.deleteErrorReport(id);
    } on Object {
      state = state.copyWith(
        errorReports: previous,
        error: '오류 제보를 삭제하지 못했습니다.',
      );
    }
  }
}
