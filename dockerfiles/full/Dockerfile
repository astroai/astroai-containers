# syntax=docker/dockerfile:1
# AstroAI full: base + current Node.js LTS (system-wide node/npm for npm CLIs).

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

LABEL org.opencontainers.image.title="AstroAI Full" \
      org.opencontainers.image.description="Base + Node.js LTS for npm-based CLIs" \
      io.canfar.skaha.session.type="headless"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN ARCH="$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')" \
    && NODE_VERSION="$(curl -fsSL https://nodejs.org/dist/index.json \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(x['version'] for x in d if x.get('lts')))")" \
    && curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${ARCH}.tar.xz" \
    | tar -xJ -C /usr/local --strip-components=1 \
    && node --version \
    && npm --version
