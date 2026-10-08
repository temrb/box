# shellcheck shell=bash
# box/lib/supervisor.sh — image-installed supervised execution wrapper.
# Validates the reserved lease and adapter version, owns runtime locks,
# installs auth, runs the client, exports, commits, scrubs and marks idle.
# Host reserves via box_auth_lease_reserve; this supervisor runs inside the
# container with /run/box-auth mounted (writable, object dir only).
# Never granted Docker socket access.
#
# Host-side file harnesses (muse/codex) perform install/collect/scrub from
# the launcher EXIT trap because the native auth.json lives on a host bind.
# The OpenCode entrypoint sources this file in-image and follows the same
# nine steps for its volume-backed SQLite projection. Both paths keep the
# same contract: validate reservation, install, run/reap, export, commit,
# scrub, mark idle. A shell run uses the wrapper too: it can execute native
# login/logout or alter credential storage.
#
# No harness-name branches: callers pass the registry-declared adapter file
# explicitly (the entrypoint knows its own adapter path statically; the
# host passes box_state_field <id> auth adapter). The expected harness id
# is only compared against the non-secret identity document.
[[ -n "${_BOX_SUPERVISOR_LOADED:-}" ]] && return 0
_BOX_SUPERVISOR_LOADED=1
: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Validate a reserved lease for <auth-dir> owned by <harness>.
# Checks object leaves, identity harness/schema, and active lease state.
# Pure check: no mutation, no secret output. Returns 0 when the supervisor
# may proceed, 1 otherwise (callers FAIL with context).
box_supervisor_validate() {
  local auth_dir=${1:-} harness=${2:-}
  [[ -n "$auth_dir" && -n "$harness" ]] || return 1
  [[ -d "$auth_dir" ]] || return 1
  [[ -f "$auth_dir/identity.json" && -f "$auth_dir/credentials.json" && -f "$auth_dir/lease.json" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg h "$harness" '.harness == $h and .schema_version == 1' -- "$auth_dir/identity.json" >/dev/null 2>&1 || return 1
  jq -e '.state == "active"' -- "$auth_dir/lease.json" >/dev/null 2>&1 || return 1
  # Adapter contract version is pinned with the image (Dockerfile
  # org.box.auth-contract=3); the envelope schema remains version 1.
  jq -e --arg h "$harness" 'type == "object" and .schema_version == 1 and .harness == $h and .adapter_schema == 1 and (.tombstone | type == "boolean")' \
    -- "$auth_dir/credentials.json" >/dev/null 2>&1 || return 1
}


# Publish the preparation boundary before modifying native auth. A reserved
# lease has not touched its native store; older leases without a phase remain
# conservatively recoverable projections, never presumed empty reservations.
box_supervisor_phase() {
  python3 -I - "$1/lease.json" "$2" <<'PHASE'
import json, os, stat, sys, tempfile
path, phase = sys.argv[1:]
if phase not in ("reserved", "preparing", "projected"):
    raise ValueError("invalid projection phase")
info = os.lstat(path)
if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
    raise ValueError("unsafe lease")
with open(path, encoding="utf-8") as stream:
    doc = json.load(stream)
if doc.get("state") != "active":
    raise ValueError("projection phase requires an active lease")
doc["phase"] = phase
fd, tmp = tempfile.mkstemp(prefix=".lease-phase.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(doc, stream, separators=(",", ":"))
    stream.write("\n")
    stream.flush()
    os.fsync(stream.fileno())
os.replace(tmp, path)
fd = os.open(os.path.dirname(path), os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(fd)
finally:
    os.close(fd)
PHASE
}

# Install the canonical envelope at <auth-dir>/credentials.json into the
# native store at <native-path> using the adapter file at <adapter-file>.
# Usage: box_supervisor_install <harness> <auth-dir> <native-path> <adapter-file>
box_supervisor_install() {
  local harness=${1:-} auth_dir=${2:-} native=${3:-} adapter=${4:-}
  [[ -n "$harness" && -n "$auth_dir" && -n "$native" && -n "$adapter" ]] || return 1
  [[ -f "$adapter" ]] || return 1
  # shellcheck disable=SC1090 # caller-provided registry-declared adapter path
  source "$adapter" || return 1
  box_supervisor_phase "$auth_dir" preparing || return 1
  box_adapter_install "$auth_dir/credentials.json" "$native" || return 1
  box_supervisor_phase "$auth_dir" projected || return 1
}

# Collect the native store at <native-path> back into the canonical
# envelope (bumping revision atomically under the single-writer lease),
# scrub only the projection, and mark the lease idle. Logout (native
# removal) commits a tombstone. The projection stays authoritative on
# failure: a failed collection leaves the lease active for recovery and
# never restores stale credentials.
# Usage: box_supervisor_collect <harness> <auth-dir> <native-path> <adapter-file>
box_supervisor_collect() {
  local harness=${1:-} auth_dir=${2:-} native=${3:-} adapter=${4:-}
  [[ -n "$harness" && -n "$auth_dir" && -n "$native" && -n "$adapter" ]] || return 1
  [[ -f "$adapter" ]] || return 1
  # shellcheck disable=SC1090 # caller-provided registry-declared adapter path
  source "$adapter" || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local tmp rev
  tmp=$(mktemp "$auth_dir/.credentials.XXXXXX") || return 1
  if ! box_adapter_collect "$native" "$tmp"; then rm -f -- "$tmp"; return 1; fi
  if ! jq -e --arg h "$harness" 'type == "object" and .schema_version == 1 and .harness == $h and (.tombstone | type == "boolean")' \
    -- "$tmp" >/dev/null 2>&1; then rm -f -- "$tmp"; return 1; fi
  rev=$(jq -r '.revision // 0' -- "$auth_dir/credentials.json" 2>/dev/null || printf '0')
  [[ "$rev" =~ ^[0-9]+$ ]] || rev=0
  if ! jq --argjson rev "$((rev + 1))" '.revision = $rev' -- "$tmp" >"$tmp.rev"; then rm -f -- "$tmp" "$tmp.rev"; return 1; fi
  chmod 600 -- "$tmp.rev" || { rm -f -- "$tmp" "$tmp.rev"; return 1; }
  cp -- "$tmp.rev" "$tmp.pending" || return 1
  chmod 600 -- "$tmp.pending" || return 1
  python3 -I - "$tmp.pending" "$auth_dir/collection-pending.json" <<'PYFLUSH' || return 1
import os, sys
src, dst = sys.argv[1:]
with open(src, "rb") as f:
    os.fsync(f.fileno())
os.replace(src, dst)
fd = os.open(os.path.dirname(dst), os.O_RDONLY)
try:
    os.fsync(fd)
finally:
    os.close(fd)
PYFLUSH
  mv -f -- "$tmp.rev" "$auth_dir/credentials.json" || { rm -f -- "$tmp" "$tmp.rev"; return 1; }
  rm -f -- "$tmp"
  box_adapter_scrub "$native" || return 1
  python3 -I - "$auth_dir/lease.json" <<'PY' || return 1
import json, os, sys, tempfile
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    doc = json.load(f)
with open(os.path.join(os.path.dirname(path), "credentials.json"), "rb") as canonical:
    os.fsync(canonical.fileno())
doc["state"] = "idle"
doc.pop("projection", None)
doc.pop("projection_lock", None)
doc.pop("phase", None)
fd, tmp = tempfile.mkstemp(prefix=".lease.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(doc, f, separators=(",", ":"))
    f.write("\n")
    f.flush()
    os.fsync(f.fileno())
os.replace(tmp, path)
fd = os.open(os.path.dirname(path), os.O_RDONLY)
try:
    os.fsync(fd)
finally:
    os.close(fd)
PY
  chmod 600 -- "$auth_dir/lease.json" || return 1
  rm -f -- "$auth_dir/collection-pending.json" || return 1
}

# Supervised run: validate reservation, install, execute <cmd...>, then
# collect/commit/scrub/idle. Returns the client exit status; a failed
# collection propagates failure while keeping the lease active for
# recovery. Callers set an EXIT trap on this function when the client must
# be reaped on signals.
# Usage: box_supervisor_run <harness> <auth-dir> <native-path> <adapter-file> -- <cmd...>
box_supervisor_run() {
  local harness=${1:-} auth_dir=${2:-} native=${3:-} adapter=${4:-}
  [[ -n "$harness" && -n "$auth_dir" && -n "$native" && -n "$adapter" ]] || return 1
  shift 4
  [[ "${1:-}" == -- ]] || return 1
  shift
  (($# > 0)) || return 1
  box_supervisor_validate "$auth_dir" "$harness" || return 1
  box_supervisor_install "$harness" "$auth_dir" "$native" "$adapter" || return 1
  local rc=0
  "$@" || rc=$?
  box_supervisor_collect "$harness" "$auth_dir" "$native" "$adapter" || return 1
  return "$rc"
}
