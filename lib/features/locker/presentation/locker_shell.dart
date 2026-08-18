import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/presentation/event_screens.dart';
import 'package:encba_locker/features/locker/services/homecoming_import_service.dart';
import 'package:encba_locker/features/locker/services/ib_operation_import_service.dart';
import 'package:encba_locker/features/locker/services/error_report_service.dart';
import 'package:encba_locker/features/locker/services/notification_category_prefs.dart';
import 'package:encba_locker/features/locker/services/attendance_report_service.dart';
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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

part 'home/home_screen.dart';
part 'videos/videos_screen.dart';
part 'games/games_screen.dart';
part 'schedule/schedule_screens.dart';
part 'profile/profile_screens.dart';
part 'members/member_screens.dart';
part 'operations/operations_screens.dart';
part 'homecoming/homecoming_screen.dart';
part 'shared/shared_widgets.dart';

class LockerShell extends ConsumerWidget {
  const LockerShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return Scaffold(
      body: IndexedStack(index: selectedTab.index, children: pages),
      bottomNavigationBar: _SlidingNavigationBar(
        selectedIndex: selectedTab.index,
        onSelected: (index) => context.go(LockerTab.values[index].path),
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
