# syntax=docker/dockerfile:1
# AstroAI full: base + pinned Node.js LTS (system-wide node/npm for npm CLIs).

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local
ARG NODE_VERSION=24.18.0

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

ARG NODE_VERSION=24.18.0

LABEL org.opencontainers.image.title="AstroAI Full" \
      org.opencontainers.image.description="Base + Node.js LTS for npm-based CLIs" \
      io.canfar.skaha.session.type="headless"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN ARCH="$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" \
    | tar -xJ -C /usr/local --strip-components=1 \
    && node --version \
    && npm --version
