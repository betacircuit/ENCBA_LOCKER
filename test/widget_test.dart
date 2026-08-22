import 'package:encba_locker/core/theme/app_theme.dart';
import 'package:encba_locker/core/routing/locker_tab.dart';
import 'package:encba_locker/features/auth/application/auth_controller.dart';
import 'package:encba_locker/features/auth/domain/user_profile.dart';
import 'package:encba_locker/features/auth/presentation/auth_screen.dart';
import 'package:encba_locker/features/locker/application/locker_controller.dart';
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/presentation/event_screens.dart';
import 'package:encba_locker/features/locker/presentation/locker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encba_locker/core/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

  testWidgets('재생 위치 버튼은 실시간 시각을 반영하고 눌렀을 때 고정된다', (tester) async {
    final position = ValueNotifier<double>(0);
    addTearDown(position.dispose);
    var pinned = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ValueListenableBuilder<double>(
              valueListenable: position,
              builder: (context, seconds, _) => PlaybackPositionButton(
                seconds: seconds,
                pinned: pinned,
                onToggle: () => setState(() => pinned = !pinned),
              ),
            ),
          ),
        ),
      ),
    );

    position.value = 65.2;
    await tester.pump();
    expect(find.text('현재 재생 위치  01:05'), findsOneWidget);

    await tester.tap(find.byType(PlaybackPositionButton));
    await tester.pump();
    expect(find.text('이 시각에 코멘트  01:05'), findsOneWidget);
  });

  testWidgets('일정 카드와 하단 탭은 스크린 리더용 동작 이름을 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    final event = LockerEvent(
      id: 'semantic-event',
      title: '접근성 훈련',
      start: DateTime(2026, 8, 20, 19),
      end: DateTime(2026, 8, 20, 21),
      place: '71동 종합체육관',
      kind: EventKind.training,
      memo: '',
      responseEnabled: false,
    );

    await tester.pumpWidget(
      _signedInApp(
        EventTicket(event: event, heroTag: 'semantic-event', onTap: () {}),
      ),
    );
    expect(
      find.bySemanticsLabel('접근성 훈련, 8월 20일, 19:00부터 21:00까지, 71동 종합체육관'),
      findsOneWidget,
    );

    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();
    for (final label in ['영상', '경기', '홈', '일정', '개인']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('세션 복원이 로그아웃으로 끝나면 로그인 화면으로 넘어간다', (tester) async {
    // 실제 라우터 정의를 그대로 쓴다. 복원이 끝나도 로그인 여부가 false
    // 그대로면 refreshListenable이 깨어나지 않아 홈에서 로딩만 돌던 적이 있다.
    final auth = _DelayedRestoreAuthController();
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: container.read(routerProvider),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Welcome to ENCBA'), findsNothing);

    auth.finishRestore();
    await tester.pumpAndSettle();

    expect(find.text('Welcome to ENCBA'), findsOneWidget);
  });

  testWidgets('첫 실행의 회원가입은 학교 Google 인증부터 시작한다', (tester) async {
    await tester.pumpWidget(_signedOutApp(const AuthScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to ENCBA'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
    // 실명 로그인 화면에서도 학교 계정으로 바로 들어올 수 있어야 한다.
    expect(find.text('Google 계정으로 로그인'), findsOneWidget);
    expect(find.text('또는'), findsOneWidget);
    expect(find.text('처음이라면 Google 회원가입'), findsOneWidget);

    await tester.tap(find.text('처음이라면 Google 회원가입'));
    await tester.pumpAndSettle();
    expect(find.text('Google로 가입하기'), findsOneWidget);
    expect(find.text('Google 계정으로 계속'), findsOneWidget);
    expect(find.textContaining('snu.ac.kr 계열 학교 계정'), findsOneWidget);
    expect(find.text('실명'), findsNothing);
    expect(find.text('비밀번호'), findsNothing);
  });

  testWidgets('회원정보 입력 단계에서는 Google 로그인 버튼을 감춘다', (tester) async {
    const registration = PendingGoogleRegistration(
      email: 'member@snu.ac.kr',
      suggestedName: '김멤버',
    );
    await tester.pumpWidget(
      _signedOutApp(const AuthScreen(), pendingRegistration: registration),
    );
    await tester.pumpAndSettle();

    expect(find.text('정보 저장하고 가입 완료'), findsOneWidget);
    expect(find.text('Google 계정으로 로그인'), findsNothing);
    expect(find.text('또는'), findsNothing);
  });

  testWidgets('Google 인증 뒤에는 학교 이메일과 회원정보 입력을 표시한다', (tester) async {
    const registration = PendingGoogleRegistration(
      email: 'member@snu.ac.kr',
      suggestedName: '김멤버',
    );
    await tester.pumpWidget(
      _signedOutApp(const AuthScreen(), pendingRegistration: registration),
    );
    await tester.pumpAndSettle();

    expect(find.text('회원 정보 입력'), findsOneWidget);
    expect(find.text('학교 계정 확인 완료'), findsOneWidget);
    expect(find.text('member@snu.ac.kr'), findsOneWidget);
    expect(find.text('로그인 아이디 (실명)'), findsOneWidget);
    expect(find.text('김멤버'), findsOneWidget);
    expect(find.textContaining('로그인 아이디는 아래에 입력한 실명'), findsOneWidget);
    expect(
      find.text('학교 Google 계정에서 확인된 실명이며, 이 이름으로 로그인합니다.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, '로그인 아이디 (실명)'), findsNothing);
    expect(find.text('학번'), findsOneWidget);
    expect(find.text('엔크바 가입 년도'), findsOneWidget);
    expect(find.text('전화번호'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '전화번호'))
          .controller!
          .text,
      '010-',
    );
    expect(find.text('정보 저장하고 가입 완료'), findsOneWidget);
    // 학교 이메일은 인증에만 쓰고, 여기서 실명 아이디와 비밀번호를 만든다.
    expect(find.text('비밀번호'), findsOneWidget);
    expect(find.text('비밀번호 확인'), findsOneWidget);

    await tester.ensureVisible(find.text('정보 저장하고 가입 완료'));
    await tester.tap(find.text('정보 저장하고 가입 완료'));
    await tester.pump();
    // 학번·가입년도는 휠 피커라 항상 유효한 값을 들고 있어 별도 오류가 없다.
    expect(find.text('010-1234-5678 형식으로 입력해 주세요.'), findsOneWidget);
    expect(find.text('0–99로 입력해 주세요.'), findsOneWidget);
    expect(find.text('8자 이상 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('가입 단계의 비밀번호 확인은 서로 다를 때 막는다', (tester) async {
    const registration = PendingGoogleRegistration(
      email: 'member@snu.ac.kr',
      suggestedName: '김멤버',
    );
    await tester.pumpWidget(
      _signedOutApp(const AuthScreen(), pendingRegistration: registration),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호'),
      'encba12345',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호 확인'),
      'encba54321',
    );
    await tester.ensureVisible(find.text('정보 저장하고 가입 완료'));
    await tester.tap(find.text('정보 저장하고 가입 완료'));
    await tester.pump();

    expect(find.text('비밀번호가 서로 다릅니다.'), findsOneWidget);
    expect(find.text('8자 이상 입력해 주세요.'), findsNothing);
  });

  test('서울대학교 본 도메인과 하위 도메인만 학교 계정으로 인정한다', () {
    expect(isSnuSchoolEmail('member@snu.ac.kr'), isTrue);
    expect(isSnuSchoolEmail('member@alumni.snu.ac.kr'), isTrue);
    expect(isSnuSchoolEmail('member@gmail.com'), isFalse);
    expect(isSnuSchoolEmail('member@snu.ac.kr.evil.example'), isFalse);
  });

  testWidgets('일정 카드에서 바로 참석을 고르고 상세 화면을 연다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('참석').first);
    await tester.tap(find.text('참석').first);
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.textContaining('저장했습니다'), findsOneWidget);

    await tester.tap(find.text('일정').last);
    await tester.pump();
    await tester.tap(find.byType(EventTicket).first);
    await tester.pumpAndSettle();
    expect(find.text('일정 상세'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('네이버 지도'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('네이버 지도'), findsOneWidget);
    expect(find.text('캘린더에 추가'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('캘린더에 추가'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(find.text('참석 여부'), findsNothing);
  });

  testWidgets('공지 편집기는 사진과 투표를 첨부할 수 있다', (tester) async {
    await tester.pumpWidget(
      _signedInApp(
        const LockerShell(),
        lockerState: LockerState(isReady: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 공지'));
    await tester.pumpAndSettle();

    expect(find.text('사진 첨부'), findsOneWidget);
    expect(find.text('사진 선택'), findsOneWidget);
    expect(find.text('투표 첨부'), findsOneWidget);
  });

  testWidgets('활성 홈커밍은 관리자에게 다시 잠그기를 제공한다', (tester) async {
    final campaign = HomecomingCampaign(
      id: 'homecoming-2026-2',
      title: '2026년 2학기 홈커밍',
      academicYear: 2026,
      term: 2,
      eventDate: DateTime(2026, 11, 7),
      startsAt: '14:00:00',
      endsAt: '18:00:00',
      venue: '서울대학교 기숙사체육관',
      isActive: true,
    );
    await tester.pumpWidget(
      _signedInApp(
        const HomecomingScreen(),
        user: testUser.copyWith(leadershipRole: 'admin'),
        lockerState: LockerState(isReady: true, homecomingCampaign: campaign),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('다시 잠그기'), findsOneWidget);
  });

  testWidgets('일정 출결은 응답 전에는 어떤 항목도 선택되지 않는다', (tester) async {
    final event = LockerEvent(
      id: 'no-default-attendance',
      title: '정기 훈련',
      start: DateTime(2026, 8, 20, 19),
      end: DateTime(2026, 8, 20, 21),
      place: '71동 종합체육관',
      kind: EventKind.training,
      memo: '',
    );
    await tester.pumpWidget(
      _signedInApp(
        Scaffold(body: AttendanceSelector(event: event)),
        lockerState: LockerState(isReady: true, events: [event]),
      ),
    );
    await tester.pumpAndSettle();

    final choices = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(AttendanceSelector),
            matching: find.byType(Semantics),
          ),
        )
        .where((node) => node.properties.selected != null)
        .toList(growable: false);
    expect(choices, hasLength(3));
    expect(choices.every((node) => node.properties.selected == false), isTrue);
  });

  testWidgets('일정 상세는 선택별 응답자와 공개 불참 사유를 함께 보여준다', (tester) async {
    final event = LockerEvent(
      id: 'attendance-detail',
      title: '정기 훈련',
      start: DateTime(2026, 8, 20, 19),
      end: DateTime(2026, 8, 20, 21),
      place: '71동 종합체육관',
      court: 'A 코트',
      kind: EventKind.training,
      memo: '',
      opponents: const ['스티즈'],
      uniformColors: const ['검정', '흰색'],
    );
    const members = [
      MemberProfile(
        id: 'member-1',
        name: '김참석',
        studentId: '23',
        generation: 1,
        status: 'YB',
        position: 'PG',
        teams: ['ENCBA'],
        note: '',
      ),
      MemberProfile(
        id: 'member-2',
        name: '박불참',
        studentId: '24',
        generation: 1,
        status: 'YB',
        position: 'SG',
        teams: ['ENCBA'],
        note: '',
      ),
      MemberProfile(
        id: 'member-3',
        name: '이미응답',
        studentId: '25',
        generation: 1,
        status: 'YB',
        position: 'SF',
        teams: ['ENCBA'],
        note: '',
      ),
    ];
    final state = LockerState(
      isReady: true,
      events: [event],
      members: members,
      eventAttendance: {
        event.id: [
          AttendanceResponse(
            profileId: 'member-1',
            name: '김참석',
            choice: '참석',
            respondedAt: DateTime(2026, 8, 14),
          ),
          AttendanceResponse(
            profileId: 'member-2',
            name: '박불참',
            choice: '불참',
            absenceReason: '수업 일정',
            respondedAt: DateTime(2026, 8, 14),
          ),
        ],
      },
    );

    await tester.pumpWidget(
      _signedInApp(EventDetailScreen(eventId: event.id), lockerState: state),
    );
    await tester.pumpAndSettle();
    final hasBlackDetailCard = tester
        .widgetList<Container>(find.byType(Container))
        .any(
          (container) =>
              container.decoration is BoxDecoration &&
              (container.decoration! as BoxDecoration).color ==
                  EncbaColors.navy,
        );
    expect(hasBlackDetailCard, isTrue);
    expect(find.text('8월 20일 (목) · 19:00–21:00'), findsOneWidget);
    final facts = find.byKey(const ValueKey('event-detail-facts'));
    expect(facts, findsOneWidget);
    expect(
      find.descendant(of: facts, matching: find.text('상대')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('스티즈')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('유니폼')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('검정 · 흰색')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('일시')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: facts,
        matching: find.text('2026년 8월 20일 (목) 19:00–21:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('장소')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('71동 종합체육관 · A 코트')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('참석 현황'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('2명 응답'), findsOneWidget);
    expect(find.text('김참석'), findsOneWidget);
    expect(find.text('박불참'), findsWidgets);
    expect(find.text('박불참 · 수업 일정'), findsOneWidget);
    expect(find.text('미응답 1명'), findsOneWidget);
  });

  testWidgets('일정 상세와 수정 화면은 ID 주소에서 직접 열린다', (tester) async {
    final event = LockerEvent(
      id: 'route-event',
      title: '주소로 여는 정기 훈련',
      start: DateTime(2026, 8, 20, 19),
      end: DateTime(2026, 8, 20, 21),
      place: '71동 종합체육관',
      kind: EventKind.training,
      memo: '',
    );
    final lockerState = LockerState(isReady: true, events: [event]);

    await tester.pumpWidget(
      _signedInApp(
        const SizedBox.shrink(),
        lockerState: lockerState,
        initialLocation: '/schedule/${event.id}',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('일정 상세'), findsOneWidget);
    expect(find.text(event.title), findsWidgets);

    await tester.pumpWidget(
      _signedInApp(
        const SizedBox.shrink(),
        lockerState: lockerState,
        initialLocation: '/schedule/${event.id}/edit',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('일정 수정'), findsOneWidget);
  });

  testWidgets('멤버 상세 화면은 ID 주소에서 직접 열린다', (tester) async {
    const member = MemberProfile(
      id: 'route-member',
      name: '주소 멤버',
      studentId: '25학번',
      generation: 44,
      status: 'YB',
      position: 'PG',
      teams: ['ENCBA'],
      note: '',
    );

    await tester.pumpWidget(
      _signedInApp(
        const SizedBox.shrink(),
        lockerState: LockerState(isReady: true, members: [member]),
        initialLocation: '/members/${member.id}',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('멤버 정보'), findsOneWidget);
    expect(find.text(member.name), findsOneWidget);
  });

  testWidgets('영상 상세 화면은 ID 주소를 해석한다', (tester) async {
    await tester.pumpWidget(
      _signedInApp(
        const SizedBox.shrink(),
        lockerState: LockerState(isReady: true),
        initialLocation: '/videos/route-video',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('영상 정보를 찾지 못했습니다.'), findsOneWidget);
  });

  testWidgets('일정 등록 화면은 필수 운영 필드를 제공한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const EventEditorScreen()));
    await tester.pumpAndSettle();

    expect(find.text('새 일정'), findsOneWidget);
    expect(find.text('제목 *'), findsNothing);
    expect(find.text('일정 유형 *'), findsOneWidget);
    expect(find.text('공지 메모'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('장소 *'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('장소 *'), findsOneWidget);
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

  testWidgets('일정 제목은 선택 입력이고 정각 선택은 분 없는 시간 선택기를 연다', (tester) async {
    await tester.pumpWidget(_signedInApp(const EventEditorScreen()));
    await tester.pumpAndSettle();

    expect(find.text('제목 (선택)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('시작'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('정각'), findsOneWidget);
    expect(find.text('분 설정'), findsOneWidget);
  });

  testWidgets('IB 일정은 1·2·3경기 고정 시간만 선택한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const EventEditorScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('훈련').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('IB 1부').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('경기 시간 *'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('1경기 · 13:00–14:00'), findsOneWidget);
    expect(find.text('정각'), findsNothing);
    expect(find.text('분 설정'), findsNothing);
  });

  testWidgets('외부 경기 등록은 주전 선택을 노출한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const EventEditorScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('훈련').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('외부 경기').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('주전 선택'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('주전 선택'), findsOneWidget);
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
    expect(find.text('외부 경기'), findsOneWidget);
  });

  testWidgets('430px 모바일 폭에서도 일정 시간과 장소 강조가 넘치지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('일정').last);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.calendar_today_outlined), findsWidgets);
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
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.textContaining('불참으로 저장했습니다'), findsOneWidget);
  });

  testWidgets('출석 응답을 빠르게 바꾸면 마지막 응답 알림만 표시한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('참석').first);
    await tester.tap(find.text('참석').first);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('미정').first);
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('미정으로 저장했습니다.'), findsOneWidget);
    expect(find.text('참석으로 저장했습니다.'), findsNothing);
  });

  testWidgets('참석 저장 성공 때 축하 이펙트가 한 번 재생되고 사라진다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('참석').first);
    await tester.tap(find.text('참석').first);
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      find.byKey(const ValueKey('attendance-celebration')),
      findsOneWidget,
    );
    expect(find.text('참석 확정!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('attendance-celebration')), findsNothing);
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

  test('OB 참여 인원은 캐시에 보존된다', () {
    final event = LockerEvent(
      id: 'ob-event',
      title: 'OB 참여 경기',
      start: DateTime(2026, 9, 4, 18),
      end: DateTime(2026, 9, 4, 20),
      place: '71동 종합체육관',
      kind: EventKind.training,
      memo: '',
      obParticipantCount: 7,
    );
    final restored = LockerEvent.fromJson(event.toJson());
    expect(restored.obParticipantCount, 7);
  });

  testWidgets('복수 유니폼 일정도 목록 카드 배경은 흰색이다', (tester) async {
    final event = LockerEvent(
      id: 'split-uniform',
      title: 'IB 경기',
      start: DateTime(2026, 8, 20, 18),
      end: DateTime(2026, 8, 20, 20),
      place: '71동 종합체육관',
      kind: EventKind.ibDivision1,
      memo: '',
      uniformColors: const ['검정', '흰색'],
      responseEnabled: false,
    );
    await tester.pumpWidget(
      _signedInApp(
        Scaffold(
          body: EventTicket(event: event, heroTag: 'test', onTap: () {}),
        ),
      ),
    );

    final ink = tester.widget<Ink>(find.byType(Ink).first);
    final decoration = ink.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.gradient, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('검정 유니폼 일정도 목록 카드 배경은 흰색이다', (tester) async {
    final event = LockerEvent(
      id: 'black-uniform',
      title: 'IB 1부',
      start: DateTime(2026, 8, 16, 18),
      end: DateTime(2026, 8, 16, 20),
      place: '71동 종합체육관',
      kind: EventKind.ibDivision1,
      memo: '',
      uniformColors: const ['검정'],
      responseEnabled: false,
    );
    await tester.pumpWidget(
      _signedInApp(
        Scaffold(
          body: EventTicket(event: event, heroTag: 'black', onTap: () {}),
        ),
      ),
    );

    final ink = tester.widget<Ink>(find.byType(Ink).first);
    final decoration = ink.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.gradient, isNull);
    expect(tester.takeException(), isNull);
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

  test('복기 영상의 쿼터·미정 링크와 경기 날짜가 캐시에 보존된다', () {
    final video = VideoItem(
      id: 'review-1',
      title: '정기전 복기',
      durationLabel: '',
      category: '복기',
      url: 'https://youtu.be/quarter-1',
      youtubeId: 'quarter-1',
      uploadedAt: DateTime(2026, 8, 13),
      recordedOn: DateTime(2026, 8, 10),
      uploader: '김민수',
      accent: 0xFF00539B,
      sourceType: 'youtube',
      links: const [
        VideoLink(url: 'https://youtu.be/quarter-1', quarterNumber: 1, id: 11),
        VideoLink(url: 'https://youtu.be/quarter-3', quarterNumber: 3, id: 13),
        VideoLink(url: 'https://youtu.be/overtime'),
      ],
      reviewPlayers: const [
        VideoTaggedMember(
          directoryId: 'allowlist:1',
          name: '김민수',
          studentYear: 22,
          jerseyNumber: 7,
        ),
        VideoTaggedMember(directoryId: 'allowlist:2', name: '박지훈'),
      ],
    );

    final restored = VideoItem.fromJson(video.toJson());
    expect(restored.sourceType, 'youtube');
    expect(restored.recordedOn, DateTime(2026, 8, 10));
    expect(restored.links.map((link) => link.url), [
      'https://youtu.be/quarter-1',
      'https://youtu.be/quarter-3',
      'https://youtu.be/overtime',
    ]);
    // 앞 네 쿼터는 예전 컬럼과 맞물리도록 계속 뽑아낼 수 있어야 한다.
    expect(restored.quarterUrls, [
      'https://youtu.be/quarter-1',
      null,
      'https://youtu.be/quarter-3',
      null,
    ]);
    expect(restored.reviewPlayers.first.label, '김민수 (7)');
    expect(restored.reviewPlayers.map((member) => member.directoryId), [
      'allowlist:1',
      'allowlist:2',
    ]);
    expect(restored.uploader, '김민수');
  });

  test('링크 테이블 이전에 저장된 캐시의 쿼터 배열도 링크로 읽힌다', () {
    final legacy = {
      'id': 'review-legacy',
      'title': '예전 복기',
      'durationLabel': '',
      'category': '복기',
      'url': 'https://youtu.be/quarter-1',
      'youtubeId': 'quarter-1',
      'uploadedAt': DateTime(2026, 8, 13).toIso8601String(),
      'uploader': '김민수',
      'accent': 0xFF00539B,
      'quarterUrls': ['https://youtu.be/quarter-1', null, null, null],
    };

    final restored = VideoItem.fromJson(legacy);
    expect(restored.links, hasLength(1));
    expect(restored.links.single.quarterNumber, 1);
    expect(restored.recordedOn, isNull);
  });

  test('쿼터 미정 링크는 쿼터 링크 뒤에 등록 순서대로 선다', () {
    final sorted = sortedVideoLinks(const [
      VideoLink(url: 'https://youtu.be/undecided-1'),
      VideoLink(url: 'https://youtu.be/q2', quarterNumber: 2),
      VideoLink(url: 'https://youtu.be/undecided-2'),
      VideoLink(url: 'https://youtu.be/q1', quarterNumber: 1),
    ]);

    expect(sorted.map((link) => link.url), [
      'https://youtu.be/q1',
      'https://youtu.be/q2',
      'https://youtu.be/undecided-1',
      'https://youtu.be/undecided-2',
    ]);
  });

  test('선수 목록은 학번이 높은 순으로 선다', () {
    final members = [
      const VideoTaggedMember(directoryId: 'a', name: '박지훈', studentYear: 20),
      const VideoTaggedMember(directoryId: 'b', name: '김민수', studentYear: 25),
      const VideoTaggedMember(directoryId: 'c', name: '이서준'),
    ]..sort(compareTaggedMembers);

    expect(members.map((member) => member.name), ['김민수', '박지훈', '이서준']);
  });

  test('영상 공유 대상과 외부 장소 지도 주소가 캐시에 보존된다', () {
    final video = VideoItem(
      id: 'shared-1',
      title: '가드 스킬 영상',
      durationLabel: '',
      category: '공유',
      url: 'https://youtu.be/M7lc1UVf-VE',
      youtubeId: 'M7lc1UVf-VE',
      uploadedAt: DateTime(2026, 8, 13),
      uploader: '최재원',
      accent: 0xFF00539B,
      audienceType: 'position',
      audienceValues: const ['PG', 'SG'],
    );
    final restoredVideo = VideoItem.fromJson(video.toJson());
    expect(restoredVideo.audienceType, 'position');
    expect(restoredVideo.audienceValues, ['PG', 'SG']);

    final event = LockerEvent(
      id: 'external-1',
      title: '외부 경기',
      start: DateTime(2026, 8, 20, 18),
      end: DateTime(2026, 8, 20, 20),
      place: '관악구민종합체육센터',
      kind: EventKind.external,
      memo: '',
      mapReference: '서울 관악구 낙성대로3길 37',
    );
    final restoredEvent = LockerEvent.fromJson(event.toJson());
    expect(restoredEvent.mapReference, '서울 관악구 낙성대로3길 37');
    expect(restoredEvent.start.day, restoredEvent.end.day);
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

  testWidgets('복기 출전 선수는 학번 높은 순이며 등번호를 달고 선택창을 닫을 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const members = [
      MemberProfile(
        id: 'member-ha',
        name: '하승윤',
        studentId: '22',
        generation: 2022,
        status: 'YB',
        position: 'C',
        teams: ['ENCBA'],
        note: '',
      ),
      MemberProfile(
        id: 'member-kim',
        name: '김창용',
        studentId: '23',
        generation: 2023,
        status: 'YB',
        position: 'F',
        teams: ['ENCBA'],
        note: '',
      ),
      MemberProfile(
        id: 'member-kang',
        name: '강준성',
        studentId: '24',
        generation: 2024,
        status: 'YB',
        position: 'G',
        teams: ['ENCBA'],
        note: '',
        jerseyNumber: 11,
      ),
    ];
    await tester.pumpWidget(
      _signedInApp(
        const LockerShell(),
        lockerState: LockerState(isReady: true, members: members),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('영상').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('복기').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('영상 링크 추가'));
    await tester.tap(find.text('영상 링크 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('출전 선수 선택'));
    await tester.pumpAndSettle();

    // 24학번 → 23학번 → 22학번 순으로 서고, 등번호가 있으면 이름 옆에 붙는다.
    expect(
      tester.getTopLeft(find.text('강준성 (11)')).dy,
      lessThan(tester.getTopLeft(find.text('김창용')).dy),
    );
    expect(
      tester.getTopLeft(find.text('김창용')).dy,
      lessThan(tester.getTopLeft(find.text('하승윤')).dy),
    );
    expect(find.text('선택 완료'), findsOneWidget);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('선택 완료'), findsNothing);
    expect(find.text('복기 추가'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('인원 제한 슬라이더는 2~20명 범위이고 끝까지 끌어도 안전하다', (tester) async {
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

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 2);
    expect(slider.max, 20);

    // 끝값(max)에서도 렌더링이 안전한지 직접 콜백을 호출해 확인한다.
    // (예전엔 값 말풍선 위치를 직접 계산해서 끝값 근처에서 어긋났었다.)
    slider.onChanged!(20);
    await tester.pumpAndSettle();
    expect(find.text('20명까지'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('홈에서 오늘의 준비 상태를 표시하지 않는다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 준비 상태'), findsNothing);
    expect(find.text('물통과 개인 준비물 챙김'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('관리자는 멤버 디렉토리에서 출결 정리 시트를 연다', (tester) async {
    await tester.pumpWidget(_signedInApp(const MemberDirectoryScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('출결 정리 시트'));
    await tester.pumpAndSettle();

    expect(find.text('출결 정리 시트'), findsOneWidget);
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('신입생'), findsOneWidget);
    expect(find.text('정리할 출결 정보가 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('군대·비활성 칩은 배타적으로 작동해 해당 인원만 남긴다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const members = [
      MemberProfile(
        id: 'member-active',
        name: '김철수',
        studentId: '22학번',
        generation: 2022,
        status: 'YB',
        position: 'PG',
        teams: ['ENCBA'],
        note: '',
      ),
      MemberProfile(
        id: 'member-military',
        name: '박군인',
        studentId: '21학번',
        generation: 2021,
        status: 'MILITARY_LEAVE',
        position: 'SF',
        teams: ['ENCBA'],
        note: '',
      ),
      MemberProfile(
        id: 'member-inactive',
        name: '이비활',
        studentId: '20학번',
        generation: 2020,
        status: 'YB',
        position: 'C',
        teams: ['ENCBA'],
        note: '',
        isActive: false,
      ),
    ];
    await tester.pumpWidget(
      _signedInApp(
        const MemberDirectoryScreen(),
        lockerState: LockerState(isReady: true, members: members),
      ),
    );
    await tester.pumpAndSettle();

    // 기본 상태: 군휴학·비활성 인원은 목록에서 빠진다.
    expect(find.text('김철수'), findsOneWidget);
    expect(find.text('박군인'), findsNothing);
    expect(find.text('이비활'), findsNothing);

    // "군대" 칩을 켜면 군휴학 인원만 남아야 한다(다른 사람이 같이 보이면 안 된다).
    // 첫 탭은 칩의 선택 애니메이션 레이어 때문에 히트테스트 경고가 나올 수 있어 무시한다.
    await tester.tap(find.text('군대'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('박군인'), findsOneWidget);
    expect(find.text('김철수'), findsNothing);
    expect(find.text('이비활'), findsNothing);

    // 다시 끄고 "비활성" 칩을 켜면 비활성 인원만 남아야 한다.
    await tester.tap(find.text('군대'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('비활성'));
    await tester.pumpAndSettle();
    expect(find.text('이비활'), findsOneWidget);
    expect(find.text('김철수'), findsNothing);
    expect(find.text('박군인'), findsNothing);
  });

  testWidgets('영상 정렬 메뉴는 좋아요순을 제공한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const LockerShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('영상').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('영상 정렬'));
    await tester.pumpAndSettle();

    expect(find.text('좋아요순'), findsOneWidget);
  });

  testWidgets('농구장 예약은 시설별 타이머와 통합 예약 버튼을 표시한다', (tester) async {
    await tester.pumpWidget(_signedInApp(const CourtReservationScreen()));
    await tester.pumpAndSettle();

    expect(find.text('71 · 71-1 RESERVATION'), findsOneWidget);
    expect(find.text('900 RESERVATION'), findsOneWidget);
    expect(find.textContaining('남음'), findsNWidgets(2));
    expect(find.text('71동 · 71-1동 예약하기'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('900동 예약하기'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('900동 예약하기'), findsOneWidget);
  });

  testWidgets('예약 화면은 시설마다 남은 시간 바로 아래 예약 버튼을 둔다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_signedInApp(const CourtReservationScreen()));
    await tester.pumpAndSettle();

    final athletics = tester.getTopLeft(find.text('71동 · 71-1동 예약하기')).dy;
    final dormCountdown = tester.getTopLeft(find.text('900 RESERVATION')).dy;
    final dorm = tester.getTopLeft(find.text('900동 예약하기')).dy;
    expect(athletics, lessThan(dormCountdown));
    expect(dormCountdown, lessThan(dorm));
  });

  testWidgets('멤버 상세는 전화번호와 등번호를 보여준다', (tester) async {
    const member = MemberProfile(
      id: 'member-kim',
      name: '김창용',
      studentId: '23학번',
      generation: 2023,
      status: 'YB',
      position: 'SG',
      teams: ['ENCBA'],
      note: '',
      phone: '010-1234-5678',
      jerseyNumber: 23,
    );
    await tester.pumpWidget(
      _signedInApp(
        const MemberDetailScreen(memberId: 'member-kim'),
        lockerState: LockerState(isReady: true, members: const [member]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SG · #23'), findsOneWidget);
    expect(find.text('010-1234-5678'), findsOneWidget);
  });

  testWidgets('복기 추가는 쿼터를 늘리거나 쿼터 미정 링크를 붙일 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _signedInApp(
        const LockerShell(),
        lockerState: LockerState(isReady: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('영상').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('복기').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('영상 링크 추가'));
    await tester.tap(find.text('영상 링크 추가'));
    await tester.pumpAndSettle();

    expect(find.text('4쿼터'), findsOneWidget);
    await tester.ensureVisible(find.text('쿼터 추가'));
    await tester.tap(find.text('쿼터 추가'));
    await tester.pumpAndSettle();
    expect(find.text('5쿼터'), findsOneWidget);

    expect(find.text('미정'), findsNothing);
    await tester.ensureVisible(find.text('쿼터 미정'));
    await tester.tap(find.text('쿼터 미정'));
    await tester.pumpAndSettle();
    expect(find.text('미정'), findsOneWidget);
    expect(find.text('경기 날짜'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('농구 영상 공유에는 경기 날짜를 표시하지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _signedInApp(
        const LockerShell(),
        lockerState: LockerState(isReady: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('영상').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('공유').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('유튜브 영상 공유'));
    await tester.pumpAndSettle();

    expect(find.text('농구 영상 공유'), findsOneWidget);
    expect(find.text('경기 날짜'), findsNothing);
  });
}

Widget _signedOutApp(
  Widget child, {
  PendingGoogleRegistration? pendingRegistration,
}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(
      (ref) =>
          AuthController.seeded(null, pendingRegistration: pendingRegistration),
    ),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

/// 로그인 이후 화면은 실제 앱과 같은 GoRouter 정의 안에 마운트한다.
Widget _signedInApp(
  Widget child, {
  UserProfile user = testUser,
  LockerState? lockerState,
  String initialLocation = '/',
}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith((ref) => AuthController.seeded(user)),
    lockerControllerProvider.overrideWith(
      (ref) => LockerController.seeded(initialState: lockerState),
    ),
  ],
  child: MaterialApp.router(
    theme: AppTheme.lightTheme,
    routerConfig: GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (context, state) => child),
        GoRoute(
          path: '/:tab(${LockerTab.pathPattern})',
          pageBuilder: (context, state) => NoTransitionPage(
            key: const ValueKey('locker-shell'),
            child: child,
          ),
        ),
        ...lockerRoutes,
      ],
    ),
  ),
);

/// 세션 복원이 늦게 끝나는 상황을 흉내 낸다. 생성 시점에는 아직 준비 전이고,
/// [finishRestore]를 부르면 "로그아웃 상태로 준비 완료"가 된다.
class _DelayedRestoreAuthController extends AuthController {
  _DelayedRestoreAuthController() : super.seeded(null) {
    state = const AuthState();
  }

  void finishRestore() => state = const AuthState(isReady: true);
}
