ARG BUILD_FROM=ghcr.io/home-assistant/base:latest
ARG ALLOY_VERSION=1.3.1

FROM grafana/alloy:v${ALLOY_VERSION} AS alloy

FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=alloy /bin/alloy /usr/local/bin/alloy

RUN apk add --no-cache \
    curl \
    gcompat \
    jq \
    libc6-compat

COPY run.sh /run.sh
COPY snippets/ /etc/alloy-logforwarder/snippets/
RUN chmod a+x /run.sh

HEALTHCHECK --interval=60s --timeout=5s --start-period=20s --retries=3 \
  CMD alloy --version >/dev/null 2>&1 || exit 1

CMD ["/run.sh"]
