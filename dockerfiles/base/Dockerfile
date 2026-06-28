# syntax=docker/dockerfile:1
# AstroAI base: platform CLI + monitoring + compression. No browser UI.
#
# Apt packages: root-only tools not practical via pixi/uv/micromamba.
# GCC + Rust + autotools, common astronomy headers; heavy ML stacks stay in pixi.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG PYTHON_VERSION=3.13

FROM ${REGISTRY}/${OWNER}/python:${PYTHON_VERSION}

LABEL org.opencontainers.image.title="AstroAI Base" \
      org.opencontainers.image.description="Headless dev environment for CANFAR" \
      io.canfar.skaha.session.type="headless"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    acl \
    autoconf \
    automake \
    bash-completion \
    bat \
    bind9-dnsutils \
    bison \
    bsdextrautils \
    build-essential \
    bzip2 \
    ca-certificates \
    cargo \
    cmake \
    curl \
    fd-find \
    file \
    flex \
    fzf \
    gfortran \
    gh \
    git \
    git-delta \
    git-lfs \
    htop \
    iproute2 \
    jq \
    less \
    libcfitsio-dev \
    libfftw3-dev \
    libgsl-dev \
    libtool \
    locales \
    lsof \
    make \
    ncdu \
    ninja-build \
    nvtop \
    openssh-client \
    patch \
    pigz \
    pkg-config \
    procps \
    ripgrep \
    rsync \
    rustc \
    shellcheck \
    tealdeer \
    tree \
    libmagic1 \
    universal-ctags \
    unzip \
    vim-tiny \
    wget \
    xxd \
    xz-utils \
    zip \
    zstd \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8 UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && git lfs install --system \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && git config --system core.pager delta \
    && git config --system interactive.diffFilter 'delta --color-only' \
    && git config --system delta.navigate true

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color \
    SHELL=/bin/bash \
    ASTROAI_DEFAULT_SRC_DIR=/srcdir \
    ASTROAI_DEFAULT_SCRATCH_DIR=/scratch

RUN printf '%s\n' \
    '[ -f /etc/profile.d/astroai.sh ] && . /etc/profile.d/astroai.sh' \
    >> /etc/bash.bashrc

COPY scripts/astroai-profile.sh /etc/profile.d/astroai.sh
RUN chmod a+r /etc/profile.d/astroai.sh

RUN mkdir -p /opt/astroai/{bin,cache,lib,venv} /cadc "${ASTROAI_DEFAULT_SRC_DIR}" \
    && chmod -R a+rX /opt/astroai \
    && chmod -R a+rwx /opt/astroai/cache \
    && chmod 1777 "${ASTROAI_DEFAULT_SRC_DIR}"

COPY config/cadc-tools.txt /opt/astroai/cadc-tools.txt
COPY scripts/patch-clint-py313.sh /tmp/patch-clint-py313.sh
RUN uv venv /opt/astroai/venv/cadc \
    && uv pip install --python /opt/astroai/venv/cadc -r /opt/astroai/cadc-tools.txt \
    && bash /tmp/patch-clint-py313.sh /opt/astroai/venv/cadc \
    && rm /tmp/patch-clint-py313.sh \
    && chmod -R a+rX /opt/astroai/venv/cadc

COPY scripts/lib/astroai-env-common.sh scripts/lib/astroai-ui.sh scripts/lib/astroai-load.sh scripts/lib/skaha-proxy.sh /opt/astroai/lib/
COPY scripts/astroai-env-save scripts/astroai-env-resume scripts/astroai-env-list \
    scripts/astroai-workspace-save.sh scripts/astroai-workspace-restore.sh \
    scripts/astroai-home-usage scripts/astroai-cache-prune \
    scripts/astroai-help.sh scripts/astroai-status.sh scripts/astroai-new.sh \
    scripts/astroai-clone.sh scripts/astroai-debug.sh scripts/astroai-install.sh \
    scripts/astroai-session-archive.sh scripts/astroai-data-sync.sh \
    scripts/astroai-project-init.sh scripts/astroai-kernel-register scripts/canfar-verify.sh \
    /opt/astroai/bin/
RUN chmod a+rx /opt/astroai/bin/* /opt/astroai/lib/* \
    && ln -sf astroai-help.sh /opt/astroai/bin/astroai-help \
    && ln -sf astroai-status.sh /opt/astroai/bin/astroai-status \
    && ln -sf astroai-new.sh /opt/astroai/bin/astroai-new \
    && ln -sf astroai-clone.sh /opt/astroai/bin/astroai-clone \
    && ln -sf astroai-debug.sh /opt/astroai/bin/astroai-debug \
    && ln -sf astroai-install.sh /opt/astroai/bin/astroai-install \
    && ln -sf astroai-session-archive.sh /opt/astroai/bin/astroai-session-archive \
    && ln -sf astroai-data-sync.sh /opt/astroai/bin/astroai-data-stage \
    && ln -sf astroai-data-sync.sh /opt/astroai/bin/astroai-data-sync \
    && ln -sf astroai-project-init.sh /opt/astroai/bin/astroai-project-init \
    && ln -sf astroai-workspace-save.sh /opt/astroai/bin/astroai-workspace-save \
    && ln -sf astroai-workspace-restore.sh /opt/astroai/bin/astroai-workspace-restore

COPY docs/USAGE.md /opt/astroai/USAGE.md
