#!/bin/bash -e
# Quick session snapshot for fast feedback loops.

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
source /opt/astroai/lib/astroai-env-common.sh

echo "AstroAI session status"
echo "======================"
echo "user:  ${USER}  home: ${HOME}"
echo "pwd:   ${PWD}"
echo "scratch: $(if [[ -d /scratch ]]; then echo yes; else echo no; fi)  tmp: ${TMPDIR:-/tmp}"
echo "uptime:  $(uptime 2>/dev/null | sed 's/^.*up//' | sed 's/,.*//' | xargs || echo unknown)"

echo "profile: $(if [[ -n "${ASTROAI_PROFILE_LOADED:-}" ]]; then echo sourced; else echo not sourced; fi)"

if [[ -d /cvmfs/soft.computecanada.ca ]]; then
    echo "cvmfs:   available (source /cvmfs/soft.computecanada.ca/config/profile/bash.sh)"
else
    echo "cvmfs:   not mounted (may be lazy — access a known path first)"
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L &>/dev/null; then
    echo "gpu:   $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
else
    echo "gpu:   not visible (CPU node or no driver)"
fi

kind=""
[[ -f pixi.toml ]] && kind="pixi"
[[ -f pyproject.toml && -z "${kind}" ]] && kind="uv"
[[ -n "${kind}" ]] && echo "project: ${kind} ($(basename "${PWD}"))" || echo "project: none (cd /scratch && pixi init)"

if command -v uv >/dev/null 2>&1; then
    uv_py_dir="$(uv python dir 2>/dev/null || true)"
    if [[ -n "${uv_py_dir}" ]]; then
        if [[ "${uv_py_dir}" == /usr/local/* ]]; then
            echo "uv:    python dir ${uv_py_dir} (root-only — run: source /etc/profile.d/astroai.sh)"
        else
            echo "uv:    python dir ${uv_py_dir}"
        fi
    fi
fi

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "git:   $(git branch --show-current 2>/dev/null) $(git status -sb 2>/dev/null | head -1)"
fi

echo ""
echo "processes (top by CPU):"
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -6 | sed 's/^/  /'

echo ""
echo "disk:"
# Quota-aware lines for scratch and home
astroai_quota_line /scratch scratch
astroai_quota_line "${HOME}" "home"
# Project quota (if inside a project)
if [[ -d /arc/projects ]]; then
    _proj="${PWD}"
    while [[ "${_proj}" != "/" && "${_proj}" != "/arc/projects" ]]; do
        _parent="$(dirname "${_proj}")"
        if [[ "${_parent}" == /arc/projects ]]; then
            astroai_quota_line "${_proj}" "project"
            break
        fi
        _proj="${_parent}"
    done
fi

echo ""
echo "commands: astroai-help | astroai-home-usage | astroai-env-list"
