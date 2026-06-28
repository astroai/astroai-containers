"""Ray head membership helpers."""

from __future__ import annotations

import os
import subprocess
from typing import Any


def ray_address() -> str:
    from settings import manager_pod_ip

    port = os.environ.get("RAY_HEAD_PORT", "6379")
    return f"{manager_pod_ip()}:{port}"


def ray_running() -> bool:
    ray_bin = os.environ.get("RAY_BIN", "/opt/astroai/venv/ray/bin/ray")
    try:
        out = subprocess.run(
            [ray_bin, "status"],
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        )
        return "Started" in out.stdout or "node_" in out.stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return False


def list_ray_nodes() -> list[dict[str, Any]]:
    python_bin = os.environ.get("PYTHON_BIN", "/opt/astroai/venv/ray/bin/python")
    script = """
import json
import ray

ray.init(address=__import__("os").environ.get("RAY_ADDRESS"), ignore_reinit_error=True)
print(json.dumps(ray.nodes()))
"""
    env = os.environ.copy()
    env["RAY_ADDRESS"] = ray_address()
    try:
        out = subprocess.run(
            [python_bin, "-c", script],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
            env=env,
        )
        import json

        return json.loads(out.stdout.strip() or "[]")
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []


def count_live_nodes() -> int:
    nodes = list_ray_nodes()
    return sum(1 for node in nodes if node.get("Alive"))


def wait_for_node_count(
    *,
    minimum: int,
    timeout_seconds: int,
    poll_seconds: int = 5,
) -> int:
    import time

    deadline = time.monotonic() + timeout_seconds
    count = count_live_nodes()
    while time.monotonic() < deadline:
        count = count_live_nodes()
        if count >= minimum:
            return count
        time.sleep(poll_seconds)
    return count
