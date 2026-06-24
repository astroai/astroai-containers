#!/bin/bash -e
# Browser terminal: ttyd + tmux on port 5000 (CANFAR Contributed session type).

export ASTROAI_SESSION_KIND=webterm

source /cadc/common-init.sh
# shellcheck disable=SC1091
source /opt/astroai/lib/skaha-proxy.sh

TTYD_ARGS=(
    --writable
    --port 5000
    -w "${PWD}"
    -t titleFixed="AstroAI Webterm"
    -t 'theme={"background":"#1e1e2e","foreground":"#cdd6f4","cursor":"#f5e0dc","selectionBackground":"#585b70"}'
    -t fontSize=15
    -t fontFamily="Menlo, monospace"
)

if [[ -n "${skaha_sessionid:-}" ]]; then
    TTYD_ARGS+=(--base-path "$(astroai_skaha_base_url "${skaha_sessionid}" contrib)")
fi

exec ttyd "${TTYD_ARGS[@]}" \
    tmux new-session -A -s astroai bash -l
