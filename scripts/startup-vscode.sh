#!/bin/bash -e
# OpenVSCode Server on port 5000 (CANFAR Contributed session type).

export ASTROAI_SESSION_KIND="${ASTROAI_SESSION_KIND:-vscode}"
source /cadc/common-init.sh
# shellcheck disable=SC1091
source /opt/astroai/lib/skaha-proxy.sh

_settings=/opt/openvscode-server/data/Machine/settings.json
if [[ -w "${_settings}" ]] && command -v astroai_session_title >/dev/null; then
    ASTROAI_TAB_TITLE="$(astroai_session_title "AstroAI VS Code")"
    export ASTROAI_TAB_TITLE
    python3 -c '
import json, os, pathlib
p = pathlib.Path("/opt/openvscode-server/data/Machine/settings.json")
data = json.loads(p.read_text())
data["window.title"] = os.environ["ASTROAI_TAB_TITLE"]
p.write_text(json.dumps(data, indent=2) + "\n")
'
fi

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
