#!/bin/bash -e
# OpenVSCode Server on port 5000 (CANFAR Contributed session type).

export ASTROAI_SESSION_KIND="${ASTROAI_SESSION_KIND:-vscode}"
source /cadc/common-init.sh
# shellcheck disable=SC1091
source /opt/astroai/lib/skaha-proxy.sh

OPS=(
    --host 0.0.0.0
    --port 5000
    --without-connection-token
    --default-folder "${PWD}"
)

if [[ -n "${skaha_sessionid:-}" ]]; then
    OPS+=(--server-base-path "$(astroai_skaha_base_url "${skaha_sessionid}" contrib)")
fi

exec /opt/openvscode-server/bin/openvscode-server "${OPS[@]}"
