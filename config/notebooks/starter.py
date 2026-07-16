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
# 🚀 AstroAI starter (marimo)

Welcome. Marimo notebooks are plain **`.py` files** — easy to git.

<div
  style="
    border-left: 4px solid #3d9cf0; background: rgba(61,156,240,0.08);
    padding: 0.75rem 1rem; border-radius: 0 8px 8px 0; margin: 1rem 0;
  "
>

**Coming from Jupyter?** Here's what's different:

- **No Run button** — Marimo is always running. Edit any cell and everything updates
  automatically, like a spreadsheet.
- **`.py` files, not `.ipynb`** — Plain Python you can `git diff`. No JSON blobs.
- **Reactive execution** — When you change a variable, every cell that reads it
  re-runs. No more "Run All" or stale state.
- **No sidebar file browser** — Use the **Session Files** cell below to browse
  `/scratch`, `/arc`, `/srcdir`. Or `File > Open` (Cmd/Ctrl+O).
- **No built-in terminal** — Open a **webterm** session tab for CLI: `git push`,
  `canfar login`, `vcp`, `astroai-lab doctor`.

</div>

### Quick rules

1. Keep notebooks under `TMP_SRC_DIR/notebooks` (this directory).
2. Put big files on `/scratch` or `/arc/projects` — never fill `/arc/home` with caches.
3. Before the session ends, push code and copy results to `/arc/projects` or `vos:`.

Help: `astroai-lab guide` · hygiene: `astroai-lab doctor`
"""
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md("### 📂 Session Files")
    return


@app.cell
def _():
    try:
        from canfar_marimo import file_browser

        fb = file_browser()
    except ImportError:
        import marimo as mo

        fb = mo.ui.file_browser(
            initial_path="/scratch",
            restrict_navigation=False,
            label="Browse session storage",
        )
    return (fb,)


@app.cell(hide_code=True)
def _(fb, mo):
    try:
        from canfar_marimo import file_browser_tips as _fb_tips
    except ImportError:

        def _fb_tips():
            return mo.md(
                """
            💡 **Tip:** Navigate to:
            - `/scratch` — fast session SSD for data & caches
            - `/arc/home/<you>` — persistent home (config, credentials)
            - `/arc/projects/<group>` — persistent shared datasets
            - `/srcdir` — session code workspace

            Use the file browser above to explore. Selected files appear here.
            """
            )

    paths = fb.value
    if not paths:
        _fb_tips()
    else:
        selected = "\n".join(f"- `{p}`" for p in paths)
        mo.md(f"**Selected:**\n{selected}")
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md("### ☁️ CANFAR Vault (VOSpace)")
    return


@app.cell
def _():
    try:
        from canfar_marimo import VOSpaceUI

        vs = VOSpaceUI()
    except ImportError:
        vs = None
    if vs is not None:
        vs.render()
    else:
        import marimo as mo

        mo.md(
            """
        ⚠️ `canfar_marimo` module not available (expected inside the Docker image).
        Use `vls` / `vcp` in a **webterm** for VOSpace access.
        """
        )
    return (vs,)


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

    scratch = pathlib.Path(os.environ.get("TMP_SCRATCH_DIR", "").strip() or "/scratch")
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
### 🧰 astroai-lab in marimo

Marimo doesn't have Jupyter-style extensions. Instead, use **astroai-lab**
for project management, AI coding agents, and data workflows — all from a
**webterm** tab running alongside this notebook.

#### Project workflow

```bash
astroai-lab init mylab          # pixi project (recommended)
astroai-lab init mylab --uv      # or uv-based project
astroai-lab clone owner/repo     # clone a GitHub project
astroai-lab clone owner/repo --from-env  # clone + restore saved deps
```

#### Save & persist

```bash
astroai-lab save                 # snapshot env to ~/.astroai/lab/saves/
astroai-lab data sync /scratch/out /arc/projects/mygroup/out
astroai-lab push --yes           # git push + data sync before session ends
```

#### AI coding agents (persist on /arc home)

```bash
astroai-lab agent setup          # MCP + skills — run once per user
astroai-lab agent install kilo    # or goose, claude, opencode, codex
astroai-lab agent update          # refresh after image upgrades
astroai-lab agent models free     # list available models
```

Full command reference: `astroai-lab guide` · [astroai-lab docs](https://github.com/astroai/astroai-lab)
"""
    )
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(
        r"""
### 🤖 Marimo AI Assistant

Marimo has a built-in AI sidebar — chat, code generation, and cell
refactoring. It's pre-configured to use **OpenRouter**, the same provider
as your `astroai-lab` agents.

**To activate:**

1. Set up your agent config once (if you haven't already):
   ```bash
   # In a webterm tab:
   astroai-lab agent setup
   ```
   This stores your OpenRouter API key on `/arc/home` — marimo picks it up
   automatically on your next session.

2. Open the AI sidebar: click the **✨ AI** button in the marimo toolbar,
   or press **Cmd/Ctrl+Shift+E** to refactor the current cell with AI.

3. The sidebar supports:
   - **Chat** — ask questions about your code or data
   - **Agent mode** — let the AI edit cells and run code
   - **Generate with AI** — create new cells from a prompt
   - **Refactor** — select a cell and press Cmd/Ctrl+Shift+E

**Tips:**
- Pass variables to the AI by typing `@variable_name` in the chat
- The AI sees your notebook code automatically — no need to copy-paste
- Models are configurable via `~/.marimo.toml` (seeded on first launch)
"""
    )
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
