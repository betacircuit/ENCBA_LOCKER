# ENCBA LOCKER

서울대학교 공대 농구동아리 ENCBA의 모바일 우선 운영 앱입니다. Flutter Web으로 개발하며 데스크톱에서도 최대 430px 모바일 프레임을 유지합니다.

## 주요 기능

- 학교 Google 계정 기반 신규 가입, 기존 실명 로그인과 가입 허용 명단
- 공지, 일정, 참석·불참·미정 투표와 팀에 공개되는 불참 사유
- IB 1·2부, 아농·자개·픽업게임, 연습 경기·삼파전·외부 경기 관리
- IB·외부 경기 주전 지정과 일정 상세의 공동 전술·전략 노트
- 서버시각 기반 71동·71-1동 예약 오픈 타이머와 900동 예약 안내
- YouTube 복기·공유, Instagram 하이라이트, 좋아요와 링크 복사
- 복기 영상은 쿼터 수를 늘리거나 쿼터 미정 링크를 덧붙일 수 있고, 경기 날짜를 따로 적습니다
- 복기 코멘트는 재생 위치를 실시간으로 따라가며, 고정해 두고 작성할 수 있습니다
- 신입생 특성과 관리자용 전체·신입생 출결표 Excel 내보내기를 갖춘 멤버 디렉터리
- 복수 일정 연결 공지, IB 운영표 Excel 가져오기·운영 교환, 홈커밍 연락 보드
- 한국어 날짜 선택기와 작성자 정보가 채워지는 오류 제보 메일
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

`service_role` 또는 secret key는 앱, Vercel 클라이언트 환경변수, Git에 넣지 않습니다.

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

`오류 제보`는 웹에서는 Gmail 작성창을, 앱에서는 기기의 기본 메일 앱을 열어 받는 사람, 제목, 작성자·학번·계정·실행 환경과 입력 내용을 자동으로 채웁니다. 마지막 전송은 사용자가 내용을 확인한 뒤 직접 누릅니다.

## 알림

웹은 브라우저 Notification API를 사용합니다. 웹 구현은 `package:web`과 `dart.library.js_interop` 조건부 임포트로 작성해 `--wasm` 빌드에서도 그대로 살아 있습니다. `dart:html`은 wasm 타깃에서 사용할 수 없으므로 다시 도입하지 않습니다.

iOS 빌드는 공지와 미정 일정 알림을 네이티브 알림 센터 형식으로 표시합니다. 체육관 예약자에게는 다음 화요일 09:30 오픈 5분 전 로컬 알림을 예약하며, 알림 수신 여부는 홈의 종 아이콘에서 설정합니다. 앱이 완전히 종료된 상태의 원격 푸시는 APNs 키와 서버 발송 함수가 준비된 뒤 연결합니다.

## 검증

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat build web --release `
  --dart-define="SUPABASE_URL=$env:SUPABASE_URL" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY" `
  --dart-define="YOUTUBE_API_KEY=$env:YOUTUBE_API_KEY"
```

## Vercel 배포

웹 프런트엔드는 Vercel만 사용합니다. 루트의 `vercel.json`이
`tool/vercel_build.sh`를 실행해 Flutter Web WASM 산출물을 `build/web`에 만들고,
SPA 딥 링크, 보안 헤더와 `/healthz` 응답을 설정합니다. `master`에 푸시하면 연결된
Vercel 프로젝트가 Production 배포를 생성합니다.

필수 환경변수는 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
`YOUTUBE_API_KEY`입니다. YouTube 키는 Vercel Production/Preview 도메인만 허용하는
HTTP 리퍼러와 YouTube Data API v3로 제한합니다.

프로젝트 생성, 고정 도메인, Supabase OAuth, 검증과 롤백 절차는
[`docs/deployment.md`](docs/deployment.md)를 따릅니다.
