#!/bin/bash -e
# astroai-lab cold-start → save → resume loop inside astroai/base image.
#
# Usage:
#   test-astroai-lab-loop.sh            full save/resume cycle
#   test-astroai-lab-loop.sh --smoke     fast smoke: doctor only (no pixi init)

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

echo "astroai-lab save/resume loop (in ${IMAGE})"
[[ "${SMOKE}" -eq 1 ]] && echo "(smoke mode — doctor only, no pixi init)"
echo "========================================"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "Image missing: ${IMAGE} — run make build/base BUILD_TAG=${TAG}" >&2
    exit 1
fi

mkdir -p "${FAKE_ARC}/testuser"
chmod -R a+rwX "${FAKE_ARC}" "${FAKE_SRC}" "${FAKE_SCRATCH}"

OUT="$(docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME="${FAKE_ARC}/testuser" \
    -e USER=testuser \
    -e ASTROAI_LAB_WORK_DIR=/srcdir \
    -e ASTROAI_LAB_SCRATCH_DIR=/scratch \
    -v "${FAKE_ARC}/testuser:${FAKE_ARC}/testuser" \
    -v "${FAKE_SRC}:/srcdir" \
    -v "${FAKE_SCRATCH}:/scratch" \
    "${IMAGE}" \
    bash -lc '
set -e
source /etc/profile.d/astroai.sh

if [[ "'"${SMOKE}"'" -eq 1 ]]; then
    astroai-lab doctor --json | head -1
    echo SMOKE_OK
else
    cd /srcdir
    pixi init loopdemo --no-progress
    cd loopdemo
    astroai-lab env save loopdemo

    # Fresh work tree (same HOME — simulates new session, same /arc/home)
    rm -rf /srcdir/loopdemo
    cd /srcdir
    astroai-lab env resume loopdemo
    test -f loopdemo/pixi.toml
    astroai-lab doctor --json | head -1
    echo LOOP_OK
fi
' 2>&1)"

echo "${OUT}"

if [[ "${SMOKE}" -eq 1 ]]; then
    if printf '%s\n' "${OUT}" | grep -q SMOKE_OK; then
        echo "astroai-lab smoke test passed."
        exit 0
    fi
    echo "astroai-lab smoke test failed." >&2
    exit 1
fi

if printf '%s\n' "${OUT}" | grep -q LOOP_OK; then
    echo "astroai-lab loop test passed."
    exit 0
fi

echo "astroai-lab loop test failed." >&2
exit 1
