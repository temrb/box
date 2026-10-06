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
# Serialize preference resets for this persistent volume (released before exec).
for parent in /persist/config /persist/config/opencode; do
  [[ ! -L "$parent" ]] || { echo 'FAIL: redirected preference parent' >&2; exit 1; }
done
mkdir -p /persist/config/opencode
[[ ! -L /persist/config/opencode/.box-launch.lock ]] || { echo 'FAIL: redirected preference lock' >&2; exit 1; }
exec 9>/persist/config/opencode/.box-launch.lock
flock -x 9
for preference in cli.json tui.json opencode.jsonc; do
  file=/persist/config/opencode/$preference
  if [[ -e "$file" || -L "$file" ]]; then
    [[ ! -L "$file" && -f "$file" && "$(stat -c %u "$file")" == "$(id -u)" ]] || { echo "FAIL: unsafe preference file: $file" >&2; exit 1; }
    [[ ! -L "$file.box-legacy" ]] || { echo "FAIL: redirected preference backup: $file" >&2; exit 1; }
    if [[ ! -e "$file.box-legacy" ]]; then
      cp -- "$file" "$file.box-legacy"
      chmod 600 "$file.box-legacy"
    else
      [[ -f "$file.box-legacy" && "$(stat -c %u "$file.box-legacy")" == "$(id -u)" && "$(stat -c %a "$file.box-legacy")" =~ ^(600|400)$ ]] || { echo "FAIL: unsafe preference backup: $file" >&2; exit 1; }
    fi
    rm -- "$file"
  fi
done
# Release the preference lock before exec: it serializes resets only, never
# the client lifetime (a held lock would block concurrent runs silently).
flock -u 9
exec 9>&-
if [[ "${BOX_OPENCODE_SHELL:-0}" == 1 ]]; then
  /bin/bash "$@"
  exit $?
fi
/usr/local/bin/opencode "$@"
