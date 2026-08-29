import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:encba_locker/core/platform/app_environment.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/core/widgets/pwa_install_prompt.dart';
import 'package:encba_locker/core/widgets/time_wheel_picker.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/services/homecoming_export_service.dart';
import 'package:encba_locker/features/locker/services/homecoming_import_service.dart';
import 'package:encba_locker/features/locker/services/ib_operation_import_service.dart';
import 'package:encba_locker/features/locker/services/notification_category_prefs.dart';
import 'package:encba_locker/features/locker/services/calendar_service.dart';
import 'package:encba_locker/features/locker/services/notification_history_service.dart';
import 'package:encba_locker/features/locker/services/announcement_read_store.dart';
import 'package:encba_locker/features/locker/services/app_update_service.dart';
import 'package:encba_locker/features/locker/services/attendance_report_service.dart';
import 'package:encba_locker/features/locker/services/ai_compose_service.dart';
import 'package:encba_locker/features/locker/services/web_notification_service.dart';
import 'package:encba_locker/features/locker/services/youtube_thumbnail_service.dart';
import 'package:encba_locker/core/routing/locker_tab.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

part 'event_screens.dart';
part 'event_detail_screens.dart';
part 'event_roster_attendance.dart';
part 'event_editor_screen.dart';
part 'home/home_screen.dart';
part 'videos/videos_screen.dart';
part 'videos/video_detail_screen.dart';
part 'videos/video_editor_sheet.dart';
part 'games/games_screen.dart';
part 'schedule/schedule_screens.dart';
part 'profile/profile_screens.dart';
part 'profile/personal_extras.dart';
part 'members/member_screens.dart';
part 'members/attendance_report_sheet.dart';
part 'members/member_detail.dart';
part 'members/member_editor.dart';
part 'members/member_widgets.dart';
part 'operations/operations_screens.dart';
part 'homecoming/homecoming_screen.dart';
part 'shared/shared_widgets.dart';
part 'shared/ai_compose_sheets.dart';

class LockerShell extends ConsumerStatefulWidget {
  const LockerShell({super.key});

  @override
  ConsumerState<LockerShell> createState() => _LockerShellState();
}

class _LockerShellState extends ConsumerState<LockerShell> {
  final Set<int> _visitedTabs = {};

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      lockerControllerProvider.select((state) => state.error),
      (previous, next) {
        if (next == null || next == previous) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(next),
                action: SnackBarAction(label: '확인', onPressed: () {}),
              ),
            );
          ref.read(lockerControllerProvider.notifier).clearError();
        });
      },
    );
    if (ref.watch(authControllerProvider).user == null) {
      // 세션 복원 중. 주소는 그대로 두고 기다렸다가 라우터가 정리하게 한다.
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: EncbaColors.snuBlue),
        ),
      );
    }
    final isReady = ref.watch(
      lockerControllerProvider.select((state) => state.isReady),
    );
    if (!isReady) {
      return Scaffold(
        body: Center(
          child: Semantics(
            liveRegion: true,
            label: '일정을 불러오는 중입니다',
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 3),
                SizedBox(height: 16),
                Text(
                  '일정을 불러오는 중입니다',
                  style: TextStyle(
                    fontFamily: 'Jua',
                    fontSize: 20,
                    color: EncbaColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    const pages = [
      VideosScreen(),
      GamesScreen(),
      HomeScreen(),
      ScheduleScreen(),
      ProfileScreen(),
    ];
    final selectedTab =
        LockerTab.fromPath(GoRouterState.of(context).matchedLocation) ??
        LockerTab.home;
    _visitedTabs.add(selectedTab.index);
    final syncStatus = ref.watch(
      lockerControllerProvider.select(
        (state) =>
            (isSyncing: state.isSyncing, isOfflineCache: state.isOfflineCache),
      ),
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (syncStatus.isSyncing || syncStatus.isOfflineCache)
              _SyncStatusBar(
                isSyncing: syncStatus.isSyncing,
                onRetry: () =>
                    ref.read(lockerControllerProvider.notifier).reload(),
              ),
            Expanded(
              // 탭 이동은 아래 탭 막대로만 한다. 좌우 손짓은 전부 브라우저
              // 뒤로가기 몫으로 남겨 둔다 - 둘이 같은 손짓을 나눠 가지면
              // 어느 쪽도 깔끔하게 동작하지 않는다.
              child: IndexedStack(
                index: selectedTab.index,
                children: [
                  for (var index = 0; index < pages.length; index++)
                    if (_visitedTabs.contains(index))
                      pages[index]
                    else
                      const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SlidingNavigationBar(
        selectedIndex: selectedTab.index,
        onSelected: (index) => context.go(LockerTab.values[index].path),
      ),
    );
  }
}

class _SyncStatusBar extends StatelessWidget {
  const _SyncStatusBar({required this.isSyncing, required this.onRetry});

  final bool isSyncing;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: EncbaColors.highlight,
    child: SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (isSyncing) ...[
              const SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                isSyncing
                    ? '저장된 화면을 먼저 열고 최신 데이터를 동기화 중입니다.'
                    : '연결이 불안정해 저장된 데이터를 표시하고 있습니다.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: EncbaColors.navy),
              ),
            ),
            if (!isSyncing)
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    ),
  );
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
                        excludeSemantics: true,
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
