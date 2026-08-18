part of '../locker_shell.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsState = ref.watch(
      lockerControllerProvider.select((state) => state.eventsState),
    );
    final operationsState = ref.watch(
      lockerControllerProvider.select((state) => state.operationsState),
    );
    final unreadNotifications = ref.watch(
      lockerControllerProvider.select((state) => state.unreadNotifications),
    );
    final user = ref.watch(authControllerProvider).user!;
    final events = [...eventsState.plannerEventsWith(operationsState)]
      ..sort((a, b) => a.start.compareTo(b.start));
    final upcoming = events
        .where((event) => event.end.isAfter(DateTime.now()))
        .toList();
    final nextEvent = upcoming.firstOrNull;
    return _Page(
      header: _Header(
        eyebrow: '${user.visibleName} · #${user.jerseyNumber} ${user.position}',
        title: 'ENCBA LOCKER',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user.canAdminister)
              IconButton(
                tooltip: '공지 등록',
                onPressed: () => _showAnnouncementEditor(context, ref),
                icon: const Icon(Icons.add_alert_outlined),
              ),
            IconButton(
              tooltip: '알림',
              onPressed: () {
                ref.read(lockerControllerProvider.notifier).readNotifications();
                _showNotifications(
                  context,
                  ref,
                  operationsState.announcements,
                  canManage: user.canAdminister,
                  user: user,
                );
              },
              icon: Badge(
                isLabelVisible: unreadNotifications > 0,
                label: Text('$unreadNotifications'),
                child: const Icon(Icons.notifications_none_rounded),
              ),
            ),
          ],
        ),
      ),
      children: [
        const _SectionHeader(title: '가장 가까운 일정'),
        const SizedBox(height: 11),
        if (nextEvent == null)
          _EmptyState(
            icon: Icons.calendar_month_outlined,
            title: '예정된 일정이 없습니다',
            action: '다시 불러오기',
            onTap: () => ref.read(lockerControllerProvider.notifier).reload(),
          )
        else
          EventTicket(
            event: nextEvent,
            heroTag: 'home-${nextEvent.id}',
            onTap: () =>
                openEventDetail(context, nextEvent.id, heroTagPrefix: 'home'),
          ),
        const SizedBox(height: 22),
        _SectionHeader(
          title: '공지',
          action: user.canAdminister ? '새 공지' : null,
          onTap: user.canAdminister
              ? () => _showAnnouncementEditor(context, ref)
              : null,
        ),
        const SizedBox(height: 10),
        if (operationsState.announcements.isEmpty)
          const _EmptyState(
            icon: Icons.campaign_outlined,
            title: '등록된 공지가 없습니다',
          )
        else
          ...operationsState.announcements
              .take(5)
              .map(
                (notice) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _NoticeCard(
                    notice: notice,
                    onTap: () => _openNotice(context, notice.id),
                  ),
                ),
              ),
      ],
    );
  }
}

void _openNotice(BuildContext context, String announcementId) =>
    context.push('/announcements/${Uri.encodeComponent(announcementId)}');

class AnnouncementDetailScreen extends ConsumerStatefulWidget {
  const AnnouncementDetailScreen({super.key, required this.announcementId});

  final String announcementId;

  @override
  ConsumerState<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState
    extends ConsumerState<AnnouncementDetailScreen> {
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
          .ensureAnnouncement(widget.announcementId);
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
    final notice = ref
        .watch(
          lockerControllerProvider.select(
            (state) => state.operationsState.announcements,
          ),
        )
        .where((item) => item.id == widget.announcementId)
        .firstOrNull;
    if (notice != null) return _AnnouncementDetailView(notice: notice);
    return _DetailLoadScaffold(
      title: '공지',
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

class _AnnouncementDetailView extends ConsumerWidget {
  const _AnnouncementDetailView({required this.notice});

  final AnnouncementItem notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final events = ref.watch(
      lockerControllerProvider.select((state) => state.eventsState.events),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('공지'),
        actions: canManage
            ? [
                IconButton(
                  tooltip: '공지 수정',
                  onPressed: () =>
                      _showAnnouncementEditor(context, ref, existing: notice),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '공지 삭제',
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('공지를 삭제할까요?'),
                        content: const Text('삭제한 공지는 되돌릴 수 없습니다.'),
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
                        .deleteAnnouncement(notice.id);
                    if (context.mounted && deleted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            notice.title,
            style: const TextStyle(
              fontFamily: 'Jua',
              fontSize: 28,
              color: EncbaColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${notice.author} · ${_relativeTime(notice.publishedAt)}',
            style: const TextStyle(color: EncbaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          _Linkified(notice.body, style: const TextStyle(height: 1.75)),
          if (notice.linkedEventIds.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('연결 일정', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...events
                .where((event) => notice.linkedEventIds.contains(event.id))
                .map(
                  (event) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: Text(event.title),
                    subtitle: Text(
                      '${event.start.month}월 ${event.start.day}일 (${weekday(event.start)}) · ${time(event.start)}–${time(event.end)}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => openEventDetail(
                      context,
                      event.id,
                      heroTagPrefix: 'notice-event',
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// URL을 자동으로 감지해 탭 가능한 링크로 바꿔 주는 텍스트.
///
/// 한글 음절 범위를 URL 문자 집합에서 아예 빼서 "...확인하세요"처럼 조사가
/// 바로 붙어도 URL 뒤에서 정확히 끊긴다. 괄호는 문장 안 짝을 세어, 안에서
/// 이미 열린 괄호가 아니면 닫는 괄호를 URL에서 떼어 낸다("(주소는
/// https://a.com)"에서 마지막 `)`가 링크에 안 딸려가게).
class _Linkified extends StatelessWidget {
  const _Linkified(this.text, {this.style});

  final String text;
  final TextStyle? style;

  // 　-〿: CJK 기호·구두점(、。「」 등), 가-힣: 완성형 한글 음절.
  static final RegExp _urlPattern = RegExp(
    '(?:https?://|www\\.)[^\\s　-〿가-힣<>]+',
    caseSensitive: false,
  );

  static const _trimmableTrailing = '.,!?;:\'"”’·';

  static String _trimTrailingPunctuation(String url) {
    var end = url.length;
    while (end > 0) {
      final ch = url[end - 1];
      if (ch == ')' || ch == ']') {
        final open = ch == ')' ? '(' : '[';
        final scanned = url.substring(0, end);
        final opens = open.allMatches(scanned).length;
        final closes = ch.allMatches(scanned).length;
        if (closes > opens) {
          end--;
          continue;
        }
        break;
      }
      if (_trimmableTrailing.contains(ch)) {
        end--;
        continue;
      }
      break;
    }
    return url.substring(0, end);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _urlPattern.allMatches(text)) {
      final url = _trimTrailingPunctuation(match.group(0)!);
      if (url.isEmpty) continue;
      final start = match.start;
      final end = start + url.length;
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      final target = url.startsWith('http') ? url : 'https://$url';
      spans.add(
        TextSpan(
          text: url,
          style: const TextStyle(
            color: EncbaColors.snuBlue,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _launch(target),
        ),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}

Future<void> _showNotifications(
  BuildContext context,
  WidgetRef ref,
  List<AnnouncementItem> announcements, {
  required bool canManage,
  required UserProfile user,
}) async {
  final service = WebNotificationService();
  final prefs = NotificationCategoryPrefs();
  var enabled = await service.isEnabled();
  final categoryEnabled = <NotificationCategory, bool>{
    for (final category in NotificationCategory.values)
      category: await prefs.isEnabled(category),
  };
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => StatefulBuilder(
      builder: (sheetContext, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '알림',
                style: TextStyle(
                  fontFamily: 'Jua',
                  fontSize: 25,
                  color: EncbaColors.navy,
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                title: const Text('알림 받기'),
                subtitle: Text(
                  user.isReservationManager
                      ? '공지 · 미정 응답 · 체육관 예약 오픈 알림'
                      : '공지와 미정 응답 알림',
                ),
                onChanged: (value) async {
                  if (value) {
                    final granted = await service.enableAndTest();
                    if (!sheetContext.mounted) return;
                    setState(() => enabled = granted);
                    if (granted) {
                      ref
                          .read(lockerControllerProvider.notifier)
                          .refreshUndecidedReminders();
                      await ref
                          .read(lockerControllerProvider.notifier)
                          .scheduleReservationOpeningReminder(
                            isReservationManager: user.isReservationManager,
                          );
                    }
                  } else {
                    await service.disable();
                    if (sheetContext.mounted) setState(() => enabled = false);
                  }
                },
              ),
              if (enabled) ...[
                const SizedBox(height: 4),
                const Text(
                  '항목별 알림',
                  style: TextStyle(
                    color: EncbaColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final category in NotificationCategory.values)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: categoryEnabled[category] ?? true,
                    title: Text(switch (category) {
                      NotificationCategory.announcements => '공지',
                      NotificationCategory.events => '일정',
                      NotificationCategory.videos => '영상',
                    }),
                    onChanged: (value) async {
                      await prefs.setEnabled(category, value);
                      setState(() => categoryEnabled[category] = value);
                    },
                  ),
              ],
              const Divider(),
              if (announcements.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.notifications_none_rounded,
                    color: EncbaColors.muted,
                  ),
                  title: Text('새 알림이 없습니다'),
                )
              else
                ...announcements
                    .take(3)
                    .map(
                      (notice) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.campaign_outlined,
                          color: EncbaColors.snuBlue,
                        ),
                        title: Text(notice.title),
                        subtitle: Text(
                          '${notice.author} · ${_relativeTime(notice.publishedAt)}',
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _openNotice(context, notice.id);
                        },
                      ),
                    ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _showAnnouncementEditor(
  BuildContext context,
  WidgetRef ref, {
  AnnouncementItem? existing,
}) async {
  final draft = await Navigator.push<_AnnouncementDraft>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _AnnouncementEditorScreen(
        existing: existing,
        events: ref.read(lockerControllerProvider).events,
      ),
    ),
  );
  if (draft != null) {
    final controller = ref.read(lockerControllerProvider.notifier);
    final saved = existing == null
        ? await controller.addAnnouncement(
            title: draft.title,
            body: draft.body,
            pinned: draft.pinned,
            linkedEventIds: draft.linkedEventIds,
          )
        : await controller.updateAnnouncement(
            announcement: existing,
            title: draft.title,
            body: draft.body,
            pinned: draft.pinned,
            linkedEventIds: draft.linkedEventIds,
          );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? (existing == null ? '공지를 등록했습니다.' : '공지를 수정했습니다.')
                : '공지를 저장하지 못했습니다.',
          ),
        ),
      );
    }
  }
}

class _AnnouncementDraft {
  const _AnnouncementDraft({
    required this.title,
    required this.body,
    required this.pinned,
    required this.linkedEventIds,
  });
  final String title;
  final String body;
  final bool pinned;
  final List<String> linkedEventIds;
}

class _AnnouncementEditorScreen extends StatefulWidget {
  const _AnnouncementEditorScreen({this.existing, required this.events});
  final AnnouncementItem? existing;
  final List<LockerEvent> events;

  @override
  State<_AnnouncementEditorScreen> createState() =>
      _AnnouncementEditorScreenState();
}

class _AnnouncementEditorScreenState extends State<_AnnouncementEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _pinned;
  late Set<String> _linkedEventIds;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '')
      ..addListener(_refresh);
    _body = TextEditingController(text: widget.existing?.body ?? '')
      ..addListener(_refresh);
    _pinned = widget.existing?.pinned ?? false;
    _linkedEventIds = widget.existing?.linkedEventIds.toSet() ?? <String>{};
  }

  @override
  void dispose() {
    _title
      ..removeListener(_refresh)
      ..dispose();
    _body
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canSave =
        _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(widget.existing == null ? '새 공지' : '공지 수정')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 28,
        ),
        children: [
          TextField(
            controller: _title,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            decoration: const InputDecoration(
              labelText: '제목 *',
              hintText: '예: 이번 주 정기훈련 안내',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            minLines: 7,
            maxLines: 16,
            maxLength: 10000,
            keyboardType: TextInputType.multiline,
            scrollPadding: const EdgeInsets.only(bottom: 180),
            decoration: const InputDecoration(
              labelText: '내용 *',
              alignLabelWithHint: true,
              hintText: '일시, 장소, 준비물처럼 부원이 바로 알아야 할 내용을 적어 주세요.',
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _pinned,
            title: const Text('홈 상단에 고정'),
            onChanged: (value) => setState(() => _pinned = value),
          ),
          if (widget.events.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('일정 연결', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children:
                  (widget.events.toList()
                        ..sort((a, b) => a.start.compareTo(b.start)))
                      .take(30)
                      .map(
                        (event) => FilterChip(
                          selected: _linkedEventIds.contains(event.id),
                          label: Text(
                            '${event.start.month}.${event.start.day} ${event.title}',
                          ),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _linkedEventIds.add(event.id);
                            } else {
                              _linkedEventIds.remove(event.id);
                            }
                          }),
                        ),
                      )
                      .toList(),
            ),
          ],
          const SizedBox(height: 18),
          const Text('미리보기', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title.text.trim().isEmpty ? '공지 제목' : _title.text.trim(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _body.text.trim().isEmpty
                        ? '공지 내용이 여기에 보입니다.'
                        : _body.text.trim(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: canSave
                ? () => Navigator.pop(
                    context,
                    _AnnouncementDraft(
                      title: _title.text.trim(),
                      body: _body.text.trim(),
                      pinned: _pinned,
                      linkedEventIds: _linkedEventIds.toList(),
                    ),
                  )
                : null,
            child: Text(widget.existing == null ? '공지 등록' : '변경 내용 저장'),
          ),
        ],
      ),
    );
  }
}

String? _youtubeIdFrom(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be' || host == 'www.youtu.be') {
    return uri.pathSegments.isEmpty
        ? null
        : _validatedYoutubeId(uri.pathSegments.first);
  }
  if (host != 'youtube.com' &&
      host != 'www.youtube.com' &&
      host != 'm.youtube.com' &&
      host != 'music.youtube.com') {
    return null;
  }
  final queryId = uri.queryParameters['v'];
  if (queryId != null && queryId.isNotEmpty) {
    return _validatedYoutubeId(queryId);
  }
  for (final marker in ['shorts', 'embed', 'live']) {
    final index = uri.pathSegments.indexOf(marker);
    if (index >= 0 && index + 1 < uri.pathSegments.length) {
      return _validatedYoutubeId(uri.pathSegments[index + 1]);
    }
  }
  return null;
}

String? _validatedYoutubeId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(value) ? value : null;

String? _videoThumbnailUrl({
  required String youtubeId,
  required String sourceUrl,
}) {
  final resolvedId =
      _validatedYoutubeId(youtubeId) ?? _youtubeIdFrom(sourceUrl);
  return resolvedId == null
      ? null
      : 'https://img.youtube.com/vi/$resolvedId/hqdefault.jpg';
}

String? _instagramThumbnailAsset(String sourceUrl) {
  final shortcode = _instagramShortcode(sourceUrl);
  if (shortcode == null || !_bundledReelShortcodes.contains(shortcode)) {
    return null;
  }
  return 'assets/images/reel_$shortcode.jpg';
}
