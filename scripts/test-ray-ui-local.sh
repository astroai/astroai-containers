#!/bin/bash -e
# Verify Ray manager contributed UI and JSON endpoints locally.
#
# Usage:
#   test-ray-ui-local.sh            full UI + dashboard proxy checks
#   test-ray-ui-local.sh --smoke     fast smoke: HTML + API endpoints only

set -o pipefail

REGISTRY="${REGISTRY:-images.canfar.net}"
OWNER="${OWNER:-astroai}"
TAG="${BUILD_TAG:-local}"
NETWORK="ray-ui-test-$$"
FAKE_ARC="$(mktemp -d)"
FAKE_SCRATCH="$(mktemp -d)"
FAILURES=0
SMOKE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --smoke) SMOKE=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

MGR="${REGISTRY}/${OWNER}/ray-manager:${TAG}"
RAY_VERSION_EXPECTED="$(docker run --rm --entrypoint /opt/astroai/venv/ray/bin/python "${MGR}" \
    -c 'import ray; print(ray.__version__)')"

cleanup() {
    docker rm -f ray-ui-test 2>/dev/null || true
    docker network rm "${NETWORK}" 2>/dev/null || true
    rm -rf "${FAKE_ARC}" "${FAKE_SCRATCH}"
}
trap cleanup EXIT

mkdir -p "${FAKE_ARC}/home/testuser" "${FAKE_SCRATCH}"
chmod -R a+rwX "${FAKE_ARC}" "${FAKE_SCRATCH}"
docker network create "${NETWORK}" >/dev/null

docker run -d --name ray-ui-test \
    --network "${NETWORK}" --shm-size=1g \
    -u "$(id -u):$(id -g)" \
    -e HOME=/arc/home/testuser -e USER=testuser \
    -e RAY_CLUSTER_ID=ui-test -e RAY_VERSION_EXPECTED="${RAY_VERSION_EXPECTED}" \
    -v "${FAKE_ARC}:/arc" -v "${FAKE_SCRATCH}:/scratch" \
    "${MGR}" >/dev/null

deadline=$((SECONDS + ${SMOKE_READYZ_TIMEOUT:-120}))
while (( SECONDS < deadline )); do
    docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" \
        -fsS "http://ray-ui-test:5000/readyz" >/dev/null 2>&1 && break
    sleep 2
done

check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  ok  %s\n' "${label}"
    else
        printf '  FAIL %s\n' "${label}" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

BASE="http://ray-ui-test:5000"
HTML="$(docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" -fsS "${BASE}/")"

echo "Ray manager UI verification"
[[ "${SMOKE}" -eq 1 ]] && echo "(smoke mode — skipping dashboard proxy wait)"
echo "==========================="

check "HTML title" grep -q "CANFAR Ray Manager" <<< "${HTML}"
check "dashboard CTA" grep -q 'href="/dashboard/"' <<< "${HTML}"
check "create cluster form" grep -q 'action="/actions/create-cluster"' <<< "${HTML}"
check "gpus form field" grep -q 'name="gpus"' <<< "${HTML}"
check "preflight action" grep -q 'action="/actions/preflight"' <<< "${HTML}"
check "stop cluster action" grep -q 'action="/actions/stop-cluster"' <<< "${HTML}"
check "clean orphans action" grep -q 'action="/actions/clean-orphans"' <<< "${HTML}"
check "public_path prefixes session" docker run --rm --entrypoint python "${MGR}" -c "
import os, sys
sys.path.insert(0, '/opt/astroai/ray-manager')
os.environ['skaha_sessionid'] = 'abc123'
from ui import public_path
assert public_path('/dashboard/') == '/session/contrib/abc123/dashboard/', public_path('/dashboard/')
assert public_path('/') == '/session/contrib/abc123/'
os.environ.pop('skaha_sessionid', None)
assert public_path('/dashboard/') == '/dashboard/'
print('ok')
"
check "auth status JSON" docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" \
    -fsS "${BASE}/api/v1/auth/status" | grep -q '"authenticated"'
check "status JSON" docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" \
    -fsS "${BASE}/api/v1/status" | grep -q '"ray_address"'
check "dashboard status JSON" docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" \
    -fsS "${BASE}/api/v1/dashboard/status" | grep -q '"path"'
check "dashboard redirect" docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" \
    -sS -o /dev/null -w '%{http_code} %{redirect_url}' "${BASE}/dashboard" \
    | grep -qE '307 .*/dashboard/'
# Wait for Ray Dashboard process (enabled on head start, proxied under /dashboard/).
# Skipped in smoke mode — the dashboard takes ~30-90s to come up.
if [[ "${SMOKE}" -eq 0 ]]; then
dash_ok=0
dash_deadline=$((SECONDS + 90))
while (( SECONDS < dash_deadline )); do
    code="$(docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" \
        -sS -o /dev/null -w '%{http_code}' "${BASE}/dashboard/" || true)"
    if [[ "${code}" == "200" ]]; then
        dash_ok=1
        break
    fi
    sleep 3
done
check "dashboard proxy 200" test "${dash_ok}" -eq 1
fi
check "preflight POST" docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" \
    -fsS -o /dev/null -w '%{http_code}' -X POST "${BASE}/actions/preflight" | grep -qE '303|200'
check "reconcile POST" docker run --rm --network "${NETWORK}" --entrypoint curl "${MGR}" \
    -fsS -o /dev/null -w '%{http_code}' -X POST "${BASE}/actions/reconcile" | grep -q '303'

echo ""
if [[ "${FAILURES}" -eq 0 ]]; then
    echo "Ray manager UI checks passed."
    exit 0
fi
echo "${FAILURES} UI check(s) failed." >&2
exit 1
