#!/bin/bash -e
# Install AI coding tools into ~/.local/bin on /arc (persistent).
#
# Usage:
#   astroai-install <tool>       install a specific tool
#   astroai-install --list       list available tools
#
# Tools install to ~/.local/bin which persists on /arc and is on PATH.

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

BIN_DIR="${HOME}/.local/bin"

list_tools() {
    cat <<'EOF'
Available tools:
  node       Node.js + npm      pixi    (persistent on /arc; enables npm CLIs)
  agent      Cursor Agent       curl    (no Node)
  claude     Claude Code        curl    (no Node)
  agy        Antigravity (Google) curl   (no Node)
  opencode   OpenCode           curl    (no Node)
  codex      Codex CLI (OpenAI) gh      (no Node)
  freebuff   Freebuff           npm     (needs node — run: astroai-install node)
  aider      Aider              uv      (no Node)

Install:  astroai-install <tool>
EOF
}

usage() {
    echo "Usage: astroai-install <tool>" >&2
    echo "       astroai-install --list" >&2
    echo "" >&2
    list_tools >&2
    exit 1
}

ensure_bin_dir() {
    if [[ ! -d "${BIN_DIR}" ]]; then
        mkdir -p "${BIN_DIR}"
    fi
    if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
        echo "Warning: ${BIN_DIR} is not on PATH. Open a new shell or run: hash -r" >&2
    fi
}

verify_install() {
    local cmd="$1"
    if command -v "${cmd}" >/dev/null 2>&1; then
        echo "✓ ${cmd} installed: $(${cmd} --version 2>&1 | head -1)"
    else
        echo "✗ ${cmd} not found on PATH — try opening a new shell" >&2
        return 1
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "$1 is required but not found." >&2; exit 1; }
}

install_node() {
    require_command pixi
    local pixi_bin="${PIXI_HOME:-${HOME}/.pixi}/bin"
    echo "Installing Node.js via pixi global (persists under ${PIXI_HOME:-${HOME}/.pixi})..."
    pixi global install nodejs
    for cmd in node npm npx; do
        if [[ -x "${pixi_bin}/${cmd}" ]]; then
            ln -sf "${pixi_bin}/${cmd}" "${BIN_DIR}/${cmd}"
        else
            echo "Expected ${pixi_bin}/${cmd} after pixi global install" >&2
            exit 1
        fi
    done
    echo ""
    echo "npm globals: npm install -g --prefix \"${HOME}/.local\" <package>"
    verify_install node
    verify_install npm
}

TOOL="${1:-}"

case "${TOOL}" in
    --list|-l)
        list_tools
        exit 0
        ;;
    -h|--help|"")
        usage
        ;;
esac

ensure_bin_dir

case "${TOOL}" in
    node)
        install_node
        ;;
    agent)
        echo "Installing Cursor Agent..."
        require_command curl
        curl -fsS https://cursor.com/install | bash
        echo ""
        echo "Run: agent auth   (or set CURSOR_API_KEY)"
        verify_install agent
        ;;
    claude)
        echo "Installing Claude Code..."
        require_command curl
        curl -fsSL https://claude.ai/install.sh | bash
        echo ""
        echo "Run: claude   (sign in on first run)"
        verify_install claude
        ;;
    agy)
        echo "Installing Antigravity CLI..."
        require_command curl
        curl -fsSL https://antigravity.google/cli/install.sh | bash
        echo ""
        echo "Run: agy   (sign in on first run)"
        verify_install agy
        ;;
    opencode)
        echo "Installing OpenCode..."
        require_command curl
        XDG_BIN_DIR="${BIN_DIR}" curl -fsSL https://opencode.ai/install | bash
        echo ""
        verify_install opencode
        ;;
    codex)
        echo "Installing Codex CLI (via GitHub releases — no Node required)..."
        require_command gh
        require_command curl

        if ! gh auth status &>/dev/null; then
            echo "gh is not authenticated. Run: gh auth login" >&2
            exit 1
        fi

        ARCH="$(uname -m)"
        case "${ARCH}" in
            x86_64)  ASSET="codex-x86_64-unknown-linux-musl.tar.gz" ;;
            aarch64) ASSET="codex-aarch64-unknown-linux-musl.tar.gz" ;;
            *)       echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
        esac

        TMPDIR="${TMPDIR:-/tmp}"
        mkdir -p "${TMPDIR}"

        echo "Downloading ${ASSET}..."
        gh release download -R openai/codex -p "${ASSET}" -D "${TMPDIR}"

        tar -xzf "${TMPDIR}/${ASSET}" -C "${BIN_DIR}"
        BINARY="${ASSET%.tar.gz}"
        if [[ -f "${BIN_DIR}/${BINARY}" ]]; then
            mv "${BIN_DIR}/${BINARY}" "${BIN_DIR}/codex"
        else
            echo "Extract failed — unexpected tarball layout (expected ${BINARY})" >&2
            exit 1
        fi
        chmod +x "${BIN_DIR}/codex" 2>/dev/null || true
        rm -f "${TMPDIR}/${ASSET}"

        echo ""
        echo "Run: codex login"
        verify_install codex
        ;;
    freebuff)
        echo "Installing Freebuff..."
        if ! command -v npm >/dev/null 2>&1; then
            echo "npm is required but not found." >&2
            echo "" >&2
            echo "Install Node.js first:" >&2
            echo "  astroai-install node" >&2
            echo "" >&2
            echo "Or use the full image (node/npm pre-installed), pixi on /scratch, or CVMFS module load nodejs." >&2
            exit 1
        fi
        npm install -g --prefix "${HOME}/.local" freebuff
        echo ""
        verify_install freebuff
        ;;
    aider)
        echo "Installing Aider..."
        require_command uv
        uv tool install aider-chat
        echo ""
        verify_install aider
        ;;
    *)
        echo "Unknown tool: ${TOOL}" >&2
        echo "" >&2
        list_tools >&2
        exit 1
        ;;
esac

echo ""
echo "Installed to ${BIN_DIR} (persists on /arc)"
echo "Try: ${TOOL} --help"
