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
flutter build web --release --wasm --no-pub \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define="YOUTUBE_API_KEY=$YOUTUBE_API_KEY"
