#!/bin/bash -e
# Clone a GitHub repo under TMP_SRC_DIR and install its dependencies.
#
# Usage:
#   astroai-clone owner/repo
#   astroai-clone --from-env ml-base owner/repo
#   astroai-clone owner/repo "${TMP_SRC_DIR}/custom-dir"

for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

usage() {
    cat <<'EOF' >&2
astroai-clone — clone a GitHub repo and install deps.
Usage: astroai-clone [--from-env <name>] [--from <path>] <owner/repo> [target-dir]
  --help for details
EOF
}

help_full() {
    cat <<'EOF'
astroai-clone — clone a GitHub repo and install deps.

Usage:
  astroai-clone [--from-env <name>] [--from <path>] <owner/repo> [target-dir]

Options:
  --from-env <name>  Warm download caches from a saved env (astroai-env-save).
                     If the repo has no lockfile yet, copy one as a local bootstrap.
                     Never overwrites an existing pixi.lock / uv.lock from git.
  --from <path>      Saved env directory (with --from-env; default: ~/.astroai/saves/<name>).
  -h                 Short help (stderr, exit 1)
  --help             This help (stdout, exit 0)

Clones a GitHub repo via `gh repo clone` and runs `pixi install`
or `uv sync` if a pixi.toml or pyproject.toml is found.

Defaults to TMP_SRC_DIR/<repo-name> when target-dir is omitted.
Requires `gh auth login` for GitHub access.

The cloned repo stays portable: no AstroAI-specific files are added.
For open-source users outside AstroAI, commit standard pixi.toml / pyproject.toml
and lockfiles — `pixi install` or `uv sync` is all they need.

Examples:
  astroai-clone astroai/astroai-containers
  astroai-clone myorg/myproject
  astroai-clone --from-env ml-base myorg/myproject
  astroai-clone --from-env ml-base --from /arc/projects/group/env-saves/ml-base myorg/myproject
  astroai-clone myorg/myproject "${TMP_SRC_DIR}/custom"
EOF
}

FROM_ENV=""
FROM_OVERRIDE=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-env)
            [[ -n "${2:-}" ]] || { astroai_err "--from-env requires a save name"; exit 1; }
            FROM_ENV="$2"
            shift 2
            ;;
        --from)
            [[ -n "${2:-}" ]] || { astroai_err "--from requires a path"; exit 1; }
            FROM_OVERRIDE="$2"
            shift 2
            ;;
        -h) usage; exit 1 ;;
        --help) help_full; exit 0 ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

REPO="${POSITIONAL[0]:-}"
TARGET="${POSITIONAL[1]:-}"

if [[ -z "${REPO}" ]]; then
    usage
    exit 1
fi

if [[ -n "${FROM_OVERRIDE}" && -z "${FROM_ENV}" ]]; then
    astroai_err "--from requires --from-env <name>"
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    astroai_err "gh (GitHub CLI) is required. Run: gh auth login"
    exit 1
fi

REPO_NAME="${REPO##*/}"
SRC_DIR="$(astroai_src_dir)"

if [[ -z "${TARGET}" ]]; then
    TARGET="${SRC_DIR}/${REPO_NAME}"
fi

if [[ -d "${TARGET}" ]]; then
    astroai_err "Target already exists: ${TARGET}"
    exit 1
fi

SAVE_DIR=""
if [[ -n "${FROM_ENV}" ]]; then
    SAVE_DIR="$(astroai_env_save_resolve "${FROM_ENV}" "${FROM_OVERRIDE}")"
    astroai_info "Warming caches from saved env '${FROM_ENV}'..."
    astroai_env_warm_cache "${SAVE_DIR}"
fi

astroai_info "Cloning ${REPO} -> ${TARGET}..."
gh repo clone "${REPO}" "${TARGET}"

cd "${TARGET}"

KIND="$(astroai_detect_project)"
BOOTSTRAP_LOCK=0

if [[ -n "${SAVE_DIR}" && -n "${KIND}" ]]; then
    astroai_env_bootstrap_lock "${SAVE_DIR}" "${KIND}"
    BOOTSTRAP_LOCK="${ASTROAI_BOOTSTRAP_LOCK:-0}"
fi

install_pixi() {
    if [[ "${BOOTSTRAP_LOCK}" -eq 1 ]]; then
        if ! pixi install 2>/dev/null; then
            astroai_warn "Saved lockfile doesn't match this pixi.toml — resolving a fresh lock."
            rm -f pixi.lock
            pixi lock
        fi
    fi
    pixi install
}

install_uv() {
    if [[ "${BOOTSTRAP_LOCK}" -eq 1 ]]; then
        if ! uv sync 2>/dev/null; then
            astroai_warn "Saved lockfile doesn't match this pyproject.toml — resolving a fresh lock."
            rm -f uv.lock
            uv lock
        fi
    fi
    uv sync
}

case "${KIND}" in
    pixi)
        astroai_info "Installing pixi environment..."
        install_pixi
        echo ""
        astroai_ok "Ready: cd ${TARGET}"
        astroai_cmd "  pixi run python script.py"
        ;;
    uv)
        astroai_info "Installing uv environment..."
        install_uv
        echo ""
        astroai_ok "Ready: cd ${TARGET}"
        astroai_cmd "  uv run python script.py"
        ;;
    *)
        astroai_hint "No pixi.toml or pyproject.toml found — skipping dependency install."
        astroai_cmd "  pixi init   (or: uv init)"
        astroai_cmd "  pixi add python numpy"
        echo ""
        astroai_ok "Ready: cd ${TARGET}"
        ;;
esac
