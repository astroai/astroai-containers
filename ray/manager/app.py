"""Minimal CANFAR Ray Manager web app (Milestone A)."""

from __future__ import annotations

import os
import socket
import subprocess
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse

app = FastAPI(title="CANFAR Ray Manager")

_ray_head_proc: subprocess.Popen[str] | None = None


def _cluster_state_dir() -> Path:
    home = Path(os.environ.get("HOME", "/tmp"))
    return home / ".canfar-ray" / "clusters" / os.environ.get("RAY_CLUSTER_ID", "default")


def _heartbeat_path() -> Path:
    return _cluster_state_dir() / "manager-heartbeat"


def _touch_heartbeat() -> None:
    path = _heartbeat_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()


def _ray_address() -> str:
    ip = os.environ.get("RAY_NODE_IP_ADDRESS", "").strip()
    if not ip:
        ip = socket.gethostbyname(socket.gethostname())
    port = os.environ.get("RAY_HEAD_PORT", "6379")
    return f"{ip}:{port}"


def _ray_running() -> bool:
    ray_bin = os.environ.get("RAY_BIN", "/opt/astroai/venv/ray/bin/ray")
    try:
        out = subprocess.run(
            [ray_bin, "status"],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
        return "Started" in out.stdout or "node_" in out.stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return False


@app.on_event("startup")
def startup() -> None:
    global _ray_head_proc
    if _ray_running():
        return
    _ray_head_proc = subprocess.Popen(
        ["/opt/astroai/bin/ray-head-start.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


@app.get("/healthz")
def healthz() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/readyz")
def readyz() -> JSONResponse:
    scratch = Path(os.environ.get("TMP_SCRATCH_DIR", "/scratch"))
    if not scratch.is_dir() or not os.access(scratch, os.W_OK):
        return JSONResponse({"ready": False, "reason": "scratch unavailable"}, status_code=503)
    if not _ray_running():
        return JSONResponse({"ready": False, "reason": "ray head unavailable"}, status_code=503)
    return JSONResponse({"ready": True, "ray_address": _ray_address()})


@app.get("/api/v1/status")
def api_status() -> JSONResponse:
    _touch_heartbeat()
    return JSONResponse(
        {
            "ray_address": _ray_address(),
            "ray_version": os.environ.get("RAY_VERSION_EXPECTED", "2.43.0"),
            "cluster_id": os.environ.get("RAY_CLUSTER_ID", "default"),
            "heartbeat_path": str(_heartbeat_path()),
            "ray_running": _ray_running(),
        }
    )


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    _touch_heartbeat()
    return f"""<!DOCTYPE html>
<html><head><title>CANFAR Ray Manager</title></head>
<body>
  <h1>CANFAR Ray Manager</h1>
  <p>Ray address: <code>{_ray_address()}</code></p>
  <p>Cluster: <code>{os.environ.get("RAY_CLUSTER_ID", "default")}</code></p>
  <p><a href="/api/v1/status">API status</a> · <a href="/healthz">healthz</a></p>
</body></html>"""
