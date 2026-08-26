part of 'locker_shell.dart';

final Map<String, int> _attendanceUiRevisions = {};

Future<void> openEventDetail(
  BuildContext context,
  String eventId, {
  String heroTagPrefix = 'event',
}) {
  return context.push<void>(
    '/schedule/${Uri.encodeComponent(eventId)}',
    extra: '$heroTagPrefix-$eventId',
  );
}

typedef _EventBuilder = Widget Function(LockerEvent event);

/// 주소의 ID를 현재 상태에서 찾고, 초기 페이지에 없으면 서버에서 한 건만 읽는다.
class _EventResolver extends ConsumerStatefulWidget {
  const _EventResolver({required this.eventId, required this.builder});

  final String eventId;
  final _EventBuilder builder;

  @override
  ConsumerState<_EventResolver> createState() => _EventResolverState();
}

class _EventResolverState extends ConsumerState<_EventResolver> {
  bool _loading = true;
  bool _notFound = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(_EventResolver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) {
      _loading = true;
      _notFound = false;
      _error = null;
      Future.microtask(_load);
    }
  }

  Future<void> _load() async {
    try {
      final found = await ref
          .read(lockerControllerProvider.notifier)
          .ensureEvent(widget.eventId);
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
    final plannerState = ref.watch(
      lockerControllerProvider.select(
        (state) => (
          events: state.eventsState.events,
          operations: state.operationsState.operations,
        ),
      ),
    );
    final event = <LockerEvent>[
      ...plannerState.events,
      ...plannerState.operations.map((item) => item.toPlannerEvent()),
    ].where((item) => item.id == widget.eventId).firstOrNull;
    if (event != null) return widget.builder(event);
    return _EntityLoadScaffold(
      title: '일정',
      loading: _loading,
      notFound: _notFound,
      error: _error,
      onRetry: () {
        setState(() {
          _loading = true;
          _notFound = false;
          _error = null;
        });
        _load();
      },
    );
  }
}

class _EntityLoadScaffold extends StatelessWidget {
  const _EntityLoadScaffold({
    required this.title,
    required this.loading,
    required this.notFound,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final bool loading;
  final bool notFound;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    notFound
                        ? Icons.search_off_rounded
                        : Icons.cloud_off_outlined,
                    size: 42,
                    color: EncbaColors.muted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    notFound
                        ? '$title 정보를 찾지 못했습니다.'
                        : '$title 정보를 불러오지 못했습니다.',
                    textAlign: TextAlign.center,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '연결 상태를 확인한 뒤 다시 시도해 주세요.',
                      style: TextStyle(color: EncbaColors.muted),
                    ),
                  ],
                  if (!notFound) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ],
              ),
      ),
    ),
  );
}

class EventTicket extends ConsumerWidget {
  const EventTicket({
    super.key,
    required this.event,
    required this.heroTag,
    required this.onTap,
    this.compact = false,
  });

  final LockerEvent event;
  final String heroTag;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = _kindColor(event.kind);
    final uniformDecoration = _uniformCardDecoration(event);
    if (event.isLocked) {
      return Semantics(
        button: true,
        label:
            '${event.title}, ${event.start.month}월 ${event.start.day}일, 출전 명단 확정 후 공개',
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: EncbaColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${event.start.month}.${event.start.day} · 출전 명단 확정 후 공개',
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: EncbaColors.line),
      ),
      child: Column(
        children: [
          Ink(
            decoration: BoxDecoration(
              color: uniformDecoration.color,
              gradient: uniformDecoration.gradient,
            ),
            child: Semantics(
              button: true,
              label:
                  '${event.title}, ${event.start.month}월 ${event.start.day}일, ${time(event.start)}부터 ${time(event.end)}까지, ${event.fullPlace}',
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(width: 7, color: accent),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 15 : 19),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  EventKindLabel(
                                    kind: event.kind,
                                    inverted:
                                        uniformDecoration.dark ||
                                        uniformDecoration.split,
                                  ),
                                ],
                              ),
                              if (event.isCancelled) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: EncbaColors.absent.withValues(
                                      alpha: .12,
                                    ),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Text(
                                    [
                                      '일정이 취소되었습니다.',
                                      if (event.cancellationReason?.trim()
                                          case final String reason
                                          when reason.isNotEmpty)
                                        reason,
                                    ].join(' '),
                                    style: const TextStyle(
                                      color: EncbaColors.absent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                SizedBox(height: compact ? 9 : 12),
                              ],
                              SizedBox(height: compact ? 10 : 16),
                              _UniformCardForeground(
                                decoration: uniformDecoration,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: encbaFontFor(
                                            event.title,
                                            display: true,
                                          ),
                                          fontSize: compact ? 18 : 23,
                                          height: 1.15,
                                          fontWeight: event.isBattle
                                              ? FontWeight.normal
                                              : FontWeight.w700,
                                        ),
                                      ),
                                      if (event.opponents.isNotEmpty) ...[
                                        const SizedBox(height: 5),
                                        Text(
                                          'vs ${event.opponents.join(' · ')}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      _MetaLine(
                                        icon: Icons.calendar_today_outlined,
                                        text:
                                            '${event.start.month}월 ${event.start.day}일 (${weekday(event.start)}) · ${time(event.start)}–${time(event.end)}',
                                        color: uniformDecoration.dark
                                            ? Colors.white
                                            : EncbaColors.ink,
                                      ),
                                      const SizedBox(height: 7),
                                      _MetaLine(
                                        icon: Icons.location_on_outlined,
                                        text: event.fullPlace,
                                        color: uniformDecoration.dark
                                            ? Colors.white
                                            : EncbaColors.ink,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 15,
                          color: uniformDecoration.dark
                              ? Colors.white70
                              : EncbaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (event.responseEnabled && !event.isCancelled) ...[
            const Divider(height: 1),
            AttendanceSelector(event: event, compact: true, flush: true),
          ],
        ],
      ),
    );
  }
}
