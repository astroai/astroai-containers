#!/bin/bash -e
# Marimo reactive notebooks on port 5000.
# Open the file browser on TMP_SRC_DIR/notebooks and seed starter.py once.

source /cadc/common-init.sh
# shellcheck disable=SC1091
source /opt/astroai/lib/skaha-proxy.sh

# common-init cds to the session work root (TMP_SRC_DIR).
NOTEBOOKS_DIR="$(pwd)/notebooks"
mkdir -p "${NOTEBOOKS_DIR}"

STARTER_SRC="/opt/astroai/notebooks/starter.py"
STARTER_DST="${NOTEBOOKS_DIR}/starter.py"
# Seed once — never overwrite student edits.
if [[ -f "${STARTER_SRC}" && ! -e "${STARTER_DST}" ]]; then
    cp "${STARTER_SRC}" "${STARTER_DST}"
fi

cd "${NOTEBOOKS_DIR}"

BASE_URL_ARG=()
if [[ -n "${skaha_sessionid:-}" ]]; then
    BASE_URL_ARG=(--base-url "$(astroai_skaha_base_url "${skaha_sessionid}" contrib)")
fi

exec marimo --log-level warn edit \
    --no-token \
    --port 5000 \
    --host 0.0.0.0 \
    --skip-update-check \
    --headless \
    "${BASE_URL_ARG[@]}" \
    .
