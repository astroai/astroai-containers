# Custom Ray manager UI — FROZEN

The FastAPI control panel under `ray/manager/ui.py` is **frozen**.

- Prefer the stock **Ray Dashboard** at `/dashboard/` for day-to-day cluster inspection.
- Prefer `scripts/ray-launch.sh` + `canfar` for creating head/workers without growing UI features.
- Do not add new UI pages, themes, or workflows here.
- Bugfixes that keep existing E2E green are OK; new product work is not.

See [docs/RAY.md](../docs/RAY.md).
