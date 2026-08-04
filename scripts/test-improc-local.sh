#!/usr/bin/env bash
# Local smoke for images.canfar.net/astroai/improc:<tag>
set -euo pipefail

TAG="${1:-${BUILD_TAG:-local}}"
IMAGE="${REGISTRY:-images.canfar.net}/${OWNER:-astroai}/improc:${TAG}"

echo "Testing ${IMAGE}"

run() {
    docker run --rm --entrypoint bash "${IMAGE}" -lc "$1"
}

run 'source /etc/profile.d/astroai.sh 2>/dev/null || true
source /etc/profile.d/improc.sh
set -euo pipefail
missing=0
for c in \
  source-extractor sextractor swarp psfex scamp stiff missfits \
  fitscut fitspng fitsverify weightwatcher montage \
  galfit imfit pqrs topcat stilts fits2idia imcore \
  astconvertt astnoisechisel h5dump maximask maxitrack; do
  if ! command -v "$c" >/dev/null; then
    echo "FAIL: missing $c"
    missing=$((missing + 1))
  else
    echo "PASS: $c -> $(command -v "$c")"
  fi
done
if ! command -v sourcextractor++ >/dev/null && ! command -v sourcextractor >/dev/null; then
  echo "FAIL: sourcextractor++"
  missing=$((missing + 1))
else
  echo "PASS: sourcextractor++"
fi
scamp_v=$(scamp -v 2>&1 | head -1 || true)
echo "$scamp_v" | grep -q '2\.15' && echo "PASS: $scamp_v" || { echo "FAIL: SCAMP not 2.15 ($scamp_v)"; missing=$((missing + 1)); }
/opt/astroai/venv/improc/bin/python -c "import ccdproc, photutils, galsim, piff, astroscrappy, lacosmic, sfft, zogyp, healpy, healsparse, mocpy, hpgeom; print(\"PASS: improc python imports\")"
/opt/astroai/venv/maximask/bin/python -c "import tensorflow; import maximask_and_maxitrack; print(\"PASS: maximask venv\")"
if /opt/astroai/venv/improc/bin/python -c "import tensorflow" 2>/dev/null; then
  echo "FAIL: tensorflow leaked into improc venv"
  missing=$((missing + 1))
else
  echo "PASS: tensorflow isolated from improc venv"
fi
exit "$missing"
'

echo "improc local smoke passed for ${IMAGE}"
