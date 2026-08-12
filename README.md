# ENCBA LOCKER

서울대학교 공대 농구 동아리 ENCBA의 모바일 우선 운영 앱입니다. Stitch 프로젝트 `17863437647083782609`의 홈, 일정, 멤버 디렉토리 화면과 `Athletic Excellence` 디자인 시스템을 바탕으로 실제 운영 흐름에 맞게 다시 설계했습니다. 데스크톱에서도 폭 430px의 모바일 앱 프레임으로 표시됩니다.

Supabase Auth와 PostgreSQL을 계정·권한·운영 데이터의 기준 서버로 사용합니다. Flutter Web은 Docker/Nginx 이미지로 빌드되어 Render에 배포되며, 데스크톱에서도 폭 430px의 모바일 앱 프레임을 유지합니다.

로그인 화면의 관리자·부원 버튼은 `admin@encba.kr`와 `member@encba.kr`를 입력합니다. 실제 계정은 Supabase Auth에 가입되어 있어야 하며, 관리자 권한은 DB의 `profiles.is_admin`으로만 부여됩니다. 클라이언트가 관리자 값을 변경하는 것은 RLS와 보호 트리거로 차단됩니다.

일정·참석·영상·좋아요는 Supabase와 동기화됩니다. 마지막 정상 조회 결과는 기기에 캐시되어 오프라인에서도 읽을 수 있고, 세션은 Supabase SDK의 플랫폼 저장소에 유지됩니다. 지도·YouTube·서버 쓰기는 네트워크가 필요합니다.

## 1. Supabase 연결

Supabase 프로젝트를 만든 뒤 CLI에서 저장소를 연결하고 마이그레이션을 적용합니다.

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

마이그레이션은 [초기 스키마](supabase/migrations/202608120001_initial_schema.sql)에 있습니다. `profiles`, 팀·시즌·리그·장소, 일정·참석, 공지, 영상·좋아요·타임스탬프 댓글, 감사 로그와 비공개 아바타 버킷을 생성합니다.

Supabase Dashboard의 Authentication → URL Configuration에서 Site URL을 실제 Render 주소로 지정하고, 필요하면 `http://localhost:*`를 개발용 Redirect URL에 추가합니다. 이메일 확인을 켠 경우 가입자는 확인 메일 인증 후 로그인해야 합니다.

초기 명단과 관리자 설정은 [seed.sql](supabase/seed.sql)을 SQL Editor에서 실행합니다. 가입 허용 명단 검사는 기본으로 켜져 있으므로 먼저 허용 명단 INSERT를 실행하고, 앱에서 두 계정을 가입시킨 다음 `admin@encba.kr` 승격 문장을 다시 실행해야 합니다. 개발 중 명단 검사를 잠시 끄려면 다음 값만 `false`로 바꿀 수 있습니다.

```sql
update public.app_settings
set value = 'false'::jsonb
where key = 'enforce_member_allowlist';
```

`service_role` 키는 Flutter 앱, Render 환경변수, Git 저장소 어디에도 넣지 않습니다. 클라이언트에는 Supabase가 공개 클라이언트용으로 제공하는 publishable key만 사용합니다.

## 2. 로컬 실행

```powershell
$env:SUPABASE_URL='https://YOUR_PROJECT.supabase.co'
$env:SUPABASE_PUBLISHABLE_KEY='YOUR_PUBLISHABLE_KEY'
C:\flutter\bin\flutter.bat run -d chrome `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY
```

## 3. Render 배포

저장소 루트의 [render.yaml](render.yaml)을 Render Blueprint로 연결합니다. 생성 화면에서 아래 두 값을 입력합니다.

- `SUPABASE_URL`: Supabase Project URL
- `SUPABASE_PUBLISHABLE_KEY`: Supabase publishable key

Render는 [Dockerfile](Dockerfile)로 Flutter Web을 빌드하고 Nginx가 `${PORT}`에서 서비스합니다. `/healthz` 상태 확인, SPA 라우팅, gzip, 정적 파일 캐시와 보안 헤더가 포함되어 있습니다. 배포 후 Render URL을 Supabase의 Site URL/Redirect URL에도 등록해야 합니다.

## 검증

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat build web --release `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY
```

## Stitch 원본

원본 내보내기는 `stitch_reference/`에 화면별로 보존했습니다. 각 폴더에는 Stitch의 `code.html`, `screen.png`, `DESIGN.md`가 있습니다.

## DB 최적화와 보안

다가오는 일정, 시즌·리그 일정, 사용자별 참석, 영상 피드·좋아요·댓글, 감사 로그 조회에 맞춘 복합·부분 인덱스를 포함합니다. RLS 식에서는 `(select auth.uid())`와 안정적인 관리자 함수를 사용해 행마다 인증 함수를 다시 평가하는 비용을 줄였습니다. 좋아요 수는 트리거로 원자적으로 집계하며, 일정·공지·영상 변경은 감사 로그로 남습니다. 프로필 사진은 DB의 Base64 문자열이 아니라 제한된 Storage 버킷에 저장됩니다.
