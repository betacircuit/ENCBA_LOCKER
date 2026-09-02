import 'package:encba_locker/core/routing/locker_tab.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/presentation/auth_screen.dart';
import 'package:encba_locker/features/auth/presentation/edit_profile_screen.dart';
import 'package:encba_locker/features/locker/presentation/locker_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 앱 전체 라우터. 로그인 여부에 따라 진입 경로를 정리하고,
/// 하단 탭과 상세 화면을 모두 주소로 표현해 새로고침·공유가 가능하게 한다.
final routerProvider = Provider<GoRouter>((ref) {
  // 뒤로가기 한 번에 화면이 두 개씩 넘어가던 원인.
  //
  // go_router는 기본값(false)에서 context.push로 띄운 화면을 브라우저
  // 주소·히스토리에 남기지 않는다. 그래서 웹에서는 "일정 탭 → 상세"처럼
  // 눌러 들어가도 히스토리 항목이 하나뿐이었고, 뒤로가기 제스처 한 번이
  // 그 항목을 통째로 건너뛰면서 쌓아 둔 화면이 한꺼번에 사라졌다. 화면이
  // 두 번 밀려나는 애니메이션은 그 결과였다.
  //
  // 이 앱의 화면은 전부 주소로 표현돼 있어(lockerRoutes) 최상단 화면의
  // 주소도 그대로 열 수 있다. 즉 이 옵션을 켜도 되는 조건을 이미 갖췄다.
  // 켜 두면 push 한 번이 히스토리 한 칸이라 제스처 한 번에 화면 하나만
  // 닫힌다.
  GoRouter.optionURLReflectsImperativeAPIs = true;

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
    pageBuilder: (context, state) =>
        _gentlePage(state: state, child: const EventEditorScreen()),
  ),
  GoRoute(
    path: '/schedule/:eventId',
    pageBuilder: (context, state) => _gentlePage(
      state: state,
      child: EventDetailScreen(eventId: state.pathParameters['eventId']!),
    ),
    routes: [
      GoRoute(
        path: 'edit',
        pageBuilder: (context, state) => _gentlePage(
          state: state,
          child: EventEditorScreen(eventId: state.pathParameters['eventId']!),
        ),
      ),
      GoRoute(
        path: 'roster',
        pageBuilder: (context, state) => _gentlePage(
          state: state,
          child: EventRosterScreen(eventId: state.pathParameters['eventId']!),
        ),
      ),
    ],
  ),
  GoRoute(
    path: '/profile/edit',
    pageBuilder: (context, state) =>
        _gentlePage(state: state, child: const EditProfileScreen()),
  ),
  GoRoute(
    path: '/reservations',
    pageBuilder: (context, state) =>
        _gentlePage(state: state, child: const CourtReservationScreen()),
  ),
  GoRoute(
    path: '/members',
    pageBuilder: (context, state) => _gentlePage(
      state: state,
      child: MemberDirectoryScreen(
        startWithPendingOnly: state.uri.queryParameters['pending'] == '1',
      ),
    ),
    routes: [
      GoRoute(
        path: 'report',
        pageBuilder: (context, state) =>
            _gentlePage(state: state, child: const AttendanceReportScreen()),
      ),
      GoRoute(
        path: ':memberId',
        pageBuilder: (context, state) => _gentlePage(
          state: state,
          child: MemberDetailScreen(
            memberId: state.pathParameters['memberId']!,
          ),
        ),
      ),
    ],
  ),
  GoRoute(
    path: '/videos/:videoId',
    pageBuilder: (context, state) => _gentlePage(
      state: state,
      child: VideoDetailScreen(videoId: state.pathParameters['videoId']!),
    ),
  ),
  GoRoute(
    path: '/announcements/:announcementId',
    pageBuilder: (context, state) => _gentlePage(
      state: state,
      child: AnnouncementDetailScreen(
        announcementId: state.pathParameters['announcementId']!,
      ),
    ),
  ),
  GoRoute(
    path: '/operations',
    pageBuilder: (context, state) =>
        _gentlePage(state: state, child: const OperationsScreen()),
  ),
  GoRoute(
    path: '/homecoming',
    pageBuilder: (context, state) =>
        _gentlePage(state: state, child: const HomecomingScreen()),
  ),
  GoRoute(
    path: '/audit',
    pageBuilder: (context, state) =>
        _gentlePage(state: state, child: const AuditLogScreen()),
  ),
  GoRoute(
    path: '/bug-report',
    pageBuilder: (context, state) =>
        _gentlePage(state: state, child: const BugReportScreen()),
  ),
  GoRoute(
    path: '/error-reports',
    pageBuilder: (context, state) =>
        _gentlePage(state: state, child: const ErrorReportInboxScreen()),
  ),
];

Page<void> _gentlePage({required GoRouterState state, required Widget child}) {
  // 웹에서는 화면 전환 애니메이션을 아예 쓰지 않는다.
  //
  // 브라우저 뒤로가기(가장자리 스와이프)는 히스토리를 먼저 되돌리고, 그
  // 결과가 라우터로 전달되면서 화면 구성이 다시 맞춰진다. 이 두 단계 사이에
  // 전환 애니메이션이 끼면 닫히던 화면이 잠깐 다시 그려졌다가 또 닫히는
  // 것처럼 보인다 - "한 번 드래그했는데 모션이 두 번" 나던 정체가 이것이다.
  //
  // 애니메이션이 없으면 중간 상태가 눈에 남지 않아 어떤 순서로 정리되든
  // 화면은 한 번만 바뀐다. 브라우저가 이미 자기 전환을 그려 주기도 한다.
  // 네이티브 빌드는 OS 제스처와 전환이 한 몸이라 그대로 둔다.
  if (kIsWeb) return NoTransitionPage<void>(key: state.pageKey, child: child);
  return MaterialPage<void>(key: state.pageKey, child: child);
}

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
