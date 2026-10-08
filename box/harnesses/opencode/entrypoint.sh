#!/bin/bash
# Native cache hygiene must apply to ordinary launches as well as verification.
# When /run/box-auth is mounted (auth-managed runs), this entrypoint installs
# the canonical envelope into the mixed SQLite database before exec, then
# collects refresh/login/logout changes, commits the canonical revision,
# scrubs only the projection and marks the lease idle. Selection sidecars
# stay in project state (/persist/state/opencode/box-auth-selection.json).
set -euo pipefail
export BOX_TOOL=box-opencode
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
# Auth-managed projection (only when the host mounted /run/box-auth).
BOX_AUTH_DIR=/run/box-auth
BOX_DB=/persist/data/opencode/opencode/opencode.db
BOX_ADAPTER=/usr/local/bin/box-auth-opencode.sh
if [[ -d "$BOX_AUTH_DIR" && -f "$BOX_AUTH_DIR/credentials.json" && -f "$BOX_AUTH_DIR/lease.json" ]]; then
  command -v python3 >/dev/null 2>&1 || { echo 'FAIL: python3 is required for auth projection' >&2; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo 'FAIL: jq is required for auth projection' >&2; exit 1; }
  [[ -f /usr/local/bin/box-supervisor.sh && -f "$BOX_ADAPTER" ]] || { echo 'FAIL: auth supervisor/adapter missing from image (rebuild the image; old images without the supervisor contract are rejected)' >&2; exit 1; }
  # shellcheck source=lib/supervisor.sh
  source /usr/local/bin/box-supervisor.sh
  box_supervisor_validate "$BOX_AUTH_DIR" opencode || { echo 'FAIL: auth lease is not active or identity mismatch' >&2; exit 1; }
  # Stop the native background service before touching the database (when present).
  python3 -I /usr/local/bin/box-supervisor-process.py --native-exe /usr/local/bin/opencode || { echo 'FAIL: native service shutdown failed' >&2; exit 1; }
  # Volume-backed migration gate (container-side, non-secret metadata only):
  # when no migration record exists and the project database already holds
  # credential rows, refuse to overwrite them with an empty canonical
  # envelope. The operator must run an explicit auth-migrate (with --db-path
  # export) or auth-init before the first managed launch. Fresh databases
  # (absent or no credential table/rows) proceed.
  if [[ ! -f "$BOX_AUTH_DIR/migration.json" ]]; then
    if [[ -f "$BOX_DB" ]] && python3 -I - "$BOX_DB" 2>/dev/null <<'PY'; then
import sqlite3, sys
db = sys.argv[1]
con = sqlite3.connect(db, timeout=10)
try:
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if "credential" in tables:
        n = con.execute('SELECT COUNT(*) FROM "credential"').fetchone()[0]
        sys.exit(0 if n == 0 else 10)
    sys.exit(0)
finally:
    con.close()
PY
      : # fresh or empty: proceed to install (native initialization below).
    else
      rc=$?
      if [[ "$rc" == 10 ]]; then
        echo 'FAIL: legacy OpenCode credentials exist without migration (project database holds credential rows but no migration record). Run auth-migrate with an explicit --db-path export, or auth-init for a fresh identity.' >&2
        exit 1
      fi
      # Unreadable database: let the adapter validation fail closed below.
    fi
    # Canonical non-tombstone already present also satisfies the gate (the
    # identity was acknowledged via auth-copy or a prior managed run).
    if [[ -f "$BOX_AUTH_DIR/credentials.json" ]] && jq -e '.tombstone == false' -- "$BOX_AUTH_DIR/credentials.json" >/dev/null 2>&1; then
      : # acknowledged canonical: proceed.
      :
    fi
  fi
  # Disable uncontrolled legacy auth.json import after migration: the native
  # v2 importer must never resurrect a retired legacy file. A migration marker
  # cannot authorize a newly introduced file. Preserve it and refuse startup;
  # quarantine requires a separately authorized legacy migration.
  for _legacy_candidate in /persist/config/opencode/auth.json /persist/data/opencode/auth.json /persist/data/opencode/opencode/auth.json; do
    if [[ -e "$_legacy_candidate" || -L "$_legacy_candidate" ]]; then
      echo "FAIL: legacy auth.json at $_legacy_candidate must be explicitly quarantined outside the native importer paths before managed launch." >&2
      exit 1
    fi
  done
  unset _legacy_candidate
  # The pinned client owns schema creation and migrations. The adapter refuses
  # absent/partial schemas rather than synthesizing upstream tables.
  box_supervisor_phase "$BOX_AUTH_DIR" preparing || { echo 'FAIL: cannot record native preparation' >&2; exit 1; }
  /usr/local/bin/opencode auth list >/dev/null || { echo 'FAIL: native database initialization failed' >&2; exit 1; }
  python3 -I /usr/local/bin/box-supervisor-process.py --native-exe /usr/local/bin/opencode || { echo 'FAIL: initialization service shutdown failed' >&2; exit 1; }
  BOX_AUTH_HELPER=/usr/local/bin/box-auth-state.py
  export BOX_AUTH_HELPER
  BOX_SIDECAR=/persist/state/opencode/box-auth-selection.json
  BOX_AUTH_ID=$(jq -c '{harness,uid,scope,project_hash}' -- "$BOX_AUTH_DIR/identity.json" 2>/dev/null | sha256sum) || { echo 'FAIL: cannot derive auth identity key' >&2; exit 1; }
  BOX_AUTH_ID=${BOX_AUTH_ID%% *}
  [[ "$BOX_AUTH_ID" =~ ^[0-9a-f]{64}$ ]] || { echo 'FAIL: cannot derive auth identity key' >&2; exit 1; }
  box_supervisor_install opencode "$BOX_AUTH_DIR" "$BOX_DB" "$BOX_ADAPTER" || { echo 'FAIL: auth projection install failed' >&2; exit 1; }
  # Restore the remembered selection for this auth identity only when its
  # credential still exists; otherwise the run starts unselected.
  python3 -I "$BOX_AUTH_HELPER" restore-selection --db "$BOX_DB" --sidecar "$BOX_SIDECAR" --auth-id "$BOX_AUTH_ID" || { echo 'FAIL: auth selection restore failed' >&2; exit 1; }
  # shellcheck disable=SC2317,SC2329 # Invoked indirectly by the EXIT trap.
  box_auth_collect() {
    local rc=$?
    # Reap background service before collection; never edit concurrently.
    local -a stop_args=(--native-exe /usr/local/bin/opencode)
    local group=${BOX_NATIVE_GROUP:-${!:-}}
    [[ -z "$group" ]] || stop_args+=(--group "$group")
    python3 -I /usr/local/bin/box-supervisor-process.py "${stop_args[@]}" || { echo 'FAIL: native processes still active; collection refused' >&2; exit 1; }
    if [[ -n "$group" ]]; then wait "$group" 2>/dev/null || true; fi
    if python3 -I "$BOX_AUTH_HELPER" save-selection --db "$BOX_DB" --sidecar "$BOX_SIDECAR" --auth-id "$BOX_AUTH_ID" \
      && box_supervisor_collect opencode "$BOX_AUTH_DIR" "$BOX_DB" "$BOX_ADAPTER"; then
      :
    else
      echo 'FAIL: auth collection failed; projection remains authoritative' >&2
      exit 1
    fi
    return "$rc"
  }
  trap box_auth_collect EXIT
  # The pinned native client can otherwise choose an unselected saved account.
  # Keep auth/debug operations available to make the selection without a turn.
  # Shells retain the managed lease for explicit native credential operations.
  if [[ "${BOX_OPENCODE_SHELL:-0}" != 1 ]]; then
    case "${1:-}" in
      auth|debug|--help|-h|--version|-v) ;;
      *) python3 -I "$BOX_AUTH_HELPER" require-selection --db "$BOX_DB" || exit 1 ;;
    esac
  fi
fi
# Put ordinary and shell clients into a distinct process group. Kill remaining
# group members/services and reap the direct child before the EXIT collection.
BOX_NATIVE_GROUP=""
# shellcheck disable=SC2317,SC2329 # Invoked indirectly by INT/TERM/HUP traps.
forward_signal() {
  local signal=$1 status=$2 group=${BOX_NATIVE_GROUP:-${!:-}}
  if [[ "$group" =~ ^[0-9]+$ ]]; then kill -s "$signal" -- "-$group" 2>/dev/null || true; fi
  exit "$status"
}
trap 'forward_signal INT 130' INT
trap 'forward_signal TERM 143' TERM
trap 'forward_signal HUP 129' HUP
if [[ "${BOX_OPENCODE_SHELL:-0}" == 1 ]]; then
  setsid /bin/bash "$@" <&0 &
else
  setsid /usr/local/bin/opencode "$@" <&0 &
fi
BOX_NATIVE_GROUP=$!
rc=0
wait "$BOX_NATIVE_GROUP" || rc=$?
exit "$rc"
