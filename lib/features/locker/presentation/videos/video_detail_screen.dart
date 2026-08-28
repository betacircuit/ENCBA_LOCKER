part of '../locker_shell.dart';

class VideoDetailScreen extends ConsumerStatefulWidget {
  const VideoDetailScreen({super.key, required this.videoId});

  final String videoId;

  @override
  ConsumerState<VideoDetailScreen> createState() =>
      _VideoDetailScreenRouteState();
}

class _VideoDetailScreenRouteState extends ConsumerState<VideoDetailScreen> {
  bool _loading = true;
  bool _notFound = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final found = await ref
          .read(lockerControllerProvider.notifier)
          .ensureVideo(widget.videoId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = !found;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = ref
        .watch(
          lockerControllerProvider.select((state) => state.videosState.videos),
        )
        .where((item) => item.id == widget.videoId)
        .firstOrNull;
    // 하이라이트는 앱 안에 상세 화면이 없다. 주소로 직접 들어와도(알림·
    // 예전 링크) 곧바로 Instagram으로 보내고 이 화면은 남기지 않는다.
    if (video != null && video.category == '하이라이트') {
      return _HighlightRedirect(url: video.url);
    }
    if (video != null) return _VideoDetailScreen(video: video);
    return _DetailLoadScaffold(
      title: '영상',
      loading: _loading,
      notFound: _notFound,
      error: _error,
      onRetry: _retry,
    );
  }

  void _retry() {
    setState(() {
      _loading = true;
      _notFound = false;
      _error = null;
    });
    _load();
  }
}

class _VideoDetailScreen extends ConsumerStatefulWidget {
  const _VideoDetailScreen({required this.video});
  final VideoItem video;

  @override
  ConsumerState<_VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends ConsumerState<_VideoDetailScreen> {
  YoutubePlayerController? _player;
  RealtimeChannel? _videoChannel;

  /// 지금 재생 중인 링크. 쿼터 미정 링크도 있으므로 쿼터 번호가 아니라
  /// 링크 자체를 들고 있어야 한다.
  VideoLink? _selectedLink;
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  final Set<String> _commentTargetIds = <String>{};
  bool _savingComment = false;

  /// "@"를 입력하는 중일 때만 채워지는 멤버 자동완성 후보.
  ///
  /// [ValueNotifier]로 들고 있어 값이 바뀔 때 댓글 입력창 아래 후보 목록만
  /// 다시 그리고, 화면 전체(영상 플레이어 포함)는 다시 그리지 않는다. 후보
  /// 목록은 입력창 "아래"에만 붙으므로 나타나거나 사라져도 입력창 자체의
  /// 위치는 움직이지 않는다. (입력창 "위"에 끼워 넣던 예전 방식은 입력 중
  /// 레이아웃이 밀리면서 모바일 키보드가 닫히는 문제가 있었다.)
  final ValueNotifier<List<MemberProfile>> _mentionMatches = ValueNotifier(
    const [],
  );

  /// 지금 완성 중인 "@" 토큰이 코멘트 텍스트에서 시작하는 위치.
  int? _mentionStart;

  /// 플레이어에서 주기적으로 읽어오는 실시간 재생 위치(초).
  /// 상세 화면 전체를 초당 한 번씩 다시 그리지 않도록 버튼만 이 값을 구독한다.
  final ValueNotifier<double> _playbackSeconds = ValueNotifier(0);

  /// 사용자가 위치를 고정하면 그 값을 담는다. null이면 실시간 위치를 따라간다.
  double? _pinnedSeconds;
  Timer? _positionTimer;

  static const _positionPollInterval = Duration(milliseconds: 500);

  VideoItem get video => widget.video;

  /// 코멘트에 기록될 시각. 고정 중이면 고정값, 아니면 현재 재생 위치.
  double get _commentSeconds => _pinnedSeconds ?? _playbackSeconds.value;

  @override
  void initState() {
    super.initState();
    final playableLinks = _playableLinks(video);
    if (video.category == '복기' && playableLinks.isNotEmpty) {
      _selectedLink = playableLinks.first;
    }
    final selected = _selectedLink;
    final initialId = selected == null
        ? (_validatedYoutubeId(video.youtubeId) ?? _youtubeIdFrom(video.url))
        : _youtubeIdFrom(selected.url);
    if (initialId != null) {
      _player = _createPlayer(initialId);
    }
    _videoChannel = Supabase.instance.client
        .channel('encba-video-${video.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'videos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: video.id,
          ),
          callback: (_) => unawaited(
            ref.read(lockerControllerProvider.notifier).refreshVideo(video.id),
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'videos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: video.id,
          ),
          callback: (_) {
            ref
                .read(lockerControllerProvider.notifier)
                .removeVideoFromRealtime(video.id);
            if (mounted) Navigator.maybePop(context);
          },
        )
        .subscribe();
    if (video.category == '복기') {
      Future.microtask(
        () => ref
            .read(lockerControllerProvider.notifier)
            .loadVideoComments(video.id),
      );
    }
    _positionTimer = Timer.periodic(
      _positionPollInterval,
      (_) => unawaited(_syncPlaybackPosition()),
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _playbackSeconds.dispose();
    _mentionMatches.dispose();
    _comment.dispose();
    _commentFocus.dispose();
    _player?.close();
    final channel = _videoChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  /// 재생 중이든 일시정지 상태에서 스크럽을 했든 동일하게 현재 위치를 따라간다.
  /// 표시 단위가 초이므로 초 값이 바뀔 때만 구독자에게 알린다.
  Future<void> _syncPlaybackPosition() async {
    final player = _player;
    if (player == null) return;
    final double seconds;
    try {
      seconds = await player.currentTime;
    } on Object {
      return; // 플레이어가 아직 준비되지 않았거나 교체 중이면 다음 주기에 다시 시도한다.
    }
    if (!mounted || seconds.isNaN || seconds.isNegative) return;
    if (seconds.floor() == _playbackSeconds.value.floor()) return;
    _playbackSeconds.value = seconds;
  }

  /// 코멘트에 적힌 시각으로 재생을 옮긴다.
  ///
  /// youtube_player_iframe 6.0.2의 [YoutubePlayerController.seekTo]는
  /// `player.seekTo(초, true)`처럼 인자를 두 개 보낸다. 웹에서는 이 문자열이
  /// player.html의 `_safeCall`로 들어가 `JSON.parse('105.0, true')`에서 예외가
  /// 나고, 그 예외를 바깥 `catch`가 삼켜 아무 일도 일어나지 않는다. 그래서
  /// 웹에서만 인자 하나짜리 호출을 직접 보낸다. 네이티브는 JS가 페이지에서
  /// 그대로 실행되므로 패키지 API를 쓴다.
  Future<void> _seekToComment(int timestampSeconds) async {
    final player = _player;
    if (player == null) return;
    final seconds = timestampSeconds.toDouble();
    try {
      if (kIsWeb) {
        await player.webViewController.runJavaScript(
          'player.seekTo(${seconds.toStringAsFixed(3)});',
        );
      } else {
        await player.seekTo(seconds: seconds, allowSeekAhead: true);
      }
      await player.playVideo();
    } on Object catch (error) {
      debugPrint('ENCBA seek failed: $error');
      return;
    }
    if (!mounted) return;
    _playbackSeconds.value = seconds;
  }

  /// 코멘트를 쓰는 동안 위치가 흘러가지 않도록 고정하거나 다시 실시간으로 돌린다.
  void _togglePinnedTimestamp() {
    setState(
      () => _pinnedSeconds = _pinnedSeconds == null
          ? _playbackSeconds.value
          : null,
    );
  }

  /// 재생할 수 있는 링크만, 쿼터 순서대로 골라 준다.
  static List<VideoLink> _playableLinks(VideoItem video) => sortedVideoLinks(
    video.links.where((link) => _youtubeIdFrom(link.url) != null),
  );

  Future<void> _selectLink(VideoLink link) async {
    final id = _youtubeIdFrom(link.url);
    if (id == null || _isSelected(link)) return;
    final previous = _player;
    final next = _createPlayer(id);
    if (!mounted) return;
    _playbackSeconds.value = 0;
    setState(() {
      _player = next;
      _selectedLink = link;
      _pinnedSeconds = null;
    });
    await previous?.close();
  }

  /// 링크는 저장 전후로 id가 달라질 수 있어 주소와 쿼터로도 견준다.
  bool _isSelected(VideoLink link) {
    final selected = _selectedLink;
    if (selected == null) return false;
    if (selected.id != null && link.id != null) return selected.id == link.id;
    return selected.url == link.url &&
        selected.quarterNumber == link.quarterNumber;
  }

  YoutubePlayerController _createPlayer(String id) =>
      YoutubePlayerController.fromVideoId(
        videoId: id,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          interfaceLanguage: 'ko',
          // 위치는 Dart 쪽에서 직접 폴링하므로 JS 브리지 알림은 성기게 받는다.
          videoStateUpdateInterval: 500,
        ),
        credentialless: true,
      );

  Future<void> _addComment() async {
    final value = _comment.text.trim();
    if (value.isEmpty || _savingComment) return;
    setState(() => _savingComment = true);
    final current = ref
        .read(lockerControllerProvider)
        .videos
        .where((item) => item.id == video.id)
        .firstOrNull;
    final targets = (current ?? video).reviewPlayers
        .where((member) => _commentTargetIds.contains(member.directoryId))
        .toList(growable: false);
    final selected = _selectedLink;
    try {
      final saved = await ref
          .read(lockerControllerProvider.notifier)
          .addVideoComment(
            videoId: video.id,
            quarterNumber: selected?.quarterNumber,
            linkId: selected?.id,
            timestampSeconds: _commentSeconds.round(),
            body: value,
            targetPlayers: targets,
          );
      if (mounted && saved) {
        _comment.clear();
        _mentionStart = null;
        _updateMentionMatches(const []);
        setState(() {
          _commentTargetIds.clear();
          _pinnedSeconds = null;
        });
      }
    } finally {
      if (mounted) setState(() => _savingComment = false);
    }
  }

  Future<void> _deleteComment(VideoCommentItem comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('댓글을 삭제할까요?'),
        content: const Text('삭제한 댓글은 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await ref
        .read(lockerControllerProvider.notifier)
        .deleteVideoComment(videoId: video.id, commentId: comment.id);
    if (mounted && deleted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('댓글을 삭제했습니다.')));
    }
  }

  /// 커서 바로 앞의 "@토큰"을 찾아 이름이 일치하는 멤버로 후보를 좁힌다.
  /// "@" 뒤로 공백이 나오면 이미 완성된 언급이라 후보를 접는다.
  void _onCommentChanged(String value) {
    final cursor = _comment.selection.baseOffset;
    if (cursor < 0) {
      _updateMentionMatches(const []);
      return;
    }
    final upToCursor = value.substring(0, cursor);
    final at = upToCursor.lastIndexOf('@');
    if (at == -1 || RegExp(r'\s').hasMatch(upToCursor.substring(at + 1))) {
      _updateMentionMatches(const []);
      return;
    }
    final query = upToCursor.substring(at + 1);
    final members = ref.read(lockerControllerProvider).membersState.members;
    // 이름 앞 6명만 자르던 예전 방식은 이름 가나다순 정렬 특성상 흔한 성(김 등)을
    // 가진 사람만 보이는 것처럼 느껴졌다. 후보 목록은 스크롤되므로 자르지 않는다.
    final matches =
        (query.isEmpty
                ? members
                : members.where((member) => member.name.contains(query)))
            .toList(growable: false);
    _mentionStart = at;
    _updateMentionMatches(matches);
  }

  /// 멘션 후보를 알림자에만 반영한다. 댓글 입력창을 담은 화면 전체를
  /// setState로 다시 그리지 않으므로 영상 플레이어가 흔들리거나 입력창이
  /// 밀리는 일이 없다.
  void _updateMentionMatches(List<MemberProfile> matches) {
    _mentionMatches.value = matches;
  }

  /// 선택한 멤버로 "@토큰"을 "@이름 "으로 완성하고, 커서를 그 뒤로 옮긴다.
  void _applyMention(MemberProfile member) {
    final start = _mentionStart;
    if (start == null) return;
    final cursor = _comment.selection.baseOffset;
    final text = _comment.text;
    final end = cursor < 0 || cursor < start ? text.length : cursor;
    final mention = '@${member.name} ';
    _comment.value = TextEditingValue(
      text: text.replaceRange(start, end, mention),
      selection: TextSelection.collapsed(offset: start + mention.length),
    );
    _mentionStart = null;
    _updateMentionMatches(const []);
    _commentFocus.requestFocus();
  }

  /// 링크를 고르기 전이거나 코멘트가 어느 링크에도 묶이지 않았으면 모두 보여준다.
  /// 예전 코멘트는 link_id가 없으므로 쿼터 번호로 견준다.
  bool _commentBelongsToSelection(VideoCommentItem comment, VideoLink? link) {
    if (link == null) return true;
    if (comment.linkId != null && link.id != null) {
      return comment.linkId == link.id;
    }
    if (comment.quarterNumber == null) return true;
    return comment.quarterNumber == link.quarterNumber;
  }

  @override
  Widget build(BuildContext context) {
    final videosState = ref.watch(
      lockerControllerProvider.select((state) => state.videosState),
    );
    final liked = videosState.likedVideoIds.contains(video.id);
    final current = videosState.videos
        .where((item) => item.id == video.id)
        .firstOrNull;
    final comments = videosState.videoComments[video.id] ?? const [];
    final selectedLink = _selectedLink;
    final visibleComments = comments
        .where((comment) => _commentBelongsToSelection(comment, selectedLink))
        .toList(growable: false);
    final user = ref.watch(authControllerProvider).user;
    final canManage = _canManageVideo(user, current ?? video);
    final displayed = current ?? video;
    final links = _playableLinks(displayed);
    return Scaffold(
      appBar: AppBar(
        title: Text(displayed.category),
        actions: [
          IconButton(
            tooltip: '링크 공유',
            onPressed: () => _shareVideo(context, displayed, selectedLink),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          ...?canManage
              ? [
                  IconButton(
                    tooltip: '영상 수정',
                    onPressed: () => _showVideoEditor(
                      context,
                      ref,
                      displayed.category,
                      existing: displayed,
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: '영상 삭제',
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('영상을 삭제할까요?'),
                          content: const Text('댓글과 시청 기록도 함께 삭제됩니다.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('취소'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('삭제'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      final deleted = await ref
                          .read(lockerControllerProvider.notifier)
                          .deleteVideo(video.id);
                      if (context.mounted && deleted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ]
              : null,
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          if (_player case final player?)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: EncbaColors.navy,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    YoutubePlayer(
                      key: ValueKey(
                        'video-${video.id}-${selectedLink?.id ?? selectedLink?.url ?? ''}',
                      ),
                      controller: player,
                      aspectRatio: 16 / 9,
                      backgroundColor: EncbaColors.navy,
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: YoutubeValueBuilder(
                          controller: player,
                          buildWhen: (previous, current) =>
                              previous.playerState != current.playerState,
                          builder: (context, value) {
                            final loading =
                                value.playerState == PlayerState.unknown ||
                                value.playerState == PlayerState.buffering;
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: loading
                                  ? const _VideoLoadingState()
                                  : const SizedBox.shrink(),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            InkWell(
              onTap: () => _launch(context, displayed.url),
              borderRadius: BorderRadius.circular(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _VideoThumbnail(video: displayed),
                      const ColoredBox(color: Color(0x33000000)),
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 52,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Instagram에서 릴스 보기',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (displayed.category == '복기' && links.isNotEmpty) ...[
            const SizedBox(height: 12),
            _VideoLinkPicker(
              links: links,
              isSelected: _isSelected,
              onSelected: _selectLink,
            ),
          ],
          const SizedBox(height: 18),
          Text(
            displayed.title,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    displayed.uploader,
                    if (displayed.recordedOn case final date?)
                      '${DateFormat('yyyy.M.d').format(date)} 경기',
                    _relativeTime(displayed.uploadedAt),
                  ].join(' · '),
                  style: const TextStyle(color: EncbaColors.muted),
                ),
              ),
              IconButton(
                tooltip: liked ? '좋아요 취소' : '좋아요',
                onPressed: () => ref
                    .read(lockerControllerProvider.notifier)
                    .toggleVideoLike(video.id),
                icon: Icon(
                  liked ? Icons.favorite_rounded : Icons.favorite_border,
                  color: liked ? EncbaColors.absent : EncbaColors.muted,
                ),
              ),
              Text('${displayed.likeCount}'),
            ],
          ),
          const SizedBox(height: 16),
          if (displayed.category == '복기') ...[
            if (displayed.reviewPlayers.isNotEmpty) ...[
              Text('출전 선수', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    (displayed.reviewPlayers.toList()
                          ..sort(compareTaggedMembers))
                        .map((member) => Chip(label: Text(member.label)))
                        .toList(growable: false),
              ),
              const SizedBox(height: 14),
            ],
            ...visibleComments.map(
              (item) => _Comment(
                timestamp: _formatTimestamp(item.timestampSeconds.toDouble()),
                text: item.body,
                author: item.author,
                quarterNumber: item.quarterNumber,
                targetPlayers: item.targetPlayers,
                onDelete:
                    item.profileId == user?.id || user?.canAdminister == true
                    ? () => unawaited(_deleteComment(item))
                    : null,
                onTimestampTap: () =>
                    unawaited(_seekToComment(item.timestampSeconds)),
              ),
            ),
            if (_player != null) ...[
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: _playbackSeconds,
                builder: (context, seconds, _) => PlaybackPositionButton(
                  seconds: _pinnedSeconds ?? seconds,
                  pinned: _pinnedSeconds != null,
                  onToggle: _togglePinnedTimestamp,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (displayed.reviewPlayers.isNotEmpty) ...[
              _MemberChecklistButton(
                label: '피드백 선수',
                members: displayed.reviewPlayers,
                selectedIds: _commentTargetIds,
                onChanged: (value) => setState(() {
                  _commentTargetIds
                    ..clear()
                    ..addAll(value);
                }),
              ),
              if (_commentTargetIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      (displayed.reviewPlayers
                              .where(
                                (member) => _commentTargetIds.contains(
                                  member.directoryId,
                                ),
                              )
                              .toList()
                            ..sort(compareTaggedMembers))
                          .map(
                            (member) => InputChip(
                              label: Text(member.label),
                              onDeleted: () => setState(
                                () => _commentTargetIds.remove(
                                  member.directoryId,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                ),
              ],
              const SizedBox(height: 8),
            ],
            TextField(
              key: const ValueKey('video-comment-input'),
              controller: _comment,
              focusNode: _commentFocus,
              onChanged: _onCommentChanged,
              onSubmitted: (_) => _addComment(),
              decoration: InputDecoration(
                hintText: '이 장면에 대한 코멘트 · "@"로 멤버 언급',
                suffixIcon: IconButton(
                  tooltip: '코멘트 등록',
                  onPressed: _savingComment ? null : _addComment,
                  icon: _savingComment
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ),
            ValueListenableBuilder<List<MemberProfile>>(
              valueListenable: _mentionMatches,
              builder: (context, matches, _) {
                if (matches.isEmpty) return const SizedBox.shrink();
                return Container(
                  constraints: const BoxConstraints(maxHeight: 176),
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: EncbaColors.highlight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: EncbaColors.line),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final member = matches[index];
                      return ListTile(
                        dense: true,
                        leading: _Avatar(name: member.name, size: 30),
                        title: Text(member.name),
                        subtitle: Text(member.studentId),
                        onTap: () => _applyMention(member),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 복기 영상의 링크 목록. 쿼터가 정해진 링크가 앞에 오고, 쿼터 미정 링크는
/// 뒤에 번호를 붙여 늘어놓는다.
class _VideoLinkPicker extends StatelessWidget {
  const _VideoLinkPicker({
    required this.links,
    required this.isSelected,
    required this.onSelected,
  });

  final List<VideoLink> links;
  final bool Function(VideoLink link) isSelected;
  final ValueChanged<VideoLink> onSelected;

  @override
  Widget build(BuildContext context) {
    var undecided = 0;
    final labels = <String>[
      for (final link in links)
        if (link.quarterNumber case final quarter?)
          '$quarter쿼터'
        else
          '미정 ${++undecided}',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (index, link) in links.indexed)
          ChoiceChip(
            label: Text(labels[index]),
            selected: isSelected(link),
            onSelected: (_) => onSelected(link),
          ),
      ],
    );
  }
}

/// 영상 주소를 클립보드에 담는다. 앱 안의 상세 주소를 우선 쓰고, 지금 보고 있는
/// 쿼터가 있으면 그 원본 주소도 함께 알려 준다.
Future<void> _shareVideo(
  BuildContext context,
  VideoItem video,
  VideoLink? selected,
) async {
  final appLink = kIsWeb
      ? '${Uri.base.origin}/videos/${Uri.encodeComponent(video.id)}'
      : null;
  final target = appLink ?? selected?.url ?? video.url;
  await Clipboard.setData(ClipboardData(text: target));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          appLink == null ? '영상 링크를 복사했습니다.' : '${video.title} 링크를 복사했습니다.',
        ),
        action: SnackBarAction(
          label: '원본 열기',
          onPressed: () => _launch(context, selected?.url ?? video.url),
        ),
      ),
    );
}

/// 코멘트에 붙을 시각을 보여준다. 평소에는 재생 위치를 실시간으로 따라가고,
/// 누르면 그 시각에 고정되어 코멘트를 쓰는 동안 흘러가지 않는다.
class PlaybackPositionButton extends StatelessWidget {
  const PlaybackPositionButton({
    super.key,
    required this.seconds,
    required this.pinned,
    required this.onToggle,
  });

  final double seconds;
  final bool pinned;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final time = _formatTimestamp(seconds);
    return Semantics(
      button: true,
      label: pinned ? '코멘트 시각 $time 고정됨. 누르면 해제' : '현재 재생 위치 $time. 누르면 고정',
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: onToggle,
        icon: Icon(
          pinned ? Icons.push_pin_rounded : Icons.timer_outlined,
          size: 18,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: pinned ? EncbaColors.snuBlue : EncbaColors.ink,
          backgroundColor: pinned ? EncbaColors.highlight : null,
          side: BorderSide(
            color: pinned ? EncbaColors.snuBlue : EncbaColors.line,
          ),
        ),
        label: Text(
          pinned ? '이 시각에 코멘트  $time' : '현재 재생 위치  $time',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

class _Comment extends StatelessWidget {
  const _Comment({
    required this.timestamp,
    required this.text,
    required this.author,
    required this.onTimestampTap,
    this.onDelete,
    this.quarterNumber,
    this.targetPlayers = const [],
  });
  final String timestamp;
  final String text;
  final String author;
  final VoidCallback onTimestampTap;
  final VoidCallback? onDelete;
  final int? quarterNumber;
  final List<VideoTaggedMember> targetPlayers;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: TextButton(
        onPressed: onTimestampTap,
        child: Text(
          timestamp,
          style: const TextStyle(
            color: EncbaColors.snuBlue,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: _MentionText(text),
      subtitle: Text(
        [
          quarterNumber == null ? author : '$author · $quarterNumber쿼터',
          if (targetPlayers.isNotEmpty)
            '피드백: ${(targetPlayers.toList()..sort(compareTaggedMembers)).map((member) => member.label).join(', ')}',
        ].join('\n'),
      ),
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: '댓글 삭제',
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: EncbaColors.absent,
              ),
            ),
    ),
  );
}

/// 코멘트 본문에서 "@이름" 토큰만 굵게 강조해 보여준다.
class _MentionText extends StatelessWidget {
  const _MentionText(this.text);
  final String text;

  static final RegExp _mentionPattern = RegExp(r'@\S+');

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _mentionPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(
            color: EncbaColors.snuBlue,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(style: DefaultTextStyle.of(context).style, children: spans),
    );
  }
}

class _MemberChecklistButton extends StatelessWidget {
  const _MemberChecklistButton({
    required this.label,
    required this.members,
    required this.selectedIds,
    required this.onChanged,
  });

  final String label;
  final List<VideoTaggedMember> members;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () async {
      final selected = await _showMemberChecklist(
        context,
        title: label,
        members: members,
        initialSelection: selectedIds,
      );
      if (selected != null) onChanged(selected);
    },
    icon: const Icon(Icons.group_outlined),
    label: Text(
      selectedIds.isEmpty ? '$label 선택' : '$label ${selectedIds.length}명',
    ),
  );
}

Future<Set<String>?> _showMemberChecklist(
  BuildContext context, {
  required String title,
  required List<VideoTaggedMember> members,
  required Set<String> initialSelection,
}) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _MemberChecklistSheet(
    title: title,
    members: members,
    initialSelection: initialSelection,
  ),
);

class _MemberChecklistSheet extends StatefulWidget {
  const _MemberChecklistSheet({
    required this.title,
    required this.members,
    required this.initialSelection,
  });

  final String title;
  final List<VideoTaggedMember> members;
  final Set<String> initialSelection;

  @override
  State<_MemberChecklistSheet> createState() => _MemberChecklistSheetState();
}

class _MemberChecklistSheetState extends State<_MemberChecklistSheet> {
  late final Set<String> _selected = {...widget.initialSelection};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    final filtered =
        widget.members
            .where(
              (member) =>
                  member.name.contains(query) ||
                  (member.jerseyNumber?.toString() ?? '') == query ||
                  (member.studentYear?.toString() ?? '') == query,
            )
            .toList(growable: false)
          ..sort(compareTaggedMembers);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('완료'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              autofocus: false,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: '이름 · 등번호 · 학번 검색',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final member = filtered[index];
                final checked = _selected.contains(member.directoryId);
                return CheckboxListTile(
                  value: checked,
                  title: Text(member.label),
                  subtitle: member.studentYear == null
                      ? null
                      : Text(
                          '${member.studentYear.toString().padLeft(2, '0')}학번',
                        ),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) => setState(() {
                    value == true
                        ? _selected.add(member.directoryId)
                        : _selected.remove(member.directoryId);
                  }),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(context, _selected);
                },
                child: const Text('선택 완료'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 하이라이트 주소로 들어왔을 때 잠깐 머무는 화면. 릴스를 열고 곧바로
/// 뒤로 돌아간다. 상세 화면을 지운 뒤 남은 옛 링크·알림을 위한 통로다.
class _HighlightRedirect extends StatefulWidget {
  const _HighlightRedirect({required this.url});

  final String url;

  @override
  State<_HighlightRedirect> createState() => _HighlightRedirectState();
}

class _HighlightRedirectState extends State<_HighlightRedirect> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      await _launch(context, widget.url);
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        context.go(LockerTab.videos.path);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: EncbaColors.snuBlue)),
  );
}
