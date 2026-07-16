#!/bin/bash -e
set -o pipefail
# Post-deploy smoke checks for AstroAI images (run inside a CANFAR session).
#
# Usage:
#   canfar-verify.sh              full check (login + non-login shells)
#   canfar-verify.sh --quick        PATH + CADC CLIs only

QUICK=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick) QUICK=1; shift ;;
        -h|--help)
            sed -n '2,6p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

failures=0

# ---------------------------------------------------------------------------
# Batch runner: pipe a shell script via stdin into ONE "bash -lc" call.
# The inner script must emit lines of the form "PASS:<label>" or "FAIL:<label>".
# ---------------------------------------------------------------------------
batch_login() {
    bash -lc "$(cat)"
}

# Process PASS/FAIL lines from a batch_login invocation, updating $failures.
# Each batch MUST end with "BATCH_END" — if missing, the batch crashed and
# we report a failure rather than silently dropping all its checks.
process_batch() {
    local status label _saw_end=0
    while IFS=: read -r status label; do
        case "${status}" in
            BATCH_END) _saw_end=1 ;;
            PASS)      printf '  ok  %s\n' "${label}" ;;
            FAIL)      printf '  FAIL %s\n' "${label}" >&2; failures=$((failures + 1)) ;;
            *)         printf '  FAIL (unexpected) %s:%s\n' "${status}" "${label}" >&2; failures=$((failures + 1)) ;;
        esac
    done
    if [[ $_saw_end -eq 0 ]]; then
        printf '  FAIL batch execution incomplete (no BATCH_END sentinel)\n' >&2
        failures=$((failures + 1))
    fi
}

echo "AstroAI image verification"
echo "=========================="

# ================================================================
# Batch 1 — ~39 checks: PATH + all command -v lookups + env var
# (replaces 39 individual login_shell calls)
# ================================================================
process_batch < <(batch_login <<'CHECK_BATCH'
# PATH
[[ ":${PATH}:" == *":/opt/astroai/venv/cadc/bin:"* ]] && echo "PASS:astroai-profile on PATH" || echo "FAIL:astroai-profile on PATH"

# CADC + bundled CLIs
for t in canfar cadcget cadcput cadc-tap vcp cadc-get-cert astroai-lab peek; do
    command -v "$t" >/dev/null 2>&1 && echo "PASS:login shell: ${t}" || echo "FAIL:login shell: ${t}"
done

# Tool ecosystem
for t in gh rg fd bat fzf hyperfine uv pixi micromamba mamba patch make file xxd hexdump lsof ss host ncdu shellcheck ctags \
         gcc g++ gfortran ld ar rustc cargo cmake ninja autoconf automake libtoolize flex bison; do
    command -v "$t" >/dev/null 2>&1 && echo "PASS:login shell: ${t}" || echo "FAIL:login shell: ${t}"
done

# Env
[[ -n "${ASTROAI_LAB_BIN_DIR:-}" ]] && echo "PASS:ASTROAI_LAB_BIN_DIR set" || echo "FAIL:ASTROAI_LAB_BIN_DIR set"
echo "BATCH_END"
CHECK_BATCH
)

# ================================================================
# Batch 2 — 5 astroai-lab subcommands (each imports Python, so
# grouping them avoids 4 extra shell + Python startups)
# ================================================================
process_batch < <(batch_login <<'CHECK_BATCH'
astroai-lab doctor >/dev/null 2>&1 && echo "PASS:astroai-lab doctor" || echo "FAIL:astroai-lab doctor"
astroai-lab paths --json | grep -q work_dir && echo "PASS:astroai-lab paths" || echo "FAIL:astroai-lab paths"
astroai-lab tools --json | grep -q '"name": "git"' && echo "PASS:astroai-lab tools" || echo "FAIL:astroai-lab tools"
astroai-lab check --json | grep -q '"ok": true' && echo "PASS:astroai-lab check" || echo "FAIL:astroai-lab check"
astroai-lab agent install --list >/dev/null 2>&1 && echo "PASS:astroai-lab agent bundle" || echo "FAIL:astroai-lab agent bundle"
echo "BATCH_END"
CHECK_BATCH
)

# Direct file-system checks (no login shell needed)
check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  ok  %s\n' "${label}"
    else
        printf '  FAIL %s\n' "${label}" >&2
        failures=$((failures + 1))
    fi
}

check "CADC venv writable" test -w /opt/astroai/venv/cadc
check "upgrade-cadc-tools helper" test -x /opt/astroai/bin/upgrade-cadc-tools.sh
check "peek helper" test -x /opt/astroai/bin/peek

# ================================================================
# Non-quick checks — batched into ONE login shell with conditional
# logic inside (replaces ~17 individual login_shell calls)
# ================================================================
if [[ "${QUICK}" -eq 0 ]]; then
    # Interactive shell is different from login shell; keep separate
    check "interactive shell: canfar" bash -ic 'command -v canfar >/dev/null' </dev/null

    process_batch < <(batch_login <<'CHECK_BATCH'
# cadcget / rg / file
canfar --help >/dev/null 2>&1 && echo "PASS:canfar CLI" || echo "FAIL:canfar CLI"
cadcget --help >/dev/null 2>&1 && echo "PASS:cadcget --help" || echo "FAIL:cadcget --help"
out=$(cadcget --version 2>&1); ! echo "$out" | grep -q SyntaxWarning && echo "PASS:cadcget --version (no SyntaxWarning)" || echo "FAIL:cadcget --version (no SyntaxWarning)"
rg --version >/dev/null 2>&1 && echo "PASS:rg search" || echo "FAIL:rg search"
file /bin/bash | grep -q ELF && echo "PASS:file magic" || echo "FAIL:file magic"

# node / npm (conditional on node being installed)
if command -v node >/dev/null 2>&1; then
    node --version >/dev/null 2>&1 && echo "PASS:node --version" || echo "FAIL:node --version"
    npm --version >/dev/null 2>&1 && echo "PASS:npm --version" || echo "FAIL:npm --version"
fi

# TMP_SRC_DIR (only report when the guard passes — matches legacy behaviour)
if [[ -n "${TMP_SRC_DIR:-}" && -d "${TMP_SRC_DIR}" && -w "${TMP_SRC_DIR}" ]]; then
    echo "PASS:TMP_SRC_DIR writable"
fi

# Scratch-mounted checks
if [[ -d "${TMP_SCRATCH_DIR}" && -w "${TMP_SCRATCH_DIR}" ]]; then
    u="${USER:-$(id -un)}"
    root="${TMP_SCRATCH_DIR}/.cache-${u}"
    [[ "${UV_CACHE_DIR}" == "${root}/"* ]] && echo "PASS:session cache root layout" || echo "FAIL:session cache root layout"
    for var in PIP_CACHE_DIR NPM_CONFIG_CACHE PIXI_CACHE_DIR MAMBA_PKGS_DIRS CONDA_PKGS_DIRS; do
        [[ "${!var}" == "${root}/"* ]] && echo "PASS:${var} under session cache root" || echo "FAIL:${var} under session cache root"
    done
    [[ "${ASTROAI_LAB_BIN_DIR}" == "${TMP_SCRATCH_DIR}/"* ]] && echo "PASS:ASTROAI_LAB_BIN_DIR on scratch" || echo "FAIL:ASTROAI_LAB_BIN_DIR on scratch"
    [[ "${ASTROAI_LAB_RUNTIME_ROOT}" == "${TMP_SCRATCH_DIR}/"* ]] && echo "PASS:ASTROAI_LAB_RUNTIME_ROOT on scratch" || echo "FAIL:ASTROAI_LAB_RUNTIME_ROOT on scratch"
    [[ "${UV_PYTHON_INSTALL_DIR}" != "${HOME}/"* ]] && echo "PASS:UV_PYTHON_INSTALL_DIR off home" || echo "FAIL:UV_PYTHON_INSTALL_DIR off home"
    [[ "${PIXI_HOME}" != "${HOME}/.pixi" ]] && echo "PASS:PIXI_HOME off home when scratch mounted" || echo "FAIL:PIXI_HOME off home when scratch mounted"
    astroai-lab env export --no-ensure | grep -q ASTROAI_LAB_BIN_DIR && echo "PASS:astroai-lab env export" || echo "FAIL:astroai-lab env export"
elif [[ -n "${TMP_SRC_DIR:-}" ]]; then
    for var in UV_CACHE_DIR PIP_CACHE_DIR NPM_CONFIG_CACHE PIXI_CACHE_DIR MAMBA_PKGS_DIRS CONDA_PKGS_DIRS; do
        [[ "${!var}" == "${TMP_SRC_DIR}/"* ]] && echo "PASS:${var} under TMP_SRC_DIR" || echo "FAIL:${var} under TMP_SRC_DIR"
    done
fi
echo "BATCH_END"
CHECK_BATCH
)

    echo ""
    echo "Running agent setup & install verification..."
    /opt/astroai/bin/canfar-verify-agents.sh || failures=$((failures + 1))
fi

echo ""
if [[ "${failures}" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "${failures} check(s) failed." >&2
exit 1
