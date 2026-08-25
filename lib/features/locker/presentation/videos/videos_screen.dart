part of '../locker_shell.dart';

class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({super.key});

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  _VideoSort _sort = _VideoSort.newest;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(
      lockerControllerProvider.select((state) => state.videoSegment),
    );
    final videos = ref.watch(
      lockerControllerProvider.select((state) => state.videos),
    );
    final likedVideoIds = ref.watch(
      lockerControllerProvider.select((state) => state.likedVideoIds),
    );
    final user = ref.watch(authControllerProvider).user!;
    const categories = ['하이라이트', '복기', '공유'];
    final visible =
        videos.where((item) => item.category == categories[selected]).toList()
          ..sort(
            (a, b) => switch (_sort) {
              _VideoSort.newest => b.uploadedAt.compareTo(a.uploadedAt),
              _VideoSort.oldest => a.uploadedAt.compareTo(b.uploadedAt),
              _VideoSort.mostLiked =>
                b.likeCount.compareTo(a.likeCount) != 0
                    ? b.likeCount.compareTo(a.likeCount)
                    : b.uploadedAt.compareTo(a.uploadedAt),
            },
          );
    return _Page(
      header: _Header(
        eyebrow: 'PLAYBACK',
        title: 'VIDEOS',
        action: PopupMenuButton<_VideoSort>(
          tooltip: '영상 정렬',
          initialValue: _sort,
          onSelected: (value) => setState(() => _sort = value),
          itemBuilder: (context) => const [
            PopupMenuItem(value: _VideoSort.newest, child: Text('최신 업로드순')),
            PopupMenuItem(value: _VideoSort.oldest, child: Text('오래된 업로드순')),
            PopupMenuItem(value: _VideoSort.mostLiked, child: Text('좋아요순')),
          ],
          icon: const Icon(Icons.swap_vert_rounded),
        ),
      ),
      children: [
        _SlidingTabBar(
          labels: const ['하이라이트', '복기', '공유'],
          icons: const [
            Icons.flash_on_rounded,
            Icons.forum_outlined,
            Icons.ios_share_rounded,
          ],
          selectedIndex: selected,
          onSelected: ref
              .read(lockerControllerProvider.notifier)
              .selectVideoSegment,
        ),
        const SizedBox(height: 18),
        ...visible.map(
          (video) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _VideoTile(
              video: video,
              liked: likedVideoIds.contains(video.id),
            ),
          ),
        ),
        if (_canCreateVideoCategory(user, categories[selected]))
          OutlinedButton.icon(
            onPressed: () =>
                _showVideoEditor(context, ref, categories[selected]),
            icon: const Icon(Icons.add_link_rounded),
            label: Text(selected == 2 ? '유튜브 영상 공유' : '영상 링크 추가'),
          ),
      ],
    );
  }
}

enum _VideoSort { newest, oldest, mostLiked }

class _VideoTile extends ConsumerWidget {
  const _VideoTile({required this.video, required this.liked});
  final VideoItem video;
  final bool liked;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() => context.push('/videos/${Uri.encodeComponent(video.id)}');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: open,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _VideoThumbnail(video: video),
                  const ColoredBox(color: Color(0x18000000)),
                  const Center(
                    child: CircleAvatar(
                      radius: 25,
                      backgroundColor: Color(0xEFFFFFFF),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 34,
                        color: EncbaColors.navy,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _VideoBadge(label: video.category),
                  ),
                  if (video.durationLabel.isNotEmpty)
                    Positioned(
                      right: 10,
                      bottom: 9,
                      child: _VideoBadge(label: video.durationLabel),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: open,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${video.uploader} · ${_relativeTime(video.uploadedAt)}',
                          style: const TextStyle(
                            color: EncbaColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: liked ? '좋아요 취소' : '좋아요',
                  onPressed: () => ref
                      .read(lockerControllerProvider.notifier)
                      .toggleVideoLike(video.id),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      liked ? Icons.favorite_rounded : Icons.favorite_border,
                      key: ValueKey(liked),
                      color: liked ? EncbaColors.absent : EncbaColors.muted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 25,
                  child: Text(
                    '${video.likeCount}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.video});
  final VideoItem video;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [EncbaColors.navy, EncbaColors.snuBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          video.sourceType == 'instagram'
              ? Icons.play_circle_fill_rounded
              : Icons.sports_basketball_rounded,
          size: 58,
          color: Colors.white,
        ),
      ),
    );
    final thumbnail = _videoThumbnailUrl(
      youtubeId: video.youtubeId,
      sourceUrl: video.url,
    );
    final asset = _instagramThumbnailAsset(video.url);
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }
    // 앱에 넣어 둔 그림이 없는 릴스는 Instagram 공개 주소로 썸네일을
    // 자동으로 가져온다. 데이터 절약 모드면 네트워크를 쓰지 않고 폴백으로
    // 넘어가 저사양 환경에서도 목록이 가볍게 열린다.
    final reelUrl = video.sourceType == 'instagram'
        ? _instagramThumbnailUrl(video.url)
        : null;
    if (reelUrl != null &&
        !const AppEnvironmentImpl().prefersReducedData) {
      return _InstagramThumbnailImage(
        url: reelUrl,
        fallbackBuilder: fallback,
      );
    }
    if (thumbnail == null) return fallback();
    return _YoutubeThumbnailImage(
      youtubeId: video.youtubeId,
      sourceUrl: video.url,
      fallbackBuilder: fallback,
    );
  }
}

class _YoutubeThumbnailImage extends StatelessWidget {
  const _YoutubeThumbnailImage({
    required this.youtubeId,
    required this.sourceUrl,
    required this.fallbackBuilder,
  });

  final String youtubeId;
  final String sourceUrl;
  final Widget Function() fallbackBuilder;

  @override
  Widget build(BuildContext context) {
    final resolvedId =
        _validatedYoutubeId(youtubeId) ?? _youtubeIdFrom(sourceUrl);
    if (resolvedId == null) return fallbackBuilder();
    return FutureBuilder<String?>(
      future: YoutubeThumbnailService.instance.load(resolvedId),
      initialData: _videoThumbnailUrl(
        youtubeId: resolvedId,
        sourceUrl: sourceUrl,
      ),
      builder: (context, snapshot) {
        final thumbnail =
            snapshot.data ??
            _videoThumbnailUrl(youtubeId: resolvedId, sourceUrl: sourceUrl)!;
        return Image.network(
          thumbnail,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return const _VideoLoadingState();
          },
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Stack(
                  fit: StackFit.expand,
                  children: [child, const _VideoLoadingState()],
                ),
          errorBuilder: (_, _, _) => fallbackBuilder(),
        );
      },
    );
  }
}

/// Instagram 공개 미디어 주소에서 릴스 썸네일을 가져온다. 실패하면
/// 기존의 그라디언트 폴백을 그대로 보여준다.
class _InstagramThumbnailImage extends StatelessWidget {
  const _InstagramThumbnailImage({
    required this.url,
    required this.fallbackBuilder,
  });

  final String url;
  final Widget Function() fallbackBuilder;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
      if (wasSynchronouslyLoaded || frame != null) return child;
      return const _VideoLoadingState();
    },
    errorBuilder: (_, _, _) => fallbackBuilder(),
  );
}

class _VideoLoadingState extends StatelessWidget {
  const _VideoLoadingState();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: EncbaColors.navy,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 9),
          Text('영상 불러오는 중', style: TextStyle(color: Colors.white)),
        ],
      ),
    ),
  );
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: Color(0xD90B2347)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    ),
  );
}
