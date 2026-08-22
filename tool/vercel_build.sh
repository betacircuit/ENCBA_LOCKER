#!/usr/bin/env bash
set -euo pipefail

readonly FLUTTER_VERSION="3.44.9"
readonly FLUTTER_SHA256="a9120fa4a01048bdef438ddc3a2d4b7389662ea98a95db86eeaf10382bc4efcb"
readonly FLUTTER_PARENT="$PWD/.flutter-sdk"
readonly FLUTTER_ROOT="$FLUTTER_PARENT/flutter"
readonly FLUTTER_ARCHIVE="${TMPDIR:-/tmp}/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
readonly FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_PUBLISHABLE_KEY:?SUPABASE_PUBLISHABLE_KEY is required}"
: "${YOUTUBE_API_KEY:?YOUTUBE_API_KEY is required}"

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  mkdir -p "$FLUTTER_PARENT"
  curl --fail --location \
    --retry 5 --retry-delay 3 --retry-all-errors \
    --connect-timeout 20 \
    --output "$FLUTTER_ARCHIVE" \
    "$FLUTTER_URL"
  echo "$FLUTTER_SHA256  $FLUTTER_ARCHIVE" | sha256sum --check --strict
  tar --extract --xz --file "$FLUTTER_ARCHIVE" --directory "$FLUTTER_PARENT"
  rm -f "$FLUTTER_ARCHIVE"
fi

export PATH="$FLUTTER_ROOT/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin:$PATH"
export CI=true

git config --global --add safe.directory "$FLUTTER_ROOT"
flutter --disable-analytics
flutter --version
flutter pub get --enforce-lockfile

dart_defines=(
  "--dart-define=SUPABASE_URL=$SUPABASE_URL"
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
  "--dart-define=YOUTUBE_API_KEY=$YOUTUBE_API_KEY"
)

optional_client_keys=(
  FIREBASE_API_KEY
  FIREBASE_PROJECT_ID
  FIREBASE_MESSAGING_SENDER_ID
  FIREBASE_WEB_APP_ID
  FIREBASE_VAPID_KEY
)
for key in "${optional_client_keys[@]}"; do
  if [[ -n "${!key:-}" ]]; then
    dart_defines+=("--dart-define=$key=${!key}")
  fi
done

# 백그라운드 웹 푸시용 서비스 워커를 Firebase 설정 값과 함께 생성한다.
# 값이 없으면 파일을 만들지 않고, 페이지도 등록을 건너뛴다.
if [[ -n "${FIREBASE_API_KEY:-}" && -n "${FIREBASE_PROJECT_ID:-}" ]]; then
  cat > web/firebase-messaging-sw.js <<SW
/* Vercel 빌드가 생성한 FCM 백그라운드 서비스 워커. 직접 수정하지 마세요. */
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "${FIREBASE_API_KEY}",
  authDomain: "${FIREBASE_PROJECT_ID}.firebaseapp.com",
  projectId: "${FIREBASE_PROJECT_ID}",
  messagingSenderId: "${FIREBASE_MESSAGING_SENDER_ID:-}",
  appId: "${FIREBASE_WEB_APP_ID:-}"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const title = notification.title || "ENCBA LOCKER";
  const body = notification.body || "";
  const data = payload.data || {};
  self.registration.showNotification(title, {
    body,
    tag: data.id ? String(data.id) : undefined,
    renotify: false,
    data
  });
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const path = event.notification.data && event.notification.data.path;
  if (!path) return;
  event.waitUntil((async () => {
    const target = new URL(path, self.registration.scope).toString();
    const windowClients = await clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of windowClients) {
      if (client.url === target && "focus" in client) return client.focus();
    }
    return clients.openWindow(target);
  })());
});
SW
fi

flutter build web --release --wasm --no-pub "${dart_defines[@]}"
