# Vercel 배포 운영

ENCBA LOCKER 웹 프런트엔드의 단일 배포 대상은 Vercel이다. Flutter Web 정적
파일은 Vercel CDN에서 제공하고, 인증·DB·Realtime·Storage·Edge Functions는
Supabase가 담당한다. 별도의 Node/Python 서버나 자체 WebSocket 서버는 운영하지
않는다.

## 프로젝트 설정

GitHub의 `betacircuit/ENCBA_LOCKER` 저장소를 Vercel 프로젝트에 연결하고 다음 값을
사용한다.

- Framework Preset: `Other`
- Root Directory: `./`
- Production Branch: `master`
- Build Command와 Output Directory: Dashboard에서 덮어쓰지 않고 `vercel.json` 사용

`vercel.json`은 `bash tool/vercel_build.sh`를 실행하고 `build/web`을 배포한다.
빌드 스크립트는 Docker 없이 고정된 Flutter 버전을 내려받고 SHA-256을 검증한 뒤
WASM 릴리스 빌드를 만든다.

## 환경변수

다음 공개 클라이언트 값은 Vercel의 Production과 Preview 환경에 모두 등록한다.

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
YOUTUBE_API_KEY
```

`SUPABASE_SERVICE_ROLE_KEY`, Google OAuth Client Secret 또는 그 밖의 서버 전용 값은
브라우저에 포함되므로 Vercel 빌드 환경변수에 넣지 않는다. 서버용 값은 해당 Supabase
Edge Function의 secret으로만 관리한다.

환경변수를 바꾼 뒤에는 새 Production 배포를 생성해야 한다. 배포 로그에 실제 값을
출력하지 않는다.

## Production Domain과 OAuth

Vercel의 `Settings > Domains`에서 짧고 고정된 Production Domain을 확인한다. 커밋마다
생기는 `<project>-<hash>-<scope>.vercel.app` 주소는 Deployment Protection 대상이 될 수
있고 주소도 바뀌므로 OAuth 기준 주소로 사용하지 않는다.

고정 주소를 `https://<production-domain>`이라고 할 때 Supabase
`Authentication > URL Configuration`을 다음과 같이 설정한다.

```text
Site URL
https://<production-domain>

Redirect URLs
https://<production-domain>/sign-in
https://*-legojmon-6277s-projects.vercel.app/**
```

Preview 로그인이 필요하지 않으면 두 번째 Redirect URL은 생략한다. 와일드카드는
Preview에만 사용하고 Production은 정확한 URL을 등록한다.

Google Cloud Console의 승인된 리디렉션 URI는 Vercel 주소가 아니라 다음 Supabase
콜백을 유지한다.

```text
https://erjuuyadevtouaqpmpjd.supabase.co/auth/v1/callback
```

YouTube API 키의 HTTP 리퍼러 제한에도 Production Domain과 실제 사용하는 Preview
패턴만 허용한다.

## 배포와 검증

`master` 푸시 후 Vercel이 Production 배포를 자동으로 시작한다. 완료 후 다음을
확인한다.

1. Production Domain의 `/healthz`가 `200`과 `ok`를 반환한다.
2. `/`, `/sign-in`, `/schedule/<id>`, `/videos/<id>`를 직접 열거나 새로고침해도 앱이 뜬다.
3. Google 로그인을 Production Domain에서 시작하고 같은 도메인의 `/sign-in`으로 돌아온다.
4. 로그아웃 후 다시 로그인해 저장된 세션과 신규 OAuth 흐름을 각각 확인한다.
5. 공지·일정·영상의 Supabase Realtime 연결과 YouTube 조회를 확인한다.
6. 시크릿 창에서 Production Domain이 Vercel 로그인 화면 없이 공개되는지 확인한다.

## 실패와 롤백

새 배포가 실패하면 Vercel은 직전 성공 배포를 계속 서비스한다. 런타임 문제가 있으면
Vercel Deployments에서 직전 성공 배포를 Promote/Rollback하고, 원인이 된 Git 커밋을
되돌린다. 환경변수 문제는 값을 수정한 뒤 새 배포로 검증한다.

전환 기간에는 기존 Render 서비스를 한 번의 운영 검증 기간 동안 외부 롤백 수단으로
남길 수 있지만, 저장소는 Render 설정을 더 이상 관리하지 않는다. Production Domain,
OAuth, 딥 링크와 로그인 검증이 끝난 뒤 Render 자동 배포와 서비스를 Dashboard에서
별도로 종료한다.

## 참고 문서

- [Vercel 프로젝트 설정](https://vercel.com/docs/project-configuration/vercel-json)
- [Vercel Deployment Protection](https://vercel.com/docs/deployment-protection)
- [Supabase Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
