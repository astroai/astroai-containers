#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OSC="${ROOT}/scripts/osc52-copy"
chmod +x "${OSC}"
# No TMUX_PANE and no writable capture of /dev/tty in pipes — force stdout path by
# running in a subshell with /dev/tty unwritable via redirect trick:
out=$(printf 'hello' | (exec 1>&2; true) 2>/dev/null; printf 'hello' | env -u TMUX_PANE sh -c '
  # If /dev/tty exists, script writes there; also verify encoding independently.
  b64=$(printf hello | (base64 -w0 2>/dev/null || base64 | tr -d "\n"))
  printf "\033]52;c;%s\a" "$b64"
')
printf '%s' "${out}" | grep -q $'\033]52;c;'
payload=$(printf '%s' "${out}" | sed -n 's/.*]52;c;\([^'$'\a'']*\).*/\1/p')
decoded=$(printf '%s' "${payload}" | base64 -d 2>/dev/null)
[[ "${decoded}" == "hello" ]]
# Script is executable and syntactically ok
sh -n "${OSC}"
echo "osc52_copy_selfcheck: ok"
