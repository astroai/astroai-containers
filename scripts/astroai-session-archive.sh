#!/bin/bash -e
# Archive current work before closing a session: git push + env save + summary.
#
# Usage:
#   astroai-session-archive         auto-detect project, push + save
#   astroai-session-archive --name  custom save name (default: dir name)

source /opt/astroai/lib/astroai-env-common.sh
[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) NAME="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,6p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

echo "Session archive"
echo "==============="
echo ""

PUSHED=0
SAVED=0
UNCOMMITTED=0

# ── Git ──────────────────────────────────────────
if git rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH="$(git branch --show-current 2>/dev/null || echo unknown)"
    REMOTE="$(git remote get-url origin 2>/dev/null || echo none)"

    # Check for unstaged / uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        echo "⚠  Uncommitted changes detected. Commit before pushing:"
        echo "   git add -A && git commit -m 'session work'"
        echo ""
        UNCOMMITTED=1
    fi

    echo "Pushing branch '${BRANCH}' to ${REMOTE}..."
    if git push; then
        echo "✓ pushed ${BRANCH}"
        PUSHED=1
    else
        echo "✗ git push failed — check remote or run: gh auth login"
    fi
else
    echo "Not in a git repo — skipping push."
    echo "  Hint: cd /scratch/myproject && gh repo create myproject --private --source=. --push"
fi

echo ""

# ── Environment ──────────────────────────────────
KIND="$(astroai_detect_project)"
if [[ -n "${KIND}" ]]; then
    if [[ -z "${NAME}" ]]; then
        NAME="$(basename "${PWD}")"
    fi

    echo "Saving ${KIND} environment '${NAME}'..."
    if /opt/astroai/bin/astroai-env-save "${NAME}"; then
        echo "✓ env saved: ${NAME}"
        SAVED=1
    else
        echo "✗ env save failed — run: astroai-env-save ${NAME}"
    fi
else
    echo "No pixi or uv project detected — skipping env save."
    echo "  Hint: pixi init && pixi add python numpy"
fi

echo ""
echo "── Summary ──"
echo "  git push:   $([[ "${PUSHED}" -eq 1 ]] && echo "done" || echo "skipped")"
echo "  env save:   $([[ "${SAVED}" -eq 1 ]] && echo "done (${NAME})" || echo "skipped")"
if [[ "${UNCOMMITTED}" -eq 1 ]]; then
    echo "  ⚠  uncommitted changes exist — not archived"
fi

if [[ -d /scratch ]]; then
    echo ""
    echo "⚠  /scratch is ephemeral — your session work will be wiped."
    if [[ "${PUSHED}" -eq 1 && "${SAVED}" -eq 1 ]]; then
        echo "   Code is on GitHub and environment is saved. Safe to close."
    elif [[ "${PUSHED}" -eq 1 ]]; then
        echo "   Code is on GitHub. Re-run astroai-env-save if you need the environment."
    elif [[ "${SAVED}" -eq 1 ]]; then
        echo "   Environment is saved. Push code with: git push"
    else
        echo "   Nothing archived! Push code and save env before closing."
    fi
fi
