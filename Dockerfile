# syntax=docker/dockerfile:1
FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241 AS build

ARG FLUTTER_VERSION=3.44.9
ARG FLUTTER_SHA256=a9120fa4a01048bdef438ddc3a2d4b7389662ea98a95db86eeaf10382bc4efcb

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git xz-utils && \
    rm -rf /var/lib/apt/lists/* && \
    curl --fail --location \
      --retry 5 --retry-delay 3 --retry-all-errors \
      --connect-timeout 20 \
      --output /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" && \
    echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum --check --strict && \
    tar --extract --xz --file /tmp/flutter.tar.xz --directory /opt && \
    rm /tmp/flutter.tar.xz && \
    git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}" \
    CI=true

WORKDIR /app
ARG SUPABASE_URL
ARG SUPABASE_PUBLISHABLE_KEY
ARG YOUTUBE_API_KEY

COPY pubspec.yaml pubspec.lock ./
# archive는 pub.dev가 아니라 third_party/archive 로컬 경로를 문다
# (dependency_overrides). pub get이 그 경로의 실제 파일을 확인하므로
# 소스 전체를 복사하기 전에 이것부터 있어야 한다.
COPY third_party ./third_party
RUN flutter --version && flutter pub get --enforce-lockfile

COPY . .
RUN test -n "$SUPABASE_URL" && \
    test -n "$SUPABASE_PUBLISHABLE_KEY" && \
    test -n "$YOUTUBE_API_KEY" && \
    flutter build web --release --wasm --no-pub \
      --dart-define="SUPABASE_URL=$SUPABASE_URL" \
      --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
      --dart-define="YOUTUBE_API_KEY=$YOUTUBE_API_KEY"

FROM nginx:1.29.1-alpine@sha256:42a516af16b852e33b7682d5ef8acbd5d13fe08fecadc7ed98605ba5e3b26ab8

ENV PORT=10000 \
    NGINX_ENVSUBST_FILTER=PORT

COPY deploy/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 10000
CMD ["nginx", "-g", "daemon off;"]
