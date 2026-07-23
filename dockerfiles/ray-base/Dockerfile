# syntax=docker/dockerfile:1
# Slim Ray runtime — FROM python (not fat interactive base).
# Used by ray-worker only. Managers stay on fat base for scientist shell/UI.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG PYTHON_VERSION=3.13
ARG TAG=local

FROM ${REGISTRY}/${OWNER}/python:${PYTHON_VERSION}

LABEL org.opencontainers.image.title="AstroAI Ray Base (slim)" \
      org.opencontainers.image.description="Minimal Ray + astroai-lab for workers"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    procps \
    rsync \
    && rm -rf /var/lib/apt/lists/*

ENV TERM=xterm-256color \
    SHELL=/bin/bash \
    ASTROAI_LAB_DEFAULT_SRC_DIR=/srcdir \
    ASTROAI_LAB_DEFAULT_SCRATCH_DIR=/scratch

RUN printf '%s\n' \
    '[ -f /etc/profile.d/astroai.sh ] && . /etc/profile.d/astroai.sh' \
    >> /etc/bash.bashrc

COPY scripts/astroai-profile.sh /etc/profile.d/astroai.sh
RUN chmod a+r /etc/profile.d/astroai.sh

RUN mkdir -p /opt/astroai/{bin,cache,lib,venv} /cadc "${ASTROAI_LAB_DEFAULT_SRC_DIR}" \
    && chmod -R a+rX /opt/astroai \
    && chmod -R a+rwx /opt/astroai/cache \
    && chmod 1777 "${ASTROAI_LAB_DEFAULT_SRC_DIR}"

# Minimal lab install (resume/save/paths) — no full CADC kitchen sink on workers.
COPY config/astroai-lab.in config/astroai-lab.lock /tmp/
RUN uv venv /opt/astroai/venv/cadc \
    && uv pip install --python /opt/astroai/venv/cadc --requirements /tmp/astroai-lab.lock \
    && rm /tmp/astroai-lab.in /tmp/astroai-lab.lock \
    && chmod -R a+rwX /opt/astroai/venv/cadc \
    && /opt/astroai/venv/cadc/bin/astroai-lab env install-shell /etc/astroai-lab \
    && HOME=/tmp ASTROAI_LAB_DEFAULT_SRC_DIR=/srcdir ASTROAI_LAB_DEFAULT_SCRATCH_DIR=/scratch \
       /opt/astroai/venv/cadc/bin/astroai-lab env export --no-ensure >/dev/null

COPY scripts/lib/astroai-env-common.sh scripts/lib/astroai-ui.sh /opt/astroai/lib/
COPY config/ray-deps.txt config/ray-deps.lock /tmp/
RUN uv python install 3.12 \
    && uv venv /opt/astroai/venv/ray --python 3.12 \
    && uv pip install --python /opt/astroai/venv/ray --requirements /tmp/ray-deps.lock \
    && rm /tmp/ray-deps.txt /tmp/ray-deps.lock \
    && /opt/astroai/venv/ray/bin/python -c "import ray; print(ray.__version__)" \
        > /opt/astroai/ray-version.txt \
    && chmod a+r /opt/astroai/ray-version.txt

ENV PATH="/opt/astroai/venv/ray/bin:/opt/astroai/venv/cadc/bin:${PATH}"

COPY ray/worker/start-worker.sh /opt/astroai/bin/start-ray-worker.sh
COPY scripts/ray-head-start.sh /opt/astroai/bin/ray-head-start.sh
COPY scripts/ray-network-probe.sh /opt/astroai/bin/ray-network-probe.sh
COPY scripts/lib/ray-version.sh /opt/astroai/lib/ray-version.sh
COPY examples/ray/ /opt/astroai/examples/ray/
COPY docs/USAGE.md /opt/astroai/USAGE.md
RUN chmod a+rx /opt/astroai/bin/start-ray-worker.sh /opt/astroai/bin/ray-head-start.sh \
    /opt/astroai/bin/ray-network-probe.sh \
    && chmod a+rx /opt/astroai/lib/*
