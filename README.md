# ENCBA LOCKER

서울대학교 공대 농구동아리 ENCBA의 모바일 우선 운영 앱입니다. Flutter Web으로 개발하며 데스크톱에서도 최대 430px 모바일 프레임을 유지합니다.

## 주요 기능

- 학교 Google 계정 기반 신규 가입, 기존 실명 로그인과 가입 허용 명단
- 공지, 일정, 참석·불참·미정 투표와 댓글처럼 읽히는 문장형 불참 사유("개인 선약이 있어서 불참합니다.")
- 관리자의 응답 독촉하기 — 아직 응답하지 않은 활동 부원에게 푸시 알림 일괄 발송
- IB 1·2부, 아농·자개·픽업게임, 연습 경기·삼파전·외부 경기 관리
- IB·외부 경기 주전 지정과 일정 상세의 공동 전술·전략 노트
- 서버시각 기반 71동·71-1동 예약 오픈 타이머와 900동 예약 안내
- YouTube 복기·공유, Instagram 하이라이트, 좋아요와 링크 복사
- 복기 영상은 쿼터 수를 늘리거나 쿼터 미정 링크를 덧붙일 수 있고, 경기 날짜를 따로 적습니다
- 복기 코멘트는 재생 위치를 실시간으로 따라가며, 고정해 두고 작성할 수 있습니다
- 가나다순이 기본 정렬인 멤버 디렉토리. 동명이인은 학번 배지로 구분합니다
- 군 휴학·교환학생·유학·비활동은 모두 비활성으로 취급해 활동 명단·로스터 집계에서 제외합니다
- 직전 학기 시작(방학 포함)부터 오늘까지가 기본 범위인 관리자용 출결 정리 시트와 전체·신입생 출결표 Excel 내보내기
- 홈 화면의 앱 수요조사 별 버튼 — 부원은 눌러 수요를 표시하고, 집계는 관리자에게만 보입니다
- 앱 안에서 저장되는 오류 제보와 관리자 전용 오류 제보함(읽음 표시·삭제)
- 복수 일정 연결 공지, IB 운영표 Excel 가져오기·운영 교환, 홈커밍 연락 보드
- 로컬 캐시와 로그인 세션 유지
- 20건 단위 일정 페이지 조회와 장애별 독립 로딩

관리자와 주장은 공지·일정을 관리하고, 계정·예약자 역할 지정은 관리자만 수행합니다. 매니저는 하이라이트를 등록합니다. 권한은 Flutter UI가 아니라 Supabase RLS와 DB 함수에서 최종 검증합니다.

## 로컬 실행

`.env.example`을 참고해 `.env`에 공개 클라이언트 값만 보관합니다. Flutter 빌드에는 `--dart-define`으로 전달합니다.

```env
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
YOUTUBE_API_KEY=YOUR_BROWSER_RESTRICTED_YOUTUBE_API_KEY
```

Firebase 원격 알림을 사용할 때만 `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`,
`FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_WEB_APP_ID`, `FIREBASE_VAPID_KEY`를
추가합니다. 이 값들은 웹 클라이언트 식별용 공개 설정이며 Firebase 서비스 계정
JSON과 Supabase `service_role` 키는 포함하지 않습니다.

VS Code에서는 `ENCBA LOCKER (Chrome + .env)` 실행 구성을 선택합니다. 웹 릴리스 빌드는 아래 명령이 `.env`를 자동으로 전달합니다.

```powershell
.\tool\build_web.ps1
```

```powershell
$env:SUPABASE_URL='https://YOUR_PROJECT.supabase.co'
$env:SUPABASE_PUBLISHABLE_KEY='YOUR_PUBLISHABLE_KEY'
$env:YOUTUBE_API_KEY='YOUR_BROWSER_RESTRICTED_YOUTUBE_API_KEY'
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat run -d chrome `
  --dart-define="SUPABASE_URL=$env:SUPABASE_URL" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY" `
  --dart-define="YOUTUBE_API_KEY=$env:YOUTUBE_API_KEY"
```

`service_role`, Firebase 서비스 계정 JSON 또는 그 밖의 secret key는 앱,
Vercel 클라이언트 환경변수, Git에 넣지 않습니다.

## Supabase

이 저장소는 순차 SQL 마이그레이션 방식을 사용합니다.

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
npx supabase migration list --linked
npx supabase db lint --linked --level error
```

초기 명단은 `supabase/seed.sql`에 있습니다. 신규 가입은 `snu.ac.kr` 계열 Google 계정을 먼저 인증한 뒤 명단의 실명과 회원정보를 확인합니다. 기존 부원의 실명 로그인용 가상 이메일은 앱 내부에서만 만들며 비밀번호는 Supabase Auth가 해시로 저장합니다.
Supabase Auth의 Google Provider에는 Google Cloud의 Web Client ID와 Client Secret을 등록합니다. `Site URL`은 Vercel의 고정 Production Domain으로 지정하고, 같은 도메인의 `/sign-in`과 필요한 Vercel Preview Domain을 Redirect URLs에 추가합니다. Google OAuth의 승인된 리디렉션 URI는 앱 주소가 아니라 `https://<project-ref>.supabase.co/auth/v1/callback`입니다. Client Secret은 앱·환경 파일·Git에 넣지 않습니다.

관리자는 `IB 운영 일정` 화면의 업로드 버튼으로 `26-1 IB리그 운영표.xlsx` 형식의 파일을 가져올 수 있습니다. 표의 날짜·운영 A/B·심판·담당자를 읽고, 아직 가입하지 않은 담당자 이름도 보존했다가 가입 후 자동 연결합니다. 마이그레이션 적용 전에는 이 기능이 동작하지 않습니다.

부원은 앞으로 예정된 상대 운영 중 하나를 골라 자신의 운영과 맞교환을 신청합니다. 상대가 수락할 때 두 배정은 하나의 DB 트랜잭션으로 함께 바뀌며, 요청자는 임의로 다른 사람의 배정을 수정할 수 없습니다. IB 운영은 PERSONAL뿐 아니라 PLANNER와 홈 준비 상태에도 표시됩니다.

`오류 제보`는 메일이 아니라 앱 안에서 `error_reports` 테이블로 저장됩니다. 작성자·학번·계정·실행 환경은 자동으로 함께 기록되고, 관리자는 PERSONAL 화면의 **오류 제보함**에서 제보를 읽고 읽음 표시를 하거나 삭제합니다. 제보는 RLS로 관리자만 조회할 수 있습니다.

## 알림

웹은 브라우저 Notification API를 사용합니다. 웹 구현은 `package:web`과 `dart.library.js_interop` 조건부 임포트로 작성해 `--wasm` 빌드에서도 그대로 살아 있습니다. `dart:html`은 wasm 타깃에서 사용할 수 없으므로 다시 도입하지 않습니다.

원격 푸시는 FCM 토큰을 `push_subscriptions` 테이블에 등록하고 Supabase Edge Function `send-push`가 발송합니다. 긴급 공지는 DB 웹훅으로, 출결 마감 3시간 전 리마인더는 크론으로 자동 발송됩니다. 관리자가 일정 상세에서 누르는 **응답 독촉하기**는 호출자 JWT로 관리자 권한을 검증한 뒤 같은 함수로 미응답자에게만 발송합니다. 카테고리(공지/일정)별 수신 설정은 홈의 종 아이콘에서 바꿀 수 있습니다.

## 검증

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat build web --release `
  --dart-define="SUPABASE_URL=$env:SUPABASE_URL" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY" `
  --dart-define="YOUTUBE_API_KEY=$env:YOUTUBE_API_KEY"
```

이 점검은 GitHub Actions(`.github/workflows/flutter_checks.yml`)가 push·PR마다 자동으로
실행합니다. 여기에 더해 저장소 시크릿에 `SUPABASE_PROJECT_REF`와
`SUPABASE_ACCESS_TOKEN`을 등록하면 RLS·RPC 회귀를 잡는
`supabase db lint --linked --level error` 잡도 함께 돕니다.

## Vercel 배포

웹 프런트엔드는 Vercel만 사용합니다. 루트의 `vercel.json`이
`tool/vercel_build.sh`를 실행해 Flutter Web WASM 산출물을 `build/web`에 만들고,
SPA 딥 링크, 보안 헤더와 `/healthz` 응답을 설정합니다. `master`에 푸시하면 연결된
Vercel 프로젝트가 Production 배포를 생성합니다.

필수 환경변수는 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
`YOUTUBE_API_KEY`입니다. YouTube 키는 Vercel Production/Preview 도메인만 허용하는
HTTP 리퍼러와 YouTube Data API v3로 제한합니다. Firebase 원격 알림을 사용할 때는
위의 공개 Firebase 변수도 Vercel에 추가합니다.

프로젝트 생성, 고정 도메인, Supabase OAuth, 검증과 롤백 절차는
[`docs/deployment.md`](docs/deployment.md)를 따릅니다.
