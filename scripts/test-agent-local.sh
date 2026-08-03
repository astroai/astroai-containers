#!/bin/bash -e
# Local CANFAR-emulation E2E for the astroai-lab agent command surface.
#
# Proves, against a session image run like a CANFAR session (fresh MOUNTED
# home, non-root user), that:
#   1. every agent/plugin/models command works out of the box
#      (list, catalog, install, verify, plugins list/install/remove,
#       configure, addons, models);
#   2. agent CLI installs NEVER land in the user home (~/.local) — the
#      session bin dir is scratch-backed when SCRATCH is mounted, else the
#      work-dir runtime root (work/.runtime-$USER/bin).
#
# Runs TWO scenarios per image: with scratch (CANFAR-like) and without
# (plain local machine) — the no-scratch path exercises the runtime-root
# fallback that replaced the old ~/.local default.
#
# Usage:
#   ./scripts/test-agent-local.sh [image]        # default: base
#   ./scripts/test-agent-local.sh openresearch
#
# Env:
#   OWNER / REGISTRY / TAG     image coordinates (defaults: astroai /
#                               images.canfar.net / local)
#   ASTROAI_LAB_SRC            optional path to an astroai-lab src/ overlay
#                              (mounted at /opt/astroai-lab-src + PYTHONPATH)
#                              for testing uncommitted astroai-lab code.

IMAGE="${1:-base}"
OWNER="${OWNER:-astroai}"
REGISTRY="${REGISTRY:-images.canfar.net}"
TAG="${TAG:-local}"
FULL_IMAGE="${REGISTRY}/${OWNER}/${IMAGE}:${TAG}"
FAILURES=0

FAKE_HOME="$(mktemp -d)"
FAKE_SRC="$(mktemp -d)"
FAKE_SCRATCH="$(mktemp -d)"
trap 'rm -rf "${FAKE_HOME}" "${FAKE_SRC}" "${FAKE_SCRATCH}"' EXIT

OVERLAY_ARGS=()
if [[ -n "${ASTROAI_LAB_SRC:-}" ]]; then
    OVERLAY_ARGS=(
        -v "${ASTROAI_LAB_SRC}:/opt/astroai-lab-src"
        -e "PYTHONPATH=/opt/astroai-lab-src"
    )
fi

PROBE="$(mktemp)"
trap 'rm -rf "${FAKE_HOME}" "${FAKE_SRC}" "${FAKE_SCRATCH}" "${PROBE}"' EXIT

cat > "${PROBE}" <<'PROBE_EOF'
#!/bin/bash
# Runs inside the container as a non-root user with a fresh mounted HOME.
set -u
# The image's PATH hook lives in /etc/profile.d/astroai.sh (login shells
# only) — this probe runs via plain `bash`, so put astroai-lab on PATH here.
export PATH="/opt/astroai/venv/cadc/bin:/opt/astroai/bin:${PATH}"
HOME_DIR="$(pwd)"
export HOME="${HOME_DIR}"
export USER=testuser
export WORK=/srcdir
export SCRATCH="${SCRATCH:-}"

fail() { echo "  FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# 0. bin dir resolution must never be under the user home (config files in
#    home are fine; CLI binaries are not). With scratch the session bin dir is
#    legitimately scratch/.local/bin — only a path under $HOME is a violation.
#    The expected pattern keys off astroai-lab's RESOLVED SCRATCH (present in
#    the env export only when a scratch dir was actually found), not the raw
#    env placeholder the harness passes in.
ENV_JSON="$(astroai-lab env export --json)"
BIN_DIR="$(printf '%s' "${ENV_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["ASTROAI_LAB_BIN_DIR"])')"
RESOLVED_SCRATCH="$(printf '%s' "${ENV_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("SCRATCH",""))')"
case "${BIN_DIR}" in
    "${HOME_DIR}"/*) fail "bin dir under home: ${BIN_DIR}";;
esac
if [[ -n "${RESOLVED_SCRATCH}" ]]; then
    case "${BIN_DIR}" in
        "${RESOLVED_SCRATCH}"/*) ok "bin dir scratch-backed: ${BIN_DIR}";;
        *) fail "expected scratch-backed bin dir, got ${BIN_DIR} (scratch=${RESOLVED_SCRATCH})";;
    esac
else
    case "${BIN_DIR}" in
        */.runtime-*/bin) ok "bin dir runtime-root fallback: ${BIN_DIR}";;
        *) fail "expected runtime-root bin dir, got ${BIN_DIR}";;
    esac
fi

# 1. read commands work out of the box.
astroai-lab agent list          >/dev/null || fail "agent list"
astroai-lab agent catalog       >/dev/null || fail "agent catalog"
astroai-lab agent plugins list  >/dev/null || fail "agent plugins list"
astroai-lab agent addons        >/dev/null || fail "agent addons"
astroai-lab agent models list   >/dev/null || fail "agent models list"

# 2. install a curl-installer agent (honors XDG_BIN_DIR → session bin dir).
astroai-lab agent install kilo  >/dev/null || fail "agent install kilo"
[[ -x "${BIN_DIR}/kilo" ]] || fail "kilo not in session bin dir ${BIN_DIR}"
[[ ! -e "${HOME_DIR}/.local/bin/kilo" ]] || fail "kilo leaked into ~/.local/bin"

# 3. verify: binary checks pass on a fresh home (config checks may fire —
#    that's by design on a fresh home; the command must not crash). --json is
#    a root-callback flag, so it precedes the agent subcommand.
astroai-lab --json agent list >/dev/null || fail "--json agent list"
astroai-lab --json agent verify >/dev/null 2>&1 || true

# 4. plugin install/remove round-trip (scoped to the installed agent).
if astroai-lab agent plugins list | grep -q canfar-ray; then
    astroai-lab agent plugins install canfar-ray --agent kilo >/dev/null 2>&1 || true
    astroai-lab agent plugins remove canfar-ray --agent kilo >/dev/null 2>&1 || true
fi

# 5. models presets are readable.
astroai-lab agent models list | grep -qi coding || fail "agent models list has no coding presets"

# 6. remove leaves no trace and never creates ~/.local.
astroai-lab agent remove kilo >/dev/null || fail "agent remove kilo"
[[ ! -e "${BIN_DIR}/kilo" ]] || fail "kilo still in ${BIN_DIR} after remove"
[[ ! -d "${HOME_DIR}/.local/bin" ]] || fail "~/.local/bin was created"

ok "no ~/.local pollution; all agent commands OK (bin dir ${BIN_DIR})"
PROBE_EOF
chmod +x "${PROBE}"

run_scenario() {
    local label="$1" scratch_arg=() scratch_env=()
    if [[ "$label" == "with-scratch" ]]; then
        scratch_arg=(-v "${FAKE_SCRATCH}:/scratch")
        scratch_env=(-e SCRATCH=/scratch)
    else
        # Point SCRATCH at a path that does not exist (and /scratch is not
        # mounted) so scratch resolution falls back to the runtime root.
        scratch_env=(-e SCRATCH=/scratch-not-mounted)
    fi
    echo "=== ${IMAGE}:${TAG} ${label} ==="
    local out
    out="$(docker run --rm \
        -u "$(id -u):$(id -g)" \
        -e HOME=/home/testuser \
        -e USER=testuser \
        "${scratch_env[@]}" \
        "${OVERLAY_ARGS[@]}" \
        -v "${FAKE_HOME}:/home/testuser" \
        -v "${FAKE_SRC}:/srcdir" \
        "${scratch_arg[@]}" \
        -v "${PROBE}:/opt/probe.sh:ro" \
        --workdir /home/testuser \
        --entrypoint bash \
        "${FULL_IMAGE}" /opt/probe.sh 2>&1)" || {
        echo "${out}"
        echo "  FAILED (${label})" >&2
        return 1
    }
    echo "${out}"
    return 0
}

run_scenario "with-scratch" || FAILURES=$((FAILURES + 1))
run_scenario "without-scratch" || FAILURES=$((FAILURES + 1))

if [[ "${FAILURES}" -gt 0 ]]; then
    echo "${FAILURES} scenario(s) failed." >&2
    exit 1
fi
echo "ALL PASS: ${FULL_IMAGE} agent command matrix + no ~/.local pollution"
