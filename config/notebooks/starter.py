"""AstroAI starter notebook for marimo sessions.

Keep in sync with astroai-lab/src/astroai_lab/data/notebooks/starter.py
Keep code under TMP_SRC_DIR (this folder). Put large data on /scratch.
"""

import marimo

__generated_with = "0.13.0"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo

    return (mo,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(
        r"""
# AstroAI starter (marimo)

Welcome. Marimo notebooks are plain **`.py` files** — easy to git.

1. Keep notebooks under `TMP_SRC_DIR/notebooks` (this directory).
2. Put big files on `/scratch` or `/arc/projects` — never fill `/arc/home` with caches.
3. Before the session ends, push code and copy results to `/arc/projects` or `vos:`.

Help: `astroai-lab guide` · hygiene: `astroai-lab doctor`
"""
    )
    return


@app.cell
def _():
    import os
    import pathlib
    import subprocess

    # Apply scratch-backed caches even if the session missed profile hooks.
    try:
        out = subprocess.check_output(["astroai-lab", "env", "export"], text=True)
        for line in out.splitlines():
            if line.startswith("export ") and "=" in line:
                body = line[len("export ") :]
                k, _, v = body.partition("=")
                os.environ[k] = v.strip().strip("'\"")
    except Exception as exc:  # noqa: BLE001 — show in notebook, don't crash
        print("env export skipped:", exc)

    scratch = pathlib.Path(os.environ.get("TMP_SCRATCH_DIR", "/scratch"))
    print("scratch writable:", scratch.is_dir() and os.access(scratch, os.W_OK), scratch)
    print("home should stay tiny:", pathlib.Path.home())
    print("xdg_cache:", os.environ.get("XDG_CACHE_HOME"))
    return (os, pathlib, scratch, subprocess)


@app.cell
def _(subprocess):
    try:
        out = subprocess.check_output(["astroai-lab", "doctor", "--json"], text=True)
        import json

        d = json.loads(out)
        print("hygiene_ok=", d.get("hygiene_ok"))
        print("scratch=", d.get("scratch_dir"))
        print("work=", d.get("work_dir"))
    except Exception as exc:  # noqa: BLE001
        print("doctor skipped:", exc)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(
        r"""
## Next steps

- Install packages into a **project** (`astroai-lab init mylab` + pixi/uv), not `$HOME`.
- Or use a short-lived venv under `/scratch` if you must.
- Re-copy this template anytime: `astroai-lab notebook starter marimo`
"""
    )
    return


if __name__ == "__main__":
    app.run()
