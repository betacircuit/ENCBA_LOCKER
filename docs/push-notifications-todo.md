# 진짜 백그라운드 푸시 알림 (미착수)

## 현재 상태 (2026-08 기준)

지금 앱의 "알림"은 전부 **탭이 열려 있을 때만** 동작하는 로컬 알림이다.

- `lib/features/locker/services/web_notification_service_web.dart`: 브라우저 `Notification` API만 쓴다. Service Worker 등록, `PushManager.subscribe()`, VAPID 키 어디에도 없다.
- 공지/일정/영상 새 글은 Supabase Realtime(WebSocket, `lib/features/locker/application/locker_controller.dart`)으로 감지해서 그 자리에서 `WebNotificationService().show()`를 호출하는 구조라, 탭을 닫거나 브라우저를 끄면 아무 것도 오지 않는다.
- `web_notification_subscriptions` 테이블(`supabase/migrations/202608120001_initial_schema.sql`)만 스키마로 존재하고 실제로 구독을 저장/조회/발송하는 코드는 전혀 없다(고아 테이블).
- 알림 항목별 켜고 끄기(공지/일정/영상)는 `lib/features/locker/services/notification_category_prefs.dart`에 기기 로컬(`LocalStore`) 설정으로 구현되어 있다 — 이건 이미 됨, 재사용 가능.

## 왜 지금 안 하는지

VAPID 키 발급, Supabase Edge Function 신규 작성·배포, 서비스워커 추가가 필요해서 Supabase 프로젝트 권한(대시보드 접근, `supabase functions deploy`)이 여러 번 필요하다. 사용자 확인 결과 지금은 탭이 열려 있을 때의 알림으로 충분하고, 이 작업은 다음으로 미룬다.

## 완전한 푸시를 만들려면 손대야 할 것

1. **VAPID 키 발급**: `web-push generate-vapid-keys` 등으로 공개/비공개 키 쌍 생성. 공개키는 클라이언트에 노출, 비공개키는 Supabase Edge Function 시크릿으로 저장.
2. **서비스워커 신규 작성**: `web/` 아래에 `push` 이벤트를 받는 별도 서비스워커(`sw.js`)를 만들고 등록. 지금 Flutter가 자동 생성하는 `flutter_service_worker.js`는 자산 캐싱용이라 push 이벤트를 못 받는다.
3. **구독 등록 코드**: `web_notification_service_web.dart`에 `PushManager.subscribe({applicationServerKey: VAPID_PUBLIC_KEY})` 추가하고, 반환된 endpoint/keys를 `web_notification_subscriptions`에 upsert하는 로직 작성 (지금은 이 테이블에 쓰는 코드가 없음).
4. **DB 스키마 확장**: `web_notification_subscriptions`에 endpoint/keys 저장 컬럼 추가, 그리고 카테고리별(공지/일정/영상) on/off를 서버에도 반영하려면 컬럼 추가 필요(지금은 기기 로컬에만 있음).
5. **발송 파이프라인**: `announcements`/`events`/`videos` INSERT 트리거 → `pg_net.http_post`로 신규 Edge Function 호출 → 그 Edge Function이 Web Push(VAPID)로 실제 발송. `supabase/functions/`에는 현재 `send-error-report`만 있고 푸시 발송용은 없음.
6. **권한 안내 UI**: 브라우저 알림 권한 요청은 지금 `home_screen.dart`의 `_showNotifications`에서 이미 하고 있으므로, 여기에 구독 등록 호출만 얹으면 됨.

## 참고

이 조사는 2026-08-18 세션에서 Explore 서브에이전트가 코드베이스 전체를 훑어서 확인한 결과다. 착수할 때는 위 상태가 그대로인지 다시 한번 확인할 것 — 특히 `web_notification_subscriptions` 스키마와 `supabase/functions/` 목록.
