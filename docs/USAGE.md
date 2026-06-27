# Usage guide

How to work in AstroAI sessions on the [CANFAR Science Platform](https://www.canfar.net/science-portal). Platform docs are built from [opencadc/canfar](https://github.com/opencadc/canfar) at [opencadc.github.io/canfar](https://opencadc.github.io/canfar/).

| Doc | Audience |
|-----|----------|
| **USAGE.md** (this file) | Session users — quickstart, storage, GPU, tools |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Developers changing this repo |
| [OPERATORS.md](OPERATORS.md) | AstroAI maintainers — build, push, register images on CANFAR |
| [README.md](../README.md) | Repo overview and build commands |

## First five minutes (quick feedback loop)

```bash
astroai-status                    # gpu, disk, project, git — sanity check
gh auth login                     # one-time GitHub setup (token or browser)
astroai-new mylab                 # pixi project under TMP_SRC_DIR (default /srcdir)
cd mylab                          # common-init already cd'd to TMP_SRC_DIR
pixi add numpy astropy
pixi run python -c "import astropy; print(astropy.__version__)"
git init && git add -A && git commit -m "start"
gh repo create mylab --private --source=. --push   # or push to an existing remote
astroai-env-save mylab            # lockfile manifest on /arc (~KB)
```

Next session:

```bash
astroai-env-resume mylab
cd "${TMP_SRC_DIR}/mylab"         # or: cd mylab after login (cwd is TMP_SRC_DIR)
pixi run python analysis.py
git push                          # before closing — TMP_SRC_DIR is ephemeral
```

**Commands on every session:** `astroai-help` · `astroai-status` · `less /opt/astroai/USAGE.md`

**On this page:** [Session types](#session-types) · [Storage](#storage) · [Team workspaces](#team-workspaces) · [CADC clients](#cadc--canfar-clients) · [CVMFS](#alliance-software-cvmfs) · [Workflows](#typical-workflow) · [Commands](#command-reference) · [Caches](#caches-and-temp-files) · [AI agents](#ai-coding-tools) · [Session notes](#session-specific-notes) · [Troubleshooting](#troubleshooting)

## Session types

| Image | Best for | CANFAR session type |
|-------|----------|---------------------|
| `webterm` | Shell-first work, tmux, quick scripts | **Contributed** |
| `vscode` | Multi-file projects, extensions, integrated terminal | **Contributed** |
| `notebook` | JupyterLab exploration and teaching notebooks | **Notebook** |
| `marimo` | Reactive notebooks and small dashboards | **Contributed** |
| `full` | Headless + Node.js LTS (`npm` CLIs, CI-style jobs) | — (not a portal session) |

`base` is a headless parent image — not launched directly from the portal. The **`full`** image is for headless jobs or local Docker runs when you want system Node without `astroai-install node`; interactive work still uses `webterm`, `vscode`, `notebook`, or `marimo`.

Launch the image you need from the Science Portal. **CPU and GPU use the same image** — when you need a GPU, select a **GPU node** at launch. The platform attaches the driver; your project supplies CUDA libraries via pixi or uv.

## Storage

CANFAR sessions mount **two ephemeral directories** on the container disk (Kubernetes `emptyDir`, wiped when the session ends). AstroAI keeps **code** and **data/caches** separate:

| Variable / path | Purpose | Lifetime |
|-----------------|---------|----------|
| **`TMP_SRC_DIR`** (default **`/srcdir`**) | Git repos, pixi/uv projects, `.astroai/workspaces` bundles | **Ephemeral** |
| **`TMP_SCRATCH_DIR`** (default **`/scratch`**) | Staged datasets, training outputs, uv/pip/npm/pixi download caches, `TMPDIR` | **Ephemeral** |
| `/arc/home/$USER` | SSH keys, dotfiles, env save manifests, AI tools in `~/.local`, HF/torch caches | Persistent |
| `/arc/projects/<group>/` | Shared group data (ACL-controlled) | Persistent |
| `/cvmfs/` | DRAC / Alliance software (read-only) | Persistent on nodes; lazy-mounted |

On Contributed session startup, `common-init` **`cd`s to `TMP_SRC_DIR`**. Run `astroai-status` to see resolved paths (`work:` and `scratch:`).

**Override at launch** (Skaha `extraEnv`, headless `canfar create --env`, or `docker run -e`):

```bash
TMP_SRC_DIR=/custom/code
TMP_SCRATCH_DIR=/custom/scratch
```

Legacy alias: `ASTROAI_WORK_ROOT` still selects the code root when `TMP_SRC_DIR` is unset.

Create projects in the code root:

```bash
astroai-new myproject && cd myproject
# equivalent: mkdir -p "${TMP_SRC_DIR}/myproject" && cd "${TMP_SRC_DIR}/myproject"
```

**Back up code with git before closing.** Both `/srcdir` and `/scratch` are wiped when the session ends.

## Team workspaces

`/arc/projects/<group>/` is CANFAR's persistent, ACL-controlled shared storage. Use it for team datasets, shared environment manifests, and collaborative results.

### Create a workspace

```bash
astroai-project-init mygroup --members alice,bob
```

Creates `/arc/projects/mygroup/` with `data/`, `results/`, and `env-saves/` subdirectories. The `--members` flag sets POSIX ACLs (`setfacl -R -m u:user:rwx`) so teammates can read and write. Re-run without `--members` to add members later.

```bash
astroai-project-init mygroup --members carol   # add another member
```

### Move data between tiers

**Stage data from persistent storage to `TMP_SCRATCH_DIR` for fast I/O** (default `/scratch`):

```bash
astroai-data-stage /arc/projects/mygroup/data/catalog.fits
# copies catalog.fits → ${TMP_SCRATCH_DIR}/catalog.fits

astroai-data-stage /arc/projects/mygroup/survey/  "${TMP_SCRATCH_DIR}/survey/"
# copies survey/ contents → ${TMP_SCRATCH_DIR}/survey/
```

**Sync results from scratch back to persistent storage:**

```bash
astroai-data-sync "${TMP_SCRATCH_DIR}/results/"  /arc/projects/mygroup/results/
```

Both use `rsync -avh --progress` with source size display. `astroai-data-stage` asks before overwriting an existing target. `astroai-data-sync` warns if the source is not under `TMP_SCRATCH_DIR`.

### Team environment saves

Share environment manifests so the whole team can reproduce the same stack:

```bash
cd "${TMP_SRC_DIR}/myproject"
astroai-env-save myproject --to /arc/projects/mygroup/env-saves/myproject
```

Discover team saves:

```bash
astroai-env-list --team          # team saves only
astroai-env-list --all           # personal + team
```

Resume a team save:

```bash
astroai-env-resume myproject --from /arc/projects/mygroup/env-saves/myproject
```

### Typical team workflow

```bash
# Session start
astroai-env-resume myproject --from /arc/projects/mygroup/env-saves/myproject
astroai-data-stage /arc/projects/mygroup/data/catalog.fits

# Work under TMP_SRC_DIR; stage data on TMP_SCRATCH_DIR
cd "${TMP_SRC_DIR}/myproject"
pixi run python analysis.py

# Share results (from scratch)
astroai-data-sync "${TMP_SCRATCH_DIR}/results/"  /arc/projects/mygroup/results/

# Close
astroai-session-archive
```

## CADC / CANFAR clients

The OpenCADC Python clients are **pre-installed** in every session (venv at `/opt/astroai/venv/cadc`, on PATH):

| Package | CLI examples | Purpose |
|---------|--------------|---------|
| `cadcdata` | `cadcget`, `cadcput`, `cadcinfo`, `cadcremove` | CADC archive data access |
| `cadctap` | `cadc-tap` | TAP catalog queries |
| `vos` | `vcp`, `vls`, `vos-config` | VOSpace storage |
| `canfar` | `canfar auth login`, `canfar sessions …` | Science Platform API/CLI |

**Authentication** (pick what your workflow needs):

```bash
canfar auth login              # Science Platform (recommended for sessions/API)
cadc-get-cert -u $USER         # X509 cert for vos / cadcdata (netrc also works)
```

**Examples:**

```bash
cadcget cadc:CFHT/806045o.fits
cadc-tap "SELECT * FROM caom2.Observation WHERE collection='CFHT' LIMIT 5"
vls vos:/
canfar sessions list
```

For **project Python code** (`import cadcdata`, etc.), add packages to your pixi/uv project under **`TMP_SRC_DIR`** so versions match your analysis stack:

```bash
pixi add cadcdata cadctap vos canfar
# or: uv add cadcdata cadctap vos canfar
```

Platform CLIs stay available for ad-hoc use; project envs keep reproducible imports.

## Alliance software (CVMFS)

CANFAR worker nodes mount **CVMFS** — a read-only software tree maintained by the [Digital Research Alliance of Canada](https://docs.alliancecan.ca/) (DRAC / Alliance; same stacks as Fir, Nibi, and other national clusters). It is available in **all** AstroAI sessions and complements the lean image: the container brings `uv`, `pixi`, and basics; CVMFS brings thousands of pre-built packages without bloating the image.

**CANFAR guide** (from [opencadc/canfar](https://github.com/opencadc/canfar/blob/main/docs/platform/cvmfs.md)): [Software Repositories (CVMFS)](https://opencadc.github.io/canfar/platform/cvmfs/)

```bash
# 1. Enable the environment-module system
source /cvmfs/soft.computecanada.ca/config/profile/bash.sh

# 2. Search and load (examples)
module avail python
module load python/3.11
module avail cfitsio
module load cfitsio
```

`ls /cvmfs` alone may look empty — repositories mount **lazily** when you access a known path. Always start from `/cvmfs/soft.computecanada.ca/`.

| Approach | Good for |
|----------|----------|
| **pixi / uv** under **`TMP_SRC_DIR`** | Project-pinned Python stacks, GPU PyTorch, fast iteration, git-tracked deps |
| **CVMFS `module load`** | Alliance-built compilers, libraries, and apps already in the national stack |
| **Image (`apt` / system `uv`)** | Session baseline — JupyterLab, marimo, CADC clients, shell tooling |

You cannot `pip install` or write into `/cvmfs`. Module changes last for the current shell unless you add the `source` and `module load` lines to `~/.bashrc` on `/arc`.

**More from Alliance docs:** [Using modules](https://docs.alliancecan.ca/wiki/Using_modules) · [Available software](https://docs.alliancecan.ca/wiki/Available_software)

## Typical workflow

**GitHub CLI (`gh`) is pre-installed** — prefer it over raw `git clone` URLs for GitHub repos. SSH keys still live in `~/.ssh` on `/arc`; `gh auth login` handles HTTPS tokens.

### Quick start with `astroai-clone`

Clones and installs deps in one step — detects pixi or uv automatically:

```bash
gh auth login
astroai-clone you/project
cd "${TMP_SRC_DIR}/project"       # or cd project if already in TMP_SRC_DIR
pixi run python analysis.py
```

### Manual clone and setup

```bash
# 0. One-time GitHub auth (persisted on /arc)
gh auth login

# 1. Clone or fork
gh repo clone you/project
cd project
# or fork first: gh repo fork owner/upstream --clone

# 2. Install dependencies (into the project — not the system image)
pixi install
# or: uv sync

# 3. Develop and run
pixi run python analysis.py

# 4. Review and share (before closing — TMP_SRC_DIR is ephemeral)
git add -A && git commit -m "session work"
git push                          # existing branch
# or open a PR in one step:
gh pr create --fill
```

### Closing a session

Run `astroai-session-archive` to push code and save your environment in one command:

```bash
astroai-session-archive           # auto-detect project, git push + env save
astroai-session-archive --name my-experiment  # custom save name
astroai-session-archive --force   # non-interactive (used by the exit hook)
```

It prints a summary of what was archived and a reminder that **`TMP_SRC_DIR` is ephemeral**.

**Periodic reminder:** interactive login shells print a yellow nudge about every **2 hours** (session age from `~/.astroai/session-started`), reminding you to `git push` or run `astroai-session-archive` before **`TMP_SRC_DIR`** is wiped.

**Exit hook (Contributed sessions with a login shell):** when you leave an interactive shell inside a git repo, AstroAI runs `astroai-session-archive --force` once per session (marker: `~/.astroai/auto-archived`). That attempts a silent `git push` and env save — still commit first if you want a clean history; the hook warns about uncommitted changes but does not commit for you.

**Common `gh` commands** (after `gh auth login`):

```bash
gh repo list                      # your repos
gh repo view                      # README + metadata for cwd repo
gh issue list
gh issue view 42
gh pr list
gh pr checkout 17                 # check out a PR branch locally
gh pr diff 17
gh pr view 17 --web               # open in browser (if portal allows)
gh release list                   # tags/releases for cwd repo
gh workflow list                  # GitHub Actions in cwd repo
gh run list --limit 5             # recent CI runs
```

### GPU workflow

1. Launch any AstroAI session on a **GPU node** in the portal.
2. Confirm the device: `nvidia-smi` or `nvtop`.
3. Add GPU deps in your project — the image does **not** ship CUDA libraries:

```bash
cd "${TMP_SRC_DIR}/myproject"
pixi add torch cuda-version=12
pixi run python train.py
```

Pixi (or uv/pip) downloads CUDA user libraries into the project environment. No separate GPU image is required.

## Command reference

| Command | Purpose |
|---------|---------|
| `astroai-help` | Full command list (compact; this doc is the long form) |
| `astroai-status` | Session snapshot: user, gpu, git, disk, session age |
| `astroai-new [name]` | `pixi init` new project under **`TMP_SRC_DIR`** (`--uv`, `--no-git`, `--no-gh`, `--astro`) |
| `astroai-env-save [name]` | Save lockfiles + manifest (~KB) |
| `astroai-env-save name --full` | Also pack `.pixi` or `.venv` with zstd (large) |
| `astroai-env-save name --to /arc/projects/group/env-saves/name` | Team-shared save |
| `astroai-env-resume <name>` | Restore to **`TMP_SRC_DIR/<name>`** and rebuild env |
| `astroai-env-resume <name> [path]` | Restore to a custom target directory |
| `astroai-env-resume <name> --from <path>` | Restore from custom save path |
| `astroai-env-list` | List personal saves under `~/.astroai/saves` (`--team`, `--all`) |
| `astroai-workspace-save [name]` | Freeze full project tree for offline batch (`--with-cache`, `--to`) |
| `astroai-workspace-restore <name>` | Restore frozen workspace — no network (`--from`, `--to`) |
| `astroai-kernel-register` | Register pixi/uv/venv project as a Jupyter kernel (notebook sessions) |
| `astroai-home-usage` | Disk breakdown under `$HOME` on `/arc` |
| `astroai-cache-prune --all-safe` | Clear pip/uv/npm/pixi caches (`--pip`, `--uv`, `--npm`, `--pixi`, `--hf`) |
| `astroai-clone <owner/repo> [dir]` | Clone repo under **`TMP_SRC_DIR`** (or custom dir) and install deps |
| `astroai-install <tool>` | Install AI coding tools to `~/.local/bin` (`--list`) |
| `astroai-data-stage <src> [dst]` | Copy data from persistent storage to **`TMP_SCRATCH_DIR`** |
| `astroai-data-sync <src> <dst>` | Copy **`TMP_SCRATCH_DIR`** results back to persistent storage |
| `astroai-project-init <name>` | Create team workspace under `/arc/projects` (`--members`) |
| `astroai-session-archive [--name <name>]` | Git push + env save + summary before closing (`--force`) |
| `astroai-debug` | Full diagnostic report (`--stdout`, `--file <path>`) |

## What is pre-installed (needs root)

The image keeps a small **apt** layer: platform essentials and monitoring tools that are not worth pulling in via pixi for every session. **Compilers, dev headers, and science packages go in your pixi project.**

| Tool | Why in the image |
|------|------------------|
| `git`, `git-lfs`, `openssh-client`, `gh`, `delta` | Clone, push, PRs/issues, readable diffs |
| `rg`, `fd`, `bat`, `tree`, `fzf`, `ctags` | Fast search, find, browse, and jump to definitions |
| `file`, `xxd`, `hexdump` | Inspect file type and binary contents |
| `patch`, `make`, `shellcheck` | Apply diffs, run Makefiles, lint shell scripts |
| `lsof`, `ss`, `host` | Debug open files, sockets, and DNS |
| `ncdu` | Explore disk usage interactively |
| `tldr` | Quick command examples (`tldr git`) |
| `uv`, `pixi` | Per-project Python environments |
| `htop`, `nvtop`, `procps` | CPU/GPU monitoring |
| `zstd`, `xz-utils`, `bzip2`, `pigz`, `zip`, `unzip` | Archives |
| `curl`, `wget`, `jq`, `rsync` | Fetch data, inspect JSON, sync files |
| `less`, `vim-tiny` | Logs and quick edits |
| `acl` | CANFAR `/arc` file permissions |

**Not in the image:** `node`/`npm`, AI agent CLIs (Cursor Agent `agent`, `claude`, `agy`, `opencode`, `codex`, `copilot`, `goose`, `pi`, `codewhale`, `swival`, `freebuff`), `build-essential`, `cmake`, Fortran, CUDA libs, Astropy, PyTorch, etc. Install agents per [AI coding tools](#ai-coding-tools); install Node via [Node.js and npm](#nodejs-and-npm). Many system packages are available via **CVMFS** (`module load`) — see [Alliance software (CVMFS)](#alliance-software-cvmfs).

```bash
pixi add nodejs                                # npm-based CLIs and Lab source extensions
pixi add cmake cxx-compiler fortran-compiler   # only if you compile extensions
pixi add cfitsio                               # instead of libcfitsio-dev
# or: source /cvmfs/.../bash.sh && module load cfitsio
```

## Caches and temp files

Sessions set cache locations in `/etc/profile.d/astroai.sh`. When **`TMP_SCRATCH_DIR`** is writable (default `/scratch` on CANFAR), **package download caches** go there — not under `$HOME`:

| Variable | Default (scratch mounted) | Purpose |
|----------|---------------------------|---------|
| `TMP_SRC_DIR` | `/srcdir` | Code root (see [Storage](#storage)) |
| `TMP_SCRATCH_DIR` | `/scratch` | Data staging + download caches |
| `UV_CACHE_DIR` | `${TMP_SCRATCH_DIR}/.cache-$USER/uv` | uv package cache |
| `PIP_CACHE_DIR` | `${TMP_SCRATCH_DIR}/.cache-$USER/pip` | pip wheel cache |
| `NPM_CONFIG_CACHE` | `${TMP_SCRATCH_DIR}/.cache-$USER/npm` | npm download cache |
| `PIXI_CACHE_DIR` | `${TMP_SCRATCH_DIR}/.cache-$USER/pixi` | pixi package cache |
| `PIXI_HOME` | `~/.pixi` | pixi global config on `/arc` |
| `TMPDIR` | `${TMP_SCRATCH_DIR}/.tmp-$USER` | Compile/temp files on SSD |
| `UV_PYTHON_INSTALL_DIR` | `~/.local/share/uv/python` | uv-managed Python installs (overrides image `/usr/local`) |
| `UV_TOOL_DIR` | `~/.local/share/uv/tools` | uv tool environments |
| `XDG_CACHE_HOME` | `~/.cache` | ML/tool caches on `/arc` |
| `HF_HOME` | `~/.cache/huggingface` | Hugging Face models |
| `TORCH_HOME` | `~/.cache/torch` | PyTorch hub checkpoints |

If scratch is not mounted, uv/pip/npm/pixi caches fall back under **`TMP_SRC_DIR/.cache-$USER/`**.

**Prune stale caches** when `/arc` quota is tight:

```bash
astroai-home-usage
astroai-cache-prune --all-safe
```

Keep **code and git repos on `TMP_SRC_DIR`**; stage **datasets and large outputs on `TMP_SCRATCH_DIR`**; keep **config, manifests, and ML model caches on `/arc`**.

### Offline batch (workspace freeze)

For headless jobs with no network, freeze a full tree (code + `.pixi`/`.venv`, optional caches):

```bash
cd "${TMP_SRC_DIR}/mylab"
astroai-workspace-save mylab --with-cache
# next session or batch job:
astroai-workspace-restore mylab
cd "${TMP_SRC_DIR}/mylab" && pixi run python job.py
```

Bundles live under **`TMP_SRC_DIR/.astroai/workspaces/`** (ephemeral unless you copy them to `/arc` first).

## Save and resume environments

`/arc/home` is **shared CephFS** — keep it small. Active projects belong on **`TMP_SRC_DIR`**; home should hold SSH keys, config, small save **manifests**, and prunable ML caches.

### Lightweight save (recommended)

```bash
cd "${TMP_SRC_DIR}/myproject"
pixi add numpy torch cuda-version=12
astroai-env-save myproject
# -> ~/.astroai/saves/myproject/  (pixi.toml, pixi.lock, manifest.json)
```

Next session:

```bash
astroai-env-resume myproject
cd "${TMP_SRC_DIR}/myproject"
pixi run python train.py
```

Pixi reuses **`PIXI_CACHE_DIR`** on scratch when resolving the lockfile — fast without storing another full env in home.

### Full pack (offline / air-gap)

```bash
astroai-env-save myproject --full
astroai-env-save myproject --full --to /arc/projects/mygroup/env-saves/myproject
```

### What belongs where

| Location | Keep | Avoid |
|----------|------|-------|
| **`TMP_SRC_DIR`** (`/srcdir`) | Repos, active `.pixi`/`.venv` envs | Assuming it persists — `git push` |
| **`TMP_SCRATCH_DIR`** (`/scratch`) | Staged datasets, training outputs, download caches | Assuming it persists — `astroai-data-sync` |
| `~/.astroai/saves/` | Lockfile manifests (small) | `--full` packs unless necessary |
| `~/.cache/` (HF, torch, matplotlib) | OK — prune with `astroai-cache-prune` | Unbounded model caches |
| `~/.local/bin` | AI tools, small user binaries | Large vendored SDKs |
| `/arc/projects/<group>/` | Shared datasets, team env-saves | Personal scratch copies |

**Git remains the primary backup** for code. `astroai-env-save` is for environment reproducibility.

## AI coding tools

The image ships **dev CLIs** that pair well with AI assistants (`gh`, `rg`, `fd`, `bat`, `fzf`, `delta`, `tldr`) but does **not** ship AI agent binaries or Node.js — those change too fast to pin.

**One-command install** (recommended):

```bash
astroai-install node              # Node.js + npm on /arc (once; enables npm CLIs)
astroai-install agent             # Cursor Agent (command is `agent`)
astroai-install --list            # full list + install methods
```

`astroai-install` picks the vendor-recommended path per tool: **curl** scripts, **gh release download** (Codex), **uv tool install** (Swival), or **npm** (Pi, CodeWhale, Freebuff). Binaries land in `~/.local/bin` on `/arc` (persistent).

**Where to install:** curl/gh/uv installers drop into **`~/.local/bin` on `/arc`**. npm-based agents need Node first — run **`astroai-install node`** (recommended) or add `nodejs` to a pixi project under **`TMP_SRC_DIR`**. Each CLI needs its own account or API key.

### Quick reference

| Tool | Command | Install | Node? |
|------|---------|---------|-------|
| [Cursor Agent](https://cursor.com/docs/cli/overview) | `agent` | curl script | No |
| [Claude Code](https://code.claude.com/docs/en/overview) | `claude` | curl script | No |
| [Antigravity CLI](https://antigravity.google/docs/cli-install) | `agy` | curl script | No |
| [OpenCode](https://dev.opencode.ai/docs/) | `opencode` | curl script (or npm) | Optional |
| [Codex CLI](https://openai-codex.mintlify.app/installation) | `codex` | npm or `gh release download` | npm path only |
| [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli) | `copilot` | curl script | No |
| [Goose](https://block.github.io/goose/) | `goose` | curl script | No |
| [Pi Coding Agent](https://pi.dev/) | `pi` | npm | Yes |
| [CodeWhale](https://www.codewhale.ai/) | `codewhale` | npm | Yes |
| [Swival](https://swival.dev/) | `swival` | `uv tool install` | No |
| [Freebuff](https://freebuff.com/) | `freebuff` | npm | Yes |

Google’s **Gemini CLI** was replaced by **Antigravity CLI** (`agy`) — use `astroai-install agy`, not a separate Gemini package.

Per-tool install steps live in `astroai-install --list` and in the script output when you run `astroai-install <tool>`. Prefer those over copying commands from docs — vendors change install URLs often.

### Choosing an agent

| You want… | Start with | Install |
|-----------|------------|---------|
| Cursor subscription / IDE workflow | **Cursor Agent** | `astroai-install agent` |
| Deep reasoning, long refactors | **Claude Code** | `astroai-install claude` |
| Google account; Gemini successor | **Antigravity CLI** | `astroai-install agy` |
| GitHub-native, issue → PR | **GitHub Copilot CLI** | `astroai-install copilot` |
| OpenAI ChatGPT / Codex | **Codex CLI** | `astroai-install codex` (needs `gh auth login`) |
| Model-agnostic, 75+ providers | **OpenCode** | `astroai-install opencode` |
| MCP + recipes, Block/Linux Foundation stack | **Goose** | `astroai-install goose` |
| Minimal harness, extensions, BYOK | **Pi** | `astroai-install node` then `astroai-install pi` |
| Open models / DeepSeek-first TUI | **CodeWhale** | `astroai-install node` then `astroai-install codewhale` |
| Local models + tight context (LM Studio, Ollama) | **Swival** | `astroai-install swival` |
| npm-only budget agent | **Freebuff** | `astroai-install node` then `astroai-install freebuff` |

You can install several agents to `~/.local/bin`; they share `gh`, `rg`, and **`TMP_SRC_DIR`** repos but use separate auth.

### Swival with local models (LM Studio / Ollama)

Swival is a good fit when you bring your own endpoint — including **local** models — without a cloud subscription:

```bash
astroai-install swival

# LM Studio on localhost (default provider; start the local server first)
swival "Summarize the README"

# OpenRouter or other hosted APIs
export OPENROUTER_API_KEY=sk-or-...
swival --provider openrouter --model z-ai/glm-5 "Refactor error handling in src/"

# Any OpenAI-compatible server (Ollama, vLLM, remote LM Studio)
swival --provider generic --base-url http://host:1234/v1 --model my-model "Review this diff"

# Interactive REPL
cd "${TMP_SRC_DIR}/myproject" && swival --repl
```

On CANFAR worker nodes you typically use a **hosted provider** (OpenRouter, Hugging Face, Gemini API) or point `--base-url` at an inference server you control. Swival docs: [swival.dev](https://swival.dev/pages/getting-started.html).

### Pair agents with `gh` and search tools

Agents work best when the repo is already on GitHub and searchable:

```bash
gh auth login
gh repo clone you/project && cd project
rg "def train" --type py          # code search
fd Dockerfile
bat README.md
gh pr list                        # context for the coding agent
gh issue list
```

Re-run installers when a tool publishes an update, or use each tool's built-in update command (Cursor Agent: `agent update`, Antigravity: `agy update`, etc.).

## Package managers

### pixi (recommended for conda-style stacks)

```bash
pixi init
pixi add numpy astropy pytorch cuda-version=12
pixi run python script.py
```

### Node.js and npm

The image has **no system `node` or `npm`** (use the **`full`** image or `astroai-install node` for zero-setup npm). JupyterLab runs without Node (prebuilt pip wheel). You need Node for:

- **npm-based AI agents** — Pi (`@earendil-works/pi-coding-agent`), CodeWhale, Freebuff, Codex (`@openai/codex`, optional), OpenCode (optional)
- **JupyterLab source extensions** from npm (rare — prefer prebuilt `pip` extensions)

**Prefer `astroai-install node`** for a persistent Node.js on `/arc` (pixi global → `~/.local/bin`). Alternatives: launch the **`full`** image, a pixi project under **`TMP_SRC_DIR`**, or CVMFS `module load nodejs`.

#### Recommended: pixi project under TMP_SRC_DIR

Same pattern as Python stacks. Package cache lands under **`PIXI_CACHE_DIR`** on scratch when mounted:

```bash
cd "${TMP_SRC_DIR}"
pixi init node-tools
cd node-tools
pixi add nodejs=22            # or: pixi add nodejs (latest); Codex needs Node 16+

pixi run node --version
pixi run npm --version
```

Install npm CLIs **into the pixi env** (not system-wide):

```bash
# OpenAI Codex
pixi run npm install -g @openai/codex
pixi run codex --version

# Pi Coding Agent
pixi run npm install -g @earendil-works/pi-coding-agent
pixi run pi --version

# CodeWhale
pixi run npm install -g codewhale
pixi run codewhale --version

# Freebuff
pixi run npm install -g freebuff
pixi run freebuff --version

# OpenCode (alternative to curl install)
pixi run npm install -g opencode-ai@latest
pixi run opencode --version
```

Run npm globals through pixi each session:

```bash
cd "${TMP_SRC_DIR}/node-tools"
pixi run codex
pixi run freebuff
```

Or add shell aliases in `~/.bashrc` on `/arc`:

```bash
alias codex='cd "${TMP_SRC_DIR}/node-tools" && pixi run codex'
```

#### Persist Node across sessions

```bash
cd "${TMP_SRC_DIR}/node-tools"
astroai-env-save node-tools     # saves pixi.toml + lockfile to /arc
# next session:
astroai-env-resume node-tools
cd "${TMP_SRC_DIR}/node-tools" && pixi install
```

Binaries from `npm install -g` inside the pixi env live under `.pixi/` on **`TMP_SRC_DIR`** — they are rebuilt by `pixi install` after resume. For long-lived personal CLIs, prefer curl → `~/.local/bin` or commit the pixi project to git.

#### npm cache

`npm` download cache defaults to **`NPM_CONFIG_CACHE`** on **`TMP_SCRATCH_DIR`** when mounted. Prune with `astroai-cache-prune --all-safe` if needed.

#### Alliance CVMFS (optional)

If you already use modules for other tools, you can load Alliance Node instead of pixi — but **pixi is simpler** for pinning npm CLIs alongside Python deps:

```bash
source /cvmfs/soft.computecanada.ca/config/profile/bash.sh
module avail nodejs
module load nodejs/22          # version varies; check module avail
node --version && npm --version
npm install -g @openai/codex   # installs to your user prefix; ensure ~/.local/bin is on PATH
```

### uv (recommended for pip/venv workflows)

```bash
uv init
uv add numpy torch
uv run python script.py
```

## Session-specific notes

### webterm

Browser terminal on port **5000**. Persistent `tmux` session named `astroai` (reattach after refresh). Login shell (`bash -l`). Starship prompt. Window tabs appear in the **tmux status bar** at the top.

**tmux tabs** (prefix `Ctrl-b`):

| Keys | Action |
|------|--------|
| `Ctrl-b` `c` | New window (tab) |
| `Ctrl-b` `n` / `p` | Next / previous window |
| `Ctrl-b` `0`–`9` | Jump to window number |
| `Ctrl-b` `w` | Interactive window list |
| `Ctrl-b` `%` / `"` | Split pane vertical / horizontal |

For GUI-style terminal tabs, use the **vscode** session instead.

```bash
# inside tmux after reconnect:
tmux attach -t astroai
```

### vscode

OpenVSCode Server on port **5000**. Integrated terminal uses bash. Extensions persist under `/arc`.

### notebook

JupyterLab on port **8888** (**Notebook** session type in the Science Portal — not Contributed).

**Stock CANFAR (most deployments today):** Skaha runs the platform script `/skaha-system/start-jupyterlab.sh`, not AstroAI’s `/skaha/startup.sh`. Expect the file browser at **`/`** (`serverRoot` `/`, not **`TMP_SRC_DIR`**), no AstroAI welcome banner, Jupyter config under `~/.jupyter` on `/arc`, and harmless `NotebookApp` deprecation warnings in logs (three `LabApp` migration warnings on startup). You can still use pixi/uv under **`TMP_SRC_DIR`** and register kernels manually.

*Validated on CANFAR staging (2026-06): session `gq7x9inz` logs show platform launcher + three deprecation warnings; JupyterLab HTML reports `baseUrl` `/session/notebook/<id>/` and `serverRoot` `/`.*

**With platform launch override (recommended):** when CANFAR ops point notebook jobs at `/skaha/startup.sh`, you get `common-init`, cwd **`TMP_SRC_DIR`**, and `base_url` `session/notebook/<session-id>`. See [OPERATORS.md](OPERATORS.md) for the helm change request.

Browser URL pattern: `https://…/session/notebook/<session-id>/lab/…?token=<session-id>`

The image ships `jupyter lab` via pip — **no Node required** to run Lab. Add extensions with `pip` when possible:

```bash
pixi add jupyterlab-git    # prebuilt extension, no Node
```

Source extensions from npm need Node — add `nodejs` to a pixi project under **`TMP_SRC_DIR`** (see [Node.js and npm](#nodejs-and-npm)).

#### Project kernels (pixi / uv / venv)

JupyterLab does **not** auto-detect environments under **`TMP_SRC_DIR`**. After `pixi install`, `uv sync`, or `astroai-env-resume`, register on demand:

```bash
cd "${TMP_SRC_DIR}/myproject"
astroai-kernel-register
```

Then pick **Python (myproject · pixi)** in the JupyterLab kernel menu (Launcher → Notebook, or Kernel → Change Kernel).

| Command | Purpose |
|---------|---------|
| `astroai-kernel-register` | Register cwd project (adds `ipykernel` if missing) |
| `astroai-kernel-register "${TMP_SRC_DIR}/other"` | Register a specific path |
| `astroai-kernel-register --name mylab` | Override kernelspec name |
| `astroai-kernel-register --list` | List AstroAI-linked kernels + `jupyter kernelspec list` |
| `astroai-kernel-register --unregister` | Remove kernel for cwd project |

Kernelspecs persist under `~/.local/share/jupyter/kernels` on `/arc`. The env binaries live on **`TMP_SRC_DIR`** — **re-run `astroai-kernel-register` after each `astroai-env-resume`** (or when imports fail because paths changed).

`astroai-new` does not register a kernel automatically; run the one-liner when you want that project in the picker.

### marimo

Reactive notebooks on port **5000**. Create `.py` notebooks under **`TMP_SRC_DIR`** from the marimo UI. Uses `--base-url` when `skaha_sessionid` is set.

## Environment variables (platform and AstroAI)

Skaha typically sets:

- `HOME` → `/arc/home/$USER`
- `USER`, UID/GID — injected non-root identity
- `skaha_sessionid` — reverse-proxy paths (**Contributed** sessions: webterm, vscode, marimo)
- `JUPYTER_TOKEN` — session ID on **Notebook** sessions (same value as Skaha session ID)
- GPU devices — on GPU nodes, via the container runtime

AstroAI profile (`/etc/profile.d/astroai.sh`) sets unless overridden at launch:

| Variable | Image default | Purpose |
|----------|---------------|---------|
| `ASTROAI_DEFAULT_SRC_DIR` | `/srcdir` | Default code root when `TMP_SRC_DIR` unset |
| `ASTROAI_DEFAULT_SCRATCH_DIR` | `/scratch` | Default scratch when `TMP_SCRATCH_DIR` unset |
| `TMP_SRC_DIR` | resolved at login | Code, git repos, pixi/uv projects |
| `TMP_SCRATCH_DIR` | `/scratch` | Datasets, download caches, `TMPDIR` parent |
| `ASTROAI_WORK_ROOT` | — | Legacy alias for code root (deprecated) |

Run `astroai-status` to see resolved values (`work:` / `scratch:` / `caches:`).

## Diagnostics

`astroai-debug` produces a comprehensive snapshot of your session — useful for troubleshooting, sharing with collaborators, or attaching to support requests.

```bash
astroai-debug                     # save to ~/.astroai/debug-<timestamp>.log + print
astroai-debug --stdout            # print only
astroai-debug --file /path/out    # save to custom path
```

The report covers:

| Section | What it shows |
|---------|---------------|
| Session | Home, **`TMP_SRC_DIR`**, **`TMP_SCRATCH_DIR`**, tmp, shell, uptime |
| Profile | ASTROAI_PROFILE_LOADED, PATH, uv/pixi/cache dirs |
| GPU | nvidia-smi summary and processes (or CPU node notice) |
| Disk | **`TMP_SRC_DIR`**, **`TMP_SCRATCH_DIR`**, and HOME `df`, top directories by size |
| Tools | Version check for git, gh, uv, pixi, jq, rg, fd, bat, and more |
| Project | Pixi/uv detection, lockfile size, env size |
| Network | Reachability check for pypi.org, github.com, conda |
| Environment | Key env vars (sanitized — tokens and keys hidden) |
| Processes | Top 10 by CPU |
| CVMFS | `/cvmfs/soft.computecanada.ca` status |

Share the log file: `cat ~/.astroai/debug-<timestamp>.log`

## Troubleshooting

| Problem | Things to try |
|---------|----------------|
| Lost work after session | Was code only on **`TMP_SRC_DIR`** without `git push`? Use `git push` or `astroai-session-archive` before closing. |
| `git clone` SSH fails | Add your key to `~/.ssh` on `/arc`. |
| GPU not visible | Did you pick a GPU node? Run `nvidia-smi`. |
| `import torch` no CUDA | GPU node + `cuda-version` / GPU torch via pixi. |
| AI CLI not found | Run `astroai-install <tool>` or `astroai-install --list`. Curl/gh/uv agents → `~/.local/bin`; npm agents → `astroai-install node` first. |
| `node` / `npm` not found | Not in the image — `astroai-install node` (persistent on `/arc`) or `pixi add nodejs` under **`TMP_SRC_DIR`** (see [Node.js and npm](#nodejs-and-npm)). |
| `gh: not authenticated` | Run `gh auth login` once; token persists on `/arc`. Required for `astroai-install codex`. |
| Wrong npm package | Codex: `@openai/codex` · OpenCode: `opencode-ai` · Pi: `@earendil-works/pi-coding-agent` · Claude Code / Cursor Agent: prefer curl via `astroai-install`. |
| pip build fails | Add compilers/libs with pixi, not system apt. |
| `uv`: Permission denied on `/usr/local/share/uv` | Image `ENV` is root-only; `source /etc/profile.d/astroai.sh` (or `bash -l`) **must** run — it force-sets `UV_PYTHON_INSTALL_DIR` to `~/.local/share/uv/python`. Check with `astroai-status`. |
| `canfar` / `cadcget` not found in webterm | Open a login shell (`bash -l`) or a new tmux window; image ≥ 26.06 fixes inherited profile guard. Run `/opt/astroai/bin/canfar-verify.sh`. |
| `/arc` quota pressure | `astroai-home-usage`; `astroai-cache-prune --all-safe`. |
| `ls /cvmfs` looks empty | Normal — CVMFS mounts lazily; `source /cvmfs/soft.computecanada.ca/config/profile/bash.sh` then `module avail`. |
| Jupyter 404 behind proxy | Notebook sessions use port **8888** and path `/session/notebook/<id>/`. On stock CANFAR, platform launcher must match ingress; full AstroAI startup needs helm override — see [OPERATORS.md](OPERATORS.md). |
| Jupyter opens in `/` not project dir | Stock platform launcher — `cd "${TMP_SRC_DIR}"` manually or ask ops for `/skaha/startup.sh` override. |
| Kernel missing after resume | Re-run `astroai-kernel-register` in the project dir (**`TMP_SRC_DIR`** paths change between sessions). |
| Contributed session 404 (webterm/vscode/marimo) | Skaha strips `/session/contrib/<id>` before forwarding; webterm must **not** use ttyd `--base-path`. Update to latest image tag. |
| tmux shell is nologin | Image sets `default-shell /bin/bash`; use `bash -l` in webterm. |
