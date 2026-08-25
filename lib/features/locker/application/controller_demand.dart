part of 'locker_controller.dart';

/// DemandApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin DemandApi on StateNotifier<LockerState>, ControllerCore {
/// 앱 수요조사: 내 별을 눌렀는지 확인한다. 실패해도 false로 처리해
  /// 버튼이 항상 동작하게 둔다.
  Future<bool> loadAppDemandVote() async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      return await repository.loadAppDemandVote();
    } on Object {
      return false;
    }
  }

/// 앱 수요조사 별 토글. true면 지금 눌린 상태.
  Future<bool> toggleAppDemand() async {
    final repository = _repository;
    if (repository == null) return false;
    return repository.toggleAppDemand();
  }

/// 앱 수요조사 합계. 관리자만 읽을 수 있으므로 실패하면 null을 돌려준다.
  Future<int?> loadAppDemandCount() async {
    final repository = _repository;
    if (repository == null) return null;
    try {
      return await repository.loadAppDemandCount();
    } on Object {
      return null;
    }
  }

/// 관리자 전용: 미응답자에게 응답 독촉 알림을 일괄 발송하고 결과 문구를
  /// 돌려준다. 실패해도 예외 대신 안내 문구를 돌려 스낵바로 보여 준다.
  Future<String> remindEventNonresponders(String eventId) async {
    final repository = _repository;
    if (repository == null) return '알림을 보내지 못했습니다.';
    try {
      final targets = await repository.remindEventNonresponders(eventId);
      return targets == 0
          ? '보낼 대상이 없습니다. 모두 응답했거나 알림을 켠 사람이 없습니다.'
          : '$targets명에게 응답 독촉 알림을 보냈습니다.';
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA response reminder failed: $error\n$stackTrace');
      return '알림을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.';
    }
  }
}
