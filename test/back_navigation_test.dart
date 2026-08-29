import 'package:encba_locker/core/routing/app_router.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/locker/presentation/locker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _user = UserProfile(
  email: 'member@encba.local',
  name: '김민수',
  studentId: '22학번',
  generation: 41,
  phone: '010-1234-5678',
  position: 'PG',
  jerseyNumber: 23,
  status: 'YB',
  teams: ['ENCBA'],
  isAdmin: true,
);

void main() {
  testWidgets('눌러서 들어간 화면도 주소에 남는다 (뒤로가기 한 번에 한 화면만 닫히게)', (
    tester,
  ) async {
    // go_router 기본값(false)에서는 context.push로 띄운 화면이 브라우저
    // 히스토리에 남지 않아, 뒤로가기 한 번에 쌓아 둔 화면이 한꺼번에
    // 사라졌다. 라우터를 만들 때 이 옵션이 켜지는지 못 박아 둔다.
    GoRouter.optionURLReflectsImperativeAPIs = false;

    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => AuthController.seeded(_user),
        ),
        lockerControllerProvider.overrideWith(
          (ref) => LockerController.seeded(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(routerProvider);

    expect(GoRouter.optionURLReflectsImperativeAPIs, isTrue);
  });


  testWidgets('탭은 손가락 방향대로 옮겨 다닌다 (왼쪽=앞 탭, 오른쪽=뒤 탭)', (
    tester,
  ) async {
    // 탭 순서: 영상 · 경기 · 홈 · 일정 · 개인.
    // 왼쪽으로 밀면 막대에서 왼쪽 탭(홈→경기), 오른쪽으로 밀면 오른쪽
    // 탭(홈→일정)으로 간다. 직관과 반대로 고쳐지지 않게 못 박아 둔다.
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => AuthController.seeded(_user),
          ),
          lockerControllerProvider.overrideWith(
            (ref) => LockerController.seeded(),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // 가장자리(왼쪽 32px)는 브라우저 뒤로가기 몫이라 가운데에서 민다.
    await tester.drag(find.byType(IndexedStack), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(find.byType(GamesScreen), findsOneWidget);

    await tester.drag(find.byType(IndexedStack), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.drag(find.byType(IndexedStack), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleScreen), findsOneWidget);
  });

  testWidgets('살짝 스친 손짓으로는 탭이 바뀌지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => AuthController.seeded(_user),
          ),
          lockerControllerProvider.overrideWith(
            (ref) => LockerController.seeded(),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 천천히 조금만 움직이면 문턱을 넘지 못한다.
    await tester.timedDrag(
      find.byType(IndexedStack),
      const Offset(-20, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
