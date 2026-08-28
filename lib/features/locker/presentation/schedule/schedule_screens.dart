part of '../locker_shell.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  DateTime? _selectedDate;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _calendarOpen = false;
  int _visibleCount = 10;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _dayKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plannerState = ref.watch(
      lockerControllerProvider.select(
        (state) => (
          events: state.plannerEvents,
          hasMore: state.eventsState.hasMoreEvents,
          isLoadingMore: state.eventsState.isLoadingMoreEvents,
        ),
      ),
    );
    final allEvents = [...plannerState.events]
      ..sort((a, b) => a.start.compareTo(b.start));
    final user = ref.watch(authControllerProvider).user!;
    final today = DateUtils.dateOnly(DateTime.now());
    final futureEvents = allEvents
        .where((event) => !DateUtils.dateOnly(event.start).isBefore(today))
        .toList();
    final showingHistory =
        _selectedDate != null && _selectedDate!.isBefore(today);
    final listedEvents = showingHistory
        ? allEvents
              .where((event) => DateUtils.isSameDay(event.start, _selectedDate))
              .toList()
        : futureEvents;
    final visible = showingHistory
        ? listedEvents
        : listedEvents.take(_visibleCount).toList();
    final canRevealMore = visible.length < listedEvents.length;
    final canLoadMore =
        !showingHistory && (canRevealMore || plannerState.hasMore);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (canLoadMore &&
            notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 180) {
          if (canRevealMore) {
            setState(() => _visibleCount += 10);
          } else {
            unawaited(_loadNextEventPage());
          }
        }
        return false;
      },
      child: _Page(
        controller: _scrollController,
        scrollKey: const ValueKey('planner-scroll'),
        header: _Header(
          eyebrow: _academicLabel(DateTime.now()),
          title: 'PLANNER',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                tooltip: _calendarOpen ? '달력 닫기' : '달력 펼치기',
                onPressed: () => setState(() => _calendarOpen = !_calendarOpen),
                icon: Icon(
                  _calendarOpen
                      ? Icons.calendar_view_week_rounded
                      : Icons.calendar_month_rounded,
                ),
              ),
              if (user.canAdminister)
                IconButton(
                  tooltip: '일정 추가',
                  onPressed: () => _openEditor(context),
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: EncbaColors.snuBlue,
                  ),
                ),
            ],
          ),
        ),
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: _calendarOpen
                ? _PlannerCalendar(
                    key: const ValueKey('month'),
                    visibleMonth: _visibleMonth,
                    selectedDate: _selectedDate,
                    events: allEvents,
                    onMonthChanged: (month) =>
                        setState(() => _visibleMonth = month),
                    onSelected: _selectDate,
                  )
                : _WeekStrip(
                    key: const ValueKey('week'),
                    selectedDate: _selectedDate,
                    events: allEvents,
                    onSelected: _selectDate,
                  ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: showingHistory
                ? '${_selectedDate!.month}.${_selectedDate!.day} 일정 ${listedEvents.length}개'
                : '오늘 이후 일정 ${futureEvents.length}개',
          ),
          const SizedBox(height: 11),
          if (visible.isEmpty)
            _EmptyState(
              icon: Icons.event_available_outlined,
              title: showingHistory ? '이 날짜에는 일정이 없습니다' : '예정된 일정이 없습니다',
              action: '다시 불러오기',
              onTap: () => ref.read(lockerControllerProvider.notifier).reload(),
            )
          else
            ...visible.indexed.expand((entry) {
              final index = entry.$1;
              final event = entry.$2;
              final startsNewDay =
                  index == 0 ||
                  !DateUtils.isSameDay(visible[index - 1].start, event.start);
              return [
                if (startsNewDay)
                  _PlannerDayHeader(
                    key: _dayKeys.putIfAbsent(
                      _dayId(event.start),
                      GlobalKey.new,
                    ),
                    date: event.start,
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: EventTicket(
                    event: event,
                    heroTag: 'schedule-${event.id}',
                    compact: true,
                    onTap: () => event.kind == EventKind.homecoming
                        ? context.push('/homecoming')
                        : openEventDetail(
                            context,
                            event.id,
                            heroTagPrefix: 'schedule',
                          ),
                  ),
                ),
              ];
            }),
          if (plannerState.isLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('일정을 더 불러오는 중입니다'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadNextEventPage() async {
    await ref.read(lockerControllerProvider.notifier).loadMoreEvents();
    if (mounted) setState(() => _visibleCount += 10);
  }

  void _selectDate(DateTime date) {
    final today = DateUtils.dateOnly(DateTime.now());
    final events = [...ref.read(lockerControllerProvider).plannerEvents]
      ..sort((a, b) => a.start.compareTo(b.start));
    final isPast = DateUtils.dateOnly(date).isBefore(today);
    final listedEvents = isPast
        ? events
              .where((event) => DateUtils.isSameDay(event.start, date))
              .toList()
        : events
              .where(
                (event) => !DateUtils.dateOnly(event.start).isBefore(today),
              )
              .toList();
    final targetIndex = listedEvents.indexWhere(
      (event) => DateUtils.isSameDay(event.start, date),
    );
    setState(() {
      _selectedDate = DateUtils.dateOnly(date);
      _visibleMonth = DateTime(date.year, date.month);
      if (!isPast && targetIndex >= 0) {
        _visibleCount = math.max(_visibleCount, ((targetIndex ~/ 10) + 1) * 10);
      }
    });
    if (targetIndex < 0) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('이 날짜에는 일정이 없습니다.')));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isPast) {
        if (_scrollController.hasClients) {
          unawaited(
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            ),
          );
        }
      } else {
        unawaited(_scrollToDate(date, targetIndex, listedEvents.length));
      }
    });
  }

  Future<void> _scrollToDate(
    DateTime date,
    int targetIndex,
    int eventCount,
  ) async {
    if (!mounted || !_scrollController.hasClients) return;
    var target = _dayKeys[_dayId(date)]?.currentContext;
    if (target == null) {
      final position = _scrollController.position;
      final ratio = eventCount <= 1 ? 0.0 : targetIndex / (eventCount - 1);
      await _scrollController.animateTo(
        position.maxScrollExtent * ratio,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      target = _dayKeys[_dayId(date)]?.currentContext;
      for (var attempt = 0; target == null && attempt < 6; attempt++) {
        final currentPosition = _scrollController.position;
        final nextOffset = math.min(
          currentPosition.maxScrollExtent,
          currentPosition.pixels + currentPosition.viewportDimension * .8,
        );
        if (nextOffset <= currentPosition.pixels) break;
        await _scrollController.animateTo(
          nextOffset,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        target = _dayKeys[_dayId(date)]?.currentContext;
      }
    }
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: .04,
    );
  }
}

class CourtReservationScreen extends ConsumerStatefulWidget {
  const CourtReservationScreen({super.key});

  @override
  ConsumerState<CourtReservationScreen> createState() =>
      _CourtReservationScreenState();
}

class _CourtReservationScreenState
    extends ConsumerState<CourtReservationScreen> {
  Timer? _ticker;
  DateTime? _serverReference;
  DateTime? _deviceReference;

  @override
  void initState() {
    super.initState();
    _syncClock();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final user = ref.read(authControllerProvider).user;
    Future.microtask(
      () => ref
          .read(lockerControllerProvider.notifier)
          .scheduleReservationOpeningReminder(
            isReservationManager: user?.isReservationManager ?? false,
          ),
    );
  }

  Future<void> _syncClock() async {
    final serverNow = await ref
        .read(lockerControllerProvider.notifier)
        .serverNow();
    if (!mounted) return;
    setState(() {
      _serverReference = serverNow;
      _deviceReference = DateTime.now();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime get _now {
    final server = _serverReference;
    final device = _deviceReference;
    if (server == null || device == null) return DateTime.now();
    return server.add(DateTime.now().difference(device));
  }

  ({bool open, DateTime target}) _reservationWindow(DateTime now) {
    final startOfDay = DateTime(now.year, now.month, now.day);
    final thisTuesday = startOfDay.add(
      Duration(days: DateTime.tuesday - now.weekday),
    );
    final opening = thisTuesday.add(const Duration(hours: 9, minutes: 30));
    final closes = thisTuesday.add(const Duration(days: 6));
    if (!now.isBefore(opening) && now.isBefore(closes)) {
      return (open: true, target: closes);
    }
    var nextOpening = opening;
    if (!nextOpening.isAfter(now)) {
      nextOpening = nextOpening.add(const Duration(days: 7));
    }
    return (open: false, target: nextOpening);
  }

  DateTime _nextDormOpening(DateTime now) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return tomorrow;
  }

  String _countdown(Duration value) {
    final duration = value.isNegative ? Duration.zero : value;
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${days > 0 ? '$days일 ' : ''}'
        '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user!;
    final now = _now;
    final window = _reservationWindow(now);
    final dormOpening = _nextDormOpening(now);
    final dormDate = dormOpening.add(const Duration(days: 14));
    return Scaffold(
      appBar: AppBar(title: const Text('농구장 예약')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          // 시설마다 남은 시간과 예약 링크를 붙여 둔다. 시간을 보고 바로 아래
          // 버튼을 누르게 되므로 둘을 떼어 놓지 않는다.
          _ReservationCountdownCard(
            eyebrow: '71 · 71-1 RESERVATION',
            title: window.open ? '지금 예약할 수 있습니다' : '화요일 09:30 오픈',
            // 열려 있을 때와 닫혀 있을 때가 서로 다른 시각을 센다. 무엇까지
            // 남은 시간인지 안 적으면 열린 동안에도 "오픈까지 남은 시간"으로
            // 읽혀서, 실제로는 지금 예약할 수 있는데 기다리게 된다.
            countdown: window.open
                ? '마감까지 ${_countdown(window.target.difference(now))}'
                : '오픈까지 ${_countdown(window.target.difference(now))}',
            serverTime: now,
            badge: user.isReservationManager,
          ),
          const SizedBox(height: 12),
          const _ReservationVenueCard(
            building: '71동 · 71-1동',
            title: '종합체육관 · 신체육관',
            rule: '매주 화요일 09:30 · 다음 주 월–일 오픈\n1인 주 1회 · 최대 2시간 · 시설별 최소 인원 확인',
            buttonLabel: '71동 · 71-1동 예약하기',
            url: 'https://athletics.snu.ac.kr/facility/list',
          ),
          const SizedBox(height: 22),
          _ReservationCountdownCard(
            eyebrow: '900 RESERVATION',
            title: '${DateFormat('M월 d일').format(dormDate)} 예약 오픈',
            countdown: '오픈까지 ${_countdown(dormOpening.difference(now))}',
            serverTime: now,
            badge: user.isReservationManager,
          ),
          const SizedBox(height: 12),
          const _ReservationVenueCard(
            building: '900동',
            title: '기숙사 체육관',
            rule: '매일 00:00 · 사용일 14일 전 오픈\n신청은 사용 3일 전 마감 · 주 1회 · 최대 2시간',
            buttonLabel: '900동 예약하기',
            url: 'https://ssims.snu.ac.kr/resvuser/list.do',
          ),
        ],
      ),
    );
  }
}

class _ReservationCountdownCard extends StatelessWidget {
  const _ReservationCountdownCard({
    required this.eyebrow,
    required this.title,
    required this.countdown,
    required this.serverTime,
    required this.badge,
  });

  final String eyebrow;
  final String title;
  final String countdown;
  final DateTime serverTime;
  final bool badge;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: EncbaColors.navy,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                eyebrow,
                style: const TextStyle(
                  fontFamily: 'BlackHanSans',
                  color: Color(0xFFFFD84D),
                  letterSpacing: .8,
                ),
              ),
            ),
            if (badge) const _ReservationRoleBadge(),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Jua',
            color: Colors.white,
            fontSize: 25,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            countdown,
            maxLines: 1,
            style: const TextStyle(
              fontFamily: 'BlackHanSans',
              fontSize: 34,
              color: Colors.white,
              letterSpacing: .8,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '서버 기준 ${DateFormat('M월 d일 HH:mm:ss').format(serverTime)}',
          style: const TextStyle(color: Color(0xFFB9C8DC), fontSize: 12),
        ),
      ],
    ),
  );
}

class _ReservationRoleBadge extends StatelessWidget {
  const _ReservationRoleBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFFFD84D),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      '예약자',
      style: TextStyle(
        color: EncbaColors.navy,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _ReservationVenueCard extends StatelessWidget {
  const _ReservationVenueCard({
    required this.building,
    required this.title,
    required this.rule,
    required this.buttonLabel,
    required this.url,
  });

  final String building;
  final String title;
  final String rule;
  final String buttonLabel;
  final String url;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: EncbaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          building,
          style: const TextStyle(
            color: EncbaColors.snuBlue,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 9),
        Text(
          rule,
          style: const TextStyle(color: EncbaColors.muted, height: 1.55),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(buttonLabel),
          ),
        ),
      ],
    ),
  );
}

class _PlannerDayHeader extends StatelessWidget {
  const _PlannerDayHeader({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(date, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 9),
      child: Row(
        children: [
          Text(
            today ? '오늘' : '${date.month}.${date.day}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: EncbaColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            weekday(date),
            style: const TextStyle(
              color: EncbaColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    super.key,
    required this.selectedDate,
    required this.events,
    required this.onSelected,
  });

  final DateTime? selectedDate;
  final List<LockerEvent> events;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return Row(
      children: List.generate(7, (index) {
        final day = monday.add(Duration(days: index));
        final selected = DateUtils.isSameDay(day, selectedDate);
        final isToday = DateUtils.isSameDay(day, now);
        final hasEvent = events.any(
          (event) => DateUtils.isSameDay(event.start, day),
        );
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 6 ? 0 : 5),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? EncbaColors.navy : Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected
                          ? EncbaColors.navy
                          : isToday
                          ? EncbaColors.snuBlue
                          : EncbaColors.line,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        weekday(day),
                        style: TextStyle(
                          fontSize: 10,
                          color: selected ? Colors.white70 : EncbaColors.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          color: selected ? Colors.white : EncbaColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasEvent
                              ? selected
                                    ? Colors.white
                                    : EncbaColors.snuBlue
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _PlannerCalendar extends StatelessWidget {
  const _PlannerCalendar({
    super.key,
    required this.visibleMonth,
    required this.selectedDate,
    required this.events,
    required this.onMonthChanged,
    required this.onSelected,
  });

  final DateTime visibleMonth;
  final DateTime? selectedDate;
  final List<LockerEvent> events;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final leading = first.weekday - 1;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EncbaColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '이전 달',
                onPressed: () => onMonthChanged(
                  DateTime(visibleMonth.year, visibleMonth.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${visibleMonth.year}년 ${visibleMonth.month}월',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '다음 달',
                onPressed: () => onMonthChanged(
                  DateTime(visibleMonth.year, visibleMonth.month + 1),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Row(
            children: [
              for (final label in ['월', '화', '수', '목', '금', '토', '일'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: EncbaColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cellCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 45,
            ),
            itemBuilder: (context, index) {
              final dayNumber = index - leading + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox.shrink();
              }
              final day = DateTime(
                visibleMonth.year,
                visibleMonth.month,
                dayNumber,
              );
              final selected = DateUtils.isSameDay(day, selectedDate);
              final isToday = DateUtils.isSameDay(day, today);
              final hasEvent = events.any(
                (event) => DateUtils.isSameDay(event.start, day),
              );
              return Semantics(
                button: true,
                selected: selected,
                label: '$dayNumber일${hasEvent ? ', 일정 있음' : ''}',
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelected(day),
                    customBorder: const CircleBorder(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? EncbaColors.navy : Colors.transparent,
                        border: isToday && !selected
                            ? Border.all(color: EncbaColors.snuBlue)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNumber',
                            style: TextStyle(
                              color: selected ? Colors.white : EncbaColors.ink,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasEvent
                                  ? selected
                                        ? Colors.white
                                        : EncbaColors.snuBlue
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

void _openEditor(BuildContext context) => context.push('/schedule/new');
