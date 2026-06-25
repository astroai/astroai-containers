#!/bin/bash -e
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

echo "AstroAI image verification"
echo "=========================="

check "astroai-profile on PATH" bash -lc '[[ ":${PATH}:" == *":/opt/astroai/venv/cadc/bin:"* ]]'
check "login shell: canfar" bash -lic 'command -v canfar >/dev/null'
check "login shell: cadcget" bash -lic 'command -v cadcget >/dev/null'
check "login shell: cadc-tap" bash -lic 'command -v cadc-tap >/dev/null'
check "login shell: vcp" bash -lic 'command -v vcp >/dev/null'
check "login shell: astroai-help" bash -lic 'command -v astroai-help >/dev/null'

for tool in gh rg fd bat fzf uv pixi patch make file xxd hexdump lsof ss host ncdu shellcheck ctags; do
    check "login shell: ${tool}" bash -lic "command -v ${tool} >/dev/null"
done

if [[ "${QUICK}" -eq 0 ]]; then
    check "interactive shell: canfar" bash -ic 'command -v canfar >/dev/null'
    check "canfar CLI" bash -lic 'canfar --help >/dev/null 2>&1'
    check "cadcget --help" bash -lic 'cadcget --help >/dev/null 2>&1'
    check "rg search" bash -lic 'rg --version >/dev/null 2>&1'
    check "file magic" bash -lic 'file /bin/bash | grep -q ELF'
    if bash -lic 'command -v node >/dev/null'; then
        check "node --version" bash -lic 'node --version >/dev/null 2>&1'
        check "npm --version" bash -lic 'npm --version >/dev/null 2>&1'
    fi
fi

echo ""
if [[ "${failures}" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "${failures} check(s) failed." >&2
exit 1
