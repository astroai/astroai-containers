#!/bin/bash -e
# Persist Harbor registry credentials (and optional active server) to
# $HOME/.canfar/config.yaml (on CANFAR: /arc/home/<user>/.canfar/config.yaml).
#
# Env:
#   REGISTRY_URL, REGISTRY_USER, REGISTRY_SECRET — Harbor pull creds (required)
#   ACTIVE_SERVER — optional canfar active.server name (e.g. staging / canfar).
#     When the manager is launched on staging but /arc/home/<user>/.canfar still
#     points at production, workers land on the wrong cluster and cannot join.
#   ACTIVE_SERVER_URL — Skaha base URL for ACTIVE_SERVER when it must be added
#     to the servers map (default: https://staging.canfar.net/skaha for staging,
#     https://ws-uv.canfar.net/skaha for canfar).

: "${REGISTRY_USER:?REGISTRY_USER required}"
: "${REGISTRY_SECRET:?REGISTRY_SECRET required}"

registry_url="${REGISTRY_URL:-https://images.canfar.net}"
registry_url="${registry_url%/}/"
cfg_dir="${HOME}/.canfar"
cfg_file="${cfg_dir}/config.yaml"

mkdir -p "${cfg_dir}"
if [[ ! -f "${cfg_file}" ]]; then
    printf 'version: 1\n' >"${cfg_file}"
fi

tmp_body="$(mktemp)"
tmp_registry="$(mktemp)"
trap 'rm -f "${tmp_body}" "${tmp_registry}"' EXIT

awk '
    BEGIN { skip = 0 }
    /^registry:/ { skip = 1; next }
    skip && /^[^ ]/ { skip = 0 }
    !skip { print }
' "${cfg_file}" >"${tmp_body}"

{
    echo "registry:"
    printf '  url: %s\n' "${registry_url}"
    printf '  username: %s\n' "${REGISTRY_USER}"
    printf '  secret: %s\n' "${REGISTRY_SECRET}"
} >"${tmp_registry}"

cat "${tmp_body}" "${tmp_registry}" >"${cfg_file}"
echo "registry config persisted"

# Align Skaha target with the cluster the manager/workers should use.
if [[ -n "${ACTIVE_SERVER:-}" ]]; then
    CANFAR_BIN="$(command -v canfar || true)"
    if [[ -z "${CANFAR_BIN}" && -x /opt/astroai/venv/cadc/bin/canfar ]]; then
        CANFAR_BIN=/opt/astroai/venv/cadc/bin/canfar
    fi
    if [[ -z "${CANFAR_BIN}" ]]; then
        echo "canfar CLI missing — could not set active.server=${ACTIVE_SERVER}" >&2
        exit 0
    fi
    # Ensure the named server exists in the mapping (arc homes often only have
    # production `canfar`).
    if ! "${CANFAR_BIN}" config set active.server "${ACTIVE_SERVER}" >/dev/null 2>&1; then
        case "${ACTIVE_SERVER}" in
            staging) default_url="https://staging.canfar.net/skaha" ;;
            canfar)  default_url="https://ws-uv.canfar.net/skaha" ;;
            *)       default_url="" ;;
        esac
        server_url="${ACTIVE_SERVER_URL:-${default_url}}"
        if [[ -z "${server_url}" ]]; then
            echo "ACTIVE_SERVER=${ACTIVE_SERVER} not in config and no ACTIVE_SERVER_URL" >&2
            exit 1
        fi
        echo "Adding servers.${ACTIVE_SERVER} -> ${server_url}"
        "${CANFAR_BIN}" config set "servers.${ACTIVE_SERVER}.url" "${server_url}" >/dev/null
        "${CANFAR_BIN}" config set "servers.${ACTIVE_SERVER}.name" "${ACTIVE_SERVER}" >/dev/null || true
        "${CANFAR_BIN}" config set "servers.${ACTIVE_SERVER}.version" "v1" >/dev/null || true
        "${CANFAR_BIN}" config set "servers.${ACTIVE_SERVER}.idp" "cadc" >/dev/null || true
        "${CANFAR_BIN}" config set active.server "${ACTIVE_SERVER}" >/dev/null
    fi
    echo "active.server set to ${ACTIVE_SERVER}"
    "${CANFAR_BIN}" auth show 2>&1 | head -20 || true
fi
