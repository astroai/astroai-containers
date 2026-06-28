#!/bin/bash -e
# AstroAI storage quotas, home/project space, and running processes.

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

usage() {
    cat <<'EOF' >&2
astroai-status — quotas, home/project space, and processes.
Usage: astroai-status
  --help for details
EOF
}

help_full() {
    cat <<'EOF'
astroai-status — quotas, home/project space, and processes.

Usage:
  astroai-status

Options:
  -h          Short help (stderr, exit 1)
  --help      This help (stdout, exit 0)

Prints:
  • /arc quota usage for home and accessible project workspaces
  • Largest directories under $HOME on shared storage
  • Top-level usage for the current /arc/projects workspace (if any)
  • Top processes by CPU

No arguments required.
EOF
}

case "${1:-}" in
    -h) usage; exit 1 ;;
    --help) help_full; exit 0 ;;
    "") ;;
    *)
        astroai_err "Unexpected argument: $1"
        usage
        exit 1
        ;;
esac

astroai_title "AstroAI status"
astroai_divider

echo ""
astroai_heading "Quotas (/arc)"
if [[ -d "${HOME}" ]]; then
    astroai_quota_line "${HOME}" "home"
else
    astroai_hint "  home: not mounted"
fi

if [[ -d /arc/projects ]]; then
    for proj in /arc/projects/*/; do
        [[ -d "${proj}" && -r "${proj}" ]] || continue
        astroai_quota_line "${proj}" "$(basename "${proj}")"
    done
fi

echo ""
astroai_heading "Home (${HOME})"
_home_entries=(
    ".cache:ML/tool caches"
    ".pixi:pixi global envs"
    ".local/share/micromamba:micromamba root"
    ".local:user tools and data"
    ".astroai:env save manifests"
    ".config:application config"
)

_home_total=0
for entry in "${_home_entries[@]}"; do
    dir="${entry%%:*}"
    label="${entry#*:}"
    path="${HOME}/${dir}"
    if [[ -e "${path}" ]]; then
        human="$(du -sh "${path}" 2>/dev/null | awk '{print $1}')"
        bytes="$(du -sb "${path}" 2>/dev/null | awk '{print $1}')"
        if astroai_ui_enabled; then
            printf '  %b%-10s%b %8s  %s\n' $'\033[1m' "${dir}" $'\033[0m' "${human}" "${label}"
        else
            printf "  %-10s %8s  %s\n" "${dir}" "${human}" "${label}"
        fi
        _home_total=$((_home_total + bytes))
    fi
done

if [[ "${_home_total}" -gt 0 ]]; then
    _home_h="$(numfmt --to=iec-i --suffix=B "${_home_total}" 2>/dev/null || echo "?")"
    astroai_kv "Tracked:" "~${_home_h}"
fi

_pct="$(astroai_quota_used_pct "${HOME}" 2>/dev/null || true)"
if [[ -n "${_pct}" && "${_pct}" -ge 80 ]]; then
    astroai_hint "  → astroai-home-usage for full breakdown · astroai-home-clean --all-safe"
fi

echo ""
astroai_heading "Project space"
_proj="$(astroai_find_arc_project_root 2>/dev/null || true)"
if [[ -n "${_proj}" ]]; then
    astroai_kv "cwd:" "${_proj}"
    du -sh "${_proj}"/* 2>/dev/null | sort -hr | head -8 | sed 's/^/  /' || astroai_hint "  (empty)"
else
    astroai_hint "  not under /arc/projects (team workspaces live there)"
fi

echo ""
astroai_heading "Processes (top CPU)"
ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | sed 's/^/  /' || true

echo ""
if [[ ! -f "${HOME}/.astroai/agent-setup-stamp" ]]; then
    astroai_hint "AI agents: run astroai-agent-setup once (persists on /arc)"
else
    astroai_hint "AI agents: $(cat "${HOME}/.astroai/agent-setup-stamp" 2>/dev/null) — refresh: astroai-agent-setup update"
fi
astroai_hint "more: astroai-home-usage · astroai-debug"
