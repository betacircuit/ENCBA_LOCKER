import 'package:encba_locker/core/routing/app_router.dart';
import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/auth/presentation/auth_screen.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/presentation/locker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _admin = UserProfile(
  email: 'admin@encba.local',
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

LockerEvent _event({
  required String id,
  required String title,
  required DateTime start,
}) => LockerEvent(
  id: id,
  title: title,
  start: start,
  end: start.add(const Duration(hours: 2)),
  place: '71동 종합체육관',
  kind: EventKind.training,
  memo: '',
);

Widget _app(Widget child, {LockerState? lockerState}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith((ref) => AuthController.seeded(_admin)),
    lockerControllerProvider.overrideWith(
      (ref) => LockerController.seeded(initialState: lockerState),
    ),
  ],
  child: Consumer(
    builder: (context, ref, _) => MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (context, state) => child),
          ...lockerRoutes,
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('공지 일정 연결에는 이미 지난 일정이 나오지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    await tester.pumpWidget(
      _app(
        const HomeScreen(),
        lockerState: LockerState(
          isReady: true,
          events: [
            _event(
              id: 'past',
              title: '지난주훈련',
              start: now.subtract(const Duration(days: 7)),
            ),
            _event(
              id: 'future',
              title: '다음주훈련',
              start: now.add(const Duration(days: 7)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 공지').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('일정 연결'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('다음주훈련'), findsOneWidget);
    expect(find.textContaining('지난주훈련'), findsNothing);
  });

  testWidgets('투표 질문을 비워 둬도 공지를 등록할 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(const HomeScreen(), lockerState: LockerState(isReady: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 공지').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '제목 *').first,
      '훈련 안내',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(SwitchListTile, '투표 첨부'));
    await tester.pumpAndSettle();

    expect(find.text('투표 질문 (선택)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('공지 등록'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '공지 등록'),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets('새 일정 화면에는 매주 반복 대신 AI 채우기가 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const EventEditorScreen(),
        lockerState: LockerState(isReady: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('AI로 채우기'), findsOneWidget);
    expect(find.text('매주 반복'), findsNothing);
  });

  testWidgets('하이라이트 주소로 들어와도 상세 화면은 뜨지 않는다', (tester) async {
    final highlight = VideoItem(
      id: 'reel-1',
      title: '엔크바 하이라이트',
      durationLabel: '',
      category: '하이라이트',
      url: 'https://www.instagram.com/reel/AbCdEfGhIjK/',
      youtubeId: '',
      sourceType: 'instagram',
      uploadedAt: DateTime(2026, 8, 20),
      uploader: 'ENCBA',
      accent: 0xFF00539B,
    );
    await tester.pumpWidget(
      _app(
        const VideoDetailScreen(videoId: 'reel-1'),
        lockerState: LockerState(isReady: true, videos: [highlight]),
      ),
    );
    await tester.pump();

    // 제목·좋아요·댓글이 있는 상세 화면 대신 잠깐의 로딩만 지나간다.
    expect(find.text('엔크바 하이라이트'), findsNothing);
    expect(find.byTooltip('링크 공유'), findsNothing);
  });

  testWidgets('비활성 계정 안내에서 관리자에게 활성화를 요청할 수 있다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => AuthController.seeded(
              null,
            )..state = const AuthState(
              isReady: true,
              inactiveAccountEmail: 'sleeping@snu.ac.kr',
              error: '비활성화된 계정입니다. 관리자에게 활성화를 요청해 주세요.',
            ),
          ),
        ],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('비활성화된 계정입니다'), findsOneWidget);
    expect(find.text('sleeping@snu.ac.kr'), findsOneWidget);
    expect(find.text('관리자에게 활성화 요청'), findsOneWidget);
  });
}
