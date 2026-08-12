import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/auth/presentation/edit_profile_screen.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/presentation/event_screens.dart';
import 'package:encba_locker/features/locker/services/homecoming_import_service.dart';
import 'package:encba_locker/features/locker/services/ib_operation_import_service.dart';
import 'package:encba_locker/features/locker/services/web_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class LockerShell extends ConsumerWidget {
  const LockerShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lockerControllerProvider);
    if (!state.isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    const pages = [
      VideosScreen(),
      GamesScreen(),
      HomeScreen(),
      ScheduleScreen(),
      ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: state.tabIndex, children: pages),
      bottomNavigationBar: _SlidingNavigationBar(
        selectedIndex: state.tabIndex,
        onSelected: ref.read(lockerControllerProvider.notifier).selectTab,
      ),
    );
  }
}

class _SlidingNavigationBar extends StatelessWidget {
  const _SlidingNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.play_circle_outline_rounded, '영상'),
    (Icons.sports_basketball_outlined, '경기'),
    (Icons.home_outlined, '홈'),
    (Icons.calendar_month_outlined, '일정'),
    (Icons.person_outline_rounded, '개인'),
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 70,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / _items.length;
            final motion = MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 320);
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                AnimatedPositioned(
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  left: selectedIndex * slot,
                  top: 0,
                  width: slot,
                  height: 70,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: EncbaColors.navy),
                  ),
                ),
                Row(
                  children: _items.asMap().entries.map((entry) {
                    final selected = entry.key == selectedIndex;
                    return Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label: entry.value.$2,
                        child: InkWell(
                          onTap: () => onSelected(entry.key),
                          child: AnimatedDefaultTextStyle(
                            duration: motion,
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : EncbaColors.muted,
                              fontFamily: 'Jua',
                              fontSize: 11,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedScale(
                                  scale: selected ? 1.08 : 1,
                                  duration: motion,
                                  curve: Curves.easeOutBack,
                                  child: Icon(
                                    entry.value.$1,
                                    size: 22,
                                    color: selected
                                        ? Colors.white
                                        : EncbaColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(entry.value.$2),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lockerControllerProvider);
    final user = ref.watch(authControllerProvider).user!;
    final canManageSchedule = user.canAdminister;
    final events = [...state.plannerEvents]
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
                  state.announcements,
                  canManage: user.canAdminister,
                );
              },
              icon: Badge(
                isLabelVisible: state.unreadNotifications > 0,
                label: Text('${state.unreadNotifications}'),
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
            action: canManageSchedule ? '일정 추가' : null,
            onTap: canManageSchedule ? () => _openEditor(context) : null,
          )
        else
          EventTicket(
            event: nextEvent,
            heroTag: 'home-${nextEvent.id}',
            onTap: () =>
                openEventDetail(context, nextEvent, heroTagPrefix: 'home'),
          ),
        const SizedBox(height: 22),
        _TodayReadinessCard(
          event: nextEvent,
          attendance: nextEvent == null ? null : state.attendance[nextEvent.id],
          hasOperationToday: state.operations.any(
            (item) => DateUtils.isSameDay(item.start, DateTime.now()),
          ),
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
        if (state.announcements.isEmpty)
          const _EmptyState(
            icon: Icons.campaign_outlined,
            title: '등록된 공지가 없습니다',
          )
        else
          ...state.announcements
              .take(5)
              .map(
                (notice) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _NoticeCard(
                    notice: notice,
                    onTap: () => _openNotice(
                      context,
                      notice,
                      ref: ref,
                      canManage: user.canAdminister,
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}

class _TodayReadinessCard extends StatelessWidget {
  const _TodayReadinessCard({
    required this.event,
    required this.attendance,
    required this.hasOperationToday,
  });

  final LockerEvent? event;
  final String? attendance;
  final bool hasOperationToday;

  @override
  Widget build(BuildContext context) {
    final current = event;
    final responseReady =
        current == null ||
        !current.responseEnabled ||
        (attendance != null && attendance != '미정');
    final uniformReady =
        current == null ||
        !current.kind.isBattle ||
        current.uniformColors.isNotEmpty;
    final readyCount = [
      responseReady,
      uniformReady,
      true,
    ].where((ready) => ready).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EncbaColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '오늘의 준비 상태',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Jua',
                  fontSize: 22,
                ),
              ),
              const Spacer(),
              Text(
                '$readyCount / 3',
                style: const TextStyle(
                  color: Color(0xFFAFC9F0),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ReadinessLine(
            ready: responseReady,
            text: current == null
                ? '오늘 이후 일정 확인 완료'
                : responseReady
                ? '참석 응답 완료'
                : '참석 여부를 정해 주세요',
          ),
          _ReadinessLine(
            ready: uniformReady,
            text: uniformReady ? '유니폼 확인 완료' : '유니폼 색을 확인해 주세요',
          ),
          _ReadinessLine(
            ready: true,
            text: hasOperationToday ? '오늘 IB 운영 배정이 있습니다' : '오늘 IB 운영 없음',
          ),
        ],
      ),
    );
  }
}

class _ReadinessLine extends StatelessWidget {
  const _ReadinessLine({required this.ready, required this.text});
  final bool ready;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Icon(
          ready ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: ready ? const Color(0xFF78D9A5) : const Color(0xFFFFC26B),
          size: 19,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({super.key});

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  bool _oldestFirst = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lockerControllerProvider);
    final selected = state.videoSegment;
    final user = ref.watch(authControllerProvider).user!;
    const categories = ['하이라이트', '복기', '공유'];
    final visible =
        state.videos
            .where((item) => item.category == categories[selected])
            .toList()
          ..sort(
            (a, b) => _oldestFirst
                ? a.uploadedAt.compareTo(b.uploadedAt)
                : b.uploadedAt.compareTo(a.uploadedAt),
          );
    return _Page(
      header: _Header(
        eyebrow: 'PLAYBACK',
        title: 'VIDEOS',
        action: PopupMenuButton<bool>(
          tooltip: '영상 정렬',
          initialValue: _oldestFirst,
          onSelected: (value) => setState(() => _oldestFirst = value),
          itemBuilder: (context) => const [
            PopupMenuItem(value: false, child: Text('최신 업로드순')),
            PopupMenuItem(value: true, child: Text('오래된 업로드순')),
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
            child: _VideoTile(video: video),
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

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lockerControllerProvider);
    final gameUser = ref.watch(authControllerProvider).user!;
    final isAdmin = gameUser.canAdminister;
    final selected = state.gameSegment;
    final selectedSub = state.gameSubSegment;
    final categories = switch (selected) {
      0 => const [
        ('아농', EventKind.morning),
        ('자개', EventKind.freeOpen),
        ('픽업게임', EventKind.pickup),
      ],
      1 => const [('1부', EventKind.ibDivision1), ('2부', EventKind.ibDivision2)],
      _ => const [('연습 경기', EventKind.scrimmage), ('삼파전', EventKind.threeWay)],
    };
    final filtered = state.events.where((event) {
      return event.kind == categories[selectedSub].$2 &&
          !event.end.isBefore(DateTime.now());
    }).toList();
    return _Page(
      header: const _Header(eyebrow: 'GAME DAY', title: 'GAME'),
      children: [
        _SlidingTabBar(
          labels: const ['내부', 'IB', '외부'],
          selectedIndex: selected,
          onSelected: ref
              .read(lockerControllerProvider.notifier)
              .selectGameSegment,
        ),
        const SizedBox(height: 12),
        _SlidingTabBar(
          labels: categories.map((category) => category.$1).toList(),
          selectedIndex: selectedSub,
          onSelected: ref
              .read(lockerControllerProvider.notifier)
              .selectGameSubSegment,
        ),
        const SizedBox(height: 20),
        if (filtered.isEmpty)
          _EmptyState(
            icon: Icons.sports_basketball_outlined,
            title: '예정된 경기가 없습니다',
            action: isAdmin ? '경기 추가' : null,
            onTap: isAdmin ? () => _openEditor(context) : null,
          )
        else
          ...filtered.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: EventTicket(
                event: event,
                heroTag: 'games-${event.id}',
                onTap: () =>
                    openEventDetail(context, event, heroTagPrefix: 'games'),
              ),
            ),
          ),
      ],
    );
  }
}

class _SlidingTabBar extends StatelessWidget {
  const _SlidingTabBar({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.icons,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Container(
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE7ECF3),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD2DAE5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: labels.asMap().entries.map((entry) {
          final selected = entry.key == selectedIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: entry.key == labels.length - 1 ? 0 : 3,
              ),
              child: Semantics(
                selected: selected,
                button: true,
                label: entry.value,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelected(entry.key),
                    child: AnimatedContainer(
                      duration: motion,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: selected ? EncbaColors.deepBlue : Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: selected
                            ? const [
                                BoxShadow(
                                  color: Color(0x260B2347),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icons != null) ...[
                                Icon(
                                  icons![entry.key],
                                  size: 17,
                                  color: selected
                                      ? Colors.white
                                      : EncbaColors.ink,
                                ),
                                const SizedBox(width: 5),
                              ],
                              AnimatedDefaultTextStyle(
                                duration: motion,
                                style: TextStyle(
                                  fontFamily: encbaFontFor(entry.value),
                                  fontFamilyFallback: encbaFontFallback,
                                  fontSize: 14,
                                  color: selected
                                      ? Colors.white
                                      : EncbaColors.ink,
                                ),
                                child: Text(entry.value, maxLines: 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

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
    final locker = ref.watch(lockerControllerProvider);
    final allEvents = [...locker.plannerEvents]
      ..sort((a, b) => a.start.compareTo(b.start));
    final user = ref.watch(authControllerProvider).user!;
    final today = DateUtils.dateOnly(DateTime.now());
    final futureEvents = allEvents
        .where((event) => !DateUtils.dateOnly(event.start).isBefore(today))
        .toList();
    final visible = futureEvents.take(_visibleCount).toList();
    final canRevealMore = visible.length < futureEvents.length;
    final canLoadMore = canRevealMore || locker.hasMoreEvents;

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
                  icon: const Icon(Icons.add_circle_outline_rounded),
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
          _SectionHeader(title: '오늘 이후 일정 ${futureEvents.length}'),
          const SizedBox(height: 11),
          if (visible.isEmpty)
            const _EmptyState(
              icon: Icons.event_available_outlined,
              title: '예정된 일정이 없습니다',
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
                    onTap: () => openEventDetail(
                      context,
                      event,
                      heroTagPrefix: 'schedule',
                    ),
                  ),
                ),
              ];
            }),
          if (locker.isLoadingMoreEvents)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
    final futureEvents = events
        .where((event) => !DateUtils.dateOnly(event.start).isBefore(today))
        .toList();
    final targetIndex = futureEvents.indexWhere(
      (event) => DateUtils.isSameDay(event.start, date),
    );
    setState(() {
      _selectedDate = DateUtils.dateOnly(date);
      _visibleMonth = DateTime(date.year, date.month);
      if (targetIndex >= 0) {
        _visibleCount = math.max(_visibleCount, ((targetIndex ~/ 10) + 1) * 10);
      }
    });
    if (targetIndex < 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('이 날짜에는 일정이 없습니다.')));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToDate(date, targetIndex, futureEvents.length));
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

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final locker = ref.watch(lockerControllerProvider);
    final rates = locker.attendanceRates;
    return _Page(
      header: _Header(
        eyebrow: 'MY LOCKER',
        title: 'PERSONAL',
        action: IconButton(
          tooltip: '로그아웃',
          onPressed: () => _confirmSignOut(context, ref),
          icon: const Icon(Icons.logout_rounded),
        ),
      ),
      children: [
        _ProfileCard(
          name: user.visibleName,
          meta:
              '${user.studentId} · ${user.joinedYear == null ? '가입 연도 미등록' : '${user.joinedYear} 가입'} · #${user.jerseyNumber} ${user.position}',
          teamLabel: user.teamLabel,
          badge: user.badge,
          photoBase64: user.photoBase64,
          leadershipLabel: user.leadershipLabel,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
          ),
        ),
        const SizedBox(height: 12),
        _StatsStrip(rates: rates),
        const SizedBox(height: 24),
        const _SectionHeader(title: '내 메뉴'),
        const SizedBox(height: 10),
        _MenuTile(
          icon: Icons.notifications_active_outlined,
          title: kIsWeb ? '웹 알림 켜기' : '앱 알림 켜기',
          subtitle: kIsWeb ? '브라우저가 열려 있을 때 공지 알림' : 'iOS 알림 센터로 공지 알림',
          onTap: () async {
            final enabled = await WebNotificationService().enableAndTest();
            if (enabled) {
              ref
                  .read(lockerControllerProvider.notifier)
                  .refreshUndecidedReminders();
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    enabled
                        ? (kIsWeb ? '웹 알림을 켰습니다.' : '앱 알림을 켰습니다.')
                        : (kIsWeb ? '브라우저 알림 권한이 필요합니다.' : 'iOS 알림 권한이 필요합니다.'),
                  ),
                ),
              );
            }
          },
        ),
        _MenuTile(
          icon: Icons.groups_2_outlined,
          title: user.canAdminister ? '계정 및 멤버 관리' : '멤버 디렉토리',
          subtitle: user.canAdminister ? '계정 정보·직책·활성 상태 관리' : '재학·군 휴학 상태 확인',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MemberDirectoryScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.bug_report_outlined,
          title: '오류 제보',
          subtitle: '발생한 문제를 개발자에게 보내기',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BugReportScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.assignment_outlined,
          title: 'IB 운영 일정',
          subtitle: '학기 초 업로드된 엑셀 기준',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OperationsScreen()),
          ),
        ),
        if (user.leadershipRole == 'admin')
          _MenuTile(
            icon: Icons.science_outlined,
            title: '테스트 일정 만들기',
            subtitle: '훈련·IB·자개·연습 경기 등 8개 샘플',
            onTap: () async {
              final approved = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('테스트 일정을 만들까요?'),
                  content: const Text('실제 일정 DB에 테스트 표시가 붙은 샘플을 추가합니다.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('추가'),
                    ),
                  ],
                ),
              );
              if (approved != true || !context.mounted) return;
              final count = await ref
                  .read(lockerControllerProvider.notifier)
                  .createDemoEvents();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    count == 0 ? '이미 테스트 일정이 있습니다.' : '$count개를 추가했습니다.',
                  ),
                ),
              );
            },
          ),
        _MenuTile(
          icon: Icons.celebration_outlined,
          title: '홈커밍 연락 보드',
          subtitle: locker.homecomingCampaign == null
              ? '관리자가 이번 학기 이벤트를 열기 전입니다'
              : '${locker.homecomingCampaign!.eventDate.month}.${locker.homecomingCampaign!.eventDate.day} 진행',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HomecomingScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.history_rounded,
          title: '수정 이력',
          subtitle: '공지와 일정의 변경 기록',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AuditLogScreen()),
          ),
        ),
      ],
    );
  }
}

class BugReportScreen extends ConsumerStatefulWidget {
  const BugReportScreen({super.key});

  @override
  ConsumerState<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends ConsumerState<BugReportScreen> {
  final _controller = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('오류 제보')),
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '어떤 문제가 있었나요?',
              style: TextStyle(
                fontFamily: 'Jua',
                fontSize: 27,
                color: EncbaColors.navy,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '작성자와 실행 환경은 메일 본문에 자동으로 포함됩니다.',
              style: TextStyle(color: EncbaColors.muted),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                scrollPadding: const EdgeInsets.only(bottom: 120),
                decoration: const InputDecoration(
                  hintText: '오류가 난 화면과 직전에 한 행동을 적어 주세요.',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _opening ? null : _openMail,
              icon: _opening
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.mail_outline_rounded),
              label: Text(_opening ? '메일 앱을 여는 중…' : '오류 제보 메일 열기'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _openMail() async {
    final report = _controller.text.trim();
    if (report.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('오류 내용을 입력해 주세요.')));
      return;
    }
    setState(() => _opening = true);
    final user = ref.read(authControllerProvider).user;
    final body =
        '''작성자: ${user?.visibleName ?? '확인 불가'}
학번: ${user?.studentId ?? '확인 불가'}
계정: ${user?.email ?? '확인 불가'}
실행 환경: ${kIsWeb ? '웹' : defaultTargetPlatform.name}

[오류 내용]
$report''';
    final uri = Uri(
      scheme: 'mailto',
      path: 'legojmon@snu.ac.kr',
      queryParameters: {'subject': 'ENCBA LOCKER 오류 제보', 'body': body},
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    setState(() => _opening = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? '메일 내용을 채웠습니다. 확인 후 보내 주세요.'
              : '메일 앱을 열지 못했습니다. legojmon@snu.ac.kr로 보내 주세요.',
        ),
      ),
    );
  }
}

class MemberDirectoryScreen extends ConsumerStatefulWidget {
  const MemberDirectoryScreen({super.key});

  @override
  ConsumerState<MemberDirectoryScreen> createState() =>
      _MemberDirectoryScreenState();
}

class _MemberDirectoryScreenState extends ConsumerState<MemberDirectoryScreen> {
  String query = '';
  int _searchRevision = 0;
  _MemberSort _sort = _MemberSort.studentYear;
  bool _showMilitary = false;
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final locker = ref.watch(lockerControllerProvider);
    final isAdmin =
        ref.watch(authControllerProvider).user?.leadershipRole == 'admin';
    final list = locker.members.where((member) {
      if (!_showMilitary && member.status == 'MILITARY_LEAVE') return false;
      if (!_showInactive && !member.isActive) return false;
      return true;
    }).toList()..sort(_compareMembers);
    return Scaffold(
      appBar: AppBar(title: const Text('멤버 디렉토리')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          TextField(
            onChanged: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '이름, 학번, 포지션 검색',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.sort_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<_MemberSort>(
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: '정렬'),
                  items: const [
                    DropdownMenuItem(
                      value: _MemberSort.studentYear,
                      child: Text('학번순'),
                    ),
                    DropdownMenuItem(
                      value: _MemberSort.name,
                      child: Text('가나다순'),
                    ),
                    DropdownMenuItem(
                      value: _MemberSort.joinedYear,
                      child: Text('가입 연도순'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _sort = value ?? _sort),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('군 휴학 멤버 표시'),
                selected: _showMilitary,
                onSelected: (value) => setState(() => _showMilitary = value),
              ),
              if (isAdmin)
                FilterChip(
                  label: const Text('비활성 계정 표시'),
                  selected: _showInactive,
                  onSelected: (value) => setState(() => _showInactive = value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (list.isEmpty)
            const _EmptyState(
              icon: Icons.group_off_outlined,
              title: '조건에 맞는 멤버가 없습니다',
            )
          else
            ...list.map(
              (member) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemberTile(
                  member: member,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MemberDetailScreen(member: member),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _compareMembers(MemberProfile a, MemberProfile b) {
    int byName() => a.name.compareTo(b.name);
    switch (_sort) {
      case _MemberSort.name:
        return byName();
      case _MemberSort.studentYear:
        final left = _studentYearOf(a);
        final right = _studentYearOf(b);
        final result = left.compareTo(right);
        return result != 0 ? result : byName();
      case _MemberSort.joinedYear:
        final result = (a.joinedYear ?? 9999).compareTo(b.joinedYear ?? 9999);
        return result != 0 ? result : byName();
    }
  }

  int _studentYearOf(MemberProfile member) =>
      int.tryParse(member.studentId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 999;

  Future<void> _search(String value) async {
    query = value.trim();
    final revision = ++_searchRevision;
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || revision != _searchRevision) return;
    await ref.read(lockerControllerProvider.notifier).searchMembers(query);
  }
}

enum _MemberSort { studentYear, name, joinedYear }

class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.member});
  final MemberProfile member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('멤버 정보')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: _Avatar(name: member.name, size: 88)),
          const SizedBox(height: 16),
          Text(
            member.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 5),
          Text(
            '${member.studentId} · ${member.joinedYear == null ? '가입 연도 미등록' : '${member.joinedYear} 가입'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: EncbaColors.muted),
          ),
          const SizedBox(height: 22),
          Card(
            child: Column(
              children: [
                if (member.leadershipLabel != null)
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('직책'),
                    trailing: _SmallBadge(member.leadershipLabel!),
                  ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('소속'),
                  trailing: Text(member.teamLabel),
                ),
                ListTile(
                  leading: Icon(
                    member.status == 'MILITARY_LEAVE'
                        ? Icons.military_tech_outlined
                        : Icons.school_outlined,
                  ),
                  title: const Text('상태'),
                  trailing: Text(
                    member.status == 'MILITARY_LEAVE' ? '군 휴학' : '재학',
                  ),
                ),
                if (isAdmin && member.id != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.edit_note_rounded),
                    title: const Text('정보 및 직책 수정'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showMemberEditor(context, ref, member),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    value: member.isActive,
                    secondary: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('계정 활성화'),
                    subtitle: Text(member.isActive ? '로그인 가능' : '로그인 차단'),
                    onChanged: (value) async {
                      final saved = await ref
                          .read(lockerControllerProvider.notifier)
                          .setMemberActive(member, value);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              saved ? '계정 상태를 변경했습니다.' : '변경하지 못했습니다.',
                            ),
                          ),
                        );
                        if (saved) Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showMemberEditor(
  BuildContext context,
  WidgetRef ref,
  MemberProfile member,
) async {
  final name = TextEditingController(text: member.name);
  final studentYear = TextEditingController(
    text: member.studentId.replaceAll(RegExp(r'[^0-9]'), ''),
  );
  final joinedYear = TextEditingController(
    text: member.joinedYear?.toString() ?? '',
  );
  final phone = TextEditingController(text: member.phone);
  final jersey = TextEditingController(text: member.jerseyNumber.toString());
  var position = member.position;
  var status = member.status;
  var role = member.leadershipRole;
  var isActive = member.isActive;
  var teams = {...member.teams};

  final save = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '멤버 정보 수정',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '실명'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: studentYear,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '학번'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: joinedYear,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '엔크바 가입 년도',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '전화번호'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: position,
                        decoration: const InputDecoration(labelText: '포지션'),
                        items: const ['PG', 'SG', 'SF', 'PF', 'C', '미정']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => position = value ?? position,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: jersey,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '등번호'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '직책'),
                  items:
                      const {
                            'member': '부원',
                            'manager': '매니저',
                            'captain': '주장',
                            'admin': '관리자',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => role = value ?? role,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '상태'),
                  items:
                      const {
                            'YB': '재학',
                            'OB': 'OB',
                            'MILITARY_LEAVE': '군 휴학',
                            'GRADUATED': '졸업',
                            'INACTIVE': '비활동',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => status = value ?? status,
                ),
                const SizedBox(height: 8),
                const Text('소속'),
                Wrap(
                  spacing: 8,
                  children: ['ENCBA', 'BEN'].map((team) {
                    return FilterChip(
                      label: Text(team),
                      selected: teams.contains(team),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          teams.add(team);
                        } else if (teams.length > 1) {
                          teams.remove(team);
                        }
                      }),
                    );
                  }).toList(),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  title: const Text('계정 활성화'),
                  onChanged: (value) => setState(() => isActive = value),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final joined = int.tryParse(joinedYear.text.trim());
                    final number = int.tryParse(jersey.text.trim());
                    if (name.text.trim().isEmpty ||
                        joined == null ||
                        joined < 1977 ||
                        number == null ||
                        number < 0 ||
                        number > 99) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('이름, 가입 년도, 등번호를 확인해 주세요.'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text('변경 사항 저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (save == true) {
    final updated = member.copyWith(
      name: name.text.trim(),
      studentId: '${studentYear.text.trim()}학번',
      joinedYear: int.parse(joinedYear.text.trim()),
      phone: phone.text.trim(),
      position: position,
      jerseyNumber: int.parse(jersey.text.trim()),
      status: status,
      teams: teams.toList()..sort(),
      leadershipRole: role,
      isActive: isActive,
    );
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .updateMember(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved ? '멤버 정보를 수정했습니다.' : '수정하지 못했습니다.')),
      );
      if (saved) Navigator.pop(context);
    }
  }
  name.dispose();
  studentYear.dispose();
  joinedYear.dispose();
  phone.dispose();
  jersey.dispose();
}

class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(lockerControllerProvider.notifier).refreshOperationSwaps(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locker = ref.watch(lockerControllerProvider);
    final operations = locker.operations;
    final pendingRequests = locker.operationSwapRequests
        .where((request) => request.status == 'pending')
        .toList(growable: false);
    final exchangeTargets = locker.operationExchangeBoard
        .where((assignment) => !assignment.isMine)
        .toList(growable: false);
    final isAdmin =
        ref.watch(authControllerProvider).user?.leadershipRole == 'admin';
    return Scaffold(
      appBar: AppBar(
        title: const Text('IB 운영 일정'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'IB 운영표 엑셀 가져오기',
              onPressed: _importing ? null : _importExcel,
              icon: _importing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (pendingRequests.isNotEmpty) ...[
            const Text(
              '교환 요청',
              style: TextStyle(
                fontFamily: 'Jua',
                fontSize: 27,
                color: EncbaColors.navy,
              ),
            ),
            const SizedBox(height: 12),
            ...pendingRequests.map(_swapRequestCard),
            const SizedBox(height: 24),
          ],
          const Text(
            '내가 맡은 일',
            style: TextStyle(
              fontFamily: 'Jua',
              fontSize: 27,
              color: EncbaColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          if (operations.isEmpty)
            const _EmptyState(
              icon: Icons.assignment_outlined,
              title: '배정된 운영 일정이 없습니다',
            )
          else
            ...operations.map(
              (item) => _TaskTile(
                date: '${item.start.month}.${item.start.day}',
                title: item.title,
                place: '${time(item.start)} · ${item.location}',
                onTap: () => _showTask(context, item.memo),
              ),
            ),
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '교환 가능한 운영',
                  style: TextStyle(
                    fontFamily: 'Jua',
                    fontSize: 27,
                    color: EncbaColors.navy,
                  ),
                ),
              ),
              IconButton(
                tooltip: '새로고침',
                onPressed: () => ref
                    .read(lockerControllerProvider.notifier)
                    .refreshOperationSwaps(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '상대 일정을 고른 뒤 내 일정과 맞교환을 신청합니다.',
            style: TextStyle(color: EncbaColors.muted),
          ),
          const SizedBox(height: 12),
          if (exchangeTargets.isEmpty)
            const _EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: '교환 가능한 운영 일정이 없습니다',
            )
          else
            ...exchangeTargets
                .take(40)
                .map(
                  (item) => _TaskTile(
                    date: '${item.start.month}.${item.start.day}',
                    title: '${item.title} · ${item.assigneeName}',
                    place: '${time(item.start)} · ${item.location}',
                    onTap: () => _requestSwap(item),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _swapRequestCard(OperationSwapRequest request) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: request.incoming ? const Color(0xFFFFF5DF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: EncbaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.incoming
              ? '${request.counterpartName}님의 교환 신청'
              : '${request.counterpartName}님에게 보낸 신청',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 7),
        Text(
          '${request.requesterTitle} ↔ ${request.targetTitle}',
          style: const TextStyle(color: EncbaColors.navy),
        ),
        if (request.message.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(request.message),
        ],
        if (request.incoming) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respondSwap(request, false),
                  child: const Text('거절'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _respondSwap(request, true),
                  child: const Text('교환 수락'),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Future<void> _requestSwap(OperationAssignment target) async {
    final own = ref.read(lockerControllerProvider).operations;
    if (own.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('교환할 내 운영 일정이 없습니다.')));
      return;
    }
    var selectedId = own.first.id;
    final message = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('IB 운영 교환 신청'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${target.assigneeName} · ${target.start.month}.${target.start.day} ${time(target.start)}',
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '교환할 내 일정'),
                  items: own
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            '${item.start.month}.${item.start.day} ${time(item.start)} · ${item.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedId = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '메시지',
                    hintText: '교환을 부탁하는 이유를 적어 주세요. (선택)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('신청 보내기'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      message.dispose();
      return;
    }
    final typedMessage = message.text.trim();
    message.dispose();
    if (approved != true) return;
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .requestOperationSwap(
          ownAssignmentId: selectedId,
          targetAssignmentId: target.id,
          message: typedMessage,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? 'IB 운영 교환 신청을 보냈습니다.' : '교환 신청을 보내지 못했습니다.'),
      ),
    );
  }

  Future<void> _respondSwap(OperationSwapRequest request, bool accept) async {
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .respondOperationSwap(requestId: request.id, accept: accept);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? accept
                    ? 'IB 운영 일정이 교환되었습니다.'
                    : '교환 요청을 거절했습니다.'
              : '교환 응답을 저장하지 못했습니다.',
        ),
      ),
    );
  }

  Future<void> _importExcel() async {
    setState(() => _importing = true);
    try {
      final parsed = await IbOperationImportService().pickAndParse();
      if (!mounted || parsed == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${parsed.academicYear}-${parsed.term} IB 운영표'),
          content: Text(
            '${parsed.dateCount}개 날짜에서 ${parsed.rows.length}건을 읽었습니다.\n\n'
            '같은 학기의 기존 엑셀 배정은 교체됩니다. 표에 시간이 없는 경우 '
            '1경기 11시, 2경기 13시, 3경기 15시로 적용합니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('가져오기'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final result = await ref
          .read(lockerControllerProvider.notifier)
          .importOperations(
            fileName: parsed.fileName,
            academicYear: parsed.academicYear,
            term: parsed.term,
            assignments: parsed.rows,
          );
      if (!mounted) return;
      final message = result == null
          ? 'IB 운영표를 가져오지 못했습니다.'
          : '${result.imported}건 저장 · 계정 미연결 ${result.unmatched}건';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('엑셀 파일을 읽지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class HomecomingScreen extends ConsumerStatefulWidget {
  const HomecomingScreen({super.key});
  @override
  ConsumerState<HomecomingScreen> createState() => _HomecomingScreenState();
}

class _HomecomingScreenState extends ConsumerState<HomecomingScreen> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        ref.watch(authControllerProvider).user?.canAdminister ?? false;
    final state = ref.watch(lockerControllerProvider);
    final campaign = state.homecomingCampaign;
    final contacts = state.homecomingContacts;
    final complete = contacts.where((item) => item.handled).length;
    return Scaffold(
      appBar: AppBar(title: const Text('홈커밍 연락 보드')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (campaign == null) ...[
            const SizedBox(height: 70),
            const Icon(
              Icons.lock_outline_rounded,
              size: 42,
              color: EncbaColors.muted,
            ),
            const SizedBox(height: 16),
            Text(
              '홈커밍 준비 기간이 아닙니다',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '관리자가 이번 학기 캠페인을 열면 연락 보드가 활성화됩니다.',
              textAlign: TextAlign.center,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _activateCampaign,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('이번 학기 홈커밍 열기'),
              ),
            ],
          ] else ...[
            Text(campaign.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${campaign.eventDate.month}월 ${campaign.eventDate.day}일 · ${campaign.startsAt.substring(0, 5)}–${campaign.endsAt.substring(0, 5)} · ${campaign.venue}',
            ),
            const SizedBox(height: 18),
            Text(
              '$complete / ${contacts.length} 응답 처리',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: contacts.isEmpty ? 0 : complete / contacts.length,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showManuals,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('연락 매뉴얼'),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _importing ? null : _importExcel,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(_importing ? '가져오는 중…' : '엑셀 가져오기'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            ...contacts.map(
              (contact) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${contact.name} 선배',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                    ),
                                  ),
                                  Text(
                                    '${contact.generation == null ? '학번 미상' : '${contact.generation}학번'} · ${contact.phone}',
                                    style: const TextStyle(
                                      color: EncbaColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '전화',
                              onPressed: () => _launch('tel:${contact.phone}'),
                              icon: const Icon(Icons.phone_outlined),
                            ),
                            IconButton(
                              tooltip: '문자',
                              onPressed: () => _sendSms(contact, campaign),
                              icon: const Icon(Icons.sms_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: contact.status,
                          decoration: const InputDecoration(labelText: '응답 상태'),
                          items: const [
                            DropdownMenuItem(
                              value: 'pending',
                              child: Text('미연락'),
                            ),
                            DropdownMenuItem(
                              value: 'contacted',
                              child: Text('미정 · 재연락'),
                            ),
                            DropdownMenuItem(
                              value: 'confirmed',
                              child: Text('참석'),
                            ),
                            DropdownMenuItem(
                              value: 'declined',
                              child: Text('불참'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _saveContact(
                                contact.copyWith(
                                  status: value,
                                  followUpAllowed: value == 'contacted'
                                      ? true
                                      : contact.followUpAllowed,
                                  followUpOn: value == 'contacted'
                                      ? DateTime.now().add(
                                          const Duration(days: 7),
                                        )
                                      : contact.followUpOn,
                                ),
                              );
                            }
                          },
                        ),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: contact.parkingRequired ?? false,
                          title: const Text('주차권 필요'),
                          onChanged: (value) => _saveContact(
                            contact.copyWith(parkingRequired: value),
                          ),
                        ),
                        if (contact.parkingRequired == true)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: contact.parkingRegistered,
                            title: const Text('주차권 처리 완료'),
                            onChanged: (value) => _saveContact(
                              contact.copyWith(parkingRegistered: value),
                            ),
                          ),
                        if (contact.followUpOn != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '다시 연락: ${contact.followUpOn!.month}.${contact.followUpOn!.day}',
                              style: const TextStyle(color: EncbaColors.late),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _editContactNotes(contact),
                            icon: const Icon(Icons.edit_note_rounded),
                            label: Text(
                              contact.notes?.trim().isNotEmpty == true
                                  ? '기록 보기'
                                  : '메모 추가',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveContact(HomecomingContact contact) async {
    await ref
        .read(lockerControllerProvider.notifier)
        .updateHomecomingContact(contact);
  }

  Future<void> _editContactNotes(HomecomingContact contact) async {
    var notes = contact.notes ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${contact.name} 선배 연락 기록'),
        content: TextFormField(
          initialValue: notes,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          maxLength: 2000,
          onChanged: (value) => notes = value,
          decoration: const InputDecoration(hintText: '통화·답장 내용을 기록해 주세요.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, notes.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (value != null) await _saveContact(contact.copyWith(notes: value));
  }

  Future<void> _activateCampaign() async {
    final now = DateTime.now();
    final term = now.month >= 9 ? 2 : 1;
    final eventDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (eventDate == null || !mounted) return;
    await ref
        .read(lockerControllerProvider.notifier)
        .activateHomecomingCampaign(
          academicYear: now.year,
          term: term,
          eventDate: eventDate,
          startsAt: '14:00',
          endsAt: '18:00',
          venue: '서울대학교 기숙사체육관',
        );
  }

  Future<void> _importExcel() async {
    setState(() => _importing = true);
    try {
      final parsed = await HomecomingImportService().pickAndParse();
      if (parsed == null || !mounted) return;
      final ok = await ref
          .read(lockerControllerProvider.notifier)
          .importHomecomingContacts(
            fileName: parsed.fileName,
            contacts: parsed.rows,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? '${parsed.rows.length}명을 가져왔습니다.' : '가져오지 못했습니다.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _sendSms(
    HomecomingContact contact,
    HomecomingCampaign campaign,
  ) async {
    final user = ref.read(authControllerProvider).user!;
    final studentYear = user.studentId.replaceAll('학번', '');
    final body =
        '${contact.name} 선배님 안녕하십니까? 서울대학교 공대농구동아리 엔크바 $studentYear학번 ${user.name}입니다.\n'
        '다름이 아니라, 이번 ${campaign.term}학기 엔크바 홈커밍 데이가 ${campaign.eventDate.month}월 ${campaign.eventDate.day}일에 예정되어 있습니다. 참석 확인 차 전화드렸는데 연락이 안되셔서 문자 드립니다.\n'
        '혹시 홈커밍 데이 때 참석 가능하실까요?\n\n감사합니다.';
    final uri = Uri(
      scheme: 'sms',
      path: contact.phone,
      queryParameters: {'body': body},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showManuals() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(22),
          children: const [
            Text('전화 매뉴얼', style: TextStyle(fontFamily: 'Jua', fontSize: 25)),
            SizedBox(height: 12),
            SelectableText(
              '안녕하세요, 혹시 XXX 선배님 맞으십니까?\n선배님 안녕하십니까, 서울대학교 공대 농구동아리 엔크바 XX학번 XXX입니다.\n다름이 아니라 이번 엔크바 홈커밍 데이가 예정되어 있습니다. 혹시 참석 가능하십니까?\n\n참석: 감사합니다 선배님. 그때 뵙겠습니다. 주차권이 필요하신지, 행사 일주일 전에 다시 연락드려도 되는지 여쭤봅니다.\n\n미정: 다음 주에 다시 확인전화 드려도 괜찮으신지 여쭤봅니다.\n\n불참: 다음 홈커밍 행사에서는 꼭 뵈었으면 좋겠습니다. 감사합니다.\n\n회식 장소: 현재 물색 중이며 확정되는 대로 안내드립니다.',
            ),
            SizedBox(height: 24),
            Text('답장 매뉴얼', style: TextStyle(fontFamily: 'Jua', fontSize: 25)),
            SizedBox(height: 12),
            SelectableText(
              '장소/시간: 서울대학교 기숙사체육관에서 진행되며 이후 뒷풀이 예정입니다.\n\n참석: 감사합니다 선배님. 주차권이 필요한지 여쭤보고 일주일 전 확인 연락 동의를 받습니다.\n\n불참: 다음 홈커밍 데이에는 꼭 뵈었으면 좋겠습니다.\n\n회식: 아직 정해지지 않았고 밴드 공지 후 안내드립니다.',
            ),
          ],
        ),
      ),
    );
  }
}

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(lockerControllerProvider).auditEntries;
    return Scaffold(
      appBar: AppBar(title: const Text('수정 이력')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: entries
            .map(
              (entry) => _AuditItem(
                icon: entry.table == 'events'
                    ? Icons.edit_calendar_outlined
                    : entry.table == 'announcements'
                    ? Icons.campaign_outlined
                    : Icons.play_circle_outline_rounded,
                title:
                    '${_auditTableLabel(entry.table)} ${_auditActionLabel(entry.action)}',
                author: '${entry.actor} · ${_relativeTime(entry.createdAt)}',
                detail:
                    '변경 시각 ${entry.createdAt.month}.${entry.createdAt.day} ${time(entry.createdAt)}',
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.header,
    required this.children,
    this.controller,
    this.scrollKey,
  });
  final Widget header;
  final List<Widget> children;
  final ScrollController? controller;
  final Key? scrollKey;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      key: scrollKey,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [header, const SizedBox(height: 22), ...children],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.eyebrow, required this.title, this.action});
  final String eyebrow;
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: TextStyle(
                fontFamily: encbaFontFor(eyebrow),
                color: EncbaColors.snuBlue,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontFamily: encbaFontFor(title, display: true),
              ),
            ),
          ],
        ),
      ),
      ?action,
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice, required this.onTap});
  final AnnouncementItem notice;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: EncbaColors.late.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.campaign_outlined, color: EncbaColors.late),
      ),
      title: Text(
        notice.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${notice.author} · ${_relativeTime(notice.publishedAt)}'),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _VideoTile extends ConsumerWidget {
  const _VideoTile({required this.video});
  final VideoItem video;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref
        .watch(lockerControllerProvider)
        .likedVideoIds
        .contains(video.id);
    void open() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _VideoDetailScreen(video: video)),
    );
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
    if (thumbnail == null) return fallback();
    return Image.network(
      thumbnail,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback(),
      errorBuilder: (_, _, _) => fallback(),
    );
  }
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

class _VideoDetailScreen extends ConsumerStatefulWidget {
  const _VideoDetailScreen({required this.video});
  final VideoItem video;

  @override
  ConsumerState<_VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends ConsumerState<_VideoDetailScreen> {
  YoutubePlayerController? _player;
  final _comment = TextEditingController();
  String _capturedTimestamp = '00:00';
  Timer? _watchTimer;
  int _lastPositionSeconds = 0;

  VideoItem get video => widget.video;

  @override
  void initState() {
    super.initState();
    if (video.youtubeId.isNotEmpty) {
      _player = YoutubePlayerController.fromVideoId(
        videoId: video.youtubeId,
        autoPlay: false,
        params: const YoutubePlayerParams(showFullscreenButton: true),
      );
    }
    if (video.category == '복기') {
      Future.microtask(
        () => ref
            .read(lockerControllerProvider.notifier)
            .loadVideoComments(video.id),
      );
    }
    final user = ref.read(authControllerProvider).user;
    if (user?.canAdminister == true ||
        video.uploader == user?.visibleName ||
        video.uploader == user?.name) {
      Future.microtask(
        () => ref
            .read(lockerControllerProvider.notifier)
            .loadVideoWatchSummary(video.id),
      );
    }
    _watchTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _recordWatch(),
    );
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    unawaited(_recordWatch());
    _comment.dispose();
    _player?.close();
    super.dispose();
  }

  Future<void> _recordWatch() async {
    final player = _player;
    if (player == null) return;
    final values = await Future.wait([player.currentTime, player.duration]);
    final current = values[0].round();
    final duration = values[1].round();
    final delta = (current - _lastPositionSeconds).abs();
    _lastPositionSeconds = current;
    if (delta <= 0 || delta > 15) return;
    await ref
        .read(lockerControllerProvider.notifier)
        .recordVideoWatch(
          videoId: video.id,
          watchedSeconds: delta,
          lastPositionSeconds: current,
          completed: duration > 0 && current >= duration - 5,
        );
  }

  Future<void> _captureTimestamp() async {
    final player = _player;
    if (player == null) return;
    final seconds = await player.currentTime;
    if (!mounted) return;
    setState(() => _capturedTimestamp = _formatTimestamp(seconds));
  }

  Future<void> _addComment() async {
    final value = _comment.text.trim();
    if (value.isEmpty) return;
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .addVideoComment(
          videoId: video.id,
          timestampSeconds: _timestampToSeconds(_capturedTimestamp).round(),
          body: value,
        );
    if (mounted && saved) _comment.clear();
  }

  @override
  Widget build(BuildContext context) {
    final locker = ref.watch(lockerControllerProvider);
    final liked = locker.likedVideoIds.contains(video.id);
    final current = locker.videos
        .where((item) => item.id == video.id)
        .firstOrNull;
    final comments = locker.videoComments[video.id] ?? const [];
    final user = ref.watch(authControllerProvider).user;
    final canManage = _canManageVideo(user, current ?? video);
    final canSeeWatch =
        user?.canAdminister == true ||
        video.uploader == user?.visibleName ||
        video.uploader == user?.name;
    final watchSummary =
        locker.videoWatchSummaries[video.id] ?? const <VideoWatchSummary>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(video.category),
        actions: canManage
            ? [
                IconButton(
                  tooltip: '영상 수정',
                  onPressed: () => _showVideoEditor(
                    context,
                    ref,
                    video.category,
                    existing: current ?? video,
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
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          if (_player case final player?)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: YoutubePlayer(controller: player, aspectRatio: 16 / 9),
            )
          else
            InkWell(
              onTap: () => _launch(video.url),
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF833AB4), Color(0xFFF77737)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
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
                ),
              ),
            ),
          if (video.category == '복기' &&
              video.quarterUrls.any((url) => url?.isNotEmpty == true)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: video.quarterUrls.indexed
                  .where((entry) => entry.$2?.isNotEmpty == true)
                  .map(
                    (entry) => OutlinedButton(
                      onPressed: () {
                        final id = _youtubeIdFrom(entry.$2!);
                        if (id != null) _player?.loadVideoById(videoId: id);
                      },
                      child: Text('${entry.$1 + 1}쿼터'),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 18),
          Text(video.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${video.uploader} · ${_relativeTime(video.uploadedAt)}',
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
              Text('${current?.likeCount ?? video.likeCount}'),
            ],
          ),
          const SizedBox(height: 16),
          if (video.category == '복기') ...[
            ...comments.map(
              (item) => _Comment(
                timestamp: _formatTimestamp(item.timestampSeconds.toDouble()),
                text: item.body,
                author: item.author,
                onTimestampTap: () => _player?.seekTo(
                  seconds: item.timestampSeconds.toDouble(),
                  allowSeekAhead: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _captureTimestamp,
              icon: const Icon(Icons.timer_outlined),
              label: Text('현재 재생 위치  $_capturedTimestamp'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              onSubmitted: (_) => _addComment(),
              decoration: InputDecoration(
                hintText: '이 장면에 대한 코멘트',
                suffixIcon: IconButton(
                  tooltip: '코멘트 등록',
                  onPressed: _addComment,
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ),
          ],
          if (canSeeWatch) ...[
            const SizedBox(height: 20),
            Text('시청 현황', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (watchSummary.isEmpty)
              const Text(
                '아직 시청 기록이 없습니다.',
                style: TextStyle(color: EncbaColors.muted),
              )
            else
              ...watchSummary.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  trailing: Text(_approximateWatchTime(item)),
                ),
              ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _launch(video.url),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('원본 영상 열기'),
          ),
        ],
      ),
    );
  }
}

String _approximateWatchTime(VideoWatchSummary item) {
  if (item.completed) return '거의 전체';
  final minutes = item.watchedSeconds ~/ 60;
  if (minutes < 1) return '1분 미만';
  if (minutes < 3) return '약 2분';
  final rounded = ((minutes + 2) ~/ 5) * 5;
  return '약 $rounded분';
}

class _Comment extends StatelessWidget {
  const _Comment({
    required this.timestamp,
    required this.text,
    required this.author,
    required this.onTimestampTap,
  });
  final String timestamp;
  final String text;
  final String author;
  final VoidCallback onTimestampTap;
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
      title: Text(text),
      subtitle: Text(author),
    ),
  );
}

String _relativeTime(DateTime value) {
  final elapsed = DateTime.now().difference(value);
  if (elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  if (elapsed.inDays < 1) return '${elapsed.inHours}시간 전';
  if (elapsed.inDays < 7) return '${elapsed.inDays}일 전';
  return '${value.month}.${value.day}';
}

String _formatTimestamp(double seconds) {
  final total = seconds.round().clamp(0, 359999);
  final minutes = total ~/ 60;
  final remainder = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

double _timestampToSeconds(String timestamp) {
  final parts = timestamp.split(':');
  if (parts.length != 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60.0 + (int.tryParse(parts[1]) ?? 0);
}

String _auditTableLabel(String table) => switch (table) {
  'events' => '일정',
  'announcements' => '공지',
  'videos' => '영상',
  'operation_assignments' => 'IB 운영',
  'homecoming_contacts' => '홈커밍',
  _ => table,
};

String _auditActionLabel(String action) => switch (action) {
  'insert' => '등록',
  'update' => '수정',
  'delete' => '삭제',
  _ => action,
};

String _academicLabel(DateTime date) {
  final monthDay = date.month * 100 + date.day;
  if (monthDay >= 301 && monthDay <= 615) return '${date.year} · 1학기';
  if (monthDay >= 901 && monthDay <= 1214) return '${date.year} · 2학기';
  return '${date.year} · 방학';
}

String _dayId(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.meta,
    required this.teamLabel,
    required this.badge,
    required this.photoBase64,
    required this.leadershipLabel,
    required this.onTap,
  });
  final String name;
  final String meta;
  final String teamLabel;
  final String? badge;
  final String? photoBase64;
  final String? leadershipLabel;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            _Avatar(name: name, size: 62, photoBase64: photoBase64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 7),
                        _SmallBadge(badge!),
                      ],
                      if (leadershipLabel != null) ...[
                        const SizedBox(width: 7),
                        _SmallBadge(leadershipLabel!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: const TextStyle(
                      color: EncbaColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    teamLabel,
                    style: const TextStyle(
                      color: EncbaColors.snuBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 20),
          ],
        ),
      ),
    ),
  );
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.rates});
  final AttendanceRates rates;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Stat(value: '${rates.training}%', label: '훈련'),
          const _Rule(),
          _Stat(value: '${rates.morning}%', label: '아농'),
          const _Rule(),
          _Stat(value: '${rates.game}%', label: '경기'),
        ],
      ),
    ),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        leading: Icon(icon, color: EncbaColors.snuBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    ),
  );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onTap});
  final MemberProfile member;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: _Avatar(name: member.name, size: 48),
      title: Row(
        children: [
          Expanded(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            member.studentId,
            style: const TextStyle(color: EncbaColors.snuBlue, fontSize: 11),
          ),
          if (member.leadershipLabel != null) ...[
            const SizedBox(width: 6),
            _SmallBadge(member.leadershipLabel!),
          ] else if (member.badge != null) ...[
            const SizedBox(width: 6),
            _SmallBadge(member.badge!),
          ],
        ],
      ),
      subtitle: Text(
        '${member.status == 'MILITARY_LEAVE' ? '군 휴학' : '재학'} · ${member.teamLabel}${member.joinedYear == null ? '' : ' · ${member.joinedYear} 가입'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SmallBadge(member.isActive ? '활성' : '비활성'),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size, this.photoBase64});
  final String name;
  final double size;
  final String? photoBase64;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: EncbaColors.highlight,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFC9D9EA)),
    ),
    clipBehavior: Clip.antiAlias,
    child: photoBase64 == null
        ? Text(
            name.substring(0, 1),
            style: TextStyle(
              fontFamily: 'Jua',
              fontSize: size * .34,
              color: EncbaColors.deepBlue,
            ),
          )
        : Image.memory(
            base64Decode(photoBase64!),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
  );
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: EncbaColors.late.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: Color(0xFF995A00),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'BlackHanSans',
          fontSize: 22,
          color: EncbaColors.deepBlue,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: EncbaColors.muted),
      ),
    ],
  );
}

class _Rule extends StatelessWidget {
  const _Rule();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: EncbaColors.line);
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.date,
    required this.title,
    required this.place,
    required this.onTap,
  });
  final String date;
  final String title;
  final String place;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: EncbaColors.highlight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            date,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: EncbaColors.deepBlue,
            ),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(place),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    ),
  );
}

class _AuditItem extends StatelessWidget {
  const _AuditItem({
    required this.icon,
    required this.title,
    required this.author,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String author;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: EncbaColors.snuBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    author,
                    style: const TextStyle(
                      color: EncbaColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(detail),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.action,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: EncbaColors.line),
    ),
    child: Column(
      children: [
        Icon(icon, size: 36, color: EncbaColors.muted),
        const SizedBox(height: 10),
        Text(title),
        if (action != null) ...[
          const SizedBox(height: 10),
          TextButton(onPressed: onTap, child: Text(action!)),
        ],
      ],
    ),
  );
}

void _openEditor(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const EventEditorScreen()),
);

void _openNotice(
  BuildContext context,
  AnnouncementItem notice, {
  required WidgetRef ref,
  required bool canManage,
}) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => Scaffold(
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
          Text(notice.body, style: const TextStyle(height: 1.75)),
        ],
      ),
    ),
  ),
);

void _showNotifications(
  BuildContext context,
  WidgetRef ref,
  List<AnnouncementItem> announcements, {
  required bool canManage,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => SafeArea(
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
          const SizedBox(height: 10),
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
                      Navigator.pop(context);
                      _openNotice(
                        context,
                        notice,
                        ref: ref,
                        canManage: canManage,
                      );
                    },
                  ),
                ),
        ],
      ),
    ),
  ),
);

void _showVideoEditor(
  BuildContext context,
  WidgetRef ref,
  String category, {
  VideoItem? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _VideoEditorSheet(category: category, existing: existing),
);

class _VideoEditorSheet extends ConsumerStatefulWidget {
  const _VideoEditorSheet({required this.category, this.existing});
  final String category;
  final VideoItem? existing;

  @override
  ConsumerState<_VideoEditorSheet> createState() => _VideoEditorSheetState();
}

class _VideoEditorSheetState extends ConsumerState<_VideoEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _duration = TextEditingController();
  late final List<TextEditingController> _quarters;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _url.text = existing?.url ?? '';
    _title.text = existing?.title ?? '';
    _duration.text = existing?.durationLabel ?? '';
    _quarters = List.generate(
      4,
      (index) => TextEditingController(
        text: existing?.quarterUrls.elementAtOrNull(index) ?? '',
      ),
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _duration.dispose();
    for (final controller in _quarters) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final isReview = widget.category == '복기';
    final isHighlight = widget.category == '하이라이트';
    final quarterUrls = _quarters.map((item) => item.text.trim()).toList();
    final sourceUrl = isReview
        ? quarterUrls.firstWhere((url) => url.isNotEmpty, orElse: () => '')
        : _url.text.trim();
    final youtubeId = _youtubeIdFrom(sourceUrl);
    final isInstagram = isHighlight && _isInstagramReel(sourceUrl);
    if (youtubeId == null && !isInstagram) return;
    if (isReview) {
      final blankQuarters = <int>[
        for (var i = 0; i < quarterUrls.length; i++)
          if (quarterUrls[i].isEmpty) i + 1,
      ];
      if (blankQuarters.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('빈 쿼터를 확인해 주세요'),
            content: Text(
              '${blankQuarters.map((quarter) => '$quarter쿼터').join(', ')} 영상이 비어 있습니다. 이대로 올릴까요?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('돌아가기'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('비운 채 올리기'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }
    final user = ref.read(authControllerProvider).user;
    final now = DateTime.now();
    final video = VideoItem(
      id: widget.existing?.id ?? 'video-${now.microsecondsSinceEpoch}',
      title: _title.text.trim(),
      durationLabel: isReview ? '' : _duration.text.trim(),
      category: widget.category,
      url: sourceUrl,
      youtubeId: youtubeId ?? '',
      sourceType: isInstagram ? 'instagram' : 'youtube',
      quarterUrls: isReview
          ? quarterUrls.map((url) => url.isEmpty ? null : url).toList()
          : const [],
      uploadedAt: widget.existing?.uploadedAt ?? now,
      uploader: widget.existing?.uploader ?? user?.name ?? 'ENCBA',
      accent: EncbaColors.snuBlue.toARGB32(),
      likeCount: widget.existing?.likeCount ?? 0,
    );
    final notifier = ref.read(lockerControllerProvider.notifier);
    final saved = widget.existing == null
        ? await notifier.addVideo(video)
        : await notifier.updateVideo(video);
    if (mounted && saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isReview = widget.category == '복기';
    final sourceUrl = isReview
        ? _quarters
              .map((controller) => controller.text.trim())
              .firstWhere((url) => url.isNotEmpty, orElse: () => '')
        : _url.text.trim();
    final previewYoutubeId = _youtubeIdFrom(sourceUrl);
    final previewInstagram =
        widget.category == '하이라이트' && _isInstagramReel(sourceUrl);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.category == '공유'
                      ? '농구 영상 공유'
                      : '${widget.category} 추가',
                  style: const TextStyle(
                    fontFamily: 'Jua',
                    fontSize: 24,
                    color: EncbaColors.navy,
                  ),
                ),
                const SizedBox(height: 14),
                if (widget.category == '복기') ...[
                  const Text('쿼터별 YouTube 링크'),
                  const SizedBox(height: 8),
                  for (var index = 0; index < 4; index++) ...[
                    TextFormField(
                      controller: _quarters[index],
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '${index + 1}쿼터${index == 0 ? ' *' : ''}',
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (index == 0 &&
                            _quarters.every(
                              (controller) => controller.text.trim().isEmpty,
                            )) {
                          return '최소 한 쿼터의 링크가 필요합니다.';
                        }
                        if (text.isNotEmpty && _youtubeIdFrom(text) == null) {
                          return '올바른 YouTube 링크를 입력해 주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ] else ...[
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: widget.category == '하이라이트'
                          ? 'YouTube 또는 Instagram Reel 링크'
                          : 'YouTube 링크',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      final validYoutube = _youtubeIdFrom(text) != null;
                      final validInstagram =
                          widget.category == '하이라이트' && _isInstagramReel(text);
                      return validYoutube || validInstagram
                          ? null
                          : '올바른 영상 링크를 입력해 주세요.';
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                if (previewYoutubeId != null || previewInstagram) ...[
                  _VideoLinkPreview(
                    youtubeId: previewYoutubeId,
                    sourceUrl: sourceUrl,
                    sourceType: previewInstagram ? 'instagram' : 'youtube',
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '제목'),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ? '제목을 입력해 주세요.' : null,
                ),
                if (!isReview) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _duration,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: '재생 시간',
                      hintText: '예: 08:24',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _save,
                  child: Text(widget.existing == null ? '등록' : '저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoLinkPreview extends StatelessWidget {
  const _VideoLinkPreview({
    required this.youtubeId,
    required this.sourceUrl,
    required this.sourceType,
  });

  final String? youtubeId;
  final String sourceUrl;
  final String sourceType;

  @override
  Widget build(BuildContext context) {
    final thumbnail = _videoThumbnailUrl(
      youtubeId: youtubeId ?? '',
      sourceUrl: sourceUrl,
    );
    final asset = _instagramThumbnailAsset(sourceUrl);
    if (thumbnail == null && asset == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: asset != null
            ? Image.asset(
                asset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              )
            : Image.network(
                thumbnail!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: EncbaColors.line,
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: EncbaColors.muted,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
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
      builder: (_) => _AnnouncementEditorScreen(existing: existing),
    ),
  );
  if (draft != null) {
    final controller = ref.read(lockerControllerProvider.notifier);
    final saved = existing == null
        ? await controller.addAnnouncement(
            title: draft.title,
            body: draft.body,
            pinned: draft.pinned,
          )
        : await controller.updateAnnouncement(
            announcement: existing,
            title: draft.title,
            body: draft.body,
            pinned: draft.pinned,
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
  });
  final String title;
  final String body;
  final bool pinned;
}

class _AnnouncementEditorScreen extends StatefulWidget {
  const _AnnouncementEditorScreen({this.existing});
  final AnnouncementItem? existing;

  @override
  State<_AnnouncementEditorScreen> createState() =>
      _AnnouncementEditorScreenState();
}

class _AnnouncementEditorScreenState extends State<_AnnouncementEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _pinned;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '')
      ..addListener(_refresh);
    _body = TextEditingController(text: widget.existing?.body ?? '')
      ..addListener(_refresh);
    _pinned = widget.existing?.pinned ?? false;
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

const _bundledReelShortcodes = {
  'Db2nVhDz4Fq',
  'DajgzpRTc4e',
  'DZDMprWogCr',
  'DXPE0fsEwcm',
  'DTnGCB7E50t',
};

String? _instagramShortcode(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host != 'instagram.com' && host != 'www.instagram.com') return null;
  if (uri.pathSegments.length < 2 ||
      !const {'reel', 'p'}.contains(uri.pathSegments.first)) {
    return null;
  }
  final shortcode = uri.pathSegments[1];
  return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(shortcode) ? shortcode : null;
}

bool _isInstagramReel(String input) {
  final uri = Uri.tryParse(input);
  return uri != null &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == 'reel' &&
      _instagramShortcode(input) != null;
}

bool _canCreateVideoCategory(UserProfile user, String category) {
  if (category == '하이라이트') return user.canManageHighlights;
  return category == '복기' || category == '공유';
}

bool _canManageVideo(UserProfile? user, VideoItem video) {
  if (user == null) return false;
  if (video.category == '하이라이트') {
    return user.canManageHighlights || user.canAdminister;
  }
  return video.category == '복기' || video.category == '공유';
}

void _showTask(BuildContext context, String text) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '운영 체크리스트',
            style: TextStyle(
              fontFamily: 'Jua',
              fontSize: 24,
              color: EncbaColors.navy,
            ),
          ),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('로그아웃할까요?'),
      content: const Text('오프라인 일정과 계정은 이 기기에 남아 있습니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('로그아웃'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await ref.read(authControllerProvider.notifier).signOut();
  }
}

Future<void> _launch(String raw) =>
    launchUrl(Uri.parse(raw), mode: LaunchMode.externalApplication);
