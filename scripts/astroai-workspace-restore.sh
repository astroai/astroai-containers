#!/bin/bash -e
set -o pipefail
# Restore a frozen workspace onto TMP_SRC_DIR — no network, no git, no pixi install.
#
# Usage:
#   astroai-workspace-restore <name> [--from path] [--to path]
#
# Headless batch example:
#   astroai-workspace-restore mylab && cd "${TMP_SRC_DIR}/mylab" && pixi run python job.py

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
astroai-workspace-restore — restore a frozen workspace for offline batch use.
Usage: astroai-workspace-restore <name> [--from <path>] [--to <path>]
  --help for details
EOF
    exit 1
}

help_full() {
    cat <<'EOF'
astroai-workspace-restore — restore a frozen workspace for offline batch use.

Extracts a workspace bundle (from astroai-workspace-save) onto TMP_SRC_DIR.
No network, no git clone, no pixi install — everything is pre-packed.

Usage:
  astroai-workspace-restore <name> [--from <path>] [--to <path>]

Arguments:
  name              Name of the workspace bundle to restore.

Options:
  --from <path>     Restore from a custom bundle location.
  --to <path>       Extract to a custom target directory (must be under
                    TMP_SRC_DIR).
  -h                Show short usage summary.
  --help            Show this detailed help.

Examples:
  astroai-workspace-restore mylab
  astroai-workspace-restore mylab --from /arc/bundles/mylab
  astroai-workspace-restore mylab --to "${TMP_SRC_DIR}/mylab-v2"

Headless batch:
  astroai-workspace-restore mylab && cd "${TMP_SRC_DIR}/mylab" && pixi run python job.py

Notes:
  • Target directory must be empty or non-existent.
  • If the bundle includes caches (--with-cache), they are also restored.
  • Bundles on /arc are read once and extracted to TMP_SRC_DIR.
EOF
    exit 0
}

FROM_OVERRIDE=""
TARGET=""
NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)
            [[ -n "${2:-}" ]] || { echo "--from requires a path" >&2; exit 1; }
            FROM_OVERRIDE="$2"
            shift 2
            ;;
        --to)
            [[ -n "${2:-}" ]] || { echo "--to requires a path" >&2; exit 1; }
            TARGET="$2"
            shift 2
            ;;
        -h) usage ;;
        --help) help_full ;;
        *)
            NAME="$1"
            shift
            ;;
    esac
done

[[ -n "${NAME}" ]] || { astroai_err "Usage: astroai-workspace-restore <name> [--from path] [--to path]"; exit 1; }

SRC_DIR="$(astroai_src_dir)"
SAVE_DIR="${FROM_OVERRIDE:-$(astroai_workspace_bundle_dir "${NAME}")}"

[[ -f "${SAVE_DIR}/manifest.json" && -f "${SAVE_DIR}/project.tar.zst" ]] || {
    astroai_err "Workspace bundle not found: ${SAVE_DIR}"
    astroai_cmd "List bundles: ls -la $(astroai_workspace_root)/"
    exit 1
}

if [[ ! -d "${SRC_DIR}" || ! -w "${SRC_DIR}" ]]; then
    astroai_err "TMP_SRC_DIR is not writable: ${SRC_DIR}"
    exit 1
fi

RESTORE_TO="$(jq -r .restore_to "${SAVE_DIR}/manifest.json")"
if [[ -z "${TARGET}" ]]; then
    TARGET="${RESTORE_TO}"
fi

if [[ "${TARGET}" != "${SRC_DIR}"/* && "${TARGET}" != "${SRC_DIR}" ]]; then
    astroai_err "Restore target must be under TMP_SRC_DIR (${SRC_DIR}); got ${TARGET}."
    astroai_hint "Set TMP_SRC_DIR to your code root, or pass --to under ${SRC_DIR}."
    exit 1
fi

if [[ -e "${TARGET}" && -n "$(ls -A "${TARGET}" 2>/dev/null)" ]]; then
    astroai_err "Target already exists and is not empty: ${TARGET}"
    exit 1
fi

if [[ "${SAVE_DIR}" == /arc/* ]]; then
    astroai_info "Reading bundle from /arc (one-time) -> extracting to ${SRC_DIR}..."
else
    astroai_info "Restoring workspace '${NAME}' from ${SAVE_DIR}..."
fi

_extract_root="$(dirname "${TARGET}")"
mkdir -p "${_extract_root}"
astroai_info "Extracting project tree to ${_extract_root}..."
zstd -d -c "${SAVE_DIR}/project.tar.zst" | tar -xf - -C "${_extract_root}"

EXTRACTED="$(jq -r .restore_to "${SAVE_DIR}/manifest.json")"
if [[ ! -d "${EXTRACTED}" ]]; then
    astroai_err "Extracted project missing at ${EXTRACTED}"
    exit 1
fi
if [[ "${TARGET}" != "${EXTRACTED}" ]]; then
    mkdir -p "$(dirname "${TARGET}")"
    mv "${EXTRACTED}" "${TARGET}"
fi

if [[ -f "${SAVE_DIR}/cache.tar.zst" ]]; then
    astroai_info "Restoring package caches..."
    _cache_root="$(astroai_scratch_cache_root)"
    _cache_parent="$(dirname "${_cache_root}")"
    mkdir -p "${_cache_parent}"
    zstd -d -c "${SAVE_DIR}/cache.tar.zst" | tar -xf - -C "${_cache_parent}"
fi

KIND="$(jq -r .kind "${SAVE_DIR}/manifest.json")"
astroai_ok "Restored -> ${TARGET}"
astroai_kv "Saved:" "$(jq -r .saved_at "${SAVE_DIR}/manifest.json") from $(jq -r .saved_from "${SAVE_DIR}/manifest.json")"

echo ""
case "${KIND}" in
    pixi)
        astroai_cmd "cd ${TARGET} && pixi run python your_script.py"
        ;;
    uv)
        astroai_cmd "cd ${TARGET} && uv run --offline python your_script.py"
        ;;
    *)
        astroai_cmd "cd ${TARGET}"
        ;;
esac
