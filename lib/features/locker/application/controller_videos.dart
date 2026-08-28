part of 'locker_controller.dart';

/// VideosApi - 컨트롤러를 도메인별로 나눈 조각.
/// 본체 클래스가 이 믹스인들을 조합해 완성된다.
mixin VideosApi on StateNotifier<LockerState>, ControllerCore {
  /// 영상 탭은 하이라이트·복기 둘뿐이다. 예전에 '공유'(2)를 보고 있던
  /// 상태가 남아 있어도 빈 화면이 뜨지 않게 범위 안으로 접어 둔다.
  void selectVideoSegment(int index) =>
      state = state.copyWith(videoSegment: index.clamp(0, 1));

  Future<void> toggleVideoLike(String id) async {
    final previousVideos = state.videos;
    final previousLikes = state.likedVideoIds;
    final liked = {...state.likedVideoIds};
    final wasLiked = liked.remove(id);
    if (!wasLiked) liked.add(id);
    final videos = state.videos
        .map(
          (video) => video.id == id
              ? video.copyWith(
                  likeCount: (video.likeCount + (wasLiked ? -1 : 1))
                      .clamp(0, 999999)
                      .toInt(),
                )
              : video,
        )
        .toList();
    state = state.copyWith(videos: videos, likedVideoIds: liked);
    try {
      await _repository?.setVideoLike(id, liked: !wasLiked);
    } on Object {
      state = state.copyWith(
        videos: previousVideos,
        likedVideoIds: previousLikes,
        error: '좋아요를 저장하지 못했습니다.',
      );
    }
  }

  void upsertVideoFromRealtime(VideoItem video) {
    final next = [...state.videos];
    final index = next.indexWhere((item) => item.id == video.id);
    if (index == -1) {
      next.add(video);
    } else {
      next[index] = video;
    }
    next.sort((a, b) {
      final byTime = b.uploadedAt.compareTo(a.uploadedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    state = state.copyWith(videos: next, clearError: true);
  }

  void removeVideoFromRealtime(String id) {
    if (!state.videos.any((video) => video.id == id)) return;
    state = state.copyWith(
      videos: state.videos.where((video) => video.id != id).toList(),
      likedVideoIds: {...state.likedVideoIds}..remove(id),
      clearError: true,
    );
  }

  Future<void> refreshVideo(String id) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final video = await repository.loadVideo(id);
      if (video == null) {
        removeVideoFromRealtime(id);
      } else {
        upsertVideoFromRealtime(video);
      }
    } on Object catch (error) {
      debugPrint('ENCBA video refresh failed: $error');
    }
  }

  /// 초기 영상 페이지에 없는 항목도 공유 주소의 ID로 읽어 현재 상태에 합친다.
  Future<bool> ensureVideo(String id) async {
    if (state.videos.any((video) => video.id == id)) return true;
    final repository = _repository;
    if (repository == null) return false;
    final video = await repository.loadVideo(id);
    if (video == null) return false;
    upsertVideoFromRealtime(video);
    return true;
  }

  Future<bool> addVideo(VideoItem video) async {
    try {
      final saved = await _repository?.addVideo(video) ?? video;
      final videos = [saved, ...state.videos];
      state = state.copyWith(videos: videos, clearError: true);
      return true;
    } on Object {
      state = state.copyWith(error: '영상 링크를 등록하지 못했습니다.');
      return false;
    }
  }

  Future<bool> updateVideo(VideoItem video) async {
    try {
      final saved = await _repository?.updateVideo(video) ?? video;
      state = state.copyWith(
        videos: state.videos
            .map((item) => item.id == saved.id ? saved : item)
            .toList(),
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '영상을 수정하지 못했습니다.');
      return false;
    }
  }

  Future<bool> deleteVideo(String id) async {
    try {
      await _repository?.deleteVideo(id);
      state = state.copyWith(
        videos: state.videos.where((item) => item.id != id).toList(),
        clearError: true,
      );
      return true;
    } on Object {
      state = state.copyWith(error: '영상을 삭제하지 못했습니다.');
      return false;
    }
  }

  Future<void> loadVideoComments(String videoId) async {
    if (_repository == null) return;
    try {
      final comments = await _repository.loadVideoComments(videoId);
      state = state.copyWith(
        videoComments: {...state.videoComments, videoId: comments},
        clearError: true,
      );
    } on Object {
      state = state.copyWith(error: '영상 코멘트를 불러오지 못했습니다.');
    }
  }

  Future<bool> addVideoComment({
    required String videoId,
    String? videoTitle,
    required int? quarterNumber,
    required int? linkId,
    required int timestampSeconds,
    required String body,
    List<VideoTaggedMember> targetPlayers = const [],
  }) async {
    if (_repository == null) return false;
    try {
      final saved = await _repository.addVideoComment(
        videoId: videoId,
        videoTitle: videoTitle,
        quarterNumber: quarterNumber,
        linkId: linkId,
        timestampSeconds: timestampSeconds,
        body: body,
        targetPlayers: targetPlayers,
      );
      final comments = [
        ...state.videoComments[videoId] ?? const <VideoCommentItem>[],
        saved,
      ]..sort((a, b) => a.timestampSeconds.compareTo(b.timestampSeconds));
      state = state.copyWith(
        videoComments: {...state.videoComments, videoId: comments},
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      debugPrint('ENCBA video comment save failed: $error');
      // 디버그 빌드에서는 실제 서버 사유를 함께 보여준다.
      final detail = kDebugMode ? '\n(${error.toString()})' : '';
      state = state.copyWith(error: '영상 코멘트를 저장하지 못했습니다.$detail');
      return false;
    }
  }

  Future<bool> deleteVideoComment({
    required String videoId,
    required int commentId,
  }) async {
    if (_repository == null) return false;
    try {
      await _repository.deleteVideoComment(commentId);
      state = state.copyWith(
        videoComments: {
          ...state.videoComments,
          videoId: (state.videoComments[videoId] ?? const <VideoCommentItem>[])
              .where((comment) => comment.id != commentId)
              .toList(growable: false),
        },
        clearError: true,
      );
      return true;
    } on Object catch (error) {
      debugPrint('ENCBA video comment delete failed: $error');
      state = state.copyWith(error: '영상 코멘트를 삭제하지 못했습니다.');
      return false;
    }
  }
}
