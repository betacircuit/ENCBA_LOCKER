FROM debian:bookworm-slim AS flutter

ARG FLUTTER_VERSION=3.44.9
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git libglu1-mesa unzip xz-utils zip && \
    rm -rf /var/lib/apt/lists/* && \
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git /opt/flutter

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN flutter config --enable-web && flutter precache --web

FROM flutter AS build

WORKDIR /app
ARG SUPABASE_URL
ARG SUPABASE_PUBLISHABLE_KEY

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN test -n "$SUPABASE_URL" && \
    test -n "$SUPABASE_PUBLISHABLE_KEY" && \
    flutter build web --release \
      --dart-define="SUPABASE_URL=$SUPABASE_URL" \
      --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"

FROM nginx:1.29.1-alpine

COPY deploy/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 10000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:${PORT:-10000}/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
