part of '../locker_shell.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeState = ref.watch(
      lockerControllerProvider.select(
        (state) => (
          events: state.eventsState.events,
          operations: state.operationsState.operations,
          announcements: state.operationsState.announcements,
        ),
      ),
    );
    final unreadNotifications = ref.watch(
      lockerControllerProvider.select((state) => state.unreadNotifications),
    );
    final user = ref.watch(authControllerProvider).user!;
    final events = <LockerEvent>[
      ...homeState.events,
      ...homeState.operations.map((item) => item.toPlannerEvent()),
    ]..sort((a, b) => a.start.compareTo(b.start));
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
            const _AppDemandButton(),
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
                _showNotifications(context, ref, user: user);
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
        // 일정 등록 입구는 플래너 탭에만 있어 관리자가 탭을 옮겨야 했다.
        // 홈에서도 같은 등록 화면으로 바로 갈 수 있게 열어 둔다.
        _SectionHeader(
          title: '가장 가까운 일정',
          action: user.canAdminister ? '새 일정' : null,
          onTap: user.canAdminister ? () => _openEditor(context) : null,
        ),
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
        if (homeState.announcements.isEmpty)
          const _EmptyState(
            icon: Icons.campaign_outlined,
            title: '등록된 공지가 없습니다',
          )
        else
          ...homeState.announcements
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

/// 홈 화면의 앱 수요조사 별 버튼. 모든 부원이 눌러 수요를 표시하고,
/// 관리자에게만 지금까지 쌓인 수요 합계가 배지 숫자로 보인다.
class _AppDemandButton extends ConsumerStatefulWidget {
  const _AppDemandButton();

  @override
  ConsumerState<_AppDemandButton> createState() => _AppDemandButtonState();
}

class _AppDemandButtonState extends ConsumerState<_AppDemandButton> {
  bool _voted = false;
  bool _busy = false;

  /// 관리자에게만 채워지는 수요 합계. 부원은 null이라 숫자가 안 보인다.
  int? _count;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final voted = await ref
          .read(lockerControllerProvider.notifier)
          .loadAppDemandVote();
      if (!mounted) return;
      setState(() => _voted = voted);
      final isAdmin =
          ref.read(authControllerProvider).user?.canAdminister ?? false;
      if (!isAdmin) return;
      final count = await ref
          .read(lockerControllerProvider.notifier)
          .loadAppDemandCount();
      if (!mounted || count == null) return;
      setState(() => _count = count);
    });
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final voted = await ref
          .read(lockerControllerProvider.notifier)
          .toggleAppDemand();
      if (!mounted) return;
      setState(() {
        _voted = voted;
        final count = _count;
        if (count != null) _count = count + (voted ? 1 : -1);
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(voted ? '앱 수요조사에 참여했습니다!' : '참여를 취소했습니다.')),
        );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('처리하지 못했습니다. 다시 시도해 주세요.')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return IconButton(
      tooltip: '앱 수요조사',
      onPressed: _busy ? null : _toggle,
      icon: Badge(
        isLabelVisible: count != null && count > 0,
        label: Text('$count'),
        child: Icon(
          _voted ? Icons.star_rounded : Icons.star_outline_rounded,
          color: _voted ? EncbaColors.late : null,
        ),
      ),
    );
  }
}

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
          if (notice.body.trim().isNotEmpty) ...[
            const SizedBox(height: 22),
            _Linkified(notice.body, style: const TextStyle(height: 1.75)),
          ],
          if (notice.imageUrl case final imageUrl?) ...[
            const SizedBox(height: 20),
            // 높이를 고정해 두면 느린 네트워크에서 사진이 도착할 때
            // 본문·투표 카드가 위아래로 튀지 않는다.
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  frameBuilder: (context, child, frame, wasSync) {
                    if (wasSync || frame != null) return child;
                    return const ColoredBox(
                      color: EncbaColors.highlight,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => const _EmptyState(
                    icon: Icons.broken_image_outlined,
                    title: '첨부 사진을 불러오지 못했습니다',
                  ),
                ),
              ),
            ),
          ],
          if (notice.pollOptions.isNotEmpty) ...[
            const SizedBox(height: 20),
            _AnnouncementPollCard(notice: notice),
          ],
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
          recognizer: TapGestureRecognizer()
            ..onTap = () => _launch(context, target),
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
  WidgetRef ref, {
  required UserProfile user,
}) async {
  final service = WebNotificationService();
  final prefs = NotificationCategoryPrefs();
  final historyService = NotificationHistoryService();
  var enabled = await service.isEnabled();
  final categoryEnabled = <NotificationCategory, bool>{
    for (final category in NotificationCategory.values)
      category: await prefs.isEnabled(category),
  };
  var history = await historyService.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => StatefulBuilder(
      builder: (sheetContext, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '알림',
                      style: TextStyle(
                        fontFamily: 'Jua',
                        fontSize: 25,
                        color: EncbaColors.navy,
                      ),
                    ),
                  ),
                  if (history.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await historyService.clear();
                        if (sheetContext.mounted) {
                          setState(() => history = const []);
                        }
                      },
                      child: const Text('기록 지우기'),
                    ),
                ],
              ),
              // 평소에는 지난 알림이 먼저 보이도록 설정은 접어 둔다.
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(
                  Icons.tune_rounded,
                  color: EncbaColors.muted,
                ),
                title: const Text('알림 설정'),
                subtitle: Text(enabled ? '알림 받는 중' : '알림 꺼짐'),
                children: [
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
                        if (sheetContext.mounted) {
                          setState(() => enabled = false);
                        }
                      }
                    },
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 4),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '항목별 알림',
                        style: TextStyle(
                          color: EncbaColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
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
                ],
              ),
              const Divider(),
              if (history.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.notifications_none_rounded,
                    color: EncbaColors.muted,
                  ),
                  title: Text('새 알림이 없습니다'),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: history.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: EncbaColors.line),
                    itemBuilder: (context, index) =>
                        _NotificationHistoryTile(entry: history[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 알림 기록 한 줄. 정확한 시각과 상대 시간을 함께 보여 준다.
class _NotificationHistoryTile extends StatelessWidget {
  const _NotificationHistoryTile({required this.entry});

  final NotificationHistoryEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: EncbaColors.snuBlue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.notifications_active_outlined,
            size: 18,
            color: EncbaColors.snuBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (entry.body.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  entry.body,
                  style: const TextStyle(fontSize: 13, color: EncbaColors.ink),
                ),
              ],
              const SizedBox(height: 5),
              Text(
                '${_notificationTimestamp(entry.receivedAt)} · ${_relativeTime(entry.receivedAt)}',
                style: const TextStyle(fontSize: 12, color: EncbaColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// "8월 25일 오후 3:42"처럼 알림을 받은 정확한 시각을 적는다.
/// intl의 기본 로케일은 영어라 오전·오후를 직접 붙인다.
String _notificationTimestamp(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour < 12 ? '오전' : '오후';
  return '${value.month}월 ${value.day}일 $meridiem $hour:$minute';
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
            imageBase64: draft.imageBase64,
            imageName: draft.imageName,
            pollOptions: draft.pollOptions,
            pollQuestion: draft.pollQuestion,
          )
        : await controller.updateAnnouncement(
            announcement: existing,
            title: draft.title,
            body: draft.body,
            pinned: draft.pinned,
            linkedEventIds: draft.linkedEventIds,
            imageBase64: draft.imageBase64,
            imageName: draft.imageName,
            removeImage: draft.removeImage,
            pollOptions: draft.pollOptions,
            pollQuestion: draft.pollQuestion,
          );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
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
    required this.pollOptions,
    this.pollQuestion = '',
    this.imageBase64,
    this.imageName,
    this.removeImage = false,
  });
  final String title;
  final String body;
  final bool pinned;
  final List<String> linkedEventIds;
  final List<String> pollOptions;
  final String pollQuestion;
  final String? imageBase64;
  final String? imageName;
  final bool removeImage;
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
  late bool _pollEnabled;
  late final TextEditingController _pollQuestion;
  late List<TextEditingController> _pollOptions;
  String? _imageBase64;

  /// 미리보기용으로 디코딩해 둔 사진 바이트. build()마다 base64Decode를
  /// 새로 부르면 매번 새 객체가 생겨 Image.memory가 다른 이미지로 보고
  /// 다시 디코딩해, 제목/본문 타이핑처럼 사소한 리렌더에도 사진이
  /// 번쩍거렸다.
  Uint8List? _imageBytes;
  String? _imageName;
  bool _removeExistingImage = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '')
      ..addListener(_refresh);
    _body = TextEditingController(text: widget.existing?.body ?? '')
      ..addListener(_refresh);
    _pinned = widget.existing?.pinned ?? false;
    _linkedEventIds = widget.existing?.linkedEventIds.toSet() ?? <String>{};
    final existingPoll = widget.existing?.pollOptions ?? const <String>[];
    _pollEnabled = existingPoll.isNotEmpty;
    _pollQuestion = TextEditingController(
      text: widget.existing?.pollQuestion ?? '',
    )..addListener(_refresh);
    _pollOptions = (existingPoll.isEmpty ? const ['찬성', '반대'] : existingPoll)
        .map((option) => TextEditingController(text: option))
        .toList();
    for (final controller in _pollOptions) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _title
      ..removeListener(_refresh)
      ..dispose();
    _body
      ..removeListener(_refresh)
      ..dispose();
    _pollQuestion
      ..removeListener(_refresh)
      ..dispose();
    for (final controller in _pollOptions) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canSave =
        _title.text.trim().isNotEmpty &&
        (!_pollEnabled ||
            (_pollQuestion.text.trim().isNotEmpty &&
                _pollOptions.length >= 2 &&
                _pollOptions.every((item) => item.text.trim().isNotEmpty) &&
                _pollOptions.map((item) => item.text.trim()).toSet().length ==
                    _pollOptions.length));
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
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '사진 첨부',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (_imageBase64 != null ||
                      (widget.existing?.imageUrl != null &&
                          !_removeExistingImage)) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _imageBytes != null
                          ? Image.memory(
                              _imageBytes!,
                              height: 180,
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                              widget.existing!.imageUrl!,
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickAnnouncementImage,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('사진 선택'),
                        ),
                      ),
                      if (_imageBase64 != null ||
                          (widget.existing?.imageUrl != null &&
                              !_removeExistingImage)) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '첨부 사진 지우기',
                          onPressed: () => setState(() {
                            _imageBase64 = null;
                            _imageBytes = null;
                            _imageName = null;
                            _removeExistingImage = true;
                          }),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _pollEnabled,
            title: const Text('투표 첨부'),
            subtitle: const Text('부원은 공지에서 한 항목을 선택할 수 있습니다.'),
            onChanged: (value) => setState(() => _pollEnabled = value),
          ),
          if (_pollEnabled) ...[
            TextField(
              controller: _pollQuestion,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '투표 질문 *',
                hintText: '예: 메뉴를 골라주세요',
              ),
            ),
            const SizedBox(height: 4),
            for (final (index, controller) in _pollOptions.indexed) ...[
              Row(
                key: ObjectKey(controller),
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      maxLength: 60,
                      decoration: InputDecoration(
                        labelText: '투표 항목 ${index + 1}',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '항목 삭제',
                    onPressed: () => _removePollOption(index),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                ],
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pollOptions.length >= 8 ? null : _addPollOption,
                icon: const Icon(Icons.add_rounded),
                label: const Text('투표 항목 추가'),
              ),
            ),
          ],
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
                      pollOptions: _pollEnabled
                          ? _pollOptions
                                .map((item) => item.text.trim())
                                .toList()
                          : const [],
                      pollQuestion: _pollEnabled
                          ? _pollQuestion.text.trim()
                          : '',
                      imageBase64: _imageBase64,
                      imageName: _imageName,
                      removeImage: _removeExistingImage,
                    ),
                  )
                : null,
            child: Text(widget.existing == null ? '공지 등록' : '변경 내용 저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAnnouncementImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 8 * 1024 * 1024) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('사진은 8MB 이하로 첨부해 주세요.')));
      return;
    }
    setState(() {
      _imageBytes = bytes;
      _imageBase64 = base64Encode(bytes);
      _imageName = image.name;
      _removeExistingImage = false;
    });
  }

  void _addPollOption() {
    final controller = TextEditingController()..addListener(_refresh);
    setState(() => _pollOptions.add(controller));
  }

  void _removePollOption(int index) {
    final controller = _pollOptions.removeAt(index);
    controller
      ..removeListener(_refresh)
      ..dispose();
    setState(() {});
  }
}

class _AnnouncementPollCard extends ConsumerWidget {
  const _AnnouncementPollCard({required this.notice});

  final AnnouncementItem notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = notice.pollVotes.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    notice.pollQuestion.trim().isEmpty
                        ? '투표'
                        : notice.pollQuestion,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '$total명 참여',
                  style: const TextStyle(color: EncbaColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final (index, option) in notice.pollOptions.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  notice.myPollOption == index
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: notice.myPollOption == index
                      ? EncbaColors.snuBlue
                      : EncbaColors.muted,
                ),
                title: Text(option),
                trailing: Text('${notice.pollVotes[index] ?? 0}표'),
                onTap: () => ref
                    .read(lockerControllerProvider.notifier)
                    .voteAnnouncement(notice, index),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    _showAnnouncementPollVoters(context, ref, notice),
                icon: const Icon(Icons.groups_outlined),
                label: const Text('투표 현황 보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 투표 항목별 응답자 이름과, 활동 부원 중 아직 투표하지 않은 사람을
/// 보여주는 시트. 집계 표만 보이던 기존 카드에서 한 단계 더 들어간
/// 정보라 관리자 전용이 아니라 공지·투표 자체처럼 모두에게 열어 둔다.
Future<void> _showAnnouncementPollVoters(
  BuildContext context,
  WidgetRef ref,
  AnnouncementItem notice,
) async {
  final controller = ref.read(lockerControllerProvider.notifier);
  final votersFuture = controller.loadAnnouncementPollVoters(notice.id);
  final membersFuture = controller.loadAllMembersForAccountCheck();
  final dataFuture = () async {
    final voters = await votersFuture;
    final members = await membersFuture;
    return (voters: voters, members: members);
  }();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child:
            FutureBuilder<
              ({
                List<AnnouncementPollVoter> voters,
                List<MemberProfile> members,
              })
            >(
              future: dataFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final voters = snapshot.data!.voters;
                final votedIds = voters.map((item) => item.profileId).toSet();
                final notVoted =
                    snapshot.data!.members
                        .where(
                          (member) =>
                              member.isActiveMember &&
                              member.id != null &&
                              !votedIds.contains(member.id),
                        )
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name));
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    const Text(
                      '투표 현황',
                      style: TextStyle(
                        fontFamily: 'Jua',
                        fontSize: 22,
                        color: EncbaColors.navy,
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final (index, option)
                        in notice.pollOptions.indexed) ...[
                      Text(
                        option,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      _PollVoterNames(
                        names: voters
                            .where((voter) => voter.optionIndex == index)
                            .map((voter) => voter.name)
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      '아직 투표하지 않음 (${notVoted.length}명)',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    _PollVoterNames(
                      names: notVoted.map((member) => member.name).toList(),
                      emptyText: '모든 활동 부원이 투표했습니다.',
                    ),
                  ],
                );
              },
            ),
      ),
    ),
  );
}

class _PollVoterNames extends StatelessWidget {
  const _PollVoterNames({required this.names, this.emptyText = '아직 없음'});

  final List<String> names;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return Text(emptyText, style: const TextStyle(color: EncbaColors.muted));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in names)
          Chip(
            label: Text(name),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
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

/// 앱에 그림 파일을 넣어 두지 않은 릴스도 Instagram의 공개 미디어 주소로
/// 썸네일을 자동으로 가져온다. 새 하이라이트를 올릴 때마다 에셋을 수동으로
/// 빌드에 추가할 필요가 없어진다. 주소가 막히면 위젯이 그라디언트 폴백을
/// 보여주므로 화면이 깨지지 않는다.
String? _instagramThumbnailUrl(String sourceUrl) {
  final shortcode = _instagramShortcode(sourceUrl);
  return shortcode == null
      ? null
      : 'https://www.instagram.com/p/$shortcode/media/?size=l';
}
