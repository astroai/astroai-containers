# Session user guide

How to use **AstroAI** session images on the
[CANFAR Science Platform](https://www.opencadc.org/canfar/).

This file ships inside images as `/opt/astroai/USAGE.md`.

| You want… | Read |
|-----------|------|
| This page | First session, storage, Ray, troubleshooting |
| `astroai-lab` command detail | [astroai-lab USAGE](https://github.com/astroai/astroai-lab/blob/main/docs/USAGE.md) · `astroai-lab guide` |
| Ray operators | [RAY.md](RAY.md) |
| Platform CLI | [opencadc.github.io/canfar](https://opencadc.github.io/canfar/) |

## Scientist card

1. Portal → launch **webterm**, **vscode**, **notebook**, **marimo**, **openresearch**, or **ray-manager**.
2. Inside: `astroai-lab` · `astroai-lab guide` · `less /opt/astroai/USAGE.md`
3. Work under `/srcdir` (code) and `/scratch` (data/caches).
4. Persist to `/arc/home` or `/arc/projects` before the session ends (`save` / `data sync` / `push`).
5. Hourly backup: `/srcdir` → `~/.astroai/lab/backups/<session>/` (`astroai-lab backup status`).

```bash
canfar login
canfar create --name myterm contributed images.canfar.net/astroai/webterm:26.07
canfar open <session-id>
```

---

## Storage (remember scratch)

| Tier | Path | Lifetime | Shared across sessions? |
|------|------|----------|-------------------------|
| Work | `/srcdir` (`TMP_SRC_DIR`) | Session | No |
| Scratch | `/scratch` (`TMP_SCRATCH_DIR`) | Session | **No** — other sessions cannot see it |
| Home | `/arc/home/<you>` | Persistent | **Yes** |
| Projects | `/arc/projects/<group>` | Persistent | **Yes** (group ACLs) |

`/scratch` is fast and private to **this** session. Use `/arc/projects/…` (or home) when another session needs the same files live; move with `astroai-lab data sync` / `data stage`.

```bash
astroai-lab paths
astroai-lab data stage /arc/projects/mygroup/raw
astroai-lab data sync /scratch/out /arc/projects/mygroup/out
```

---

## Ray (first-class)

Launch **ray-manager** from the portal (or CLI), open Connect URL, create a cluster from the UI. Workers are headless images the manager starts for you.

```bash
canfar create --name raymgr contributed images.canfar.net/astroai/ray-manager:26.07
astroai-lab ray guide    # cheat sheet (inside any AstroAI session)
astroai-lab ray status   # when inside a manager session
```

Dashboard: `connectURL/dashboard/`. Full detail: [RAY.md](RAY.md). Prefer manager memory **≥8 GiB**.

Put env saves on `/arc` (`~/.astroai/lab/saves/` or `/arc/projects/<group>/env-saves/`). Slim workers can resume with `ASTROAI_LAB_RESUME=<name>` (optional) before joining — see RAY.md.

---

## Everyday `astroai-lab`

```bash
astroai-lab init mylab          # or clone owner/repo
astroai-lab save / resume / push --yes
astroai-lab agent setup         # once (opt-in at startup too: ASTROAI_LAB_AGENT_SETUP=1)
astroai-lab agent install claude
astroai-lab kernel ensure       # notebook
astroai-lab notebook starter
astroai-lab doctor
```

Compilers and editors are in interactive images; put CUDA/ML stacks in your pixi/uv project locks.

---

## Session notes

| Image | Notes |
|-------|-------|
| `webterm` | ttyd + tmux on `:5000` |
| `vscode` | OpenVSCode on `:5000` |
| `marimo` | Reactive `.py` notebooks; starter seeded once under `/srcdir/notebooks` |
| `notebook` | JupyterLab `:8888`. Stock Skaha may run platform Jupyter CMD — AstroAI `startup-notebook.sh` only with a platform override ([OPERATORS.md](OPERATORS.md)) |
| `openresearch` | Autoresearch UI (`orx`) on `:5000` |
| `ray-manager` | Cluster UI + Ray head; see Ray section |

CADC clients (`cadcget`, `vls`, …) are on PATH from `/opt/astroai/venv/cadc`.

---

## Diagnostics / troubleshooting

```bash
astroai-lab doctor --json
astroai-lab status --json
```

| Symptom | Action |
|---------|--------|
| Other session missing `/scratch` files | Expected — scratch is session-private; use `/arc/projects` or `data sync` |
| Lost files after session end | Check `~/.astroai/lab/backups/` or sync to `/arc` next time |
| Home quota full | `astroai-lab clean home --all-safe --dry-run` |
| Session stuck **Pending** | `canfar ps` / events; contributed quota ≈3; headless Pending is often a Skaha flake ([OPERATORS](OPERATORS.md#platform-notes-headless-pending)) |

---

## Related

- [astroai-lab](https://github.com/astroai/astroai-lab) — CLI detail
- [astroai-workload](https://github.com/astroai/astroai-workload) — Ray Jobs from Python
- [OPERATORS.md](OPERATORS.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [RAY.md](RAY.md)
