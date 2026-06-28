# AGENTS.md

CANFAR AstroAI project — guidance for AI coding agents.

## Setup (each developer, once)

```bash
astroai-agent-setup          # on /arc — MCP + skills
astroai-install agent        # or claude, goose, opencode, codex
gh auth login
```

Refresh: `astroai-agent-setup update`

## This repo

```bash
pixi install    # or uv sync
pixi run …      # or uv run …
git push        # before session ends — code on TMP_SRC_DIR is ephemeral
```

Search: `rg`, `fd`, `sg` (ast-grep skill). Help: `astroai-help`, `astroai-status`.
