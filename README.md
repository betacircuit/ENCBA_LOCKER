# ENCBA LOCKER

서울대학교 공대 농구동아리 ENCBA의 운영 앱. Flutter Web으로 만들고 Vercel에 배포하며, 데이터와 권한은 Supabase가 맡는다. 모바일 우선이고 데스크톱에서도 430px 폭의 모바일 프레임을 유지한다.

## 화면과 기능

앱은 다섯 탭으로 나뉜다. 각 탭에서 실제로 무엇을 할 수 있는지만 적는다.

### 홈

- 가장 가까운 일정 한 건을 카드로 띄우고, 카드에서 바로 참석·불참을 고른다.
- 공지 목록. 사진과 투표를 붙일 수 있고, 투표는 항목마다 정원을 둘 수 있다. 정원이 차면 그 항목은 잠긴다.
- 종 아이콘의 알림 패널. 받은 알림이 항목·시각과 함께 쌓이고, 누르면 해당 화면으로 이동하면서 읽음으로 표시된다. 읽은 알림만 골라 지운다.
- 관리자는 공지를 등록·수정한다. **AI로 채우기**로 초안을 받을 수 있다.

### 일정 (PLANNER)

- 오늘 이후 일정을 시간순으로 본다. 달력을 펼쳐 날짜를 고르면 그날 일정만 추린다.
- 일정 상세에서 참석·불참을 고르고, 불참은 사유를 문장으로 남긴다. 네이버 지도와 기기 캘린더로 넘길 수 있다.
- 인원 제한은 참석 항목에만 걸린다. 정원이 차거나 마감되면 버튼이 잠기고 이유를 알려 준다.
- 경기 일정에는 주전 지정과 공동 전술 노트가 붙는다.
- IB 운영 배정은 본인 것만 보인다. 역할 이름의 A·B는 담당 코트로 읽어 `71동 종합체육관 · A코트`처럼 표시한다.
- 관리자는 일정을 등록·수정·취소하고, 취소한 일정을 되살린다. 시작·종료·마감 시각은 시·분·초 휠로 고른다. 공개 대상은 팀 단위 또는 부원 직접 선택이다.

### 경기 (GAME)

- 내부 경기(아침농구·자유개방·픽업게임)와 IB 리그, 외부 경기를 분류별로 본다.

### 영상

- **하이라이트**: Instagram 릴스. 카드를 누르면 앱을 거치지 않고 바로 릴스로 나간다.
- **복기**: 쿼터별 YouTube 링크(최대 6쿼터, 쿼터 미정 허용). 재생 위치를 따라가는 시점 코멘트를 달고, 특정 선수를 지목해 피드백한다.

### 개인 (PERSONAL)

- 내 프로필, 출석률, 직책 뱃지.
- 71동·71-1동 예약 오픈 타이머와 900동 안내. 예약 담당자는 오픈 전날 밤과 당일 아침에 알림을 받는다.
- IB 운영 일정과 운영 교환 신청. 홈커밍 연락 보드. 공지·일정 수정 이력.
- 오류 제보.
- 관리자 메뉴: 멤버 등록·직책 관리, 가입 대기 명단, 계정 활성화 요청 처리, 오류 제보함, IB 운영표 Excel 가져오기, 홈커밍 캠페인 관리, 출결 정리 시트.

## 권한

| 역할 | 할 수 있는 일 |
| --- | --- |
| 부원 | 일정 응답, 공지 투표, 영상 시청·댓글, 운영 교환 신청 |
| 매니저 | 위 + 하이라이트 등록 |
| 주장 | 위 + 공지·일정 등록·수정 |
| 관리자 | 위 + 계정 활성화, 직책 지정, 명단 관리, 운영표 가져오기, 출결 시트 |

권한은 Flutter UI가 아니라 Supabase RLS와 DB 함수가 최종 판정한다. 화면에서 버튼을 감추는 것은 편의일 뿐이다.

## 계정

신규 가입은 `snu.ac.kr` 계열 Google 계정을 먼저 인증한 뒤 가입 명단의 실명과 대조한다. 기존 부원의 실명 로그인용 가상 이메일은 앱 내부에서만 만들고 비밀번호는 Supabase Auth가 해시로 보관한다.

비활성 계정으로 로그인하면 세션을 즉시 끊고, 로그인 화면에서 관리자에게 활성화를 요청할 수 있다. 요청은 세션 없이 부를 수 있는 `request_account_activation` 함수로 들어가며 계정 존재 여부는 응답으로 알려 주지 않는다. 관리자에게는 실시간 알림이 가고 PERSONAL에서 승인한다.

## 로컬 실행

`.env.example`을 참고해 `.env`에 공개 클라이언트 값만 둔다. 빌드에는 `--dart-define`으로 전달한다.

```env
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
YOUTUBE_API_KEY=YOUR_BROWSER_RESTRICTED_YOUTUBE_API_KEY
```

원격 알림을 쓸 때만 `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_WEB_APP_ID`, `FIREBASE_VAPID_KEY`를 더한다. 모두 웹 클라이언트 식별용 공개 값이며, 서비스 계정 JSON과 `service_role` 키는 여기 넣지 않는다.

VS Code에서는 `ENCBA LOCKER (Chrome + .env)` 실행 구성을 쓴다. 웹 릴리스 빌드는 `.\tool\build_web.ps1`이 `.env`를 자동으로 넘긴다.

## Supabase

순차 SQL 마이그레이션 방식이다.

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
npx supabase migration list --linked
npx supabase db lint --linked --level error
```

초기 명단은 `supabase/seed.sql`에 있다. Auth의 Google Provider에는 Google Cloud의 Web Client ID와 Secret을 등록하고, `Site URL`은 Vercel 고정 도메인으로 둔다. Google OAuth의 승인된 리디렉션 URI는 앱 주소가 아니라 `https://<project-ref>.supabase.co/auth/v1/callback`이다. Client Secret은 앱·환경 파일·Git에 넣지 않는다.

## 알림

웹은 브라우저 Notification API를 쓴다. 웹 구현은 `package:web`과 `dart.library.js_interop` 조건부 임포트로 작성해 `--wasm` 빌드에서도 살아 있다. `dart:html`은 wasm 타깃에서 쓸 수 없으므로 다시 도입하지 않는다.

원격 푸시는 FCM 토큰을 `push_subscriptions`에 등록하고 Edge Function `send-push`가 발송한다. 긴급 공지는 DB 웹훅으로, 출결 마감 3시간 전 리마인더는 크론으로 나간다. 관리자의 **응답 독촉하기**는 호출자 JWT로 권한을 확인한 뒤 미응답자에게만 보낸다. 항목별 수신 설정은 홈의 종 아이콘에서 바꾼다.

## AI 채우기

새 일정·새 공지 화면 오른쪽 위의 **AI로 채우기**는 Edge Function `ai-compose`를 통해 초안을 받아 온다. "이번 학기 동안 매주 화요일 8시부터 10시까지 종합체육관에서 훈련"처럼 적으면 기간 전체를 날짜별 일정으로 펼쳐 만들고, 목록에서 확인·해제한 뒤 한 번에 등록한다. 아농·자개·연겜 같은 줄임말을 알아듣는다. AI가 정하지 못한 값은 되묻고, 비워 두고 넘어가면 기본값을 쓴다.

API 키는 브라우저에서 그대로 읽히므로 앱 빌드에 넣지 않고 Edge Function 환경변수에만 둔다. 소스에도 적지 않는다.

```powershell
npx supabase functions deploy ai-compose
npx supabase secrets set GROQ_API_KEY=gsk_...
npx supabase secrets set GROQ_MODEL=openai/gpt-oss-120b,openai/gpt-oss-20b   # 선택
```

여러 모델을 쉼표로 적으면 앞에서부터 시도하고, 한도 초과나 혼잡(429·5xx)이면 다음 모델로 내려간다. 키가 없으면 버튼이 안내만 띄우고 다른 기능에는 영향을 주지 않는다.

## 검증

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
```

## 배포

`master`에 푸시하면 Vercel이 `tool/vercel_build.sh`로 빌드해 배포한다. 새 배포는 서비스 워커가 교체되는 순간 페이지를 한 번 새로고침해 곧바로 적용된다.
