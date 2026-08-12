# Session user guide

How to use **AstroAI** session images on the
[CANFAR Science Platform](https://www.opencadc.org/canfar/).

This file ships inside images as `/opt/astroai/USAGE.md`.

| You want… | Read |
|-----------|------|
| This page | First session, storage, Ray, troubleshooting |
| `astroai-lab` command detail | [astroai-lab USAGE](https://github.com/astroai/astroai-lab/blob/main/docs/USAGE.md) · `astroai-lab help` |
| Ray operators | [RAY.md](RAY.md) |
| Platform CLI | [opencadc.github.io/canfar](https://opencadc.github.io/canfar/) |

## Scientist card

1. Portal → launch **openresearch** or **openworker** as your day-to-day home base (or webterm/vscode/notebook/marimo/ray-manager as needed).
2. Inside: `astroai-lab` · `astroai-lab help` · `less /opt/astroai/USAGE.md`
3. Work under `/srcdir` (code) and `/scratch` (data/caches).
4. Persist to `/arc/home` or `/arc/projects` before the session ends (`astroai-lab save` / `git push`).
5. Env snapshots live in `~/.astroai/lab/saves/` on `/arc/home` — resume them in the next session with `astroai-lab resume NAME`.

### Home base: AstroAI hub (openresearch / openworker)

1. Launch **`openresearch`** or **`openworker`** with tag `26.07` / `latest`.
2. Open the connect URL, then either:
   - click the blue **AstroAI** chip (top-right), or
   - append `/astroai-agents/` (e.g. `…/session/contrib/<id>/astroai-agents/`).
3. In the hub (one screen):
   - **Start batch compute** — ensures ray-manager + workers and wires OpenResearch (when on openresearch)
   - **Setup agents** — optional config seed on shared `/arc/home` (`astroai-lab agent install …` for CLIs)
   - Status shows CANFAR auth, manager Running/Pending, wire state, Jobs URL
   - **← Back** returns to the main UI
4. Run experiments in OpenResearch — default compute is already CANFAR batch. Put shared I/O on `/arc` (`/scratch` is per-pod only).
5. Power users: `astroai-lab agent …` in webterm; cluster ops on ray-manager.

```bash
canfar login   # once, from webterm — persists under /arc/home
canfar create --name orx contributed images.canfar.net/astroai/openresearch:26.07
canfar open <session-id>
# Hub: …/astroai-agents/ → Start batch compute
```

---

## Storage (remember scratch)

| Tier | Path | Lifetime | Shared across sessions? |
|------|------|----------|-------------------------|
| Work | `/srcdir` (`WORK`) | Session | No |
| Scratch | `/scratch` (`SCRATCH`) | Session | **No** — other sessions cannot see it |
| Home | `/arc/home/<you>` | Persistent | **Yes** |
| Projects | `/arc/projects/<group>` | Persistent | **Yes** (group ACLs) |

`/scratch` is fast and private to **this** session. Use `/arc/projects/…` (or home) when another session needs the same files live; move with `canfar data` (platform archive I/O).

**Home quota %:** CANFAR homes use CephFS directory quotas (`ceph.quota.max_bytes`). `astroai-lab status` prefers those xattrs; `ceph.dir.rbytes` can lag a few seconds after large writes — that is Ceph MDS accounting, not a frozen UI cache. Refresh with `astroai-lab status`.

```bash
astroai-lab status
canfar data stage /arc/projects/mygroup/raw
canfar data sync /scratch/out /arc/projects/mygroup/out
```

---

## Ray (first-class)

**Preferred:** from openresearch/openworker, AstroAI hub → **Start batch compute**.
That launches **ray-manager**, starts workers, and wires OpenResearch.

Manual path: launch **ray-manager** from the portal (or CLI), open Connect URL,
create a cluster from the UI. Workers are headless images the manager starts for you.

```bash
# AstroAI hub → Start batch compute
# or:
canfar create --name astroai-compute --cpu 2 --memory 8 contributed images.canfar.net/astroai/ray-manager:26.07
# after workers join:
astroai-workload run train.py --cpus 2 --memory 8GiB
```

Dashboard: `connectURL/dashboard/`. Full detail: [RAY.md](RAY.md). Prefer manager memory **≥8 GiB**.

### OpenResearch → Ray (`orx exp run --backend ray`)

`openresearch` defaults compute to CANFAR batch (Ray Jobs under the hood). Preferred path:

1. AstroAI hub → **Start batch compute** — ensures manager + workers and wires Settings.
2. Set agent API keys in agent configs / OpenResearch settings (not in the hub).
3. Run experiments in OpenResearch (no `--backend` needed once defaulted).

Manual fallback: Settings → Compute → Ray with the manager Jobs URL (`connectURL/dashboard`). Cluster lifecycle stays on the hub / ray-manager — not a CANFAR card in upstream OpenResearch.

Put env saves on `/arc` (`~/.astroai/lab/saves/` or `/arc/projects/<group>/env-saves/`). Slim workers can resume with `ASTROAI_LAB_RESUME=<name>` (optional) before joining — see RAY.md.

---

## Everyday `astroai-lab`

```bash
astroai-lab init mylab          # or clone owner/repo
astroai-lab save / resume --yes
astroai-lab agent setup         # once (UI sessions auto-run in background; webterm opt-in)
astroai-lab agent install claude
# Or open /astroai-agents/ in openresearch / openworker for Start batch compute
astroai-lab kernel ensure       # notebook
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
| `openresearch` | Autoresearch UI (`orx`) on `:5000`; lean AstroAI hub at `/astroai-agents/` (batch compute + agent setup) |
| `openworker` | OpenWorker browser UI + local agent server (no Tauri); lean AstroAI hub at `/astroai-agents/` |
| `ray-manager` | Cluster UI + Ray head; see Ray section |
| `improc` | Headless FITS/HDF5 image-processing CLIs — see [Image processing (`improc`)](#image-processing-improc) |
| `improc-webterm` | Same tools + browser terminal (ttyd/tmux) |
| `improc-notebook` | Same tools + JupyterLab (default kernel = science venv) |

CADC clients (`cadcget`, `vls`, …) are on PATH from `/opt/astroai/venv/cadc`.

---

## Image processing (`improc`)

| Image | Use |
|-------|-----|
| `improc` | Headless batch |
| `improc-webterm` | Interactive CLI (Contributed, :5000) |
| `improc-notebook` | JupyterLab (Notebook, :8888); kernel **Python 3 (improc)** has healpy/galsim/… |

PATH includes `/opt/astroai/venv/improc/bin` and sourcextractor++.

| Area | Tools |
|------|--------|
| Detection / catalog | `source-extractor` (`sextractor`), sourcextractor++, `scamp` (2.15 from sid), IRAF |
| Cosmic rays / clean | `astroscrappy`, `lacosmic`, `ccdproc` helpers |
| Contaminant masks | `maximask`, `maxitrack` (own TF venv — not mixed with science Python) |
| DIA (difference imaging) | **`sfft`**, `zogyp` (modern; not HOTPANTS) |
| Mask / weight | `weightwatcher`, `missfits`, gnuastro `astnoisechisel` / `astsegment` |
| PSF | `psfex`, `piff`, gnuastro `astscript-psf-*`, `galfit`, `imfit` |
| Mosaic / coadd | `swarp`, `montage`, `theli`, `reproject` |
| Spherical / HEALPix | `healpy`, `healsparse`, `astropy-healpix`, `mocpy`, `hpgeom` |
| Pretty pictures | `stiff`, `fitspng`, `fitscut`, `astconvertt`, ImageMagick |
| FITS / HDF5 / tables | cfitsio utils, `fitsverify`, `topcat`/`stilts`, `pqrs`, `h5dump` |

Science Python lives in `/opt/astroai/venv/improc` (on PATH). MaxiMask uses a
**separate** `/opt/astroai/venv/maximask` so TensorFlow cannot conflict with
GalSim/numba; only the `maximask` / `maxitrack` wrappers are on PATH.

---

## Diagnostics / troubleshooting

```bash
astroai-lab status --json
```

| Symptom | Action |
|---------|--------|
| Other session missing `/scratch` files | Expected — scratch is session-private; use `/arc/projects` or `canfar data` |
| Lost files after session end | Persist to `/arc` next time (`astroai-lab save` / `git push` / `canfar data`) |
| Home quota full | `astroai-lab status` (quota %) — prune caches under `/scratch` manually |
| Session stuck **Pending** | `canfar ps` / events; contributed quota ≈3; headless Pending is often a Skaha flake ([OPERATORS](OPERATORS.md#platform-notes-headless-pending)) |

---

## Related

- [astroai-lab](https://github.com/astroai/astroai-lab) — CLI detail
- [astroai-workload](https://github.com/astroai/astroai-workload) — Ray Jobs CLI (`astroai-workload run`) on ray-manager
- [OPERATORS.md](OPERATORS.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [RAY.md](RAY.md)
