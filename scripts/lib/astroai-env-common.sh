# Session path + quota helpers for AstroAI startup scripts.
# Env save/resume/workspace logic lives in astroai-lab — do not duplicate here.

ASTROAI_ENV_COMMON_LOADED=1
set -o pipefail 2>/dev/null || true

if [[ -f /opt/astroai/lib/astroai-ui.sh ]]; then
    # shellcheck disable=SC1091
    source /opt/astroai/lib/astroai-ui.sh
elif [[ -f "${BASH_SOURCE[0]%/*}/astroai-ui.sh" ]]; then
    # shellcheck disable=SC1091
    source "${BASH_SOURCE[0]%/*}/astroai-ui.sh"
fi

# Runtime paths — set TMP_SRC_DIR / TMP_SCRATCH_DIR to override; defaults from image ENV only.
astroai_default_src_dir() {
    echo "${ASTROAI_LAB_DEFAULT_SRC_DIR:-/srcdir}"
}

astroai_default_scratch_dir() {
    echo "${ASTROAI_LAB_DEFAULT_SCRATCH_DIR:-/scratch}"
}

astroai_scratch_dir() {
    echo "${TMP_SCRATCH_DIR:-$(astroai_default_scratch_dir)}"
}

astroai_scratch_available() {
    local _scratch
    _scratch="$(astroai_scratch_dir)"
    [[ -d "${_scratch}" && -w "${_scratch}" ]]
}

# Code/env root: TMP_SRC_DIR when set, else default src dir if writable, else scratch, else HOME.
astroai_src_dir() {
    if [[ -n "${TMP_SRC_DIR:-}" ]]; then
        echo "${TMP_SRC_DIR}"
        return
    fi
    local _default_src
    _default_src="$(astroai_default_src_dir)"
    if [[ -d "${_default_src}" && -w "${_default_src}" ]]; then
        echo "${_default_src}"
    elif astroai_scratch_available; then
        echo "$(astroai_scratch_dir)"
    else
        echo "${HOME}"
    fi
}

# Echo integer 0-100 used percentage for path, or empty if unknown.
astroai_quota_used_pct() {
    local path="${1:-}"
    [[ -d "${path}" ]] || return 0
    df "${path}" 2>/dev/null | awk 'NR>1 {used=$3; size=$2; if(size>0) printf "%.0f", (used/size)*100; else print 0}'
}

# Echo /arc/projects/<name> when start path is inside a project, else empty.
astroai_find_arc_project_root() {
    local start="${1:-${PWD}}"
    local proj_path="${start}"

    [[ -d /arc/projects ]] || return 0
    while [[ "${proj_path}" != "/" && "${proj_path}" != "/arc/projects" ]]; do
        local parent
        parent="$(dirname "${proj_path}")"
        if [[ "${parent}" == /arc/projects ]]; then
            echo "${proj_path}"
            return 0
        fi
        proj_path="${parent}"
    done
}

# Check storage quota for a path. Prints warnings at thresholds.
# Returns: 0 = OK, 1 = warning (>80%), 2 = critical (>95%)
astroai_check_quota() {
    local path="${1:-}"
    local label="${2:-$(basename "${path}")}"

    [[ -d "${path}" ]] || return 0

    local used_pct
    used_pct="$(astroai_quota_used_pct "${path}")"
    [[ -n "${used_pct}" ]] || return 0

    if [[ "${used_pct}" -ge 95 ]]; then
        astroai_warn "  ⚠  ${label}: ${used_pct}% used — CRITICAL (near quota limit)"
        return 2
    elif [[ "${used_pct}" -ge 90 ]]; then
        astroai_warn "  ⚠  ${label}: ${used_pct}% used — prune soon (astroai-lab clean home --all-safe)"
        return 1
    elif [[ "${used_pct}" -ge 80 ]]; then
        astroai_warn "  ⚠  ${label}: ${used_pct}% used — monitor (astroai-lab status)"
        return 1
    fi
    return 0
}

# Print a one-line quota summary for a path.
astroai_quota_line() {
    local path="${1:-}"
    local label="${2:-$(basename "${path}")}"

    [[ -d "${path}" ]] || { echo "  ${label}: not mounted"; return; }

    df -h "${path}" 2>/dev/null | awk -v lbl="${label}" 'NR>1 {
        pct=$5; gsub(/%/, "", pct);
        if (pct >= 95) alert=" ⚠ CRITICAL";
        else if (pct >= 90) alert=" ⚠ high";
        else if (pct >= 80) alert=" ⚠ monitor";
        else alert="";
        printf "  %-8s %s / %s (%s%%)%s\n", lbl, $3, $2, $5, alert
    }'
}

# Run quota warnings for relevant paths at session start.
# Skip when stderr is not a TTY (CANFAR session logs capture startup stderr).
astroai_quota_startup_check() {
    if [[ ! -t 2 ]]; then
        return 0
    fi

    local warned=0

    if [[ -d "${HOME}" ]]; then
        astroai_check_quota "${HOME}" "home (/arc/home/${USER})" || warned=1
    fi

    local proj_path
    proj_path="$(astroai_find_arc_project_root)"
    if [[ -n "${proj_path}" ]]; then
        local proj_label="project ($(basename "${proj_path}"))"
        astroai_check_quota "${proj_path}" "${proj_label}" || warned=1
    fi

    if [[ "${warned}" -eq 1 ]]; then
        echo ""
    fi
    return 0
}
