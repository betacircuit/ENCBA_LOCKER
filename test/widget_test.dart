import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/auth/presentation/auth_screen.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/presentation/event_screens.dart';
import 'package:encba_locker/features/locker/presentation/locker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const testUser = UserProfile(
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
  test('영문 UI는 ENCBA 디스플레이 글꼴을 사용한다', () {
    expect(encbaFontFor('PLANNER', display: true), 'BlackHanSans');
    expect(encbaFontFor('ENCBA'), 'BlackHanSans');
    expect(encbaFontFor('일정'), 'Jua');
  });

  test('참석 마감은 경기는 3시간, 그 외 일정은 1시간 전이다', () {
    final start = DateTime(2026, 9, 1, 18);
    LockerEvent event(EventKind kind) => LockerEvent(
      id: kind.name,
      title: kind.label,
      start: start,
      end: start.add(const Duration(hours: 2)),
      place: '71동 종합체육관',
      kind: kind,
      memo: '공지',
    );

    expect(
      start.difference(event(EventKind.ibDivision1).responseDeadline),
      const Duration(hours: 3),
    );
    expect(
      start.difference(event(EventKind.operations).responseDeadline),
      const Duration(hours: 1),
    );
  });

  testWidgets('첫 실행에는 로그인과 회원가입 진입점을 표시한다', (tester) async {
    await tester.pumpWidget(_signedOutApp(const AuthScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to ENCBA'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('처음이라면 회원가입'), findsOneWidget);

    await tester.tap(find.text('처음이라면 회원가입'));
    await tester.pumpAndSettle();
    expect(find.text('라커에 자리 만들기'), findsOneWidget);
    expect(find.text('실명'), findsOneWidget);
    expect(find.text('가입하고 시작'), findsOneWidget);
  });

  testWidgets('일정 카드에서 바로 참석을 고르고 상세 화면을 연다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('참석').first);
    await tester.tap(find.text('참석').first);
    await tester.pump();
    expect(find.textContaining('저장했습니다'), findsOneWidget);

    await tester.tap(find.text('일정').last);
    await tester.pump();
    await tester.tap(find.byType(EventTicket).first);
    await tester.pumpAndSettle();
    expect(find.text('일정 상세'), findsOneWidget);
    expect(find.text('네이버 지도'), findsOneWidget);
    expect(find.text('캘린더에 추가'), findsOneWidget);
    expect(find.text('참석 여부'), findsNothing);
  });

  testWidgets('일정 등록 화면은 필수 운영 필드를 제공한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const EventEditorScreen()));
    await tester.pumpAndSettle();

    expect(find.text('새 일정'), findsOneWidget);
    expect(find.text('제목 *'), findsNothing);
    expect(find.text('일정 유형 *'), findsOneWidget);
    expect(find.text('장소 *'), findsOneWidget);
    expect(find.text('공지 메모'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('인원 제한'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('제한 없음'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('마감 정하기'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('마감 정하기'), findsOneWidget);
  });

  testWidgets('일반 부원에게 일정 생성·제안·수정을 노출하지 않는다', (tester) async {
    await tester.pumpWidget(
      _signedInApp(
        const LockerShell(),
        user: testUser.copyWith(isAdmin: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ENCBA LOCKER'), findsOneWidget);
    expect(find.text('일정 만들기'), findsNothing);

    await tester.tap(find.text('일정').last);
    await tester.pump();
    expect(find.text('제안하기'), findsNothing);

    await tester.tap(find.text('정기 훈련').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('일정 수정'), findsNothing);
  });

  testWidgets('홈에는 바로 하기가 없고 경기에는 2단 카테고리가 표시된다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    expect(find.text('바로 하기'), findsNothing);

    await tester.tap(find.text('경기').last);
    await tester.pump();
    expect(find.text('1부'), findsOneWidget);
    expect(find.text('2부'), findsOneWidget);
    expect(find.text('신입생'), findsNothing);
    expect(find.text('방학 중에는 IB가 잠깁니다'), findsNothing);

    await tester.tap(find.text('외부'));
    await tester.pump();
    expect(find.text('연습 경기'), findsWidgets);
    expect(find.text('삼파전'), findsWidgets);
    expect(find.text('외부 경기'), findsNothing);
  });

  testWidgets('430px 모바일 폭에서도 일정 시간과 장소 강조가 넘치지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('일정').last);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.schedule_rounded), findsWidgets);
    expect(find.byIcon(Icons.location_on_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('불참은 수기 사유를 입력해야 저장된다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('불참').first);
    await tester.tap(find.text('불참').first);
    await tester.pumpAndSettle();
    expect(find.text('불참 사유'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '학과 필수 수업과 시간이 겹칩니다.');
    await tester.tap(find.text('저장'));
    await tester.pump();
    expect(find.textContaining('불참으로 저장했습니다'), findsOneWidget);
  });

  test('픽업게임과 복수 유니폼·가변 투표가 캐시에 보존된다', () {
    final event = LockerEvent(
      id: 'pickup',
      title: '금요일 픽업게임',
      start: DateTime(2026, 9, 4, 18),
      end: DateTime(2026, 9, 4, 20),
      place: '71동 종합체육관',
      kind: EventKind.pickup,
      memo: '공지',
      uniformColors: const ['검정', '흰색'],
      pollOptions: const ['18시 참석', '19시 참석', '불참'],
      opponents: const ['스티즈'],
    );
    final restored = LockerEvent.fromJson(event.toJson());
    expect(restored.kind, EventKind.pickup);
    expect(restored.uniformColors, ['검정', '흰색']);
    expect(restored.pollOptions, ['18시 참석', '19시 참석', '불참']);
    expect(restored.opponents, ['스티즈']);
  });

  test('주장은 관리자 권한을 가지며 복수 팀 소속은 하나의 라벨로 표시된다', () {
    final captain = testUser.copyWith(
      isAdmin: false,
      leadershipRole: 'captain',
      teams: const ['ENCBA', 'BEN'],
    );

    expect(captain.canAdminister, isTrue);
    expect(captain.leadershipLabel, '주장');
    expect(captain.teamLabel, 'ENCBA & BEN');
  });

  test('복기 영상의 네 쿼터 링크와 출처가 캐시에 보존된다', () {
    final video = VideoItem(
      id: 'review-1',
      title: '정기전 복기',
      durationLabel: '',
      category: '복기',
      url: 'https://youtu.be/quarter-1',
      youtubeId: 'quarter-1',
      uploadedAt: DateTime(2026, 8, 13),
      uploader: '김민수',
      accent: 0xFF00539B,
      sourceType: 'youtube',
      quarterUrls: const [
        'https://youtu.be/quarter-1',
        null,
        'https://youtu.be/quarter-3',
        null,
      ],
    );

    final restored = VideoItem.fromJson(video.toJson());
    expect(restored.sourceType, 'youtube');
    expect(restored.quarterUrls, video.quarterUrls);
    expect(restored.uploader, '김민수');
  });

  test('매니저만 하이라이트 등록 권한을 가진다', () {
    final manager = testUser.copyWith(
      isAdmin: false,
      leadershipRole: 'manager',
    );
    final captain = testUser.copyWith(
      isAdmin: false,
      leadershipRole: 'captain',
    );

    expect(manager.canManageHighlights, isTrue);
    expect(captain.canManageHighlights, isFalse);
    expect(captain.canAdminister, isTrue);
  });

  testWidgets('플래너 달력은 펼쳐지고 일정이 있는 날을 표시한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('일정').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('달력 펼치기'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('달력 닫기'), findsOneWidget);
    expect(find.byTooltip('이전 달'), findsOneWidget);
    expect(find.byTooltip('다음 달'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('날짜를 눌러도 미래 일정 목록은 유지되고 해당 날짜로 이동한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('일정').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('달력 펼치기'));
    await tester.pumpAndSettle();

    final target = DateTime.now().add(const Duration(days: 12));
    if (target.month != DateTime.now().month) {
      await tester.tap(find.byTooltip('다음 달'));
      await tester.pumpAndSettle();
    }
    final plannerList = find.byKey(const ValueKey('planner-scroll'));
    final before = tester.widget<ListView>(plannerList).controller!.offset;
    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.text('${target.day}'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final after = tester.widget<ListView>(plannerList).controller!.offset;

    expect(find.text('날짜 필터 해제'), findsNothing);
    expect(after, greaterThan(before));
    expect(find.text('${target.month}.${target.day}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('복기 추가는 재생 시간 없이 YouTube 썸네일을 미리 본다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영상').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('복기').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('영상 링크 추가'));
    await tester.tap(find.text('영상 링크 추가'));
    await tester.pumpAndSettle();

    expect(find.text('재생 시간'), findsNothing);
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://www.youtube.com/watch?v=M7lc1UVf-VE',
    );
    await tester.pump();

    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('인원 제한 슬라이더의 숫자는 60명에서도 영역을 벗어나지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_signedInApp(const EventEditorScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('인원 제한'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('인원 제한'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(find.text('60명'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('오늘의 준비 상태는 직접 체크할 수 있는 체크리스트다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 준비 상태'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));

    await tester.ensureVisible(find.text('물통과 개인 준비물 챙김'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();

    final checks = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(checks.last.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Widget _signedOutApp(Widget child) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith((ref) => AuthController.seeded(null)),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

Widget _signedInApp(
  Widget child, {
  UserProfile user = testUser,
}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith((ref) => AuthController.seeded(user)),
    lockerControllerProvider.overrideWith((ref) => LockerController.seeded()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);
