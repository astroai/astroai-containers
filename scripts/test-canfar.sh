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
#   CANFAR_REGISTRY__USERNAME / CANFAR_REGISTRY__SECRET  Harbor pull creds
#   REGISTRY_USER / REGISTRY_PASSWORD  alternate Harbor cred env names

IMAGE="${1:-base}"
TAG="${2:-${TAG:-latest}}"
OWNER="${OWNER:-astroai}"
REGISTRY="${REGISTRY:-images.canfar.net}"
TIMEOUT="${CANFAR_TEST_TIMEOUT:-600}"
FULL_IMAGE="${REGISTRY}/${OWNER}/${IMAGE}:${TAG}"
SESSION_NAME="astroai-verify-${IMAGE}-${TAG}-$(date -u +%Y%m%d%H%M%S)"

ensure_registry_auth() {
    if [[ -n "${CANFAR_REGISTRY__USERNAME:-}" && -n "${CANFAR_REGISTRY__SECRET:-}" ]]; then
        export CANFAR_REGISTRY__URL="${CANFAR_REGISTRY__URL:-https://${REGISTRY}}"
        return 0
    fi

    if [[ -n "${REGISTRY_USER:-}" && -n "${REGISTRY_PASSWORD:-}" ]]; then
        export CANFAR_REGISTRY__USERNAME="${REGISTRY_USER}"
        export CANFAR_REGISTRY__SECRET="${REGISTRY_PASSWORD}"
        export CANFAR_REGISTRY__URL="${CANFAR_REGISTRY__URL:-https://${REGISTRY}}"
        return 0
    fi

    local configured_user
    configured_user="$(canfar config get registry.username 2>/dev/null | tail -1 || true)"
    if [[ -n "${configured_user}" && "${configured_user}" != "null" ]]; then
        return 0
    fi

    local docker_cfg="${HOME}/.docker/config.json"
    if [[ ! -f "${docker_cfg}" ]]; then
        echo "Harbor credentials required for private image ${FULL_IMAGE}." >&2
        echo "Set CANFAR_REGISTRY__USERNAME and CANFAR_REGISTRY__SECRET, or:" >&2
        echo "  canfar config set registry.username <user>" >&2
        echo "  canfar config set registry.secret <token>" >&2
        echo "  canfar config set registry.url https://${REGISTRY}" >&2
        exit 1
    fi

    if ! mapfile -t _reg_creds < <(
        python3 - "${REGISTRY}" "${docker_cfg}" <<'PY'
import base64
import json
import sys

registry, path = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    cfg = json.load(fh)
entry = cfg.get("auths", {}).get(registry, {})
if "auth" in entry:
    user, secret = base64.b64decode(entry["auth"]).decode().split(":", 1)
elif entry.get("username") and entry.get("password"):
    user, secret = entry["username"], entry["password"]
else:
    sys.exit(1)
print(user)
print(secret)
PY
    ) || [[ ${#_reg_creds[@]} -lt 2 ]]; then
        echo "Could not read Harbor credentials from ${docker_cfg} for ${REGISTRY}." >&2
        echo "Log in with: docker login ${REGISTRY}" >&2
        exit 1
    fi

    CANFAR_REGISTRY__USERNAME="${_reg_creds[0]}"
    CANFAR_REGISTRY__SECRET="${_reg_creds[1]}"
    export CANFAR_REGISTRY__USERNAME CANFAR_REGISTRY__SECRET
    export CANFAR_REGISTRY__URL="${CANFAR_REGISTRY__URL:-https://${REGISTRY}}"
    echo "Using Harbor credentials for ${REGISTRY} (user: ${CANFAR_REGISTRY__USERNAME})"
}

if ! command -v canfar >/dev/null 2>&1; then
    echo "canfar CLI not found. Install with: uv tool install canfar" >&2
    exit 1
fi

if ! canfar auth show >/dev/null 2>&1; then
    echo "canfar is not authenticated. Run: canfar auth login" >&2
    exit 1
fi

ensure_registry_auth

session_status() {
    local sid="$1"
    canfar ps -a --json 2>/dev/null | python3 -c "
import json, sys

target = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    print('')
    raise SystemExit(0)
for marker in ('[', '{'):
    idx = raw.find(marker)
    if idx >= 0:
        raw = raw[idx:]
        break
try:
    rows = json.loads(raw)
except json.JSONDecodeError:
    print('')
    raise SystemExit(0)
if isinstance(rows, dict):
    rows = [rows]
for row in rows:
    if row.get('id') == target:
        print(row.get('status', ''))
        break
" "${sid}" || true
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

SESSION_ID="$(
    printf '%s\n' "${CREATE_OUT}" \
        | tr -d '\r' \
        | tr '\n' ' ' \
        | sed -n 's/.*(ID:[[:space:]]*\([^)]*\)).*/\1/p' \
        | awk '{print $1}'
)"
if [[ -z "${SESSION_ID}" ]]; then
    SESSION_ID="$(
        canfar ps -a --json 2>/dev/null | python3 -c "
import json, sys

name = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
for marker in ('[', '{'):
    idx = raw.find(marker)
    if idx >= 0:
        raw = raw[idx:]
        break
try:
    rows = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)
if isinstance(rows, dict):
    rows = [rows]
for row in rows:
    if row.get('name') == name:
        print(row.get('id', ''))
        break
" "${SESSION_NAME}" || true
    )"
fi
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
        Succeeded|Completed)
            echo "Session finished (${status})."
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

if [[ "${status}" != "Succeeded" && "${status}" != "Completed" ]]; then
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
