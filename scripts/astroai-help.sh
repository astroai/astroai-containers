#!/bin/bash -e
# AstroAI user command reference.

cat <<'EOF'
AstroAI commands (on PATH via /opt/astroai/bin)
=================================================

Quick loop
  astroai-status              where am I, gpu, git, disk, session age
  astroai-new [name]          pixi init + git + GH repo (--uv, --no-git, --no-gh, --astro)
  astroai-clone owner/repo    clone + install deps (optional target dir)

Environment save/resume (/arc-friendly)
  astroai-env-save [name]     save lockfiles to ~/.astroai/saves (--full, --to)
  astroai-env-resume <name>   restore on /scratch + pixi install (--from, [path])
  astroai-env-list            list personal saves (--team, --all)

JupyterLab (notebook sessions)
  astroai-kernel-register     add cwd pixi/uv/venv to kernel picker (on demand)
  astroai-kernel-register --list | --unregister | --name | <path>

Home hygiene (shared CephFS)
  astroai-home-usage          disk breakdown under $HOME
  astroai-cache-prune --all-safe   clear pip/uv/npm/pixi caches
  astroai-cache-prune --hf    also drop Hugging Face model cache
  astroai-debug               diagnostic report (--stdout, --file)
  astroai-debug --stdout      print only (no file save)

Project workflow
  astroai-project-init <name> create team workspace on /arc/projects (--members)
  pixi install / uv sync      deps into project (not system image)
  astroai-session-archive     git push + env save + summary (--force, --name)
  git push                    before session ends — scratch is wiped

Reminders (interactive login shells)
  ~every 2h                   yellow /scratch nudge (git push or archive)
  on shell exit               auto astroai-session-archive --force once (in git repo)

Dev CLIs (pre-installed)
  gh, rg, fd, bat, fzf, delta, tldr   GitHub + fast search/browse
  gh auth login               one-time GitHub token setup

CADC / CANFAR clients (pre-installed — see USAGE.md)
  cadcget, cadcput, vcp, cadc-tap, canfar, cadc-get-cert
  canfar auth login           Science Platform authentication

AI agents (install once to ~/.local/bin on /arc — see USAGE.md)
  astroai-install node       Node.js + npm via pixi (persistent on /arc)
  astroai-install <tool>     Cursor Agent (agent), claude, agy, opencode, codex,
                             copilot, goose, pi, codewhale, swival, freebuff
  astroai-install --list     full list + install methods
  curl: Cursor Agent (agent), claude, agy, opencode, copilot, goose
  gh release (no Node): codex
  uv tool (no Node): swival
  npm (needs node): pi, codewhale, freebuff

Docs: less /opt/astroai/USAGE.md  (or docs/USAGE.md in repo)

Storage
  /scratch     active work (ephemeral)
  ~/.cache     tool caches on /arc (prune when large)
  ~/.astroai   env save manifests
  astroai-data-stage <src> [dst]  copy data to /scratch for fast I/O
  astroai-data-sync <src> <tgt>   sync /scratch results to persistent
EOF
