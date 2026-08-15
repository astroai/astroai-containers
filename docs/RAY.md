# Distributed Ray on AstroAI (CANFAR)

User-owned Ray clusters: a **contributed `ray-manager`** session launches
**headless `ray-worker`** sessions over pod networking. Images are published as
`images.canfar.net/astroai/ray-manager:<tag>` and
`images.canfar.net/astroai/ray-worker:<tag>`.

```mermaid
flowchart TB
  User[You] --> Portal["Science Portal / canfar create"]
  Portal --> Mgr["ray-manager :5000"]
  Mgr --> Pref[Network preflight]
  Pref --> W1[ray-worker]
  Pref --> W2[ray-worker]
  Mgr --> Dash["/dashboard/ → Ray Dashboard :8265"]
  Mgr --> Jobs["ASTROAI_RAY_JOBS_ADDRESS → Jobs API"]
  Jobs --> WL["astroai-workload RayExecutor"]
```

## Prefer

| Path | Why |
|------|-----|
| Stock **Ray Dashboard** at `connectURL/dashboard/` | Jobs, actors, nodes, logs |
| Manager control panel at `/` | Auth, preflight, create/stop cluster |
| AstroAI hub → **Start batch compute** | Ensures manager + workers + orx wiring (idempotent) |
| **`astroai-workload run`** (on PATH in ray-manager) | Scripted Jobs submit / status / logs |
| One `ray-worker` image | Request `gpus=N` per worker; CPU and GPU share the image |


The FastAPI control panel is feature-frozen for stability (`ray/manager/FROZEN.md`).
ML/CUDA stacks live in user pixi/uv projects. Spill/temp need **`/scratch`** on
every node. Persist cluster state under `/arc/home/<user>/` or
`/arc/projects/<group>/` — not the `/arc` mount root.

## Images

| Image | Skaha type | Portal | Parent |
|-------|------------|--------|--------|
| `ray-manager` | Contributed | Register — users launch this | Fat `base` (compilers + shell tools) |
| `ray-worker` | Headless | Manager launches workers | Slim `ray-base` (from `python`) |
| `ray-base` | Build-only | — | Minimal apt + `astroai-lab` + Ray |

Workers join with the image Ray venv. Env snapshots stay on `/arc`
(`astroai-lab save` / `resume` in an interactive session). `/scratch` is
**per-pod** — not shared with the manager or other sessions; put shared data
on `/arc`.

## Build and test

```bash
make build-ray BUILD_TAG=26.08
make test-ray
make push-ray TAG=26.08
make test-canfar-ray TAG=26.08
make test-canfar-ray-gpu TAG=26.08
```

Ray layers use the **same bake `TAG` as `base`**.

For Jobs / Dashboard on CANFAR, start the manager with **≥8 GiB** memory.

If headless probes hang Pending, see
[OPERATORS.md — platform notes](OPERATORS.md#platform-notes-headless-pending)
or set `CANFAR_RAY_SKIP_PREFLIGHT=1` for UI-only checks.

## Authentication

From any AstroAI session (webterm/vscode):

```bash
canfar login
canfar create --name raymgr contributed images.canfar.net/astroai/ray-manager:26.08
```

Credentials persist as `~/.canfar/config.yaml` (and optionally
`~/.ssl/cadcproxy.pem`) on `/arc/home`. The manager reuses that volume to launch
workers via the `canfar` Python client.

For maintainer headless pulls when required:

```bash
canfar config set registry.url https://images.canfar.net
canfar config set registry.username <harbor-user>
canfar config set registry.secret <harbor-cli-secret>
```

## Network preflight

Preflight starts a headless probe and checks **worker→manager** TCP on Ray ports
(6379–6381). Manager→worker samples against the probe pod are not used (the probe
never listens on Ray ports).

| Outcome | Meaning |
|---------|---------|
| Probe stays **Pending** | Headless scheduling issue — [science-platform#1124](https://github.com/opencadc/science-platform/issues/1124) |
| `worker→manager` checks fail | Often **wrong Skaha server** in `~/.canfar` on `/arc/home/<user>` (e.g. manager on staging, `active.server=canfar` → workers on production). Also possible: true session-to-session network isolation |
| Worker log: cannot reach head `:6379` | Same class — confirm worker and manager are on the same server (`canfar auth show` / session lists) before assuming platform isolation |

**Server pin:** `/arc/home/<user>/.canfar` must use the same `active.server` as the cluster where the manager runs. Registry bootstrap can set `ACTIVE_SERVER=staging` (or `canfar`). Manager sessions also accept `CANFAR_ACTIVE_SERVER` / `ACTIVE_SERVER` env to re-pin on startup.

Preflight results are bound to the manager pod IP. Creating a cluster after moving
to a new manager session requires a fresh preflight.

## Web UI

Contributed **`ray-manager`** serves port **5000** under
`/session/contrib/<session-id>/` (prefix stripped before the container).

| Surface | Purpose |
|---------|---------|
| `/` | Auth, preflight, create/stop cluster, worker table |
| `/dashboard/` | Official Ray Dashboard (proxy to `127.0.0.1:8265`) |
| `/actions/*` | Form POSTs for cluster lifecycle |
| `/api/v1/*` | JSON automation |

Always open the Dashboard **with a trailing slash**, using the session connect
URL (`…/dashboard/`), not a bare workloads hostname.

On the manager pod, Jobs clients use **`ASTROAI_RAY_JOBS_ADDRESS`**
(`http://127.0.0.1:8265`).

### OpenResearch (`orx`) on Ray

AstroAI’s `openresearch` image defaults compute to CANFAR batch (Ray Jobs under
the hood). Preferred path:

```bash
# From openresearch / openworker (or any AstroAI session with canfar auth):
# AstroAI hub → Start batch compute
# Then in OpenResearch: run experiments (no --backend needed)
```

Manual:

```bash
export ASTROAI_RAY_JOBS_ADDRESS=http://127.0.0.1:8265   # on the manager
# or connectURL/dashboard from another session
orx exp run <expId> --backend ray
```

CANFAR session create/join stays in the AstroAI hub (`/astroai-agents/`) or
ray-manager — not in upstream OpenResearch’s Compute list.

Local UI smoke: `./scripts/test-ray-ui-local.sh` (part of `make test-ray`).

## Cluster workflow

```mermaid
sequenceDiagram
  participant U as User
  participant M as ray-manager
  participant C as canfar / Skaha
  participant W as ray-workers
  U->>M: Run network preflight
  M->>C: Headless probe
  U->>M: Create cluster N workers
  M->>C: Launch ray-worker sessions
  C->>W: Start workers
  W->>M: Join Ray head
  U->>M: Open /dashboard/ or submit Jobs
  U->>M: Stop cluster
  M->>C: Delete workers
```

1. **Run network preflight**
2. **Create cluster** — worker count, CPU/RAM, GPUs per worker, `min_joined`, partial-start policy
3. **Use Ray** — Dashboard, `ray.init(address="auto")`, or `astroai-workload run train.py --cpus 2 --memory 8GiB`
4. **Stop cluster** — destroys worker sessions

Partial-start policies: `accept_partial`, `fail_and_cleanup`, `continue_waiting`.

State lives at `~/.astroai/ray/clusters/<cluster-id>/state.json` (worker logs archived
beside it). Each manager session defaults `RAY_CLUSTER_ID` to `mgr-<skaha_sessionid>`
so a new manager does not inherit another pod’s `default` state on shared `/arc/home`.
Override `RAY_CLUSTER_ID` for a stable team path under `/arc/projects` if needed.
On manager start, terminal-phase leftovers are destroyed (startup GC); **Reconcile
state** refreshes membership for an active cluster after restart.

## Autoscaling (Ray-native, on demand)

Ray's own autoscaler can launch/destroy `ray-worker` sessions on demand — no
fixed worker count. The manager head starts with
`ray start --head --autoscaling-config=<yaml>` when enabled; a CANFAR
`NodeProvider` (in `astroai-workload`, `ray-as-*` sessions) does the scaling.

Enable it per manager session via a file on `/arc/home` (Skaha rejects `-e`
env on contributed sessions):

```bash
# from a webterm / vscode / openresearch session before launching the manager
mkdir -p ~/.config/canfar/lab
cat > ~/.config/canfar/lab/ray-manager.env <<EOF
RAY_AUTOSCALING_ENABLED=1
RAY_AUTOSCALING_MIN_WORKERS=0
RAY_AUTOSCALING_MAX_WORKERS=8
RAY_AUTOSCALING_CORES=1
RAY_AUTOSCALING_RAM_GB=4
RAY_AUTOSCALING_GPUS=0
RAY_AUTOSCALING_IDLE_TIMEOUT_MINUTES=5
EOF
```

`startup-ray-manager.sh` sources that file (if present) before launching the
head, so `ray-head-start.sh` writes the autoscaling YAML
(`astroai-workload autoscaler write-config`) and passes
`--autoscaling-config` to `ray start --head`. The autoscaler then:

- **scales up**: a job that demands more CPUs than are scheduled triggers
  `ray-as-*` worker sessions (head schedules 0 CPUs by default)
- **scales down**: idle workers are terminated after `idle_timeout_minutes`
  (default 5; env `RAY_AUTOSCALING_IDLE_TIMEOUT_MINUTES`)

Verify end-to-end on CANFAR (manager UI + dynamic scale-up + idle scale-down):

```bash
make test-canfar-ray-autoscale TAG=26.08
```

## Manager API

| Endpoint | Purpose |
|----------|---------|
| `GET /api/v1/auth/status` | Credential check |
| `POST /api/v1/preflight/run` | Network preflight (`?async=1`) |
| `POST /api/v1/cluster/create` | Launch workers (`?async=1`) |
| `POST /api/v1/cluster/stop` | Stop and destroy workers |
| `POST /api/v1/cluster/reconcile` | Refresh state |
| `POST /api/v1/cluster/clean-orphans` | Destroy untracked workers |
| `POST /api/v1/workers/{id}/retry` | Retry a failed worker |
| `GET /api/v1/status` | Full cluster JSON |
| `GET /api/v1/workers/{id}/logs` | Archived worker logs |

## Layout

```
ray/manager/                 FastAPI + cluster lifecycle
ray/worker/                  Worker entrypoint helpers
scripts/test-ray-*.sh        Local and CANFAR tests
examples/ray/                Container smokes
```

## Related

- [USAGE.md](USAGE.md) — general sessions
- [OPERATORS.md](OPERATORS.md) — publish and platform notes
- [astroai-workload](https://github.com/astroai/astroai-workload) — Jobs CLI (`astroai-workload run`) + MNIST example
- Starter notebook in-image: `/opt/astroai/notebooks/ray_train.ipynb`
