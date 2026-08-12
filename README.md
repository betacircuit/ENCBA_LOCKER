# ENCBA LOCKER

서울대학교 공대 농구동아리 ENCBA의 모바일 우선 운영 앱입니다. Flutter Web으로 개발하며 데스크톱에서도 최대 430px 모바일 프레임을 유지합니다.

## 주요 기능

- 실명 기반 Supabase Auth와 가입 허용 명단
- 공지, 일정, 참석·불참·미정 투표와 불참 사유
- IB 1·2부, 내부 경기, 연습 경기, 삼파전 관리
- YouTube 복기·공유, Instagram 하이라이트, 좋아요·시청 기록
- 멤버 디렉터리, IB 운영 일정, 홈커밍 연락 보드
- 로컬 캐시와 로그인 세션 유지

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
```

초기 명단은 `supabase/seed.sql`에 있습니다. 실명 로그인용 가상 이메일은 앱 내부에서만 만들며 비밀번호는 Supabase Auth가 해시로 저장합니다.
Supabase Auth의 Email Confirm은 끄고, Site URL에 Render 주소를 등록합니다.

## 검증과 배포

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat build web --release `
  --dart-define="SUPABASE_URL=$env:SUPABASE_URL" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY"
```

Render는 루트의 `render.yaml`과 `Dockerfile`을 사용합니다. 환경변수는 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` 두 개입니다. 자동 배포는 꺼져 있어 Render Dashboard에서 수동 배포합니다.
