part of 'locker_controller.dart';

/// MembersApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin MembersApi on StateNotifier<LockerState>, ControllerCore {
Future<void> searchMembers(String query) async {
    if (_repository == null) return;
    _memberQuery = query;
    try {
      final members = await _repository.loadMembers(
        membership: _memberMembership,
        query: query,
      );
      state = state.copyWith(members: members, clearError: true);
    } on Object {
      state = state.copyWith(error: '멤버 검색에 실패했습니다.');
    }
  }

/// 엑셀 배정을 보내기 전 계정 등록·활성 상태를 확인할 때는 현재 화면의
  /// 검색어나 군휴학 필터와 무관한 전체 명단이 필요하다.
  Future<List<MemberProfile>> loadAllMembersForAccountCheck() async {
    final repository = _repository;
    if (repository == null) return state.members;
    return _orDefault(repository.loadMembers(membership: 'ALL'), state.members);
  }

/// 검색 결과에서 빠진 멤버도 상세 주소의 ID로 읽어 현재 상태에 합친다.
  Future<bool> ensureMember(String id) async {
    if (state.members.any((member) => member.id == id)) return true;
    final repository = _repository;
    if (repository == null) return false;
    final member = await repository.loadMember(id);
    if (member == null) return false;
    state = state.copyWith(
      members: [...state.members.where((item) => item.id != member.id), member],
      clearError: true,
    );
    return true;
  }

/// 관리자 전용: 대기 중인 계정 활성화 요청을 다시 읽는다.
  Future<void> refreshActivationRequests() async {
    final repository = _repository;
    if (repository == null) return;
    final requests = await _orDefault(
      repository.loadAccountActivationRequests(),
      state.activationRequests,
    );
    state = state.copyWith(activationRequests: requests);
  }

  /// 관리자가 요청을 승인(활성화)하거나 거절한다. 승인하면 명단의
  /// 계정 상태도 함께 최신으로 맞춘다.
  Future<bool> resolveActivationRequest({
    required AccountActivationRequest request,
    required bool approve,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    final previous = state.activationRequests;
    state = state.copyWith(
      activationRequests: previous
          .where((item) => item.id != request.id)
          .toList(),
    );
    try {
      await repository.resolveAccountActivation(
        requestId: request.id,
        approve: approve,
      );
      if (approve) {
        state = state.copyWith(
          members: state.members
              .map(
                (item) => item.id == request.profileId
                    ? item.copyWith(isActive: true)
                    : item,
              )
              .toList(),
        );
      }
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA activation resolve failed: $error\n$stackTrace');
      state = state.copyWith(
        activationRequests: previous,
        error: '활성화 요청을 처리하지 못했습니다.',
      );
      return false;
    }
  }

Future<bool> setMemberActive(MemberProfile member, bool isActive) async {
    if (_repository == null || member.id == null) return false;
    final previous = state.members;
    state = state.copyWith(
      members: previous
          .map(
            (item) =>
                item.id == member.id ? item.copyWith(isActive: isActive) : item,
          )
          .toList(),
    );
    try {
      await _repository.setMemberActive(member.id!, isActive);
      return true;
    } on Object {
      state = state.copyWith(members: previous, error: '계정 상태를 변경하지 못했습니다.');
      return false;
    }
  }

/// 성공하면 null, 실패하면 화면에 그대로 띄울 사유를 돌려준다.
  /// 예전에는 실패 사유를 삼키고 '수정하지 못했습니다'만 보여줘서
  /// 어디가 막혔는지 알 수 없었다.
  Future<String?> updateMember(MemberProfile member) async {
    if (_repository == null || member.id == null) {
      return '멤버 정보를 수정할 수 없는 상태입니다.';
    }
    try {
      await _repository.updateMember(member);
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA member update failed: $error\n$stackTrace');
      final message = _memberUpdateMessage(error);
      state = state.copyWith(error: message);
      return message;
    }
    // 서버가 이름 공백을 다듬거나 뱃지를 다시 계산하므로 저장된 값을 다시 읽는다.
    // 재조회가 실패해도 방금 저장한 값은 화면에 남겨 둔다.
    final members = await _orDefault(
      _repository.loadMembers(
        membership: _memberMembership,
        query: _memberQuery,
      ),
      state.members
          .map((item) => item.id == member.id ? member : item)
          .toList(growable: false),
    );
    // 검색 조건 때문에 방금 고친 멤버가 목록에서 빠지면 상세 화면이 빈 채로
    // 남는다. 조건과 무관하게 그 한 명은 붙여 둔다.
    final refreshed = members.any((item) => item.id == member.id)
        ? members
        : [...members, member];
    state = state.copyWith(members: refreshed, clearError: true);
    return null;
  }

/// 구글 로그인 때 대조하는 가입 명단에 아직 계정이 없는 신규 인원을 추가한다.
  /// 성공하면 null, 실패하면 화면에 그대로 띄울 사유를 돌려준다.
  Future<String?> addMember(MemberProfile member) async {
    if (_repository == null) return '멤버를 등록할 수 없는 상태입니다.';
    try {
      await _repository.addAllowlistMember(member);
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA member add failed: $error\n$stackTrace');
      final message = _memberUpdateMessage(error, adding: true);
      state = state.copyWith(error: message);
      return message;
    }
    final members = await _orDefault(
      _repository.loadMembers(
        membership: _memberMembership,
        query: _memberQuery,
      ),
      state.members,
    );
    state = state.copyWith(members: members, clearError: true);
    return null;
  }

String _memberUpdateMessage(Object error, {bool adding = false}) {
    final text = error is PostgrestException
        ? '${error.code ?? ''} ${error.message}'
        : error.toString();
    if (error is PostgrestException && error.code == '23505') {
      return '이미 등록된 이름입니다.';
    }
    if (text.contains('ENCBA_RESERVATION_ROLE_ADMIN_ONLY')) {
      return '체육관 예약자 지정은 관리자만 바꿀 수 있습니다.';
    }
    if (text.contains('ENCBA_DEPARTMENT_ADMIN_ONLY')) {
      return '학과는 관리자만 바꿀 수 있습니다.';
    }
    if (text.contains('ENCBA_ADMIN_OR_CAPTAIN_REQUIRED')) {
      return adding
          ? '관리자나 주장만 멤버를 등록할 수 있습니다.'
          : '관리자나 주장만 멤버 정보를 수정할 수 있습니다.';
    }
    if (text.contains('ENCBA_INVALID_MEMBER_PROFILE')) {
      return '학번·가입 연도·등번호·소속을 확인해 주세요.';
    }
    if (text.contains('PGRST202') ||
        text.contains('Could not find the function')) {
      return '서버에 최신 마이그레이션이 적용되지 않았습니다. supabase db push가 필요합니다.';
    }
    return adding ? '멤버를 등록하지 못했습니다.' : '멤버 정보를 수정하지 못했습니다.';
  }
}
