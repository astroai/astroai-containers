---
name: astroai-workflow
description: >-
  CANFAR AstroAI quick reference — setup, pixi/uv, storage, astroai-* commands.
  Use for new users or session workflow questions on AstroAI.
---
# AstroAI in 3 commands

```bash
astroai-agent-setup              # once per user — MCP + skills (persists on /arc)
astroai-install agent            # or: claude, goose, opencode, codex
gh auth login                    # GitHub for gh + GitHub MCP
```

Refresh after image upgrade: `astroai-agent-setup update`

## Daily workflow

```bash
astroai-new mylab                # or astroai-clone owner/repo
astroai-clone --from-env ml-base owner/repo   # warm caches from saved stack
cd "${TMP_SRC_DIR}/mylab"
pixi install                     # or uv sync
pixi run python analysis.py
git push                         # before session ends!
```

## Storage (memorize this)

| Path | What |
|------|------|
| `${TMP_SRC_DIR}` | Code + `.pixi`/`.venv` — **gone when session ends** |
| `${TMP_SCRATCH_DIR}` | Big data + download caches |
| `/arc` (`$HOME`) | Agent config, saves, `~/.local/bin` |

## Search & run (standard tools — no custom commands)

```bash
rg 'pattern' --type py
fd name
sg -p 'class $N' -l py          # needs: astroai-install ast-grep
pixi run pytest -q
uv run python script.py
```

## Help

```bash
astroai-help
astroai-status                   # quotas, home/project space
astroai-debug                    # paths, caches, uv python dir
astroai-home-clean --all-safe    # when /arc quota is tight
less /opt/astroai/USAGE.md
```
