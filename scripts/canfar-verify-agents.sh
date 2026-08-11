#!/bin/bash -e
set -o pipefail
# Agent setup + install smoke checks (run inside a CANFAR session).
#
# Usage:
#   canfar-verify-agents.sh                 full agent setup and install loop
#   canfar-verify-agents.sh --setup         setup + verify only (no installs)
#   canfar-verify-agents.sh --install-fast  install only goose/opencode/kilo (4 agents)

SETUP_ONLY=0
INSTALL_FAST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup|--setup-only) SETUP_ONLY=1; shift ;;
        --install-fast) INSTALL_FAST=1; shift ;;
        -h|--help)
            sed -n '2,7p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

failures=0
skips=0

login_shell() {
    bash -lc "$*"
}

check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  ok  %s\n' "${label}"
    else
        printf '  FAIL %s\n' "${label}" >&2
        failures=$((failures + 1))
    fi
}

skip() {
    local label="$1"
    local reason="$2"
    printf '  skip %s (%s)\n' "${label}" "${reason}"
    skips=$((skips + 1))
}

gh_authed() {
    login_shell 'gh auth status >/dev/null 2>&1'
}

needs_gh_auth() {
    case "$1" in codex|ast-grep) return 0 ;; *) return 1 ;; esac
}

install_cmd_for() {
    case "$1" in
        ast-grep) echo sg ;;
        cursor) echo agent ;;  # upstream Cursor Agent binary name
        *) echo "$1" ;;
    esac
}

install_path_candidates() {
    local tool="$1"
    local cmd path
    cmd="$(install_cmd_for "${tool}")"
    if [[ -n "${ASTROAI_LAB_BIN_DIR:-}" ]]; then
        printf '%s\n' "${ASTROAI_LAB_BIN_DIR}/${cmd}"
    fi
    printf '%s\n' "${HOME}/.local/bin/${cmd}"
    case "${tool}" in
        opencode) printf '%s\n' "${HOME}/.opencode/bin/opencode" ;;
    esac
}

install_binary_present() {
    local tool="$1"
    local path
    while IFS= read -r path; do
        if login_shell "test -x \"${path}\""; then
            return 0
        fi
    done < <(install_path_candidates "${tool}")
    local cmd
    cmd="$(install_cmd_for "${tool}")"
    login_shell "command -v ${cmd} >/dev/null"
}

check_install() {
    local tool="$1"

    if needs_gh_auth "${tool}" && ! gh_authed; then
        skip "agent install ${tool}" "gh auth login required"
        return 0
    fi

    if ! login_shell "astroai-lab --yes agent install ${tool}"; then
        if [[ "${tool}" == "goose" || "${tool}" == "copilot" ]]; then
            skip "agent install ${tool}" "download failed (network)"
            return 0
        fi
        printf '  FAIL agent install %s (install command)\n' "${tool}" >&2
        failures=$((failures + 1))
        return 0
    fi
    if install_binary_present "${tool}"; then
        printf '  ok  agent install %s\n' "${tool}"
    else
        printf '  FAIL agent install %s (binary not found after install)\n' "${tool}" >&2
        failures=$((failures + 1))
    fi
}

echo "Agent setup & install verification"
echo "=================================="

check "agent setup" login_shell 'astroai-lab --yes agent setup'
check "agent verify" login_shell 'astroai-lab agent verify'
check "agent verify --fix" login_shell 'astroai-lab agent verify --fix'
# Lean agent surface (repair / list / list config / status --ui).
check "agent repair" login_shell 'astroai-lab agent repair'
check "agent repair --all" login_shell 'astroai-lab agent repair --all'
check "agent repair --clean" login_shell 'astroai-lab agent repair --clean'
# astroai-lab renders its tables via a rich console on stderr — pipe 2>&1 so
# the greps see the rows on a plain pipe (discovered by remote CANFAR smoke).
check "agent list" login_shell 'astroai-lab agent list 2>&1 | grep -qE "kilo|Agent"'
check "agent list config" login_shell 'astroai-lab agent list config 2>&1 | grep -q ponytail'
check "agent status --ui" login_shell 'astroai-lab agent status --ui 2>&1 | grep -q Endpoints'
# Plugin registry surface (Phase 3): list must render the shipped plugins
# (canfar-ray skill + ray-manager-mcp) whether or not they are installed yet.
check "agent plugins list" login_shell 'astroai-lab agent plugins list 2>&1 | grep -q canfar-ray'
check "agent plugins list --kind mcp" login_shell 'astroai-lab agent plugins list --kind mcp 2>&1 | grep -q ray-manager-mcp'
check "agent setup stamp" login_shell 'test -f "${HOME}/.astroai/lab/agent-setup-stamp"'
check "cursor MCP" login_shell 'python3 -c "import json, pathlib; d=json.loads(pathlib.Path(\"${HOME}/.cursor/mcp.json\").read_text()); assert d.get(\"mcpServers\")"'
check "astroai-lab-workflow skill" login_shell 'test -f "${HOME}/.cursor/skills/astroai-lab-workflow/SKILL.md"'
check "kilo starter config" login_shell 'test -f "${HOME}/.config/kilo/kilo.jsonc"'
check "agent-env hook" login_shell 'test -f "${HOME}/.config/canfar/lab/agent-env.sh"'

check "agent install --list" login_shell 'astroai-lab agent install --list 2>&1 | grep -q kilo'

if [[ "${SETUP_ONLY}" -eq 1 ]]; then
    echo ""
    if [[ "${failures}" -eq 0 ]]; then
        echo "Agent setup checks passed (${skips} skipped)."
        exit 0
    fi
    echo "${failures} agent setup check(s) failed." >&2
    exit 1
fi

echo ""
echo "Agent tool installs"
echo "-------------------"

# node first — npm-based agents depend on it.
if [[ "${INSTALL_FAST}" -eq 1 ]]; then
    echo "(fast mode — top agents only: goose, opencode, kilo, node)"
    AGENT_TOOLS=(
        node
        goose
        opencode
        kilo
    )
else
    AGENT_TOOLS=(
        node
        goose
        opencode
        swival
        kilo
        cline
        freebuff
        pi
        codewhale
        cursor
        claude
        agy
        copilot
        codex
        ast-grep
        hyperfine
    )
fi

for tool in "${AGENT_TOOLS[@]}"; do
    check_install "${tool}"
done

# After real installs, the registry-driven verbs must operate on the now-
# installed agents: `repair --all` scaffolds missing configs for every
# installed registry agent (kilo/goose/opencode/codex/cline), and
# `agent config <id>` must show the resulting scaffold (parseable).
echo ""
echo "Phase 2/3 registry surface after installs"
echo "------------------------------------------"
check "agent repair --all (installed)" login_shell 'astroai-lab agent repair --all'
# Coupled: if kilo's binary isn't detected by the registry check, repair
# --all no-ops (exit 0) and config kilo would fail with "config not found" —
# assert the scaffold first so the failure is attributable.
check "kilo config present" login_shell 'test -f "${HOME}/.config/kilo/kilo.jsonc"'
check "agent config kilo" login_shell 'astroai-lab agent config kilo >/dev/null 2>&1'

if [[ "${failures}" -eq 0 ]]; then
    echo "All agent checks passed (${skips} skipped)."
    exit 0
fi
echo "${failures} agent check(s) failed (${skips} skipped)." >&2
exit 1
