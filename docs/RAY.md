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
make test-ray                              # local Docker cluster
make push-ray TAG=26.06
make test-canfar-ray TAG=26.06             # Milestone B on CANFAR (needs canfar auth)
```

Ray layers use the **same bake `TAG` as `base`** — no separate `BASE_TAG` pin.

## CANFAR authentication (Milestone B)

The manager launches workers with the **`canfar` Python client** (`canfar.sessions.Session.create`). Credentials must exist in the manager session:

1. From an AstroAI **webterm** or **vscode** session, run once: `canfar auth login`
2. Config persists under `/arc/home/<you>/.config/canfar/`
3. Launch **ray-manager** — it inherits the same home directory
4. Open the manager UI → **Run network preflight** → **Launch one worker**

Harbor pull for worker images may require maintainer registry credentials via `CANFAR_REGISTRY__*` env vars on the manager session (see [OPERATORS.md](OPERATORS.md)).

## Manager API

| Endpoint | Purpose |
|----------|---------|
| `GET /api/v1/auth/status` | CANFAR credential check |
| `POST /api/v1/preflight/run` | Network preflight (one probe session) |
| `POST /api/v1/workers/launch` | Launch one headless worker |
| `POST /api/v1/workers/destroy-all` | Tear down recorded workers |
| `GET /api/v1/status` | Ray address, workers, preflight |

## Layout in this repo

```
dockerfiles/ray-{base,manager,worker-cpu}/
ray/manager/                # FastAPI app + CANFAR worker control
ray/worker/start-worker.sh
scripts/ray-network-probe.sh
scripts/test-canfar-ray.sh
examples/ray/
```

Full product spec: [ray-build-plan.md](ray-build-plan.md).

## Status

| Milestone | Scope | Status |
|-----------|--------|--------|
| A | Local manager + worker join | Done |
| B | CANFAR auth, preflight, one worker via API | Done (needs `make test-canfar-ray` on platform) |
| C | Multi-worker UI, persistence, stop/recover | Planned |
