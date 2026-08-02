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
    emacs-nox \
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
    hyperfine \
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
    nano \
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
    vim \
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

# Node.js LTS pinned (official tarball + sha256) so every session image ships
# node/npm/npx on PATH — astroai-lab no longer needs `pixi global install nodejs`.
# x86_64-pinned (bake is single-arch amd64; no platform decls in docker-bake.hcl).
# Bump NODE_LTS_VERSION + NODE_LTS_SHA256 together (SHASUMS256.txt on nodejs.org).
ARG NODE_LTS_VERSION=24.18.1
ARG NODE_LTS_SHA256=d6c664df3f3f61458e8c277585571328522d705166723a7c7823a9253a4d15a0
RUN curl -fsSL -o /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_LTS_VERSION}/node-v${NODE_LTS_VERSION}-linux-x64.tar.xz" \
    && echo "${NODE_LTS_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && node --version \
    && npm --version \
    && npx --version

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color \
    SHELL=/bin/bash \
    WORK=/srcdir \
    SCRATCH=/scratch

RUN printf '%s\n' \
    '[ -f /etc/profile.d/astroai.sh ] && . /etc/profile.d/astroai.sh' \
    >> /etc/bash.bashrc

COPY scripts/astroai-profile.sh /etc/profile.d/astroai.sh
RUN chmod a+r /etc/profile.d/astroai.sh

RUN mkdir -p /opt/astroai/{bin,cache,lib,venv} /cadc "${WORK}" \
    && chmod -R a+rX /opt/astroai \
    && chmod -R a+rwx /opt/astroai/cache \
    && chmod 1777 "${WORK}"

COPY config/cadc-tools.txt /opt/astroai/cadc-tools.txt
COPY scripts/patch-clint-py313.sh /tmp/patch-clint-py313.sh
COPY config/astroai-lab.in config/astroai-lab.lock /tmp/
COPY config/astroai-workload.in config/astroai-workload.lock /tmp/
RUN uv venv /opt/astroai/venv/cadc \
    && uv pip install --python /opt/astroai/venv/cadc -r /opt/astroai/cadc-tools.txt \
    && uv pip install --python /opt/astroai/venv/cadc --requirements /tmp/astroai-lab.lock \
    # astroai-workload[cluster] puts `astroai-workload cluster ensure|dashboard` on
    # PATH in every session image (webterm/vscode/notebook/marimo/orx/openworker) so
    # any agent can launch/manage a CANFAR Ray cluster without Ray installed (py3.13).
    # Installed from the regenerated lock (single source of truth for the pin).
    && uv pip install --python /opt/astroai/venv/cadc --requirements /tmp/astroai-workload.lock \
    && /opt/astroai/venv/cadc/bin/astroai-workload cluster --help >/dev/null \
    # mcp serve needs only the [cluster] extra (no Ray). A real stdio
    # handshake proves the lean base venv imports the MCP module and serves
    # the tools without ray installed.
    && printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
        | /opt/astroai/venv/cadc/bin/astroai-workload mcp serve \
        | grep -q cluster_ensure \
    && bash /tmp/patch-clint-py313.sh /opt/astroai/venv/cadc \
    && rm /tmp/patch-clint-py313.sh /tmp/astroai-lab.in /tmp/astroai-lab.lock \
       /tmp/astroai-workload.in /tmp/astroai-workload.lock \
    && chmod -R a+rwX /opt/astroai/venv/cadc \
    # Copy the packaged session shell files straight out of the installed
    # astroai-lab wheel — astroai-lab itself stays an in-session tool only.
    && mkdir -p /etc/astroai-lab \
    && /opt/astroai/venv/cadc/bin/python -c "import importlib.resources as r, shutil; p=r.files('astroai_lab.data.shell'); shutil.copy(p.joinpath('profile.sh'), '/etc/astroai-lab/profile.sh'); shutil.copy(p.joinpath('hooks.sh'), '/etc/astroai-lab/hooks.sh')" \
    && chmod a+r /etc/astroai-lab/profile.sh /etc/astroai-lab/hooks.sh \
    && test -f /etc/astroai-lab/profile.sh \
    && test -f /etc/astroai-lab/hooks.sh \
    && HOME=/tmp WORK=/srcdir SCRATCH=/scratch \
       /opt/astroai/venv/cadc/bin/astroai-lab env export --no-ensure >/dev/null

COPY scripts/lib/astroai-env-common.sh scripts/lib/astroai-ui.sh scripts/lib/skaha-proxy.sh /opt/astroai/lib/
COPY scripts/canfar-verify.sh scripts/canfar-verify-agents.sh scripts/bootstrap-canfar-registry.sh scripts/upgrade-cadc-tools.sh scripts/peek /opt/astroai/bin/
RUN chmod a+rx /opt/astroai/bin/* /opt/astroai/lib/* \
    && ln -sf /opt/astroai/bin/peek /usr/local/bin/peek

COPY docs/USAGE.md /opt/astroai/USAGE.md
