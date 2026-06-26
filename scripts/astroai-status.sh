#!/bin/bash -e
# AstroAI session status summary.

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

astroai_title "AstroAI session status"
astroai_divider
astroai_kv "user:" "${USER}  home: ${HOME}"
astroai_kv "pwd:" "${PWD}"
astroai_kv "scratch:" "$(if [[ -d /scratch ]]; then echo yes; else echo no; fi)  tmp: ${TMPDIR:-/tmp}"

# Session age (written by common-init.sh at startup)
if [[ -f "${HOME}/.astroai/session-started" ]]; then
    _start_epoch="$(cat "${HOME}/.astroai/session-started" 2>/dev/null || echo 0)"
    if [[ "${_start_epoch}" -gt 0 ]]; then
        _now="$(date +%s)"
        _age_sec=$(( _now - _start_epoch ))
        if [[ "${_age_sec}" -ge 3600 ]]; then
            _age="$(( _age_sec / 3600 ))h $(( (_age_sec % 3600) / 60 ))m"
        else
            _age="$(( _age_sec / 60 ))m"
        fi
        _start_fmt="$(date -d "@${_start_epoch}" '+%H:%M %Z' 2>/dev/null || echo unknown)"
        astroai_kv "session:" "started ${_start_fmt} (${_age} ago)"
    fi
fi

astroai_kv "uptime:" "$(uptime 2>/dev/null | sed 's/^.*up//' | sed 's/,.*//' | xargs || echo unknown)"

if [[ -n "${ASTROAI_PROFILE_LOADED:-}" ]]; then
    astroai_kv "profile:" "sourced"
else
    astroai_warn "profile: not sourced"
fi

if [[ -d /cvmfs/soft.computecanada.ca/config/profile ]]; then
    astroai_kv "cvmfs:" "available (source /cvmfs/soft.computecanada.ca/config/profile/bash.sh)"
else
    astroai_hint "cvmfs:   not mounted (may be lazy — access a known path first)"
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi &>/dev/null; then
    astroai_kv "gpu:" "$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
else
    astroai_hint "gpu:   not visible (CPU node or no driver)"
fi

kind="$(astroai_detect_project 2>/dev/null || true)"
if [[ -n "${kind}" ]]; then
    astroai_kv "project:" "${kind} ($(basename "${PWD}"))"
else
    astroai_hint "project: none (cd /scratch && pixi init)"
fi

if command -v uv >/dev/null 2>&1; then
    uv_py_dir="$(uv python dir 2>/dev/null || echo unknown)"
    if [[ "${uv_py_dir}" == /usr/local/* ]]; then
        astroai_warn "uv:    python dir ${uv_py_dir} (root-only — run: source /etc/profile.d/astroai.sh)"
    else
        astroai_kv "uv:" "python dir ${uv_py_dir}"
    fi
fi

if git rev-parse --is-inside-work-tree &>/dev/null; then
    astroai_kv "git:" "$(git branch --show-current 2>/dev/null) $(git status -sb 2>/dev/null | head -1)"
fi

echo ""
astroai_heading "cadc:"
for tool in cadcget cadcput vcp cadc-tap canfar cadc-get-cert; do
    if command -v "${tool}" >/dev/null 2>&1; then
        ver="$("${tool}" --version 2>&1 | head -1 || echo ok)"
        astroai_kv "  ${tool}" "${ver}"
    else
        astroai_hint "  ${tool} not installed"
    fi
done

echo ""
astroai_heading "processes (top by CPU):"
ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | sed 's/^/  /' || true

echo ""
astroai_heading "disk:"
astroai_quota_line "${HOME}" "home" 2>/dev/null || true
if [[ -d /scratch ]]; then
    astroai_quota_line /scratch "scratch" 2>/dev/null || true
fi

echo ""
astroai_hint "commands: astroai-help | astroai-home-usage | astroai-env-list"
