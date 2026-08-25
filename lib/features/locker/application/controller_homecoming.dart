part of 'locker_controller.dart';

/// HomecomingApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin HomecomingApi on StateNotifier<LockerState>, ControllerCore {
/// 홈커밍 연락망은 전용 화면에 들어올 때만 불러와 초기 동기화를 가볍게 유지한다.
  Future<void> loadHomecomingContacts() {
    final inFlight = _homecomingContactsLoadInFlight;
    if (inFlight != null) return inFlight;
    if (_repository == null) return Future<void>.value();
    final next = _repository
        .loadHomecomingContacts()
        .then((contacts) {
          state = state.copyWith(
            homecomingContacts: contacts,
            clearError: true,
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'ENCBA homecoming contacts load failed: $error\n$stackTrace',
          );
          state = state.copyWith(error: '홈커밍 연락망을 불러오지 못했습니다.');
        });
    _homecomingContactsLoadInFlight = next;
    return next.whenComplete(() {
      if (identical(_homecomingContactsLoadInFlight, next)) {
        _homecomingContactsLoadInFlight = null;
      }
    });
  }

Future<bool> updateHomecomingContact(HomecomingContact contact) async {
    final previous = state.homecomingContacts;
    final next = previous
        .map((item) => item.id == contact.id ? contact : item)
        .toList();
    state = state.copyWith(homecomingContacts: next);
    try {
      await _repository?.updateHomecomingContact(contact);
      return true;
    } on Object {
      state = state.copyWith(
        homecomingContacts: previous,
        error: '홈커밍 연락 상태를 저장하지 못했습니다.',
      );
      return false;
    }
  }

Future<bool> assignHomecomingContact({
    required HomecomingContact contact,
    MemberProfile? member,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    final previous = state.homecomingContacts;
    final updated = contact.assignedTo(id: member?.id, name: member?.name);
    state = state.copyWith(
      homecomingContacts: previous
          .map((item) => item.id == contact.id ? updated : item)
          .toList(growable: false),
    );
    try {
      await repository.assignHomecomingContact(
        id: contact.id,
        assignedToId: member?.id,
        assignedToName: member?.name,
      );
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint(
        'ENCBA homecoming assignee update failed: $error\n$stackTrace',
      );
      state = state.copyWith(
        homecomingContacts: previous,
        error: '홈커밍 담당자를 저장하지 못했습니다.',
      );
      return false;
    }
  }

Future<bool> activateHomecomingCampaign({
    required int academicYear,
    required int term,
    required DateTime eventDate,
    required String startsAt,
    required String endsAt,
    required String venue,
  }) async {
    try {
      final campaign = await _repository?.activateHomecomingCampaign(
        academicYear: academicYear,
        term: term,
        eventDate: eventDate,
        startsAt: startsAt,
        endsAt: endsAt,
        venue: venue,
      );
      state = state.copyWith(homecomingCampaign: campaign, clearError: true);
      return campaign != null;
    } on Object {
      state = state.copyWith(error: '홈커밍 캠페인을 열지 못했습니다.');
      return false;
    }
  }

Future<bool> deactivateHomecomingCampaign(String campaignId) async {
    try {
      await _repository?.deactivateHomecomingCampaign(campaignId);
      state = state.copyWith(
        clearHomecomingCampaign: true,
        homecomingContacts: const [],
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '홈커밍 캠페인을 다시 잠그지 못했습니다.');
      return false;
    }
  }

Future<bool> importHomecomingContacts({
    required String fileName,
    required List<Map<String, dynamic>> contacts,
  }) async {
    final campaign = state.homecomingCampaign;
    if (campaign == null || _repository == null) return false;
    try {
      await _repository.importHomecomingContacts(
        campaignId: campaign.id,
        fileName: fileName,
        contacts: contacts,
      );
      final refreshed = await _repository.loadHomecomingContacts();
      state = state.copyWith(homecomingContacts: refreshed, clearError: true);
      return true;
    } on Object {
      state = state.copyWith(error: '엑셀 연락망을 가져오지 못했습니다.');
      return false;
    }
  }

/// 관리자가 홈커밍 연락 보드에 선배를 한 명 직접 추가한다.
  Future<bool> addHomecomingContact({
    required String name,
    required String phone,
    int? generation,
    String? assignedToId,
    String? assignedToName,
  }) async {
    final campaign = state.homecomingCampaign;
    final repository = _repository;
    if (campaign == null || repository == null) return false;
    try {
      await repository.addHomecomingContact(
        campaignId: campaign.id,
        name: name,
        phone: phone,
        generation: generation,
        assignedToId: assignedToId,
        assignedToName: assignedToName,
      );
      final refreshed = await repository.loadHomecomingContacts();
      state = state.copyWith(homecomingContacts: refreshed, clearError: true);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA homecoming contact add failed: $error\n$stackTrace');
      state = state.copyWith(error: '선배 연락처를 추가하지 못했습니다.');
      return false;
    }
  }

/// 관리자가 홈커밍 연락 보드에서 선배 카드를 삭제한다.
  Future<bool> deleteHomecomingContact(String id) async {
    final repository = _repository;
    if (repository == null) return false;
    final previous = state.homecomingContacts;
    state = state.copyWith(
      homecomingContacts: previous.where((item) => item.id != id).toList(),
    );
    try {
      await repository.deleteHomecomingContact(id);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('ENCBA homecoming contact delete failed: $error\n$stackTrace');
      state = state.copyWith(
        homecomingContacts: previous,
        error: '선배 연락처를 삭제하지 못했습니다.',
      );
      return false;
    }
  }
}
