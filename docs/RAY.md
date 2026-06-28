# Distributed Ray on CANFAR

User-owned Ray clusters: a **contributed `ray-manager` session** (port 5000) launches **headless `ray-worker-cpu` sessions** over pod networking. Same storage model as other AstroAI images (`/arc`, `/scratch`).

## Images

| Image | Skaha type | Portal |
|-------|------------|--------|
| `ray-manager` | Contributed | Register — users launch this |
| `ray-worker-cpu` | Headless | **Do not register** — manager launches workers |

`ray-base` is build-only (extends `base` with a Python 3.12 Ray venv).

## Build and test

```bash
make build-ray BUILD_TAG=26.06
make test-ray
make push-ray TAG=26.06
```

Ray layers use the **same bake `TAG` as `base`** — no separate `BASE_TAG` pin.

## Layout in this repo

```
dockerfiles/ray-{base,manager,worker-cpu}/
ray/manager/app.py          # manager web UI (Milestone A)
ray/worker/start-worker.sh  # worker entrypoint
scripts/ray-head-start.sh
scripts/startup-ray-manager.sh
scripts/test-ray-local.sh
examples/ray/
```

Full product spec: [ray-build-plan.md](ray-build-plan.md) (when present).

## Status

Milestone A: local manager + worker join works. CANFAR session API integration (launch workers from UI) is Milestone B.
