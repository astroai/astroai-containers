"""Jupyter server config: force scratch-backed package caches.

Loaded via jupyter --config or JUPYTER_CONFIG_PATH. Avoids relying on login shells
when the platform overrides the notebook entrypoint.
"""
import os
import subprocess


def _apply() -> None:
    try:
        out = subprocess.check_output(
            ["astroai-lab", "env", "export"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("export "):
            continue
        body = line[len("export ") :]
        if "=" not in body:
            continue
        key, _, val = body.partition("=")
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1]
        os.environ[key] = val


_apply()
