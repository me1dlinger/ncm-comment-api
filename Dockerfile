# Build the server binary, then ship it on a small runtime image.
#
# The SDK image is only needed at build time; the result is a self-contained
# executable, so the runtime image does not carry a Dart SDK.
#
# The Dart version is pinned to the one CI tests with (see the test job in
# .github/workflows/docker-publish.yml), so a locally built image and the
# published one compile the same source the same way.
ARG DART_VERSION=3.9.2
FROM dart:${DART_VERSION} AS build

WORKDIR /app

# The lock file goes in with the manifest, so the build resolves the exact
# versions CI tested rather than whatever is newest that day.
COPY pubspec.yaml pubspec.lock ./

COPY bin ./bin
COPY lib ./lib

RUN dart pub get \
    && dart compile exe bin/ncm_comment_api.dart -o /app/build/ncm_comment_api

FROM alpine:latest

RUN apk add --no-cache libc6-compat ca-certificates

WORKDIR /app
COPY --from=build /app/build/ncm_comment_api /app/ncm_comment_api

ENV PORT=8383
ENV WYY_API_BASE_URL=http://127.0.0.1:3000
ENV API_USERNAME=
ENV API_PASSWORD=

EXPOSE 8383

# config.conf is generated on first start when missing, from the environment,
# so `docker run -e WYY_API_BASE_URL=...` is enough.
CMD ["sh", "-c", "\
if [ ! -f config.conf ]; then \
  printf '[api]\\nwyy_api_base_url=%s\\ndefault_port=%s\\nusername=%s\\npassword=%s\\n' \
    \"${WYY_API_BASE_URL}\" \"${PORT}\" \"${API_USERNAME}\" \"${API_PASSWORD}\" > config.conf; \
fi; \
exec ./ncm_comment_api \
"]
