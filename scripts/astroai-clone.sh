#!/bin/bash -e
# Clone a GitHub repo onto /scratch and install its dependencies.
#
# Usage:
#   astroai-clone owner/repo
#   astroai-clone owner/repo /scratch/custom-dir

source /opt/astroai/lib/astroai-env-common.sh

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

REPO="${1:-}"
TARGET="${2:-}"

if [[ -z "${REPO}" ]]; then
    echo "Usage: astroai-clone <owner/repo> [target-dir]" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  astroai-clone astroai/astroai-containers" >&2
    echo "  astroai-clone myorg/myproject /scratch/custom-dir" >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "gh (GitHub CLI) is required. Run: gh auth login" >&2
    exit 1
fi

# Derive repo name from owner/repo or bare repo
REPO_NAME="${REPO##*/}"

if [[ -z "${TARGET}" ]]; then
    if [[ -d /scratch && -w /scratch ]]; then
        TARGET="/scratch/${REPO_NAME}"
    else
        TARGET="${HOME}/${REPO_NAME}"
        echo "No writable /scratch — cloning to ${TARGET}" >&2
    fi
fi

if [[ -d "${TARGET}" ]]; then
    echo "Target already exists: ${TARGET}" >&2
    exit 1
fi

echo "Cloning ${REPO} -> ${TARGET}..."
gh repo clone "${REPO}" "${TARGET}"

cd "${TARGET}"

KIND="$(astroai_detect_project)"
case "${KIND}" in
    pixi)
        echo "Installing pixi environment..."
        pixi install
        echo ""
        echo "Ready: cd ${TARGET}"
        echo "  pixi run python script.py"
        ;;
    uv)
        echo "Installing uv environment..."
        uv sync
        echo ""
        echo "Ready: cd ${TARGET}"
        echo "  uv run python script.py"
        ;;
    *)
        echo "No pixi.toml or pyproject.toml found — skipping dependency install."
        echo "  pixi init   (or: uv init)"
        echo "  pixi add python numpy"
        echo ""
        echo "Ready: cd ${TARGET}"
        ;;
esac
