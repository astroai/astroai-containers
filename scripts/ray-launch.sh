#!/usr/bin/env bash
# Launch a Ray manager session via canfar, then print Dashboard-oriented next steps.
# Does not grow the custom FastAPI UI — stock Ray Dashboard is the user-facing surface.
set -euo pipefail

IMAGE="${RAY_MANAGER_IMAGE:-images.canfar.net/astroai/ray-manager:latest}"
NAME="${RAY_MANAGER_NAME:-ray-manager}"
CORES="${RAY_MANAGER_CORES:-2}"
RAM="${RAY_MANAGER_RAM:-8}"
GPUS="${RAY_MANAGER_GPUS:-0}"

if ! command -v canfar >/dev/null 2>&1; then
  echo "canfar not found. Install the OpenCADC client and run: canfar auth login" >&2
  exit 1
fi

extra=()
if [[ "${GPUS}" != "0" ]]; then
  extra+=(--gpus "${GPUS}")
fi

echo "Creating contributed session: ${IMAGE}"
canfar create contributed "${IMAGE}" --name "${NAME}" --cores "${CORES}" --ram "${RAM}" "${extra[@]}"

cat <<'EOF'

Next steps:
  1. Open the session connect URL from `canfar ps`.
  2. Use the stock Ray Dashboard at .../dashboard/ (trailing slash).
  3. Attach workers with the manager API or documented canfar headless flow
     (see docs/RAY.md). Prefer Dashboard + scripts over the frozen control UI.
  4. From a driver notebook/project: ray.init(address="auto") or Ray Jobs.

Optional laptop helper:
EOF
