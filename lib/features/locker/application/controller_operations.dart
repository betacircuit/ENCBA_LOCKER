part of 'locker_controller.dart';

/// OperationsApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin OperationsApi on StateNotifier<LockerState>, ControllerCore {
  Future<({int imported, int unmatched})?> importOperations({
    required String fileName,
    required int academicYear,
    required int term,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final repository = _repository;
    if (repository == null) return null;
    try {
      final result = await repository.importOperations(
        fileName: fileName,
        academicYear: academicYear,
        term: term,
        assignments: assignments,
      );
      final operations = await repository.loadOperations();
      final board = await repository.loadOperationExchangeBoard();
      final allOperations = await repository.loadAllOperations();
      state = state.copyWith(
        operations: operations,
        allOperations: allOperations,
        operationExchangeBoard: board,
        clearError: true,
      );
      return result;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation import failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영표를 가져오지 못했습니다.');
      return null;
    }
  }

  Future<bool> deactivateOperations() async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      final deactivated = await repository.deactivateOperations();
      if (!deactivated) return false;
      state = state.copyWith(
        operations: const [],
        allOperations: const [],
        operationExchangeBoard: const [],
        operationSwapRequests: const [],
        clearError: true,
      );
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation deactivate failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영을 비활성화하지 못했습니다.');
      return false;
    }
  }

  /// 관리자용: 학기 전체 IB 운영 배정을 읽어 온다.
  Future<List<OperationAssignment>> loadAllOperations() async {
    final repository = _repository;
    if (repository == null) return const [];
    return _orDefault(
      repository.loadAllOperations(),
      const <OperationAssignment>[],
    );
  }

  /// 관리자가 전체 운영 배정을 수정한 뒤 내 일정과 교환 게시판을 새로 읽는다.
  Future<bool> updateOperationAssignment({
    required OperationAssignment assignment,
    required DateTime start,
    required DateTime end,
    required String title,
    required String location,
    required String memo,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      await repository.updateOperationAssignment(
        id: assignment.id,
        start: start,
        end: end,
        title: title,
        location: location,
        memo: memo,
      );
      await refreshOperationSwaps();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation update failed: $error\n$stackTrace');
      state = state.copyWith(error: '운영 일정을 수정하지 못했습니다.');
      return false;
    }
  }

  Future<void> refreshOperationSwaps() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final operationsFuture = repository.loadOperations();
      final allOperationsFuture = repository.loadAllOperations();
      final boardFuture = repository.loadOperationExchangeBoard();
      final requestsFuture = repository.loadOperationSwapRequests();
      state = state.copyWith(
        operations: await operationsFuture,
        allOperations: await allOperationsFuture,
        operationExchangeBoard: await boardFuture,
        operationSwapRequests: await requestsFuture,
        clearError: true,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation swap refresh failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영 교환 정보를 불러오지 못했습니다.');
    }
  }

  Future<bool> requestOperationSwap({
    required String ownAssignmentId,
    required String targetAssignmentId,
    required String message,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      await repository.createOperationSwapRequest(
        ownAssignmentId: ownAssignmentId,
        targetAssignmentId: targetAssignmentId,
        message: message,
      );
      await refreshOperationSwaps();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation swap request failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영 교환 신청을 보내지 못했습니다.');
      return false;
    }
  }

  Future<bool> respondOperationSwap({
    required String requestId,
    required bool accept,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      await repository.respondOperationSwapRequest(
        requestId: requestId,
        accept: accept,
      );
      await refreshOperationSwaps();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA operation swap response failed: $error\n$stackTrace');
      state = state.copyWith(error: 'IB 운영 교환 응답을 저장하지 못했습니다.');
      return false;
    }
  }
}
