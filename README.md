> **Repository:** `astroai-containers` (formerly `containers`). Harbor images remain `images.canfar.net/astroai/*`. Session CLI is `astroai-lab`.

# AstroAI Containers

Lean CANFAR session images for astronomy and ML development. Published to `images.canfar.net/astroai/`.

Licensed under [BSD-2-Clause](LICENSE).

## Sessions

| Image | Use for | Skaha type |
|-------|---------|------------|
| `webterm` | Browser terminal (ttyd + tmux) | Contributed |
| `vscode` | Browser IDE (OpenVSCode Server) | Contributed |
| `notebook` | JupyterLab | **Notebook** |
| `marimo` | Reactive notebooks | Contributed |
| `base` | Headless parent (CI, batch, not a portal session) | — |
| `ray-manager` | Distributed Ray control UI ([docs/RAY.md](docs/RAY.md)) | Contributed |
| `ray-worker` | Ray worker CPU or GPU (launched by manager, not portal) | Headless |

## Documentation

| Doc | Audience |
|-----|----------|
| [docs/USAGE.md](docs/USAGE.md) | **Session users** — AstroAI images, storage, GPU, CADC, workflows |
| [astroai-lab USAGE](https://github.com/sfabbro/canfar-lab/blob/main/docs/USAGE.md) | **`astroai-lab` CLI** — commands, env, agents |
| [docs/RAY.md](docs/RAY.md) | **Ray clusters** — manager + worker images (prototype) |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | **Developers** — clone, build, test, open PRs |
| [docs/OPERATORS.md](docs/OPERATORS.md) | **AstroAI maintainers** — build, push, register images on CANFAR |

In-session: `astroai-lab guide` · `less /opt/astroai/USAGE.md`

## Build

Requires Docker with buildx. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full dev loop.

```bash
make build-all          # full stack
make build/vscode       # one image (+ parents)
docker buildx bake      # direct bake
make clean              # remove local images.canfar.net/astroai/*
make clean-all          # clean + prune buildx cache
```

## Local test

```bash
make build/webterm
./scripts/test-local.sh webterm 5000

make build/notebook
./scripts/test-local.sh notebook 8888
```

## Push to Harbor

Maintainers only — see [OPERATORS.md](docs/OPERATORS.md). The `astroai` Harbor project is **public** (anonymous pull); push still needs `docker login`.

```bash
make build/vscode
make push/vscode TAG=26.06
```

## Layout

```
dockerfiles/
  python/       # 3.13-slim + uv + pixi
  base/         # headless: git, monitoring, CLI, astroai-lab
  webterm/      # contributed: ttyd + tmux
  vscode/       # contributed: OpenVSCode Server
  notebook/     # notebook: JupyterLab + ipykernel (port 8888)
  marimo/       # contributed: marimo
  ray-base/     # build-only: base + Ray 3.12 venv
  ray-manager/  # contributed: Ray head + UI :5000
  ray-worker/
ray/            # manager app + worker scripts
examples/ray/
scripts/
  startup-*.sh  # session + ray-manager entrypoints
  test-ray-*.sh
  lib/          # profile helpers (env paths, UI, skaha proxy)
docs/
  USAGE.md      # user-facing session guide
  RAY.md        # distributed Ray (manager + workers)
  CONTRIBUTING.md
  OPERATORS.md
```

## Design

- **Same images for CPU and GPU** — pick the node in the portal; CUDA libs via pixi/uv in the project.
- **Minimal bake stack** — `python` → `base` → four session images; Ray adds `ray-base` → `ray-manager` / `ray-worker` (same `TAG` as `base`); heavy software via pixi or [CVMFS on CANFAR nodes](https://opencadc.github.io/canfar/platform/cvmfs/) ([source](https://github.com/opencadc/canfar/blob/main/docs/platform/cvmfs.md)).
- **Quick feedback loops** — **`TMP_SRC_DIR`** (`/srcdir`) for code, **`TMP_SCRATCH_DIR`** (`/scratch`) for data and package caches, `astroai-lab init` / `astroai-lab resume`. Keep `/arc/home` tiny (auth, MCP, lockfile saves only).
- **Skaha session types** — Contributed (5000) for webterm/vscode/marimo; Notebook (8888) for notebook.
- **Authentication** — Jupyter, VS Code, Marimo, and ttyd run without built-in auth. CANFAR Skaha terminates TLS and enforces portal login. Do not expose these images on the public internet without an authenticating reverse proxy.

## Contributing

Pull requests welcome — see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).
