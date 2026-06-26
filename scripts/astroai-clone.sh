#!/bin/bash -e
# Clone a GitHub repo onto /scratch and install its dependencies.
#
# Usage:
#   astroai-clone owner/repo
#   astroai-clone owner/repo /scratch/custom-dir

for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

REPO="${1:-}"
TARGET="${2:-}"

if [[ -z "${REPO}" ]]; then
    astroai_err "Usage: astroai-clone <owner/repo> [target-dir]"
    echo "" >&2
    astroai_cmd "  astroai-clone astroai/astroai-containers"
    astroai_cmd "  astroai-clone myorg/myproject /scratch/custom-dir"
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    astroai_err "gh (GitHub CLI) is required. Run: gh auth login"
    exit 1
fi

REPO_NAME="${REPO##*/}"

if [[ -z "${TARGET}" ]]; then
    if [[ -d /scratch && -w /scratch ]]; then
        TARGET="/scratch/${REPO_NAME}"
    else
        TARGET="${HOME}/${REPO_NAME}"
        astroai_warn "No writable /scratch — cloning to ${TARGET}"
    fi
fi

if [[ -d "${TARGET}" ]]; then
    astroai_err "Target already exists: ${TARGET}"
    exit 1
fi

astroai_info "Cloning ${REPO} -> ${TARGET}..."
gh repo clone "${REPO}" "${TARGET}"

cd "${TARGET}"

KIND="$(astroai_detect_project)"
case "${KIND}" in
    pixi)
        astroai_info "Installing pixi environment..."
        pixi install
        echo ""
        astroai_ok "Ready: cd ${TARGET}"
        astroai_cmd "  pixi run python script.py"
        ;;
    uv)
        astroai_info "Installing uv environment..."
        uv sync
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
