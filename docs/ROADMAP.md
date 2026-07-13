# AstroAI Containers roadmap

CANFAR session images under `images.canfar.net/astroai/*`. Same audience as
`astroai-lab`: students and researchers, notebook-first and project-first.

## Principles

- **Hard rename:** this repo is `astroai-containers` (local/git name). Harbor
  project stays `astroai`.
- **Home hygiene:** session profile + notebook kernel config always redirect
  package caches off `/arc/home` onto `/scratch`.
- **Lean Debian slim base** (`python:X-slim`); CUDA via project/notebook env on
  GPU nodes — not baked into the image.
- **No OpenCADC platform changes** as part of this program; image-side workarounds
  when Jupyter CMD is overridden.
- **Ray:** keep head/worker images and stock Ray Dashboard; freeze/retire custom
  FastAPI manager UI maintenance.

## Image matrix

`python` → `base` → `{webterm,vscode,notebook,marimo}` plus
`ray-base` → `{ray-manager,ray-worker}` (manager may slim to launch+dashboard proxy).

## Phases

0. Architecture freeze (this doc)
1. Wire renamed `astroai-lab` wheel + `/etc/astroai-lab` profiles
2. Enforce cache redirects in profile/notebook even without login shell
3. Starter notebooks + student-first USAGE
4. Slim Ray docs/scripts around stock Dashboard
5. Optional org migration notes

## Non-goals

- Thin wrappers around `canfar` or `vcp`/`vls` (use those tools directly).

Custom Ray console product; science-platform PRs unless unblockable; fat science OS.
