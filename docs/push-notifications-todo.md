# 원격 푸시 알림 — 구현 기록과 운영 체크리스트

원격 푸시의 앱·DB·발송 코드는 모두 구현되어 master에 반영되어 있다. 이 문서는
무엇이 만들어져 있는지 기록하고, 외부 서비스 설정·배포 검증을 진행하는 사람이
순서대로 확인할 수 있는 체크리스트만 남긴다.

## 구현 완료 항목

- `PushNotificationService`가 Firebase 초기화, 토큰 등록·갱신, 카테고리 설정과 알림
  클릭 라우팅을 담당한다. Firebase 공개 설정이 없으면 기존 브라우저 로컬 알림으로
  안전하게 돌아간다.
- `push_subscriptions`와 `push_deliveries` 마이그레이션이 구독 소유권과 중복 발송 방지를
  정의한다.
- `supabase/functions/send-push`가 긴급 공지 웹훅과 출결 마감 크론 후보를
  FCM HTTP v1으로 발송한다. 같은 함수가 관리자 JWT를 검증한 뒤 미응답자에게 보내는
  응답 독촉(`kind: response_reminder`)도 처리한다.
- Flutter Web 프런트엔드는 Vercel에 배포하고, 발송 서버는 Supabase Edge Functions에
  둔다. Render 서버는 사용하지 않는다.

## 운영 체크리스트

1. Firebase 프로젝트에서 Web App과 Cloud Messaging을 활성화하고 Web Push 인증서의
   공개 VAPID 키를 발급한다.
2. Vercel Production/Preview 환경에 다음 공개 클라이언트 값을 등록한다.

   ```text
   FIREBASE_API_KEY
   FIREBASE_PROJECT_ID
   FIREBASE_MESSAGING_SENDER_ID
   FIREBASE_WEB_APP_ID
   FIREBASE_VAPID_KEY
   ```

3. Firebase 백그라운드 메시지를 받는 `web/firebase-messaging-sw.js`가 Flutter
   부트스트랩 전에 등록되어 있는지 확인한다. 이 파일이 없으면 탭이 닫힌 웹 푸시를
   완료할 수 없다.
4. Supabase Edge Function secrets에 다음 서버 전용 값을 저장한다. 이 값들은 Vercel이나
   Flutter 빌드에 넣지 않는다.

   ```text
   PUSH_WEBHOOK_SECRET
   FCM_PROJECT_ID
   FCM_SERVICE_ACCOUNT_JSON
   ```

5. DB 마이그레이션을 적용하고 `send-push` Edge Function을 배포한다.
6. 긴급 공지 INSERT Webhook과 출결 마감 점검 Cron이 같은
   `PUSH_WEBHOOK_SECRET`을 사용해 함수를 호출하도록 연결한다.

## 검증 체크리스트

- Vercel Production Domain에서 알림 권한 허용 후 `push_subscriptions`에 현재 사용자의
  FCM 토큰이 저장된다.
- 긴급 공지는 대상 사용자에게 한 번만 도착하고, 이미 응답한 사용자는 출결 마감
  알림에서 제외된다.
- 관리자가 일정 상세에서 응답 독촉하기를 누르면 미응답자에게만 알림이 가고,
  관리자·주장이 아닌 계정으로 호출하면 401로 거부된다.
- 로그아웃하거나 알림을 끈 사용자의 구독은 발송되지 않는다.
- 만료된 FCM 토큰은 비활성화되고, 재시도 후에도 중복 알림이 생기지 않는다.
- 탭이 열려 있을 때, 백그라운드일 때, 완전히 닫혔을 때를 각각 실제 브라우저에서
  검증한다.

배포 명령과 OAuth/도메인 설정은 [`deployment.md`](deployment.md)를 따른다.

