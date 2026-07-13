# Org migration & CANFAR adoption notes

See also [`astroai/astroai-lab` docs/ORG_MIGRATION.md](https://github.com/astroai/astroai-lab/blob/main/docs/ORG_MIGRATION.md)
(or the sibling checkout `../astroai-lab/docs/ORG_MIGRATION.md`).

## This repository

- **GitHub:** [`astroai/astroai-containers`](https://github.com/astroai/astroai-containers) (formerly `containers`).
- **Harbor:** unchanged — `images.canfar.net/astroai/<image>:<tag>`.
- **Session CLI:** `astroai-lab` from [`astroai/astroai-lab`](https://github.com/astroai/astroai-lab) (baked into `base`).

## Sibling remotes

| Repo | URL |
|------|-----|
| Lab | https://github.com/astroai/astroai-lab |
| Workload | https://github.com/astroai/astroai-workload |
| Containers | https://github.com/astroai/astroai-containers |

## Adoption message for CANFAR ops (copy/paste)

AstroAI provides lean Debian-slim session images (webterm, vscode, notebook, marimo)
plus Ray head/worker images. Users manage in-session work with `astroai-lab`
(notebook-first or pixi/uv). Package caches are forced onto `/scratch` to protect
the 10 GB `/arc/home` quota. Ray users should use the stock Ray Dashboard; the
optional FastAPI control panel is frozen. No science-platform Helm changes are
required for the default AstroAI workflow.
