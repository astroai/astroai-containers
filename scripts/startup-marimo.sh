#!/bin/bash -e
# Marimo reactive notebooks on port 5000.
# Open the file browser on TMP_SRC_DIR/notebooks and seed starter.py once.

source /cadc/common-init.sh

# common-init cds to the session work root (TMP_SRC_DIR).
NOTEBOOKS_DIR="$(pwd)/notebooks"
mkdir -p "${NOTEBOOKS_DIR}"

STARTER_SRC="/opt/astroai/notebooks/starter.py"
STARTER_DST="${NOTEBOOKS_DIR}/starter.py"
# Seed once — never overwrite student edits.
if [[ -f "${STARTER_SRC}" && ! -e "${STARTER_DST}" ]]; then
    cp "${STARTER_SRC}" "${STARTER_DST}"
fi

# Convenience symlinks so File > Open and the file browser widget can reach
# session storage (/scratch, /srcdir) and persistent storage (/arc) in one click.
ln -sfn /scratch "${NOTEBOOKS_DIR}/📁_scratch" 2>/dev/null || true
ln -sfn /srcdir "${NOTEBOOKS_DIR}/📁_srcdir" 2>/dev/null || true
ln -sfn /arc "${NOTEBOOKS_DIR}/📁_arc" 2>/dev/null || true

cd "${NOTEBOOKS_DIR}"

# Bridge astroai-lab agent OpenRouter config to marimo's AI assistant.
# astroai-lab agent setup stores the API key at ~/.config/canfar/lab/agent-env.sh.
#
# TODO(marimo-ai): Remove this block + the marimo.toml seed below once
# astroai-lab agent setup natively writes ~/.marimo.toml with the API key.
# See docs/CONTRIBUTING.md § "Marimo AI ↔ astroai-lab upstream integration".
_AGENT_ENV="${HOME}/.config/canfar/lab/agent-env.sh"
if [[ -f "${_AGENT_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${_AGENT_ENV}"
fi
unset _AGENT_ENV

# Seed default marimo.toml on first launch (persistent on /arc/home).
# User customizations are never overwritten.
# TODO(marimo-ai): Remove once astroai-lab agent setup owns this.
# See docs/CONTRIBUTING.md § "Marimo AI ↔ astroai-lab upstream integration".
_MARIMO_TOML="${HOME}/.marimo.toml"
if [[ ! -f "${_MARIMO_TOML}" ]]; then
    cp /opt/astroai/config/marimo.toml "${_MARIMO_TOML}"
fi
unset _MARIMO_TOML

# CANFAR contributed ingress strips /session/contrib/<id> before forwarding
# (same as webterm). Do not pass --base-url here — marimo would only serve under
# that prefix and the proxied request for / would 404.

exec marimo --log-level warn edit \
    --no-token \
    --port 5000 \
    --host 0.0.0.0 \
    --skip-update-check \
    --headless \
    .
