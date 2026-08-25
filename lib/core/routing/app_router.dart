import 'package:encba_locker/core/routing/locker_tab.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/presentation/auth_screen.dart';
import 'package:encba_locker/features/auth/presentation/edit_profile_screen.dart';
import 'package:encba_locker/features/locker/presentation/locker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 앱 전체 라우터. 로그인 여부에 따라 진입 경로를 정리하고,
/// 하단 탭과 상세 화면을 모두 주소로 표현해 새로고침·공유가 가능하게 한다.
final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter는 Listenable로만 갱신을 받으므로 로그인 상태 변화를 중계한다.
  //
  // 로그인 여부만 실어 보내면 안 된다. 세션 복원이 "아직 모름"에서 "로그아웃"
  // 으로 끝날 때 값이 false 그대로라 ValueNotifier가 아무도 깨우지 않고,
  // 복원 중이라 판단을 미뤘던 redirect가 다시 돌지 않아 홈 화면 로딩만
  // 계속 돈다. 그래서 값이 같아도 매번 바뀌는 카운터를 쓴다.
  final authRevision = ValueNotifier<int>(0);
  ref.listen<({bool isReady, bool signedIn})>(
    authControllerProvider.select(
      (state) => (isReady: state.isReady, signedIn: state.user != null),
    ),
    (_, _) => authRevision.value++,
    fireImmediately: true,
  );
  ref.onDispose(authRevision.dispose);

  return GoRouter(
    initialLocation: LockerTab.home.path,
    refreshListenable: authRevision,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      // 세션 복원 중에는 어디로도 보내지 않고 스플래시를 유지한다.
      if (!auth.isReady) return null;
      final isSignedIn = auth.user != null;
      final isSigningIn = state.matchedLocation == _signInPath;
      if (!isSignedIn) return isSigningIn ? null : _signInPath;
      if (isSigningIn) return LockerTab.home.path;
      return null;
    },
    routes: [
      GoRoute(
        path: _signInPath,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/:tab(${LockerTab.pathPattern})',
        // 다섯 탭이 같은 페이지 키를 공유해야 탭을 옮겨도 각 화면의
        // 스크롤 위치와 상태가 살아 있는다.
        pageBuilder: (context, state) => NoTransitionPage(
          key: const ValueKey('locker-shell'),
          child: const LockerShell(),
        ),
      ),
      ...lockerRoutes,
    ],
    errorBuilder: (context, state) => const _RouteNotFoundScreen(),
  );
});

const _signInPath = '/sign-in';

/// 탭 위에 쌓이는 화면들. 위젯 테스트도 같은 정의를 재사용해
/// 라우트가 한 곳에만 적히도록 한다.
final List<RouteBase> lockerRoutes = [
  GoRoute(
    path: '/schedule/new',
    builder: (context, state) => const EventEditorScreen(),
  ),
  GoRoute(
    path: '/schedule/:eventId',
    pageBuilder: (context, state) => CustomTransitionPage(
      child: EventDetailScreen(eventId: state.pathParameters['eventId']!),
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(curve),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    ),
    routes: [
      GoRoute(
        path: 'edit',
        builder: (context, state) =>
            EventEditorScreen(eventId: state.pathParameters['eventId']!),
      ),
      GoRoute(
        path: 'roster',
        builder: (context, state) =>
            EventRosterScreen(eventId: state.pathParameters['eventId']!),
      ),
    ],
  ),
  GoRoute(
    path: '/profile/edit',
    builder: (context, state) => const EditProfileScreen(),
  ),
  GoRoute(
    path: '/reservations',
    builder: (context, state) => const CourtReservationScreen(),
  ),
  GoRoute(
    path: '/members',
    builder: (context, state) => MemberDirectoryScreen(
      startWithPendingOnly:
          state.uri.queryParameters['pending'] == '1',
    ),
    routes: [
      GoRoute(
        path: 'report',
        builder: (context, state) => const AttendanceReportScreen(),
      ),
      GoRoute(
        path: ':memberId',
        builder: (context, state) =>
            MemberDetailScreen(memberId: state.pathParameters['memberId']!),
      ),
    ],
  ),
  GoRoute(
    path: '/videos/:videoId',
    builder: (context, state) =>
        VideoDetailScreen(videoId: state.pathParameters['videoId']!),
  ),
  GoRoute(
    path: '/announcements/:announcementId',
    builder: (context, state) => AnnouncementDetailScreen(
      announcementId: state.pathParameters['announcementId']!,
    ),
  ),
  GoRoute(
    path: '/operations',
    builder: (context, state) => const OperationsScreen(),
  ),
  GoRoute(
    path: '/homecoming',
    builder: (context, state) => const HomecomingScreen(),
  ),
  GoRoute(path: '/audit', builder: (context, state) => const AuditLogScreen()),
  GoRoute(
    path: '/bug-report',
    builder: (context, state) => const BugReportScreen(),
  ),
  GoRoute(
    path: '/error-reports',
    builder: (context, state) => const ErrorReportInboxScreen(),
  ),
];

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '주소를 찾지 못했습니다.',
            style: TextStyle(fontFamily: 'Jua', fontSize: 20),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.go(LockerTab.home.path),
            style: FilledButton.styleFrom(backgroundColor: EncbaColors.snuBlue),
            child: const Text('홈으로'),
          ),
        ],
      ),
    ),
  );
}
