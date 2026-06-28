"""CANFAR Ray Manager web app — Milestone B: CANFAR worker launch."""

from __future__ import annotations

import os
import subprocess
from dataclasses import asdict
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from pydantic import BaseModel, Field

from canfar_ops import CanfarOps
from preflight import run_preflight
from ray_cluster import count_live_nodes, list_ray_nodes, ray_address, ray_running
from settings import ManagerSettings, manager_pod_ip
from state_store import StateStore
from workers import destroy_all_workers, destroy_worker, launch_worker

app = FastAPI(title="CANFAR Ray Manager")

_ray_head_proc: subprocess.Popen[str] | None = None
_settings = ManagerSettings.from_env()
_store = StateStore(_settings.cluster_id)
_canfar = CanfarOps()


def _heartbeat_path() -> Path:
    return _store.dir / "manager-heartbeat"


def _touch_heartbeat() -> None:
    path = _heartbeat_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()


class WorkerLaunchRequest(BaseModel):
    cores: int = Field(default=1, ge=1, le=32)
    ram_gb: int = Field(default=4, ge=1, le=128)
    gpus: int = Field(default=0, ge=0, le=8)
    require_preflight: bool = True


@app.on_event("startup")
def startup() -> None:
    global _ray_head_proc
    _store.ensure_dir()
    if ray_running():
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
    if not ray_running():
        return JSONResponse({"ready": False, "reason": "ray head unavailable"}, status_code=503)
    return JSONResponse({"ready": True, "ray_address": ray_address()})


@app.get("/api/v1/auth/status")
def api_auth_status() -> JSONResponse:
    status = _canfar.auth_status()
    return JSONResponse(asdict(status))


@app.get("/api/v1/status")
def api_status() -> JSONResponse:
    _touch_heartbeat()
    state = _store.load()
    return JSONResponse(
        {
            "ray_address": ray_address(),
            "manager_ip": manager_pod_ip(),
            "ray_version": _settings.ray_version,
            "cluster_id": _settings.cluster_id,
            "heartbeat_path": str(_heartbeat_path()),
            "ray_running": ray_running(),
            "ray_nodes_alive": count_live_nodes(),
            "worker_image": _settings.worker_image,
            "preflight": state.preflight if state else None,
            "workers": [asdict(w) for w in state.workers] if state else [],
        }
    )


@app.post("/api/v1/preflight/run")
def api_preflight_run() -> JSONResponse:
    _touch_heartbeat()
    report = run_preflight(_settings, _canfar, _store)
    code = 200 if report.passed else 503
    return JSONResponse(report.as_dict(), status_code=code)


@app.post("/api/v1/workers/launch")
def api_workers_launch(body: WorkerLaunchRequest) -> JSONResponse:
    _touch_heartbeat()
    try:
        result = launch_worker(
            settings=_settings,
            canfar=_canfar,
            store=_store,
            heartbeat_path=str(_heartbeat_path()),
            cores=body.cores,
            ram_gb=body.ram_gb,
            gpus=body.gpus,
            require_preflight=body.require_preflight,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    payload: dict[str, Any] = {"worker": asdict(result.worker)}
    if result.logs_excerpt:
        payload["logs_excerpt"] = result.logs_excerpt
    code = 200 if result.worker.ray_joined else 503
    return JSONResponse(payload, status_code=code)


@app.delete("/api/v1/workers/{session_id}")
def api_workers_destroy(session_id: str) -> JSONResponse:
    return JSONResponse(destroy_worker(canfar=_canfar, store=_store, session_id=session_id))


@app.post("/api/v1/workers/destroy-all")
def api_workers_destroy_all() -> JSONResponse:
    results = destroy_all_workers(canfar=_canfar, store=_store)
    return JSONResponse({"destroyed": results})


@app.get("/api/v1/ray/nodes")
def api_ray_nodes() -> JSONResponse:
    return JSONResponse({"nodes": list_ray_nodes(), "alive": count_live_nodes()})


@app.post("/actions/preflight")
def action_preflight() -> RedirectResponse:
    run_preflight(_settings, _canfar, _store)
    return RedirectResponse("/", status_code=303)


@app.post("/actions/launch-worker")
def action_launch_worker() -> RedirectResponse:
    try:
        launch_worker(
            settings=_settings,
            canfar=_canfar,
            store=_store,
            heartbeat_path=str(_heartbeat_path()),
        )
    except RuntimeError:
        pass
    return RedirectResponse("/", status_code=303)


@app.post("/actions/destroy-all")
def action_destroy_all() -> RedirectResponse:
    destroy_all_workers(canfar=_canfar, store=_store)
    return RedirectResponse("/", status_code=303)


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    _touch_heartbeat()
    auth = _canfar.auth_status()
    state = _store.load()
    preflight = (state.preflight if state else None) or {}
    workers_html = ""
    if state and state.workers:
        rows = "".join(
            f"<tr><td>{w.name}</td><td><code>{w.session_id}</code></td>"
            f"<td>{w.phase}</td><td>{'yes' if w.ray_joined else 'no'}</td></tr>"
            for w in state.workers
        )
        workers_html = f"<table border='1' cellpadding='4'><tr><th>Name</th><th>Session</th><th>Phase</th><th>Ray</th></tr>{rows}</table>"

    auth_line = (
        f"<span style='color:green'>Authenticated ({auth.idp})</span>"
        if auth.authenticated
        else f"<span style='color:red'>Not authenticated</span> — run <code>canfar auth login</code> in a terminal session, then refresh."
    )
    pf_line = (
        f"<span style='color:green'>Passed</span> (worker IP {preflight.get('worker_ip', '?')})"
        if preflight.get("passed")
        else "<span style='color:orange'>Not run or failed</span>"
    )

    return f"""<!DOCTYPE html>
<html><head><title>CANFAR Ray Manager</title></head>
<body>
  <h1>CANFAR Ray Manager</h1>
  <p>Ray: <code>{ray_address()}</code> · cluster <code>{_settings.cluster_id}</code></p>
  <p>CANFAR auth: {auth_line}</p>
  <p>Network preflight: {pf_line}</p>
  <p>Live Ray nodes: {count_live_nodes()}</p>
  <h2>Actions</h2>
  <form method="post" action="/actions/preflight"><button type="submit">Run network preflight</button></form>
  <form method="post" action="/actions/launch-worker"><button type="submit">Launch one worker</button></form>
  <form method="post" action="/actions/destroy-all"><button type="submit">Destroy all workers</button></form>
  <h2>Workers</h2>
  {workers_html or "<p>No workers recorded.</p>"}
  <p><a href="/api/v1/status">JSON status</a> · <a href="/healthz">healthz</a></p>
</body></html>"""
