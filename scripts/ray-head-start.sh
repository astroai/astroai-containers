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
spill_root="${TMP_SCRATCH_DIR:-/scratch}/ray/${cluster_id}"
mkdir -p "${spill_root}"
export RAY_spill_dir="${spill_root}"

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
    --include-dashboard=false \
    --disable-usage-stats

echo "Ray head ready: ${RAY_NODE_IP_ADDRESS}:${RAY_HEAD_PORT}"
