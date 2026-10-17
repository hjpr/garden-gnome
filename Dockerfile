# Builds the Flutter web app and serves it with nginx.
# Build context is the repository root: flutter/assets/icons is a symlink
# to ../../src/icons, so src/icons must be in the context too.

FROM ghcr.io/cirruslabs/flutter:3.38.9 AS build
WORKDIR /app/flutter

# Dependencies first, so code changes reuse the cached pub get layer.
COPY flutter/pubspec.yaml flutter/pubspec.lock ./
RUN flutter pub get

COPY src/icons /app/src/icons
COPY flutter/ ./
RUN flutter build web --release --no-pub

FROM nginx:1.29-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/flutter/build/web /usr/share/nginx/html
# Some source files (e.g. the scraped catalog) are owner-only on disk;
# nginx runs as another user and would answer 403 for them.
RUN chmod -R a+rX /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO /dev/null http://127.0.0.1/ || exit 1
