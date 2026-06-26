# Terminal colour helpers for astroai-* commands.
# Respects NO_COLOR and ASTROAI_UI_PLAIN; disabled when not attached to a TTY.

[[ -n "${ASTROAI_UI_LOADED:-}" ]] && return 0 2>/dev/null || true
ASTROAI_UI_LOADED=1

astroai_ui_enabled() {
    [[ -z "${NO_COLOR:-}" && -z "${ASTROAI_UI_PLAIN:-}" && -t 1 ]]
}

astroai_ui_stderr_enabled() {
    [[ -z "${NO_COLOR:-}" && -z "${ASTROAI_UI_PLAIN:-}" && -t 2 ]]
}

astroai__println() {
    local fd="$1" color="$2"
    shift 2
    local msg="$*"

    if [[ "${fd}" == 2 ]]; then
        if astroai_ui_stderr_enabled; then
            printf '%b%s%b\n' "${color}" "${msg}" $'\033[0m' >&2
        else
            printf '%s\n' "${msg}" >&2
        fi
        return 0
    fi

    if astroai_ui_enabled; then
        printf '%b%s%b\n' "${color}" "${msg}" $'\033[0m'
    else
        printf '%s\n' "${msg}"
    fi
}

astroai_title()   { astroai__println 1 $'\033[1;36m' "$@"; }
astroai_heading() { astroai__println 1 $'\033[1;34m' "$@"; }
astroai_info()    { astroai__println 1 $'\033[36m' "$@"; }
astroai_ok()      { astroai__println 1 $'\033[1;32m' "$@"; }
astroai_warn()    { astroai__println 2 $'\033[1;33m' "$@"; }
astroai_err()     { astroai__println 2 $'\033[1;31m' "$@"; }
astroai_hint()    { astroai__println 1 $'\033[2m' "$@"; }
astroai_cmd()     { astroai__println 1 $'\033[36m' "$@"; }

astroai_kv() {
    local label="$1" value="$2"
    if astroai_ui_enabled; then
        printf '%b%-10s%b %s\n' $'\033[1m' "${label}" $'\033[0m' "${value}"
    else
        printf '%-10s %s\n' "${label}" "${value}"
    fi
}

astroai_section() {
    local title="$1"
    if astroai_ui_enabled; then
        printf '\n%b=== %s ===%b\n' $'\033[1;34m' "${title}" $'\033[0m'
    else
        printf '\n=== %s ===\n' "${title}"
    fi
}

astroai_divider() {
    if astroai_ui_enabled; then
        printf '%b%s%b\n' $'\033[2m' '────────────────────────────────────────' $'\033[0m'
    else
        echo '────────────────────────────────────────'
    fi
}
