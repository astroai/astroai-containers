#!/bin/bash -e
# Post-push smoke test on CANFAR using a headless Skaha session.
#
# Requires: canfar CLI authenticated (canfar auth login)
#
# Usage:
#   ./scripts/test-canfar.sh [image] [tag]
#   ./scripts/test-canfar.sh base 26.06
#   ./scripts/test-canfar.sh webterm latest
#
# Environment:
#   REGISTRY   default images.canfar.net
#   OWNER      default astroai
#   CANFAR_TEST_TIMEOUT  seconds to wait for session (default 600)

IMAGE="${1:-base}"
TAG="${2:-${TAG:-latest}}"
OWNER="${OWNER:-astroai}"
REGISTRY="${REGISTRY:-images.canfar.net}"
TIMEOUT="${CANFAR_TEST_TIMEOUT:-600}"
FULL_IMAGE="${REGISTRY}/${OWNER}/${IMAGE}:${TAG}"
SESSION_NAME="astroai-verify-${IMAGE}-${TAG}-$(date -u +%Y%m%d%H%M%S)"

if ! command -v canfar >/dev/null 2>&1; then
    echo "canfar CLI not found. Install with: uv tool install canfar" >&2
    exit 1
fi

if ! canfar auth show >/dev/null 2>&1; then
    echo "canfar is not authenticated. Run: canfar auth login" >&2
    exit 1
fi

session_status() {
    local sid="$1"
    canfar ps -a --json 2>/dev/null | python3 -c "
import json, sys
target = sys.argv[1]
for row in json.load(sys.stdin):
    if row.get('id') == target:
        print(row.get('status', ''))
        break
" "${sid}"
}

cleanup() {
    if [[ -n "${SESSION_ID:-}" ]]; then
        echo ""
        echo "Deleting test session ${SESSION_ID}..."
        canfar delete --force "${SESSION_ID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "CANFAR headless verification"
echo "  image:   ${FULL_IMAGE}"
echo "  name:    ${SESSION_NAME}"
echo "  timeout: ${TIMEOUT}s"
echo ""

CREATE_OUT="$(
    canfar create --name "${SESSION_NAME}" headless "${FULL_IMAGE}" -- \
        bash /opt/astroai/bin/canfar-verify.sh 2>&1
)" || {
    echo "${CREATE_OUT}" >&2
    echo "Failed to create headless session." >&2
    exit 1
}

echo "${CREATE_OUT}"

SESSION_ID="$(printf '%s\n' "${CREATE_OUT}" | sed -n 's/.*(ID: \([^)]*\)).*/\1/p' | head -1)"
if [[ -z "${SESSION_ID}" ]]; then
    echo "Could not parse session ID from canfar create output." >&2
    exit 1
fi

echo "Session ID: ${SESSION_ID}"
echo "Waiting for completion (poll every 10s)..."

deadline=$((SECONDS + TIMEOUT))
status=""
while (( SECONDS < deadline )); do
    status="$(session_status "${SESSION_ID}")"
    case "${status}" in
        Succeeded)
            echo "Session succeeded."
            break
            ;;
        Failed|Error|Terminating)
            echo "Session ended with status: ${status}" >&2
            break
            ;;
        "")
            # Session may not appear in ps immediately
            ;;
        *)
            :
            ;;
    esac
    sleep 10
done

if [[ "${status}" != "Succeeded" ]]; then
    echo ""
    echo "=== Session logs ==="
    canfar logs "${SESSION_ID}" 2>&1 || true
    echo ""
    echo "Verification failed (status: ${status:-timeout})." >&2
    exit 1
fi

echo ""
echo "=== Session logs ==="
LOGS="$(canfar logs "${SESSION_ID}" 2>&1 || true)"
printf '%s\n' "${LOGS}"

if printf '%s\n' "${LOGS}" | grep -q "All checks passed."; then
    echo ""
    echo "CANFAR headless verification passed for ${FULL_IMAGE}."
    exit 0
fi

echo ""
echo "Session succeeded but verification output missing success marker." >&2
exit 1
