# syntax=docker/dockerfile:1
# AstroAI openresearch: OpenResearch (orx) autoresearch dashboard.
# Builds orx from a pinned git SHA (Ray Jobs backend). Proxies :4791 → :5000.
# When alphaXiv ships a release with Ray, prefer switching back to their
# musl tarball + ORX_VERSION / ORX_SHA256_* args.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local
# Fork pin until https://github.com/alphaXiv/openresearch-cli/pull/138 lands in a release.
ARG ORX_REPO=https://github.com/sfabbro/openresearch-cli.git
ARG ORX_SHA=e076d027c9cbbac8b7bb5ded0821efa9d0a41c6b
ARG NODE_VERSION=20

# --- UI (embedded into orx via rust-embed) ---
FROM node:${NODE_VERSION}-bookworm-slim AS ui-build
ARG ORX_REPO
ARG ORX_SHA
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git init repo && cd repo \
    && git remote add origin "${ORX_REPO}" \
    && git fetch --depth 1 origin "${ORX_SHA}" \
    && git checkout FETCH_HEAD \
    && cd ui \
    && npm install -g pnpm@9.15.0 \
    && pnpm install --frozen-lockfile \
    && pnpm run build

# --- orx binary ---
FROM rust:1-bookworm AS orx-build
ARG ORX_REPO
ARG ORX_SHA
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
        pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && git init repo && cd repo \
    && git remote add origin "${ORX_REPO}" \
    && git fetch --depth 1 origin "${ORX_SHA}" \
    && git checkout FETCH_HEAD
COPY --from=ui-build /src/repo/ui/dist /src/repo/ui/dist
WORKDIR /src/repo
RUN cargo build --release \
    && install -m 0755 target/release/orx /orx \
    && /orx --version

# --- Runtime ---
FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

ARG ORX_SHA

LABEL io.canfar.skaha.session.type="contributed" \
      org.opencontainers.image.title="AstroAI OpenResearch" \
      org.opencontainers.image.description="OpenResearch (orx) autoresearch dashboard for CANFAR" \
      org.opencontainers.image.source="https://github.com/alphaXiv/openresearch-cli" \
      org.opencontainers.image.revision="${ORX_SHA}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=orx-build /orx /opt/astroai/bin/orx
RUN /opt/astroai/bin/orx --version

ENV PATH="/opt/astroai/bin:${PATH}" \
    ORX_NO_UPDATE_CHECK=1 \
    ASTROAI_SESSION_KIND=openresearch

COPY scripts/lib/skaha-proxy.sh scripts/lib/orx-canfar-proxy.py \
     scripts/lib/agent-wizard.py scripts/lib/orx-wire-compute.py /opt/astroai/lib/
COPY scripts/common-init.sh scripts/startup-openresearch.sh /cadc/
COPY scripts/skaha-startup-openresearch.sh /skaha/startup.sh
RUN chmod a+rx /opt/astroai/lib/orx-canfar-proxy.py /opt/astroai/lib/agent-wizard.py \
        /opt/astroai/lib/orx-wire-compute.py \
        /cadc/*.sh /skaha/startup.sh \
    && chmod a+r /opt/astroai/lib/skaha-proxy.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/ >/dev/null

WORKDIR /tmp
CMD ["/skaha/startup.sh"]
