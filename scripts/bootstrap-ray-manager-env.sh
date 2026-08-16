#!/bin/bash -e
# Persist ray-manager session overrides to $HOME/.config/canfar/lab/ray-manager.env
# (on CANFAR: /arc/home/<user>/.../.config/canfar/lab/ray-manager.env).
#
# Why a script file: CANFAR Skaha splits the headless session `args` string on
# whitespace, so `bash -c '<multi-word script>'` can never work (probe: the
# args are passed as separate argv tokens). The registry bootstrap uses the
# same script-file pattern for the same reason.
#
# Why env vars: Skaha does pass `-e KEY=VALUE` to headless sessions (the
# registry bootstrap relies on it), but *rejects* `-e` on contributed sessions —
# which is why the manager pod reads this file at startup instead
# (startup-ray-manager.sh sources it with `set -a`).
#
# Env (any subset, each written verbatim as KEY=VALUE):
#   RAY_AUTOSCALING_ENABLED, MIN_WORKERS, MAX_WORKERS, CORES, RAM_GB, GPUS,
#   IDLE_TIMEOUT_MINUTES, and any future RAY_* manager override.
#
# Usage (headless bootstrap session):
#   canfar create --name NAME headless <base-image> \
#       -e RAY_AUTOSCALING_ENABLED=1 -e RAY_AUTOSCALING_MAX_WORKERS=3 ... \
#       -- bash /opt/astroai/bin/bootstrap-ray-manager-env.sh

: "${HOME:?HOME required}"

lab_dir="${HOME}/.config/canfar/lab"
mkdir -p "${lab_dir}"
env_file="${lab_dir}/ray-manager.env"

# ENABLED!=1 (or unset) removes a leftover file so the next contributed
# manager does not inherit autoscaling from a prior test/session.
if [[ "${RAY_AUTOSCALING_ENABLED:-0}" != "1" ]]; then
    rm -f "${env_file}"
    echo "ray-manager.env removed (autoscaler off)"
    exit 0
fi

# Truncate any stale file first, then write every RAY_AUTOSCALING_* var that is
# present in the environment (values are numeric today; keep them free of
# spaces/$ so `set -a; source` in startup-ray-manager.sh parses cleanly).
: > "${env_file}"
env | sed -n 's/^\(RAY_AUTOSCALING_[A-Z_]*\)=\(.*\)$/\1=\2/p' >> "${env_file}"
chmod a+r "${env_file}"

# Fail fast if the -e vars did not arrive (a silent drop would only surface
# much later as a confusing "autoscaler enabled" log FAIL in the manager).
if ! grep -q '^RAY_AUTOSCALING_ENABLED=1$' "${env_file}"; then
    echo "ERROR: RAY_AUTOSCALING_ENABLED missing from environment — -e vars not passed?" >&2
    env | grep '^RAY_AUTOSCALING' || true
    exit 1
fi

echo "ray-manager.env persisted:"
cat "${env_file}"
