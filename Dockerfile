# Runtime image only: it copies an already compiled binary.
#
# The binary is built by the workflow on a runner of the target architecture
# (`dart compile exe`, the same SDK the tests run with), and a locally built
# image is made the same way:
#
#   dart pub get
#   dart compile exe bin/ncm_comment_api.dart -o build/ncm_comment_api
#   docker build .
#
# Keeping compilation out of the image build means no Dart SDK is needed here
# and nothing has to be compiled under QEMU for the arm64 image.
#
# The base is Debian rather than Alpine: `dart compile exe` produces a
# dynamically linked binary against glibc, which musl cannot load.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# The workflow puts the binary at build/ncm_comment_api before building.
ARG BINARY=build/ncm_comment_api
COPY ${BINARY} /app/ncm_comment_api

RUN chmod +x /app/ncm_comment_api

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
