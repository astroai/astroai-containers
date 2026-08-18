#!/bin/bash -e
# Start Ray head with fixed ports; head schedules zero CPUs by default.

set -o pipefail

RAY_BIN="${RAY_BIN:-/opt/astroai/venv/ray/bin/ray}"

RAY_HEAD_PORT="${RAY_HEAD_PORT:-6379}"
RAY_NODE_MANAGER_PORT="${RAY_NODE_MANAGER_PORT:-6380}"
RAY_OBJECT_MANAGER_PORT="${RAY_OBJECT_MANAGER_PORT:-6381}"
RAY_RUNTIME_ENV_AGENT_PORT="${RAY_RUNTIME_ENV_AGENT_PORT:-6382}"
RAY_DASHBOARD_AGENT_GRPC_PORT="${RAY_DASHBOARD_AGENT_GRPC_PORT:-6383}"
RAY_MIN_WORKER_PORT="${RAY_MIN_WORKER_PORT:-15000}"
RAY_MAX_WORKER_PORT="${RAY_MAX_WORKER_PORT:-15199}"
RAY_DASHBOARD_PORT="${RAY_DASHBOARD_PORT:-8265}"

if [[ -z "${RAY_NODE_IP_ADDRESS:-}" ]]; then
    RAY_NODE_IP_ADDRESS="$(hostname -i | awk '{print $1}')"
fi
export RAY_NODE_IP_ADDRESS

cluster_id="${RAY_CLUSTER_ID:-local}"
spill_root="${SCRATCH:-/scratch}/ray/${cluster_id}"
mkdir -p "${spill_root}"
export RAY_spill_dir="${spill_root}"

# Ray-native autoscaling: when enabled, write the CANFAR node-provider config
# and hand it to `ray start --head` so Ray's own autoscaler launches/destroys
# ray-worker sessions on demand (see `astroai autoscaler`).
autoscaling_args=()
if [[ "${RAY_AUTOSCALING_ENABLED:-0}" == "1" ]]; then
    autoscaling_cfg="${RAY_AUTOSCALING_CONFIG:-${spill_root}/autoscaling.yaml}"
    astroai_cli="${ASTROAI_BIN:-/opt/astroai/venv/ray/bin/astroai}"
    if [[ ! -x "${astroai_cli}" ]]; then
        echo "Warning: RAY_AUTOSCALING_ENABLED=1 but ${astroai_cli} missing — skipping autoscaling config" >&2
    else
        # Explicit idle-timeout knob (otherwise defaults to env or 5m).
        idle_args=()
        if [[ -n "${RAY_AUTOSCALING_IDLE_TIMEOUT_MINUTES:-}" ]]; then
            idle_args=(--idle-timeout-minutes "${RAY_AUTOSCALING_IDLE_TIMEOUT_MINUTES}")
        fi
        "${astroai_cli}" autoscaler write-config \
            --path "${autoscaling_cfg}" \
            --cluster-name "${cluster_id}" \
            --workers "${RAY_AUTOSCALING_MIN_WORKERS:-0}" \
            --max-workers "${RAY_AUTOSCALING_MAX_WORKERS:-8}" \
            --cores "${RAY_AUTOSCALING_CORES:-1}" \
            --ram-gb "${RAY_AUTOSCALING_RAM_GB:-4}" \
            --gpus "${RAY_AUTOSCALING_GPUS:-0}" \
            --ray-head-port "${RAY_HEAD_PORT:-6379}" \
            --ray-version "${RAY_VERSION_EXPECTED:-}" \
            --heartbeat-path "${RAY_MANAGER_HEARTBEAT_PATH:-}" \
            --spill-dir "${spill_root}" \
            "${idle_args[@]}"
        autoscaling_args=(--autoscaling-config="${autoscaling_cfg}")
        echo "Ray autoscaler enabled: ${autoscaling_cfg} (max ${RAY_AUTOSCALING_MAX_WORKERS:-8} workers)"
    fi
fi

echo "Starting Ray head on ${RAY_NODE_IP_ADDRESS}:${RAY_HEAD_PORT} (cluster ${cluster_id})"

"${RAY_BIN}" start --head \
    --num-cpus="${RAY_HEAD_CPUS:-0}" \
    --node-ip-address="${RAY_NODE_IP_ADDRESS}" \
    --port="${RAY_HEAD_PORT}" \
    --node-manager-port="${RAY_NODE_MANAGER_PORT}" \
    --object-manager-port="${RAY_OBJECT_MANAGER_PORT}" \
    --runtime-env-agent-port="${RAY_RUNTIME_ENV_AGENT_PORT}" \
    --dashboard-agent-grpc-port="${RAY_DASHBOARD_AGENT_GRPC_PORT}" \
    --dashboard-host=127.0.0.1 \
    --dashboard-port="${RAY_DASHBOARD_PORT}" \
    --min-worker-port="${RAY_MIN_WORKER_PORT}" \
    --max-worker-port="${RAY_MAX_WORKER_PORT}" \
    --include-dashboard=true \
    "${autoscaling_args[@]}" \
    --disable-usage-stats

echo "Ray head ready: ${RAY_NODE_IP_ADDRESS}:${RAY_HEAD_PORT}"
echo "Ray Dashboard (local only): http://127.0.0.1:${RAY_DASHBOARD_PORT}/ — proxied at /dashboard/"
