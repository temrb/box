#!/bin/bash
# Native cache hygiene must apply to ordinary launches as well as verification.
set -euo pipefail
umask 077
for parent in /persist/data /persist/data/opencode /persist/data/opencode/opencode; do
  [[ ! -L "$parent" ]] || { echo 'FAIL: redirected native OpenCode cache parent' >&2; exit 1; }
done
# v2 credentials, sessions and saved approvals live in SQLite. Guard its journals too.
for cache in /persist/data/opencode/opencode/opencode.db /persist/data/opencode/opencode/opencode.db-wal /persist/data/opencode/opencode/opencode.db-shm; do
  if [[ -e "$cache" || -L "$cache" ]]; then
    [[ ! -L "$cache" && -f "$cache" && "$(stat -c %u "$cache")" == "$(id -u)" && "$(stat -c %a "$cache")" == 600 && -w "$cache" ]] || {
      echo 'FAIL: unsafe native OpenCode authentication cache owner/mode/writability' >&2
      exit 1
    }
  fi
done
if [[ "${BOX_OPENCODE_SHELL:-0}" == 1 ]]; then
  exec /bin/bash "$@"
fi
exec /usr/local/bin/opencode "$@"
