import 'dart:async';
import 'dart:convert';

import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/presentation/edit_profile_screen.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/presentation/event_screens.dart';
import 'package:encba_locker/features/locker/services/homecoming_import_service.dart';
import 'package:encba_locker/features/locker/services/web_notification_service.dart';
import 'package:flutter/material.dart';
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
    final canManageSchedule = user.isAdmin || user.isScheduleManager;
    final events = [...state.events]
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
            Image.asset(
              'assets/images/encba_logo.png',
              width: 48,
              height: 48,
              fit: BoxFit.contain,
            ),
            if (user.isAdmin)
              IconButton(
                tooltip: '공지 등록',
                onPressed: () => _showAnnouncementEditor(context, ref),
                icon: const Icon(Icons.add_alert_outlined),
              ),
            IconButton(
              tooltip: '알림',
              onPressed: () {
                ref.read(lockerControllerProvider.notifier).readNotifications();
                _showNotifications(context, state.announcements);
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
        if (state.announcements.firstOrNull case final notice?) ...[
          _NoticeCard(
            notice: notice,
            onTap: () => _openNotice(context, notice),
          ),
          const SizedBox(height: 26),
        ],
        _SectionHeader(
          title: '이번 주',
          action: '전체 일정',
          onTap: () => ref.read(lockerControllerProvider.notifier).selectTab(3),
        ),
        const SizedBox(height: 6),
        ...upcoming
            .skip(1)
            .take(3)
            .map(
              (event) => _CompactEventRow(
                event: event,
                onTap: () =>
                    openEventDetail(context, event, heroTagPrefix: 'home-row'),
              ),
            ),
      ],
    );
  }
}

class VideosScreen extends ConsumerWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lockerControllerProvider);
    final selected = state.videoSegment;
    final isAdmin = ref.watch(authControllerProvider).user!.isAdmin;
    const categories = ['하이라이트', '복기', '공유'];
    final visible = state.videos
        .where((item) => item.category == categories[selected])
        .toList();
    return _Page(
      header: const _Header(eyebrow: 'PLAYBACK', title: '영상 라커'),
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
        if (selected == 2 || isAdmin)
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
    final isAdmin = gameUser.isAdmin || gameUser.isScheduleManager;
    final selected = state.gameSegment;
    final selectedSub = state.gameSubSegment;
    final categories = switch (selected) {
      0 => const [
        ('아농', EventKind.morning),
        ('내부 경기', EventKind.internal),
        ('픽업게임', EventKind.pickup),
      ],
      1 => const [('1부', EventKind.ibDivision1), ('2부', EventKind.ibDivision2)],
      _ => const [
        ('연습 경기', EventKind.scrimmage),
        ('삼파전', EventKind.threeWay),
        ('외부 경기', EventKind.external),
      ],
    };
    final filtered = state.events.where((event) {
      return event.kind == categories[selectedSub].$2;
    }).toList();
    final ibLocked = selected == 1 && _isAcademicBreak(DateTime.now());
    return _Page(
      header: const _Header(eyebrow: 'GAME DAY', title: '경기'),
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
          labels: categories
              .map(
                (category) =>
                    '${category.$1}  ${state.events.where((event) => event.kind == category.$2).length}',
              )
              .toList(),
          selectedIndex: selectedSub,
          onSelected: ref
              .read(lockerControllerProvider.notifier)
              .selectGameSubSegment,
        ),
        const SizedBox(height: 20),
        if (ibLocked)
          const _EmptyState(
            icon: Icons.lock_clock_outlined,
            title: '방학 중에는 IB가 잠깁니다',
          )
        else if (filtered.isEmpty)
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final slot = constraints.maxWidth / labels.length;
      final motion = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260);
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: EncbaColors.navy),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: motion,
              curve: Curves.easeOutCubic,
              left: selectedIndex * slot,
              top: 0,
              width: slot,
              height: 46,
              child: const ColoredBox(color: EncbaColors.deepBlue),
            ),
            Row(
              children: labels.asMap().entries.map((entry) {
                final selected = entry.key == selectedIndex;
                return Expanded(
                  child: Semantics(
                    selected: selected,
                    button: true,
                    child: InkWell(
                      onTap: () => onSelected(entry.key),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icons != null) ...[
                            Icon(
                              icons![entry.key],
                              size: 18,
                              color: selected ? Colors.white : EncbaColors.ink,
                            ),
                            const SizedBox(width: 7),
                          ],
                          AnimatedDefaultTextStyle(
                            duration: motion,
                            style: TextStyle(
                              fontFamily: 'Jua',
                              fontSize: 14,
                              color: selected ? Colors.white : EncbaColors.ink,
                            ),
                            child: Text(entry.value),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    },
  );
}

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(lockerControllerProvider).events;
    final user = ref.watch(authControllerProvider).user!;
    final canManage = user.isAdmin || user.isScheduleManager;
    return _Page(
      header: _Header(
        eyebrow: _academicLabel(DateTime.now()),
        title: '일정',
        action: canManage
            ? IconButton(
                tooltip: '일정 추가',
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add_circle_outline_rounded),
              )
            : null,
      ),
      children: [
        const _WeekStrip(),
        const SizedBox(height: 22),
        _SectionHeader(title: '예정 일정 ${events.length}'),
        const SizedBox(height: 11),
        ...events.map(
          (event) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: EventTicket(
              event: event,
              heroTag: 'schedule-${event.id}',
              compact: true,
              onTap: () =>
                  openEventDetail(context, event, heroTagPrefix: 'schedule'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (canManage)
          FilledButton.icon(
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('새 일정 등록'),
          ),
      ],
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    return _Page(
      header: _Header(
        eyebrow: 'MY LOCKER',
        title: '개인',
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
              '${user.studentId} · ${user.generation}기 · #${user.jerseyNumber} ${user.position}',
          teams: user.teams,
          badge: user.badge,
          photoBase64: user.photoBase64,
          isAdmin: user.isAdmin,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
          ),
        ),
        const SizedBox(height: 12),
        const _StatsStrip(),
        const SizedBox(height: 24),
        const _SectionHeader(title: '내 메뉴'),
        const SizedBox(height: 10),
        _MenuTile(
          icon: Icons.notifications_active_outlined,
          title: '웹 알림 켜기',
          subtitle: '브라우저가 열려 있을 때 공지 알림',
          onTap: () async {
            final enabled = await WebNotificationService().enableAndTest();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(enabled ? '웹 알림을 켰습니다.' : '브라우저 알림 권한이 필요합니다.'),
                ),
              );
            }
          },
        ),
        _MenuTile(
          icon: Icons.groups_2_outlined,
          title: '멤버 디렉토리',
          subtitle: '팀 내부 연락처',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MemberDirectoryScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.assignment_outlined,
          title: 'IB 운영 일정',
          subtitle: '이번 학기 내 담당 3건',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OperationsScreen()),
          ),
        ),
        _MenuTile(
          icon: Icons.celebration_outlined,
          title: '홈커밍 연락 보드',
          subtitle: '연락 2/3 · 주차권 1건',
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

class MemberDirectoryScreen extends ConsumerStatefulWidget {
  const MemberDirectoryScreen({super.key});

  @override
  ConsumerState<MemberDirectoryScreen> createState() =>
      _MemberDirectoryScreenState();
}

class _MemberDirectoryScreenState extends ConsumerState<MemberDirectoryScreen> {
  String query = '';
  int _searchRevision = 0;

  @override
  Widget build(BuildContext context) {
    final locker = ref.watch(lockerControllerProvider);
    final segment = locker.memberSegment;
    final list = locker.members;
    return Scaffold(
      appBar: AppBar(title: const Text('멤버 디렉토리')),
      body: ListView(
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
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('YB 재학생')),
              ButtonSegment(value: 1, label: Text('OB 졸업생')),
            ],
            selected: {segment},
            showSelectedIcon: false,
            onSelectionChanged: (value) => ref
                .read(lockerControllerProvider.notifier)
                .selectMemberSegment(value.first),
          ),
          const SizedBox(height: 18),
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

  Future<void> _search(String value) async {
    query = value.trim();
    final revision = ++_searchRevision;
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || revision != _searchRevision) return;
    await ref.read(lockerControllerProvider.notifier).searchMembers(query);
  }
}

class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({super.key, required this.member});
  final MemberProfile member;

  @override
  Widget build(BuildContext context) => Scaffold(
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
          '${member.studentId} · ${member.generation}기 · #${member.jerseyNumber} ${member.position}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: EncbaColors.muted),
        ),
        const SizedBox(height: 22),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.groups_2_outlined),
                title: const Text('소속'),
                trailing: Text(member.teams.join(' · ')),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('연락 메모'),
                subtitle: Text(member.note),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('전화번호'),
                subtitle: Text(member.phone),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _launch('sms:${member.phone}'),
          icon: const Icon(Icons.sms_outlined),
          label: const Text('문자 보내기'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _launch('tel:${member.phone}'),
          icon: const Icon(Icons.phone_outlined),
          label: const Text('전화하기'),
        ),
      ],
    ),
  );
}

class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operations = ref.watch(lockerControllerProvider).operations;
    return Scaffold(
      appBar: AppBar(title: const Text('IB 운영 일정')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
        ],
      ),
    );
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
    final isAdmin = ref.watch(authControllerProvider).user?.isAdmin ?? false;
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
  const _Page({required this.header, required this.children});
  final Widget header;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
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

class _CompactEventRow extends StatelessWidget {
  const _CompactEventRow({required this.event, required this.onTap});
  final LockerEvent event;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 8,
      leading: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: EncbaColors.highlight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${event.start.month}.${event.start.day}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: EncbaColors.deepBlue,
          ),
        ),
      ),
      title: Text(
        event.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Wrap(
          spacing: 6,
          runSpacing: 5,
          children: [
            _CompactScheduleFact(
              icon: Icons.schedule_rounded,
              text: time(event.start),
              color: EncbaColors.timeMarker,
            ),
            _CompactScheduleFact(
              icon: Icons.location_on_outlined,
              text: event.fullPlace,
              color: EncbaColors.placeMarker,
            ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _CompactScheduleFact extends StatelessWidget {
  const _CompactScheduleFact({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color.withValues(alpha: .82)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 1),
          Icon(icon, size: 14, color: EncbaColors.navy),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 205),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Jua',
                fontSize: 12,
                height: 1.15,
                color: EncbaColors.navy,
              ),
            ),
          ),
        ],
      ),
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
        child: Image.asset(
          'assets/images/encba_logo.png',
          width: 86,
          height: 86,
          fit: BoxFit.contain,
        ),
      ),
    );
    if (video.id.startsWith('highlight') || video.youtubeId.isEmpty) {
      return fallback();
    }
    final thumbnail = YoutubePlayerController.getThumbnail(
      videoId: video.youtubeId,
      quality: ThumbnailQuality.high,
      format: ThumbnailFormat.webp,
    );
    return Image.network(
      thumbnail,
      fit: BoxFit.cover,
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
  late final YoutubePlayerController _player;
  final _comment = TextEditingController();
  String _capturedTimestamp = '00:00';
  Timer? _watchTimer;
  int _lastPositionSeconds = 0;

  VideoItem get video => widget.video;

  @override
  void initState() {
    super.initState();
    _player = YoutubePlayerController.fromVideoId(
      videoId: video.youtubeId,
      autoPlay: false,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
    if (video.category == '복기') {
      Future.microtask(
        () => ref
            .read(lockerControllerProvider.notifier)
            .loadVideoComments(video.id),
      );
    }
    final user = ref.read(authControllerProvider).user;
    if (user?.isAdmin == true ||
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
    _player.close();
    super.dispose();
  }

  Future<void> _recordWatch() async {
    final values = await Future.wait([_player.currentTime, _player.duration]);
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
    final seconds = await _player.currentTime;
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
    final canSeeWatch =
        user?.isAdmin == true ||
        video.uploader == user?.visibleName ||
        video.uploader == user?.name;
    final watchSummary =
        locker.videoWatchSummaries[video.id] ?? const <VideoWatchSummary>[];
    return Scaffold(
      appBar: AppBar(title: Text(video.category)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: YoutubePlayer(controller: _player, aspectRatio: 16 / 9),
          ),
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
                onTimestampTap: () => _player.seekTo(
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
                  trailing: Text(
                    '${item.watchedSeconds ~/ 60}분 ${item.watchedSeconds % 60}초',
                  ),
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

bool _isAcademicBreak(DateTime date) {
  final monthDay = date.month * 100 + date.day;
  return (monthDay >= 616 && monthDay <= 831) ||
      monthDay >= 1215 ||
      monthDay <= 228;
}

String _academicLabel(DateTime date) {
  final monthDay = date.month * 100 + date.day;
  if (monthDay >= 301 && monthDay <= 615) return '${date.year} · 1학기';
  if (monthDay >= 901 && monthDay <= 1214) return '${date.year} · 2학기';
  return '${date.year} · 방학';
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip();
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return Row(
      children: List.generate(7, (index) {
        final day = monday.add(Duration(days: index));
        final selected = day.day == now.day;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: EdgeInsets.only(right: index == 6 ? 0 : 5),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? EncbaColors.navy : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? EncbaColors.navy : EncbaColors.line,
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
                const SizedBox(height: 3),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: selected ? Colors.white : EncbaColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.meta,
    required this.teams,
    required this.badge,
    required this.photoBase64,
    required this.isAdmin,
    required this.onTap,
  });
  final String name;
  final String meta;
  final List<String> teams;
  final String? badge;
  final String? photoBase64;
  final bool isAdmin;
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
                      if (isAdmin) ...[
                        const SizedBox(width: 7),
                        const _SmallBadge('관리자'),
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
                    teams.join(' · '),
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
  const _StatsStrip();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 17),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Stat(value: '12.4', label: 'PTS'),
          _Rule(),
          _Stat(value: '5.8', label: 'AST'),
          _Rule(),
          _Stat(value: '82%', label: '참석률'),
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
          Text(
            member.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 7),
          Text(
            member.studentId,
            style: const TextStyle(color: EncbaColors.snuBlue, fontSize: 11),
          ),
          if (member.badge != null) ...[
            const SizedBox(width: 6),
            _SmallBadge(member.badge!),
          ],
        ],
      ),
      subtitle: Text(
        '#${member.jerseyNumber} ${member.position} · ${member.teams.join(' / ')} · ${member.note}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
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
          fontFamily: 'Jua',
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

void _openNotice(BuildContext context, AnnouncementItem notice) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('공지')),
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
  List<AnnouncementItem> announcements,
) => showModalBottomSheet<void>(
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
                      _openNotice(context, notice);
                    },
                  ),
                ),
        ],
      ),
    ),
  ),
);

void _showVideoEditor(BuildContext context, WidgetRef ref, String category) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VideoEditorSheet(category: category),
    );

class _VideoEditorSheet extends ConsumerStatefulWidget {
  const _VideoEditorSheet({required this.category});
  final String category;

  @override
  ConsumerState<_VideoEditorSheet> createState() => _VideoEditorSheetState();
}

class _VideoEditorSheetState extends ConsumerState<_VideoEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _duration = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final youtubeId = _youtubeIdFrom(_url.text.trim());
    if (youtubeId == null) return;
    final user = ref.read(authControllerProvider).user;
    final now = DateTime.now();
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .addVideo(
          VideoItem(
            id: 'video-${now.microsecondsSinceEpoch}',
            title: _title.text.trim(),
            durationLabel: _duration.text.trim(),
            category: widget.category,
            url: _url.text.trim(),
            youtubeId: youtubeId,
            uploadedAt: now,
            uploader: user?.name ?? 'ENCBA',
            accent: EncbaColors.snuBlue.toARGB32(),
          ),
        );
    if (mounted && saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.category == '공유' ? '농구 영상 공유' : '${widget.category} 추가',
            style: const TextStyle(
              fontFamily: 'Jua',
              fontSize: 24,
              color: EncbaColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'YouTube 링크'),
            validator: (value) => _youtubeIdFrom(value?.trim() ?? '') == null
                ? '올바른 YouTube 링크를 입력해 주세요.'
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: '제목'),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? '제목을 입력해 주세요.' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _duration,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: '재생 시간',
              hintText: '예: 08:24',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('등록')),
        ],
      ),
    ),
  );
}

Future<void> _showAnnouncementEditor(
  BuildContext context,
  WidgetRef ref,
) async {
  var title = '';
  var body = '';
  var pinned = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('새 공지'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                maxLength: 120,
                onChanged: (value) => title = value,
                decoration: const InputDecoration(labelText: '제목 *'),
              ),
              const SizedBox(height: 10),
              TextField(
                minLines: 4,
                maxLines: 8,
                maxLength: 10000,
                onChanged: (value) => body = value,
                decoration: const InputDecoration(labelText: '내용 *'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: pinned,
                title: const Text('홈 상단에 고정'),
                onChanged: (value) => setState(() => pinned = value ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (title.trim().isNotEmpty && body.trim().isNotEmpty) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('등록'),
          ),
        ],
      ),
    ),
  );
  if (result == true) {
    final saved = await ref
        .read(lockerControllerProvider.notifier)
        .addAnnouncement(
          title: title.trim(),
          body: body.trim(),
          pinned: pinned,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved ? '공지를 등록했습니다.' : '공지를 저장하지 못했습니다.')),
      );
    }
  }
}

String? _youtubeIdFrom(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be' || host == 'www.youtu.be') {
    return uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  }
  if (host != 'youtube.com' &&
      host != 'www.youtube.com' &&
      host != 'm.youtube.com' &&
      host != 'music.youtube.com') {
    return null;
  }
  final queryId = uri.queryParameters['v'];
  if (queryId != null && queryId.isNotEmpty) return queryId;
  for (final marker in ['shorts', 'embed', 'live']) {
    final index = uri.pathSegments.indexOf(marker);
    if (index >= 0 && index + 1 < uri.pathSegments.length) {
      return uri.pathSegments[index + 1];
    }
  }
  return null;
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
