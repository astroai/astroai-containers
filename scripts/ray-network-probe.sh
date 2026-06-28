#!/bin/bash -e
# Headless network probe — tests worker pod -> manager TCP connectivity.
# Used by ray-manager preflight (Milestone B). Exits 0 on PASS.

set -o pipefail

PROBE_MANAGER_IP="${PROBE_MANAGER_IP:?PROBE_MANAGER_IP required}"
PROBE_PORTS="${PROBE_PORTS:-6379,6380,6381}"

worker_ip="$(hostname -i | awk '{print $1}')"
echo "WORKER_IP=${worker_ip}"

fail=0
IFS=',' read -ra ports <<< "${PROBE_PORTS}"
for port in "${ports[@]}"; do
    port="${port// /}"
    [[ -n "${port}" ]] || continue
    if timeout 10 bash -c "echo >/dev/tcp/${PROBE_MANAGER_IP}/${port}" 2>/dev/null; then
        echo "PROBE worker->manager:${port} PASS"
    else
        echo "PROBE worker->manager:${port} FAIL"
        fail=1
    fi
done

if (( fail )); then
    echo "PROBE_RESULT FAIL"
    exit 1
fi

echo "PROBE_RESULT PASS"
exit 0
