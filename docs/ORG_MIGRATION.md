# Org migration & CANFAR adoption notes

See also `astroai-lab` [`docs/ORG_MIGRATION.md`](https://github.com/sfabbro/canfar-lab/blob/main/docs/ORG_MIGRATION.md)
(or the sibling checkout `../astroai-lab/docs/ORG_MIGRATION.md`).

## This repository

- **Name:** `astroai-containers` (formerly `containers`).
- **Harbor:** unchanged — `images.canfar.net/astroai/<image>:<tag>`.
- **Session CLI:** `astroai-lab` (baked into `base`).

## Human transfer checklist

1. Push/rename remote to `astroai/astroai-containers` when the org is ready.
2. Keep Harbor project public for anonymous pulls.
3. Re-register Science Portal image entries only if tags/URLs change (usually they do not).

## Adoption message for CANFAR ops (copy/paste)

AstroAI provides lean Debian-slim session images (webterm, vscode, notebook, marimo)
plus Ray head/worker images. Users manage in-session work with `astroai-lab`
(notebook-first or pixi/uv). Package caches are forced onto `/scratch` to protect
the 10 GB `/arc/home` quota. Ray users should use the stock Ray Dashboard; the
optional FastAPI control panel is frozen. No science-platform Helm changes are
required for the default AstroAI workflow.
