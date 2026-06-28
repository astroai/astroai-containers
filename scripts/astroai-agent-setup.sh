#!/bin/bash -e
# One-shot AI agent setup for CANFAR AstroAI (persists on /arc).
#
#   astroai-agent-setup           first-time install
#   astroai-agent-setup update    refresh configs + GitHub skills
#   astroai-agent-setup project   AGENTS.md + .cursor/ in current repo

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

BUNDLE_ROOT="${ASTROAI_AGENT_BUNDLE:-/opt/astroai/agent}"
if [[ ! -d "${BUNDLE_ROOT}" ]]; then
    _dev_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    [[ -d "${_dev_root}/config/agent" ]] && BUNDLE_ROOT="${_dev_root}/config/agent"
fi

FORCE=0
DRY_RUN=0
MODE=install
PROJECT_DIR=""
BUNDLES=()

usage() {
    cat <<'EOF' >&2
astroai-agent-setup — AI agent config for CANFAR (one command setup).
Usage:
  astroai-agent-setup              install (safe to re-run)
  astroai-agent-setup update       refresh from image + GitHub
  astroai-agent-setup project      templates for current git repo
  --help for details
EOF
    exit 1
}

help_full() {
    cat <<'EOF'
astroai-agent-setup — AI agent config for all CANFAR AstroAI users.

WHAT IT DOES (persists on /arc across sessions):
  • MCP servers (Context7 docs, GitHub, memory, fetch) for Cursor/Claude/Goose/…
  • Cursor rules (AstroAI paths, Python, search tips)
  • Skills from GitHub (ast-grep, skill-forge matplotlib/pr-review/…)
  • GitHub token hook for MCP

NEW USER — run once:
  gh auth login
  astroai-agent-setup
  astroai-install agent          # or claude, goose, opencode, codex, copilot

AFTER IMAGE UPGRADE — refresh:
  astroai-agent-setup update

IN A PROJECT REPO:
  astroai-agent-setup project

THEN USE STANDARD TOOLS (no extra commands to memorize):
  pixi install && pixi run python script.py
  uv sync && uv run pytest -q
  rg, fd, sg, hyperfine

Options:
  update           Re-fetch bundled config + GitHub skills (--force)
  project [dir]    Install AGENTS.md + .cursor/ in repo (default: cwd)
  --force, -f      Overwrite without using 'update' subcommand
  --dry-run, -n    Show actions only
  --verify         Check install and exit
  --list, -l       Advanced: list bundles (cursor, claude, …)
  --help           This help

Advanced: astroai-agent-setup cursor claude   # single bundle only
EOF
    exit 0
}

list_bundles() {
    if [[ -f "${BUNDLE_ROOT}/manifest.json" ]]; then
        jq -r '.bundles | to_entries[] | "  \(.key)\t\(.value.description // "")"' "${BUNDLE_ROOT}/manifest.json"
    else
        echo "  all, cursor, claude, opencode, goose, codex, copilot, cli, project"
    fi
}

require_bundle_root() {
    [[ -d "${BUNDLE_ROOT}" ]] || { astroai_err "Bundle directory not found: ${BUNDLE_ROOT}"; exit 1; }
}

require_jq() {
    command -v jq >/dev/null || { astroai_err "jq is required"; exit 1; }
}

log_action() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then astroai_hint "[dry-run] $*"; else astroai_info "$*"; fi
}

run_or_echo() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then astroai_hint "[dry-run] $*"; else "$@"; fi
}

install_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "${dst}")"
    if [[ -f "${dst}" && "${FORCE}" -eq 0 ]]; then
        astroai_hint "skip (exists): ${dst}"
        return 0
    fi
    log_action "install ${dst}"
    run_or_echo cp -f "${src}" "${dst}"
}

install_tree() {
    local src_dir="$1" dst_dir="$2"
    [[ -d "${src_dir}" ]] || return 0
    mkdir -p "${dst_dir}"
    local src rel dst
    while IFS= read -r src; do
        [[ -n "${src}" ]] || continue
        rel="${src#"${src_dir}/"}"
        dst="${dst_dir}/${rel}"
        if [[ -f "${dst}" && "${FORCE}" -eq 0 ]]; then
            astroai_hint "skip (exists): ${dst}"
            continue
        fi
        log_action "install ${dst}"
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            mkdir -p "$(dirname "${dst}")"
            cp -f "${src}" "${dst}"
        fi
    done < <(find "${src_dir}" -type f ! -name '.DS_Store')
}

merge_mcp_servers() {
    local src_json="$1" dst_json="$2"
    mkdir -p "$(dirname "${dst_json}")"
    if [[ ! -f "${dst_json}" ]] || [[ "${FORCE}" -eq 1 ]]; then
        log_action "install ${dst_json}"
        run_or_echo cp -f "${src_json}" "${dst_json}"
        return 0
    fi
    log_action "merge MCP → ${dst_json}"
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    local merged
    merged="$(mktemp)"
    jq -s '.[0].mcpServers * .[1].mcpServers | {mcpServers: .}' "${dst_json}" "${src_json}" > "${merged}"
    mv "${merged}" "${dst_json}"
}

merge_claude_json() {
    local src_mcp="$1" dst="$2"
    mkdir -p "$(dirname "${dst}")"
    if [[ ! -f "${dst}" ]]; then
        run_or_echo cp -f "${src_mcp}" "${dst}"
        return 0
    fi
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    local merged
    merged="$(mktemp)"
    jq --slurpfile s "${src_mcp}" '.mcpServers = ((.mcpServers // {}) * $s[0].mcpServers)' "${dst}" > "${merged}"
    mv "${merged}" "${dst}"
}

merge_opencode_mcp() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "${dst}")"
    if [[ ! -f "${dst}" ]] || [[ "${FORCE}" -eq 1 ]]; then
        run_or_echo cp -f "${src}" "${dst}"
        return 0
    fi
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    local merged
    merged="$(mktemp)"
    jq --slurpfile s "${src}" '.mcp = ((.mcp // {}) * ($s[0].mcp // {})) | .lsp = ((.lsp // {}) * ($s[0].lsp // {}))' "${dst}" > "${merged}"
    mv "${merged}" "${dst}"
}

install_goose_config() {
    local dst="${HOME}/.config/goose/config.yaml"
    local src="${BUNDLE_ROOT}/goose/extensions.yaml"
    if [[ -f "${dst}" && "${FORCE}" -eq 0 ]]; then
        astroai_hint "skip (exists): ${dst}"
        return 0
    fi
    log_action "install ${dst}"
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    mkdir -p "$(dirname "${dst}")"
    cat > "${dst}" <<EOF
# AstroAI — run: goose configure
$(cat "${src}")
EOF
}

ensure_agent_dirs() {
    local d
    for d in \
        "${HOME}/.cursor/rules" "${HOME}/.cursor/skills" \
        "${HOME}/.config/goose" "${HOME}/.config/opencode" \
        "${HOME}/.codex" "${HOME}/.copilot" "${HOME}/.claude" \
        "${HOME}/.config/astroai" "${HOME}/.local/share/astroai/agent" \
        "${HOME}/.astroai"; do
        run_or_echo mkdir -p "${d}"
    done
}

hook_github_token() {
    local hook="${HOME}/.config/astroai/agent-env.sh"
    [[ -f "${hook}" && "${FORCE}" -eq 0 ]] && return 0
    log_action "install ${hook}"
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    cat > "${hook}" <<'EOF'
# AstroAI agent-setup — GitHub token for gh + GitHub MCP
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    export GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
fi
EOF
}

install_bashrc_hook() {
    local marker="# astroai-agent-setup"
    local rc="${HOME}/.bashrc"
    touch "${rc}"
    grep -qF "${marker}" "${rc}" 2>/dev/null && return 0
    log_action "hook ${rc} → agent-env.sh"
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    cat >> "${rc}" <<EOF

${marker}
[[ -f "\${HOME}/.config/astroai/agent-env.sh" ]] && source "\${HOME}/.config/astroai/agent-env.sh"
EOF
}

install_upstream_skill() {
    local name="$1" repo="$2" path="$3"
    local dst="${HOME}/.cursor/skills/${name}"
    local src="${BUNDLE_ROOT}/.upstream-cache/${repo}/${path}"
    local cache_root="${BUNDLE_ROOT}/.upstream-cache/${repo}"

    if [[ -f "${dst}/SKILL.md" && "${FORCE}" -eq 0 ]]; then
        astroai_hint "skip (exists): ${name} skill"
        return 0
    fi

    log_action "skill ${name} ← github.com/${repo}"
    [[ "${DRY_RUN}" -eq 1 ]] && return 0

    command -v git >/dev/null || { astroai_warn "git missing — skip ${name}"; return 0; }
    if [[ ! -d "${cache_root}/.git" ]]; then
        rm -rf "${cache_root}"
        git clone --depth 1 --filter=blob:none --sparse "https://github.com/${repo}.git" "${cache_root}" 2>/dev/null || {
            astroai_warn "could not clone ${repo} — skip ${name}"
            return 0
        }
    else
        (cd "${cache_root}" && git pull --ff-only) 2>/dev/null || true
    fi
    (cd "${cache_root}" && git sparse-checkout set "${path}") 2>/dev/null || {
        astroai_warn "sparse checkout failed for ${name}"
        return 0
    }
    [[ -f "${src}/SKILL.md" ]] || { astroai_warn "no SKILL.md for ${name}"; return 0; }
    rm -rf "${dst}"
    cp -a "${src}" "${dst}"
    astroai_ok "✓ ${name}"
}

install_upstream_skills() {
    local sources="${BUNDLE_ROOT}/skills-sources.json"
    [[ -f "${sources}" ]] || return 0
    local name repo path
    while IFS=$'\t' read -r name repo path; do
        [[ -n "${name}" ]] && install_upstream_skill "${name}" "${repo}" "${path}"
    done < <(jq -r '.upstream_skills[] | [.name, .repo, .path] | @tsv' "${sources}")
}

write_stamp() {
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    local ver="unknown"
    [[ -f "${BUNDLE_ROOT}/VERSION" ]] && ver="$(tr -d '[:space:]' < "${BUNDLE_ROOT}/VERSION")"
    date -u +"%Y-%m-%dT%H:%M:%SZ bundle=${ver} mode=${MODE}" > "${HOME}/.astroai/agent-setup-stamp"
}

bundle_cursor() {
    merge_mcp_servers "${BUNDLE_ROOT}/cursor/mcp.json" "${HOME}/.cursor/mcp.json"
    install_tree "${BUNDLE_ROOT}/cursor/rules" "${HOME}/.cursor/rules"
    install_tree "${BUNDLE_ROOT}/cursor/skills" "${HOME}/.cursor/skills"
    install_upstream_skills
}

bundle_claude() {
    merge_claude_json "${BUNDLE_ROOT}/claude/mcp.json" "${HOME}/.claude.json"
    install_file "${BUNDLE_ROOT}/claude/settings.json" "${HOME}/.claude/settings.json"
}

bundle_opencode() { merge_opencode_mcp "${BUNDLE_ROOT}/opencode/opencode.json" "${HOME}/.config/opencode/opencode.json"; }
bundle_goose() {
    install_goose_config
    install_file "${BUNDLE_ROOT}/goose/goosehints" "${HOME}/.config/goose/.goosehints"
}
bundle_codex() { install_file "${BUNDLE_ROOT}/codex/config.toml" "${HOME}/.codex/config.toml"; }
bundle_copilot() { merge_mcp_servers "${BUNDLE_ROOT}/copilot/mcp-config.json" "${HOME}/.copilot/mcp-config.json"; }
bundle_cli() {
    install_file "${BUNDLE_ROOT}/cli/agent-tools.sh" "${HOME}/.config/astroai/agent-tools-reminder.sh"
    hook_github_token
    install_bashrc_hook
}

bundle_project() {
    local root="${PROJECT_DIR:-${PWD}}"
    root="$(cd "${root}" && pwd)"
    log_action "project → ${root}"
    merge_mcp_servers "${BUNDLE_ROOT}/project/.cursor/mcp.json" "${root}/.cursor/mcp.json"
    install_tree "${BUNDLE_ROOT}/project/.cursor/rules" "${root}/.cursor/rules"
    install_file "${BUNDLE_ROOT}/project/AGENTS.md" "${root}/AGENTS.md"
    install_file "${BUNDLE_ROOT}/goose/goosehints" "${root}/.goosehints"
}

resolve_bundle() {
    case "$1" in
        all)
            while IFS= read -r inc; do
                [[ -n "${inc}" ]] && BUNDLES+=("${inc}")
            done < <(jq -r '.bundles.all.includes[]?' "${BUNDLE_ROOT}/manifest.json" 2>/dev/null || echo -e "cursor\nclaude\nopencode\ngoose\ncodex\ncopilot\ncli")
            ;;
        cursor|claude|opencode|goose|codex|copilot|cli|project) BUNDLES+=("$1") ;;
        *) astroai_err "Unknown: $1 (try: update, project, or --list)"; exit 1 ;;
    esac
}

run_bundles() {
    local b
    for b in "${BUNDLES[@]}"; do
        astroai_section "${b}"
        "bundle_${b}"
    done
}

verify_install() {
    local ok=0
    astroai_title "agent setup check"
    [[ -f "${HOME}/.cursor/mcp.json" ]] && jq -e '.mcpServers | length > 0' "${HOME}/.cursor/mcp.json" >/dev/null 2>&1 \
        && astroai_ok "✓ MCP configured" || { astroai_err "✗ MCP missing"; ok=1; }
    [[ -f "${HOME}/.cursor/skills/astroai-workflow/SKILL.md" ]] \
        && astroai_ok "✓ astroai-workflow skill" || astroai_warn "○ astroai-workflow missing"
    [[ -f "${HOME}/.cursor/skills/ast-grep/SKILL.md" ]] \
        && astroai_ok "✓ ast-grep skill (GitHub)" || astroai_warn "○ ast-grep missing (needs network on setup/update)"
    [[ -f "${HOME}/.astroai/agent-setup-stamp" ]] && astroai_hint "last run: $(cat "${HOME}/.astroai/agent-setup-stamp")"
    [[ "${ok}" -eq 0 ]] || exit 1
}

newbie_next_steps() {
    echo ""
    astroai_title "Next steps"
    if ! command -v agent >/dev/null 2>&1 && ! command -v claude >/dev/null 2>&1 \
        && ! command -v goose >/dev/null 2>&1 && ! command -v opencode >/dev/null 2>&1; then
        astroai_cmd "  astroai-install agent       # or: claude, goose, opencode, codex"
    fi
    if ! gh auth status >/dev/null 2>&1; then
        astroai_cmd "  gh auth login               # GitHub + GitHub MCP"
    fi
    if ! command -v sg >/dev/null 2>&1; then
        astroai_hint "  astroai-install ast-grep    # optional: sg for syntax search"
    fi
    astroai_cmd "  astroai-new myproject       # start coding"
    astroai_hint "  Refresh later: astroai-agent-setup update"
    astroai_hint "  Help: astroai-help  |  less /opt/astroai/USAGE.md"
}

# --- parse args ---
VERIFY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        update)
            MODE=update
            FORCE=1
            shift
            ;;
        project)
            MODE=project
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then PROJECT_DIR="$2"; shift 2; else shift; fi
            BUNDLES+=(project)
            ;;
        --list|-l) list_bundles; exit 0 ;;
        --force|-f) FORCE=1; shift ;;
        --dry-run|-n) DRY_RUN=1; shift ;;
        --verify) VERIFY=1; shift ;;
        -h) usage ;;
        --help) help_full ;;
        -*)
            astroai_err "Unknown option: $1"
            usage
            ;;
        *)
            resolve_bundle "$1"
            shift
            ;;
    esac
done

[[ "${VERIFY}" -eq 1 ]] && { verify_install; exit 0; }

require_bundle_root
require_jq

if [[ "${MODE}" == "install" && "${#BUNDLES[@]}" -eq 0 ]]; then
    resolve_bundle all
fi

if [[ "${MODE}" == "update" && "${#BUNDLES[@]}" -eq 0 ]]; then
    astroai_title "Updating agent config + GitHub skills"
    resolve_bundle all
fi

ensure_agent_dirs
run_bundles
write_stamp

if [[ "${DRY_RUN}" -eq 0 ]]; then
    verify_install
    newbie_next_steps
fi
