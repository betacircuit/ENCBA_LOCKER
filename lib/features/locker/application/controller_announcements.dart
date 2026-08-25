part of 'locker_controller.dart';

/// AnnouncementsApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin AnnouncementsApi on StateNotifier<LockerState>, ControllerCore {
/// 공지 목록의 로드 범위와 무관하게 공유 주소의 공지를 상태에 합친다.
  Future<bool> ensureAnnouncement(String id) async {
    if (state.announcements.any((notice) => notice.id == id)) return true;
    final repository = _repository;
    if (repository == null) return false;
    final notice = await repository.loadAnnouncement(id);
    if (notice == null) return false;
    state = state.copyWith(
      announcements: [
        notice,
        ...state.announcements.where((item) => item.id != notice.id),
      ],
      clearError: true,
    );
    return true;
  }

Future<bool> addAnnouncement({
    required String title,
    required String body,
    required bool pinned,
    bool isUrgent = false,
    List<String> linkedEventIds = const [],
    String? imageBase64,
    String? imageName,
    List<String> pollOptions = const [],
    String pollQuestion = '',
  }) async {
    try {
      final saved = await _repository?.addAnnouncement(
        title: title,
        body: body,
        pinned: pinned,
        isUrgent: isUrgent,
        linkedEventIds: linkedEventIds,
        imageBase64: imageBase64,
        imageName: imageName,
        pollOptions: pollOptions,
        pollQuestion: pollQuestion,
      );
      if (saved != null) {
        // Realtime 구독이 같은 INSERT를 이 응답보다 먼저 받아 이미 추가해
        // 뒀을 수 있다. 그 경우 낙관적 추가를 또 하면 같은 공지가 두 번
        // 보인다.
        final alreadyMerged = state.announcements.any(
          (item) => item.id == saved.id,
        );
        if (!alreadyMerged) {
          state = state.copyWith(
            announcements: [saved, ...state.announcements],
          );
        }
      }
      return saved != null;
    } on Object catch (error) {
      state = state.copyWith(
        error: _announcementError(error, '공지를 저장하지 못했습니다.'),
      );
      return false;
    }
  }

Future<bool> updateAnnouncement({
    required AnnouncementItem announcement,
    required String title,
    required String body,
    required bool pinned,
    bool? isUrgent,
    List<String> linkedEventIds = const [],
    String? imageBase64,
    String? imageName,
    bool removeImage = false,
    List<String> pollOptions = const [],
    String pollQuestion = '',
  }) async {
    try {
      final saved = await _repository?.updateAnnouncement(
        id: announcement.id,
        title: title,
        body: body,
        pinned: pinned,
        isUrgent: isUrgent ?? announcement.isUrgent,
        linkedEventIds: linkedEventIds,
        existingImageUrl: announcement.imageUrl,
        imageBase64: imageBase64,
        imageName: imageName,
        removeImage: removeImage,
        pollOptions: pollOptions,
        pollQuestion: pollQuestion,
      );
      if (saved == null) return false;
      state = state.copyWith(
        announcements: state.announcements
            .map((item) => item.id == saved.id ? saved : item)
            .toList(),
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      state = state.copyWith(
        error: _announcementError(error, '공지를 수정하지 못했습니다.'),
      );
      return false;
    }
  }

Future<bool> deleteAnnouncement(String id) async {
    try {
      final imageUrl = state.announcements
          .where((item) => item.id == id)
          .firstOrNull
          ?.imageUrl;
      await _repository?.deleteAnnouncement(id, imageUrl: imageUrl);
      state = state.copyWith(
        announcements: state.announcements
            .where((item) => item.id != id)
            .toList(),
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '공지를 삭제하지 못했습니다.');
      return false;
    }
  }

Future<bool> voteAnnouncement(
    AnnouncementItem announcement,
    int optionIndex,
  ) async {
    if (optionIndex < 0 || optionIndex >= announcement.pollOptions.length) {
      return false;
    }
    final previousOption = announcement.myPollOption;
    final counts = Map<int, int>.from(announcement.pollVotes);
    if (previousOption != null && previousOption != optionIndex) {
      final previousCount = counts[previousOption] ?? 0;
      if (previousCount <= 1) {
        counts.remove(previousOption);
      } else {
        counts[previousOption] = previousCount - 1;
      }
    }
    if (previousOption != optionIndex) {
      counts.update(optionIndex, (count) => count + 1, ifAbsent: () => 1);
    }
    final optimistic = announcement.copyWith(
      pollVotes: counts,
      myPollOption: optionIndex,
    );
    state = state.copyWith(
      announcements: state.announcements
          .map((item) => item.id == announcement.id ? optimistic : item)
          .toList(),
    );
    try {
      await _repository?.voteAnnouncement(announcement.id, optionIndex);
      state = state.copyWith(clearError: true);
      return true;
    } on Object {
      state = state.copyWith(
        announcements: state.announcements
            .map((item) => item.id == announcement.id ? announcement : item)
            .toList(),
        error: '공지 투표를 저장하지 못했습니다.',
      );
      return false;
    }
  }

String _announcementError(Object error, String fallback) =>
      error is LockerRepositoryException ? error.message : fallback;

/// 투표 현황 시트를 열 때만 부르는 온디맨드 조회라 다른 보조 데이터처럼
  /// 실패해도 전역 에러 상태를 건드리지 않고 빈 목록으로 조용히 넘어간다.
  Future<List<AnnouncementPollVoter>> loadAnnouncementPollVoters(
    String announcementId,
  ) async {
    final repository = _repository;
    if (repository == null) return const [];
    return _orDefault(
      repository.loadAnnouncementPollVoters(announcementId),
      const <AnnouncementPollVoter>[],
    );
  }
}
