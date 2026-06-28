#!/bin/bash -e
# Install AI coding tools into ~/.local/bin on /arc (persistent).
#
# Usage:
#   astroai-install <tool>       install a specific tool
#   astroai-install --list       list available tools
#
# Tools install to ~/.local/bin which persists on /arc and is on PATH.

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

BIN_DIR="${HOME}/.local/bin"

list_tools() {
    cat <<'EOF'
Available tools:
  node       Node.js + npm      pixi    (persistent on /arc; enables npm CLIs)
  agent      Cursor Agent       curl    (no Node)
  claude     Claude Code        curl    (no Node)
  agy        Antigravity CLI    curl    (no Node; replaced Gemini CLI)
  opencode   OpenCode           curl    (no Node)
  codex      Codex CLI (OpenAI) gh      (no Node)
  copilot    GitHub Copilot CLI curl   (no Node)
  goose      Goose              curl    (no Node)
  pi         Pi Coding Agent    npm     (needs node — run: astroai-install node)
  codewhale  CodeWhale          npm     (needs node — run: astroai-install node)
  swival     Swival             uv      (no Node)
  freebuff   Freebuff           npm     (needs node — run: astroai-install node)

Install:  astroai-install <tool>
EOF
}

usage() {
    cat <<'EOF' >&2
astroai-install — install AI coding tools into ~/.local/bin.
Usage: astroai-install <tool>
       astroai-install --list
  --help for details
EOF
    list_tools >&2
}

help_full() {
    cat <<'EOF'
astroai-install — install AI coding tools into ~/.local/bin.

Usage:
  astroai-install <tool>
  astroai-install --list

Options:
  <tool>      Install the named tool (see list below)
  --list, -l  List available tools
  -h          Short help (stderr, exit 1)
  --help      This help (stdout, exit 0)

Tools are installed to ~/.local/bin, which persists on /arc
and is on PATH. Some tools require Node.js — install it first
with `astroai-install node`.

Examples:
  astroai-install claude
  astroai-install agy
  astroai-install node    # install Node.js first for npm-based tools
  astroai-install --list  # see all available tools
EOF
    list_tools
}

ensure_bin_dir() {
    if [[ ! -d "${BIN_DIR}" ]]; then
        mkdir -p "${BIN_DIR}"
    fi
    if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
        astroai_warn "Warning: ${BIN_DIR} is not on PATH. Open a new shell or run: hash -r"
    fi
}

verify_install() {
    local cmd="$1"
    if command -v "${cmd}" >/dev/null 2>&1; then
        astroai_ok "✓ ${cmd} installed: $(${cmd} --version 2>&1 | head -1)"
    else
        astroai_err "✗ ${cmd} not found on PATH — try opening a new shell"
        return 1
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || { astroai_err "$1 is required but not found."; exit 1; }
}

require_npm() {
    if command -v npm >/dev/null 2>&1; then
        return 0
    fi
    astroai_err "npm is required but not found."
    echo "" >&2
    astroai_hint "Install Node.js first:"
    astroai_cmd "  astroai-install node"
    echo "" >&2
    astroai_hint "Or use the full image (node/npm pre-installed), pixi under TMP_SRC_DIR, or CVMFS module load nodejs."
    exit 1
}

install_node() {
    require_command pixi
    local pixi_bin="${PIXI_HOME:-${HOME}/.pixi}/bin"
    astroai_info "Installing Node.js via pixi global (persists under ${PIXI_HOME:-${HOME}/.pixi})..."
    pixi global install nodejs
    for cmd in node npm npx; do
        if [[ -x "${pixi_bin}/${cmd}" ]]; then
            ln -sf "${pixi_bin}/${cmd}" "${BIN_DIR}/${cmd}"
        else
            astroai_err "Expected ${pixi_bin}/${cmd} after pixi global install"
            exit 1
        fi
    done
    echo ""
    astroai_hint "npm globals: npm install -g --prefix \"${HOME}/.local\" <package>"
    verify_install node
    verify_install npm
}

TOOL="${1:-}"

case "${TOOL}" in
    --list|-l)
        list_tools
        exit 0
        ;;
    -h|"")
        usage
        exit 1
        ;;
    --help)
        help_full
        exit 0
        ;;
esac

ensure_bin_dir

case "${TOOL}" in
    node)
        install_node
        ;;
    agent)
        astroai_info "Installing Cursor Agent..."
        require_command curl
        curl -fsS https://cursor.com/install | bash
        astroai_hint "Run: agent auth   (or set CURSOR_API_KEY)"
        verify_install agent
        ;;
    claude)
        astroai_info "Installing Claude Code..."
        require_command curl
        curl -fsSL https://claude.ai/install.sh | bash
        astroai_hint "Run: claude   (sign in on first run)"
        verify_install claude
        ;;
    agy)
        astroai_info "Installing Antigravity CLI (Google; successor to Gemini CLI)..."
        require_command curl
        curl -fsSL https://antigravity.google/cli/install.sh | bash
        astroai_hint "Run: agy   (sign in on first run)"
        verify_install agy
        ;;
    opencode)
        astroai_info "Installing OpenCode..."
        require_command curl
        XDG_BIN_DIR="${BIN_DIR}" curl -fsSL https://opencode.ai/install | bash
        echo ""
        verify_install opencode
        ;;
    codex)
        astroai_info "Installing Codex CLI (via GitHub releases — no Node required)..."
        require_command gh
        require_command curl

        if ! gh auth status &>/dev/null; then
            astroai_err "gh is not authenticated. Run: gh auth login"
            exit 1
        fi

        ARCH="$(uname -m)"
        case "${ARCH}" in
            x86_64)  ASSET="codex-x86_64-unknown-linux-musl.tar.gz" ;;
            aarch64) ASSET="codex-aarch64-unknown-linux-musl.tar.gz" ;;
            *)       astroai_err "Unsupported architecture: ${ARCH}"; exit 1 ;;
        esac

        TMPDIR="${TMPDIR:-/tmp}"
        mkdir -p "${TMPDIR}"

        astroai_info "Downloading ${ASSET}..."
        gh release download -R openai/codex -p "${ASSET}" -D "${TMPDIR}"

        tar -xzf "${TMPDIR}/${ASSET}" -C "${BIN_DIR}"
        BINARY="${ASSET%.tar.gz}"
        if [[ -f "${BIN_DIR}/${BINARY}" ]]; then
            mv "${BIN_DIR}/${BINARY}" "${BIN_DIR}/codex"
        else
            astroai_err "Extract failed — unexpected tarball layout (expected ${BINARY})"
            exit 1
        fi
        chmod +x "${BIN_DIR}/codex" 2>/dev/null || true
        rm -f "${TMPDIR}/${ASSET}"

        astroai_hint "Run: codex login"
        verify_install codex
        ;;
    copilot)
        astroai_info "Installing GitHub Copilot CLI..."
        require_command curl
        PREFIX="${HOME}/.local" curl -fsSL https://gh.io/copilot-install | bash
        astroai_hint "Run: copilot   (sign in on first run; GitHub Copilot subscription required)"
        verify_install copilot
        ;;
    goose)
        astroai_info "Installing Goose..."
        require_command curl
        GOOSE_BIN_DIR="${BIN_DIR}" CONFIGURE=false \
            curl -fsSL https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh | bash
        astroai_hint "Run: goose configure   then goose"
        verify_install goose
        ;;
    freebuff)
        astroai_info "Installing Freebuff..."
        require_npm
        npm install -g --prefix "${HOME}/.local" freebuff
        verify_install freebuff
        ;;
    pi)
        astroai_info "Installing Pi Coding Agent..."
        require_npm
        npm install -g --prefix "${HOME}/.local" @earendil-works/pi-coding-agent
        astroai_hint "Run: pi   (configure provider/API key on first run)"
        verify_install pi
        ;;
    codewhale)
        astroai_info "Installing CodeWhale..."
        require_npm
        npm install -g --prefix "${HOME}/.local" codewhale
        astroai_hint "Run: codewhale auth set   then codewhale"
        verify_install codewhale
        ;;
    swival)
        astroai_info "Installing Swival..."
        require_command uv
        uv tool install swival
        astroai_hint "Run: swival   (interactive) or swival \"task\""
        verify_install swival
        ;;
    *)
        astroai_err "Unknown tool: ${TOOL}"
        echo "" >&2
        list_tools >&2
        exit 1
        ;;
esac

echo ""
astroai_ok "Installed to ${BIN_DIR} (persists on /arc)"
astroai_cmd "Try: ${TOOL} --help"
