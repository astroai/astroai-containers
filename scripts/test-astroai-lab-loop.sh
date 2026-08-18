#!/bin/bash -e
# astroai cold-start → save → resume loop inside astroai/base image.
#
# Runs two layouts:
#   bind    — host dir mounted at /srcdir (local docker). WORK stays /srcdir.
#   overlay — /srcdir is the image overlay, /scratch is a volume (CANFAR).
#             WORK relocates to /scratch/src. This is the production path;
#             bind-only tests never exercise it.
#
# Usage:
#   test-astroai-lab-loop.sh            full save/resume cycle (both layouts)
#   test-astroai-lab-loop.sh --smoke     fast smoke: status only (no pixi init)

set -o pipefail

REGISTRY="${REGISTRY:-images.canfar.net}"
OWNER="${OWNER:-astroai}"
TAG="${BUILD_TAG:-local}"
IMAGE="${REGISTRY}/${OWNER}/base:${TAG}"
FAKE_ARC="$(mktemp -d)"
FAKE_SRC="$(mktemp -d)"
FAKE_SCRATCH="$(mktemp -d)"
SMOKE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --smoke) SMOKE=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

cleanup() {
    rm -rf "${FAKE_ARC}" "${FAKE_SRC}" "${FAKE_SCRATCH}"
}
trap cleanup EXIT

echo "astroai save/resume loop (in ${IMAGE})"
[[ "${SMOKE}" -eq 1 ]] && echo "(smoke mode — status only, no pixi init)"
echo "========================================"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "Image missing: ${IMAGE} — run make build/base BUILD_TAG=${TAG}" >&2
    exit 1
fi

mkdir -p "${FAKE_ARC}/testuser"
chmod -R a+rwX "${FAKE_ARC}" "${FAKE_SRC}" "${FAKE_SCRATCH}"

run_loop() {
    local layout="$1"
    local expected_work="$2"
    shift 2
    docker run --rm \
        -u "$(id -u):$(id -g)" \
        -e HOME="${FAKE_ARC}/testuser" \
        -e USER=testuser \
        -e SCRATCH=/scratch \
        "$@" \
        -v "${FAKE_ARC}/testuser:${FAKE_ARC}/testuser" \
        -v "${FAKE_SCRATCH}:/scratch" \
        "${IMAGE}" \
        bash -c '
set -e
# shellcheck disable=SC1091
source /etc/profile.d/astroai.sh
layout="'"${layout}"'"
expected_work="'"${expected_work}"'"
if [[ "${WORK}" != "${expected_work}" ]]; then
    echo "WORK=${WORK} (want ${expected_work})" >&2
    exit 1
fi
cd "${WORK}"

if [[ "'"${SMOKE}"'" -eq 1 ]]; then
    astroai status --json | head -1
    echo "SMOKE_OK_${layout}"
else
    pixi init "loopdemo-${layout}" --no-progress
    cd "loopdemo-${layout}"
    astroai save "loopdemo-${layout}"

    # Fresh work tree (same HOME — simulates new session, same /arc/home)
    rm -rf "${WORK}/loopdemo-${layout}"
    cd "${WORK}"
    astroai resume "loopdemo-${layout}"
    test -f "loopdemo-${layout}/pixi.toml"
    astroai status --json | head -1
    echo "LOOP_OK_${layout}"
fi
'
}

# Bind-mounted /srcdir is a different device from / → WORK stays /srcdir.
BIND_OUT="$(run_loop bind /srcdir -e WORK=/srcdir -v "${FAKE_SRC}:/srcdir" 2>&1)" || true
echo "${BIND_OUT}"
echo ""

# No /srcdir mount: overlay + scratch volume → WORK=/scratch/src.
OVERLAY_OUT="$(run_loop overlay /scratch/src 2>&1)" || true
echo "${OVERLAY_OUT}"

ok=1
if [[ "${SMOKE}" -eq 1 ]]; then
    printf '%s\n' "${BIND_OUT}" | grep -q SMOKE_OK_bind || ok=0
    printf '%s\n' "${OVERLAY_OUT}" | grep -q SMOKE_OK_overlay || ok=0
    if [[ "${ok}" -eq 1 ]]; then
        echo "astroai smoke test passed (bind + overlay)."
        exit 0
    fi
    echo "astroai smoke test failed." >&2
    exit 1
fi

printf '%s\n' "${BIND_OUT}" | grep -q LOOP_OK_bind || ok=0
printf '%s\n' "${OVERLAY_OUT}" | grep -q LOOP_OK_overlay || ok=0
if [[ "${ok}" -eq 1 ]]; then
    echo "astroai loop test passed (bind + overlay)."
    exit 0
fi

echo "astroai loop test failed." >&2
exit 1
