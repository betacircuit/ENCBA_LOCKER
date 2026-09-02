import 'package:encba_locker/core/routing/app_router.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
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
  testWidgets('/profile 딥링크에서 새 일정을 닫으면 프로필로 돌아온다', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/profile';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => AuthController.seeded(_user),
        ),
        lockerControllerProvider.overrideWith(
          (ref) =>
              LockerController.seeded(initialState: LockerState(isReady: true)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/profile');

    router.push('/schedule/new');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/schedule/new');

    router.pop();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/profile');
  });

  testWidgets('눌러서 들어간 화면도 주소에 남는다 (뒤로가기 한 번에 한 화면만 닫히게)', (tester) async {
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
}
