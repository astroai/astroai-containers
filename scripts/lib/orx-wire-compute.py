#!/usr/bin/env python3
"""Best-effort: default OpenResearch compute to CANFAR batch (Ray under the hood).

Called from openresearch startup. Never fails the session.
- If a manager Jobs URL is already known, wire orx settings.
- Else leave a defaultBackend=ray so the first `ray ensure` / hub Start is enough.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def main() -> int:
    try:
        # Prefer lab helper when available (newer images).
        from astroai_lab.cli.ray_ensure import (  # type: ignore
            canfar_sessions,
            find_manager_sessions,
            jobs_url_from_connect,
            read_persisted_connect_url,
            wire_orx,
            _session_connect_url,
            _session_status,
        )
    except Exception:
        # Minimal fallback without lab helpers.
        cfg = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "openresearch"
        cfg.mkdir(parents=True, exist_ok=True)
        settings_path = cfg / "settings.json"
        settings: dict = {}
        if settings_path.is_file():
            try:
                settings = json.loads(settings_path.read_text(encoding="utf-8"))
            except Exception:
                settings = {}
        if not settings.get("defaultBackend"):
            settings["defaultBackend"] = "ray"
            settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
        return 0

    jobs = (os.environ.get("ASTROAI_RAY_JOBS_ADDRESS") or "").strip().rstrip("/")
    if not jobs:
        connect = read_persisted_connect_url()
        if not connect:
            try:
                managers = find_manager_sessions(canfar_sessions(timeout=15))
                running = [
                    m
                    for m in managers
                    if _session_status(m) == "Running" and _session_connect_url(m)
                ]
                if running:
                    connect = _session_connect_url(running[0])
            except Exception:
                connect = None
        if connect:
            jobs = jobs_url_from_connect(connect)

    if jobs:
        wire_orx(jobs_address=jobs, make_default=True)
    else:
        # Still prefer ray as default so agents don't pick HF by accident.
        cfg = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "openresearch"
        cfg.mkdir(parents=True, exist_ok=True)
        settings_path = cfg / "settings.json"
        settings = {}
        if settings_path.is_file():
            try:
                settings = json.loads(settings_path.read_text(encoding="utf-8"))
            except Exception:
                settings = {}
        if not settings.get("defaultBackend"):
            settings["defaultBackend"] = "ray"
            settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"orx-wire-compute: {exc}\n")
        raise SystemExit(0)
