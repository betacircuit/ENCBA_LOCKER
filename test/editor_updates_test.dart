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

    expect(find.text('AI로 채우기'), findsOneWidget);
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

  test('공지 투표 항목은 정원이 차면 잠기고, 내가 고른 항목은 잠기지 않는다', () {
    final notice = AnnouncementItem(
      id: 'a1',
      title: '엠티',
      body: '',
      author: '운영진',
      publishedAt: DateTime(2026, 8, 29),
      pollOptions: const ['1일차', '2일차', '불참'],
      pollOptionLimits: const [2, 0, 0],
      pollVotes: const {0: 2, 1: 5},
    );

    expect(notice.limitFor(0), 2);
    expect(notice.isOptionFull(0), isTrue);
    // 정원이 0인 항목은 표가 아무리 많아도 잠기지 않는다.
    expect(notice.isOptionFull(1), isFalse);
    // 이미 내가 고른 항목은 다시 눌러도 막히면 안 된다.
    expect(notice.copyWith(myPollOption: 0).isOptionFull(0), isFalse);
  });

  test('OB는 인원을 밝히지 않아도 참여로 센다', () {
    final base = _event(
      id: 'e1',
      title: '훈련',
      start: DateTime(2026, 9, 1, 13),
    );

    expect(base.hasObParticipants, isFalse);
    expect(
      LockerEvent(
        id: base.id,
        title: base.title,
        start: base.start,
        end: base.end,
        place: base.place,
        kind: base.kind,
        memo: base.memo,
        obParticipantsUnknown: true,
      ).hasObParticipants,
      isTrue,
    );
  });

  testWidgets('새 일정의 기본 시각은 13:00:00~15:00:00이다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(const EventEditorScreen(), lockerState: LockerState(isReady: true)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('시작'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('13:00:00'), findsOneWidget);
    expect(find.text('15:00:00'), findsOneWidget);
  });

  testWidgets('공개 대상에서 직접 선택하면 멤버 고르기가 열린다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(const EventEditorScreen(), lockerState: LockerState(isReady: true)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('공개 대상 *'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('직접 선택').last);
    await tester.pumpAndSettle();

    expect(find.text('멤버 고르기'), findsOneWidget);
    expect(find.text('아직 고른 부원이 없습니다'), findsOneWidget);
  });

  testWidgets('취소된 일정도 관리자는 수정 화면을 열 수 있다', (tester) async {
    final cancelled = LockerEvent(
      id: 'cancelled-1',
      title: '취소된훈련',
      start: DateTime.now().add(const Duration(days: 3)),
      end: DateTime.now().add(const Duration(days: 3, hours: 2)),
      place: '71동 종합체육관',
      kind: EventKind.training,
      memo: '',
      cancelledAt: DateTime.now(),
      cancellationReason: '체육관 공사',
    );
    await tester.pumpWidget(
      _app(
        const EventDetailScreen(eventId: 'cancelled-1'),
        lockerState: LockerState(isReady: true, events: [cancelled]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('일정 수정'), findsOneWidget);
  });

  test('IB 운영 역할 이름 끝의 A·B는 코트로 읽는다', () {
    expect(ibOperationCourt('3경기 운영 A'), 'A코트');
    expect(ibOperationCourt('1경기 운영 B'), 'B코트');
    // 심판은 코트가 정해져 있지 않다.
    expect(ibOperationCourt('2경기 심판'), isNull);
  });

  test('IB 운영 일정은 종합체육관과 담당 코트를 함께 보여 준다', () {
    final merged = mergedOperationPlannerEvents([
      OperationAssignment(
        id: 'a1',
        title: '3경기 운영 A',
        start: DateTime(2026, 4, 4, 15, 20),
        end: DateTime(2026, 4, 4, 16, 20),
        location: '',
        memo: '',
        assigneeName: '김민수',
      ),
    ]);

    expect(merged.single.place, ibOperationVenue);
    expect(merged.single.court, 'A코트');
    expect(merged.single.fullPlace, '71동 종합체육관 · A코트');
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
