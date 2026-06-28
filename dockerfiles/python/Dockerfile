# syntax=docker/dockerfile:1
# AstroAI Python foundation: Debian slim + uv + pixi (system-wide paths).
# uv/pixi: official install scripts (latest at build time), not pinned GHCR tags.

ARG PYTHON_VERSION=3.13
ARG UV_VERSION=0.11.25
ARG PIXI_VERSION=0.71.1

FROM python:${PYTHON_VERSION}-slim

ARG UV_VERSION
ARG PIXI_VERSION

LABEL org.opencontainers.image.title="AstroAI Python Runtime" \
      org.opencontainers.image.vendor="AstroAI"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bzip2 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin \
    UV_TOOL_DIR=/usr/local/share/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    PIXI_HOME=/usr/local/share/pixi \
    PIXI_BIN_DIR=/usr/local/bin \
    PIXI_CACHE_DIR=/usr/local/share/pixi/cache
# ^ build-time paths for `uv pip install --system` only.
# Session users: /etc/profile.d/astroai.sh overrides UV_* / PIXI_HOME / MAMBA_* to ~/.local;
# package caches (uv, pip, pixi, npm, conda/mamba pkgs) go to /scratch when mounted.

ENV MAMBA_ROOT_PREFIX=/usr/local/share/micromamba \
    MAMBA_PKGS_DIRS=/usr/local/share/micromamba/pkgs
# ^ build-time paths only. Session users: astroai.sh sets MAMBA_ROOT_PREFIX under
# ~/.local/share and MAMBA_PKGS_DIRS on /scratch when mounted.

RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh \
    | env UV_VERSION="${UV_VERSION}" UV_UNMANAGED_INSTALL=/usr/local/bin sh \
    && curl -fsSL https://pixi.sh/install.sh \
    | env PIXI_VERSION="${PIXI_VERSION}" PIXI_HOME=/usr/local/share/pixi PIXI_BIN_DIR=/usr/local/bin bash \
    && ARCH="$(uname -m)" \
    && case "${ARCH}" in \
        x86_64) MAMBA_ARCH=linux-64 ;; \
        aarch64) MAMBA_ARCH=linux-aarch64 ;; \
        *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && curl -Ls "https://micro.mamba.pm/api/micromamba/${MAMBA_ARCH}/latest" \
        | tar -xvj -C /usr/local/bin --strip-components=1 bin/micromamba \
    && ln -sf micromamba /usr/local/bin/mamba \
    && uv --version \
    && pixi --version \
    && micromamba --version \
    && command -v uvx >/dev/null
