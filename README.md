# ENCBA LOCKER

서울대학교 공대 농구동아리 ENCBA의 모바일 우선 운영 앱입니다. Flutter Web으로 개발하며 데스크톱에서도 최대 430px 모바일 프레임을 유지합니다.

## 주요 기능

- 실명 기반 Supabase Auth와 가입 허용 명단
- 공지, 일정, 참석·불참·미정 투표와 팀에 공개되는 불참 사유
- IB 1·2부, 아농·자개·픽업게임, 연습 경기·삼파전 관리
- YouTube 복기·공유, Instagram 하이라이트, 좋아요·시청 기록
- 정렬·상태 필터가 있는 멤버 디렉터리, IB 운영표 Excel 가져오기·운영 교환, 홈커밍 연락 보드
- 오늘의 준비 상태, 한국어 날짜 선택기, 작성자 정보가 채워지는 오류 제보 메일
- 로컬 캐시와 로그인 세션 유지
- 20건 단위 일정 페이지 조회와 장애별 독립 로딩

관리자와 주장은 공지·일정·계정을 관리합니다. 매니저는 하이라이트를 등록합니다. 권한은 Flutter UI가 아니라 Supabase RLS와 DB 함수에서 최종 검증합니다.

## 로컬 실행

`.env.example`을 참고해 `.env`에 공개 클라이언트 값만 보관합니다. Flutter 빌드에는 `--dart-define`으로 전달합니다.

```env
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

```powershell
$env:SUPABASE_URL='https://YOUR_PROJECT.supabase.co'
$env:SUPABASE_PUBLISHABLE_KEY='YOUR_PUBLISHABLE_KEY'
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat run -d chrome `
  --dart-define="SUPABASE_URL=$env:SUPABASE_URL" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY"
```

`service_role` 또는 secret key는 앱, Render, Git에 넣지 않습니다.

## Supabase

이 저장소는 순차 SQL 마이그레이션 방식을 사용합니다.

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
npx supabase migration list --linked
npx supabase db lint --linked --level error
```

초기 명단은 `supabase/seed.sql`에 있습니다. 실명 로그인용 가상 이메일은 앱 내부에서만 만들며 비밀번호는 Supabase Auth가 해시로 저장합니다.
Supabase Auth의 Email Confirm은 끄고, Site URL에 Render 주소를 등록합니다.

관리자는 `IB 운영 일정` 화면의 업로드 버튼으로 `26-1 IB리그 운영표.xlsx` 형식의 파일을 가져올 수 있습니다. 표의 날짜·운영 A/B·심판·담당자를 읽고, 아직 가입하지 않은 담당자 이름도 보존했다가 가입 후 자동 연결합니다. 마이그레이션 적용 전에는 이 기능이 동작하지 않습니다.

부원은 앞으로 예정된 상대 운영 중 하나를 골라 자신의 운영과 맞교환을 신청합니다. 상대가 수락할 때 두 배정은 하나의 DB 트랜잭션으로 함께 바뀌며, 요청자는 임의로 다른 사람의 배정을 수정할 수 없습니다. IB 운영은 PERSONAL뿐 아니라 PLANNER와 홈 준비 상태에도 표시됩니다.

`오류 제보`는 웹에서는 Gmail 작성창을, 앱에서는 기기의 기본 메일 앱을 열어 받는 사람, 제목, 작성자·학번·계정·실행 환경과 입력 내용을 자동으로 채웁니다. 마지막 전송은 사용자가 내용을 확인한 뒤 직접 누릅니다.

기능 확인용 일정은 관리자 개인 화면의 `테스트 일정 만들기`에서 한 번에 추가합니다.

## iOS 알림

iOS 빌드는 공지와 미정 일정 알림을 네이티브 알림 센터 형식으로 표시합니다. 현재 구현은 앱이 실행 중일 때 발생한 알림을 로컬 알림으로 전달합니다. 앱이 완전히 종료된 상태의 원격 푸시는 APNs 키와 서버 발송 함수가 준비된 뒤 연결합니다.

## 검증과 배포

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat build web --release `
  --dart-define="SUPABASE_URL=$env:SUPABASE_URL" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY"
```

Render는 루트의 `render.yaml`과 `Dockerfile`을 사용합니다. 환경변수는 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` 두 개입니다. 자동 배포는 꺼져 있어 Render Dashboard에서 수동 배포합니다.
