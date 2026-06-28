#!/bin/bash -e
# Persist Harbor registry credentials to ~/.canfar/config.yaml on /arc/home.
# Reads REGISTRY_URL, REGISTRY_USER, and REGISTRY_SECRET from the environment.

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
