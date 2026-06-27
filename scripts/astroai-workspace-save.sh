#!/bin/bash -e
set -o pipefail
# Freeze a full project tree for offline batch restore (code + env + optional caches).
#
# Stores under TMP_SRC_DIR/.astroai/workspaces by default — not on /arc.
#
# Usage:
#   cd "${TMP_SRC_DIR}/myproject"
#   astroai-workspace-save [name] [--with-cache]
#
# Batch (no network):
#   astroai-workspace-restore mylab
#   cd "${TMP_SRC_DIR}/mylab" && pixi run python job.py

for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

WITH_CACHE=0
DEST_OVERRIDE=""
NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-cache) WITH_CACHE=1; shift ;;
        --to)
            [[ -n "${2:-}" ]] || { echo "--to requires a path" >&2; exit 1; }
            DEST_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,15p' "$0"
            exit 0
            ;;
        *)
            NAME="$1"
            shift
            ;;
    esac
done

PROJECT_ROOT="$(pwd)"
PROJECT_BASE="$(basename "${PROJECT_ROOT}")"
NAME="${NAME:-${PROJECT_BASE}}"
STAMP="$(astroai_timestamp)"
KIND="$(astroai_detect_project)"
SRC_DIR="$(astroai_src_dir)"

if [[ "${PROJECT_ROOT}" != "${SRC_DIR}"/* && "${PROJECT_ROOT}" != "${SRC_DIR}" ]]; then
    astroai_warn "Project is not under TMP_SRC_DIR (${SRC_DIR}): ${PROJECT_ROOT}"
fi

if [[ -n "${DEST_OVERRIDE}" ]]; then
    SAVE_DIR="${DEST_OVERRIDE%/}"
else
    SAVE_DIR="$(astroai_workspace_bundle_dir "${NAME}")"
fi

if [[ "${SAVE_DIR}" == "${PROJECT_ROOT}"* ]]; then
    astroai_err "Save directory cannot be inside the project tree: ${SAVE_DIR}"
    exit 1
fi

mkdir -p "${SAVE_DIR}"

astroai_info "Freezing workspace '${NAME}'..."
astroai_kv "Project:" "${PROJECT_ROOT}"
astroai_kv "Bundle:" "${SAVE_DIR}"

PROJECT_PARENT="$(dirname "${PROJECT_ROOT}")"
astroai_info "Packing project tree..."
tar -C "${PROJECT_PARENT}" -cf - "${PROJECT_BASE}" | zstd -T0 -o "${SAVE_DIR}/project.tar.zst"

CACHE_BYTES=0
if [[ "${WITH_CACHE}" -eq 1 ]]; then
    CACHE_ROOT="$(astroai_scratch_cache_root)"
    if [[ -d "${CACHE_ROOT}" && -n "$(ls -A "${CACHE_ROOT}" 2>/dev/null)" ]]; then
        astroai_info "Packing package caches from ${CACHE_ROOT}..."
        _cache_parent="$(dirname "${CACHE_ROOT}")"
        _cache_name="$(basename "${CACHE_ROOT}")"
        tar -C "${_cache_parent}" -cf - "${_cache_name}" | zstd -T0 -o "${SAVE_DIR}/cache.tar.zst"
        CACHE_BYTES="$(stat -c '%s' "${SAVE_DIR}/cache.tar.zst" 2>/dev/null || echo 0)"
    else
        astroai_hint "No package cache at ${CACHE_ROOT} — skipping cache.tar.zst"
    fi
fi

PROJECT_BYTES="$(stat -c '%s' "${SAVE_DIR}/project.tar.zst")"

jq -n \
    --arg name "${NAME}" \
    --arg kind "${KIND:-none}" \
    --arg saved_at "${STAMP}" \
    --arg saved_from "${PROJECT_ROOT}" \
    --arg user "${USER}" \
    --arg restore_to "${PROJECT_ROOT}" \
    --arg src_dir "${SRC_DIR}" \
    --argjson with_cache "${WITH_CACHE}" \
    --argjson project_bytes "${PROJECT_BYTES}" \
    --argjson cache_bytes "${CACHE_BYTES}" \
    '{
        name: $name,
        kind: $kind,
        saved_at: $saved_at,
        saved_from: $saved_from,
        user: $user,
        restore_to: $restore_to,
        src_dir: $src_dir,
        with_cache: $with_cache,
        project_bytes: $project_bytes,
        cache_bytes: $cache_bytes
    }' > "${SAVE_DIR}/manifest.json"

du -sh "${SAVE_DIR}"
astroai_ok "Workspace frozen -> ${SAVE_DIR}"
echo ""
astroai_cmd "Batch (offline): astroai-workspace-restore ${NAME}"
if [[ "${SAVE_DIR}" == /arc/* ]]; then
    astroai_warn "Bundle is on /arc — restore still extracts to ${SRC_DIR} (one-time read, do not run from /arc)."
fi
