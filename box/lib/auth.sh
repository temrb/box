# shellcheck shell=bash
# box/lib/auth.sh — shared auth-scope policy, canonical store and lease layer.
# Backs the declarative auth state in lib/tools.sh. Never branches on harness
# names: harness identity comes from the registry (git_prefix, default_scope,
# adapter); storage mechanics come from the declared adapter.
# Requires lib/preflight.sh + lib/tools.sh + lib/config-file.sh + lib/test-state.sh.
# shellcheck disable=SC2034,SC2154 # policy globals cross files.
[[ -n "${_BOX_AUTH_LOADED:-}" ]] && return 0
_BOX_AUTH_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

_auth_src=${BASH_SOURCE[0]}
if command -v realpath >/dev/null 2>&1; then
  _auth_src=$(realpath -- "$_auth_src" 2>/dev/null || printf '%s' "$_auth_src")
elif command -v readlink >/dev/null 2>&1; then
  _auth_src=$(readlink -f -- "$_auth_src" 2>/dev/null || printf '%s' "$_auth_src")
fi
_auth_dir=$(dirname -- "$_auth_src")
unset _auth_src
# shellcheck source=lib/tools.sh
source "$_auth_dir/tools.sh"
# shellcheck source=lib/test-state.sh
source "$_auth_dir/test-state.sh"
# shellcheck source=lib/config-file.sh
source "$_auth_dir/config-file.sh"
# shellcheck source=lib/supervisor.sh
source "$_auth_dir/supervisor.sh"
unset _auth_dir

BOX_AUTH_SCHEMA_VERSION=1

# Validate a scope string (exactly global|project).
box_auth_valid_scope() {
  case "${1:-}" in global|project) return 0 ;; *) return 1 ;; esac
}

# Selected state configuration file. Prints path or nothing for valid
# pre-upgrade absence. Dies on explicit-missing, unreadable or unsafe files.
# Selection: explicit BOX_STATE_CONFIG, else implicit ~/.config/box/state.toml.
box_auth_config_file() {
  local has_explicit=0 explicit="" implicit="$HOME/.config/box/state.toml"
  if [[ -n "${BOX_STATE_CONFIG+x}" ]]; then
    has_explicit=1
    explicit=${BOX_STATE_CONFIG}
    [[ -n "$explicit" ]] || die 'BOX_STATE_CONFIG must not be empty.'
  fi
  if ((has_explicit)); then
    [[ "$explicit" == /* ]] || die 'BOX_STATE_CONFIG must be an absolute path.'
    [[ -f "$explicit" && -r "$explicit" ]] || die 'Missing readable BOX_STATE_CONFIG.'
    [[ ! -L "$explicit" ]] || die 'State configuration must not be a symlink.'
    box_plan_directory "$(dirname -- "$explicit")" >/dev/null || return 1
    explicit=$(box_realpath -e -- "$explicit") || die 'Cannot resolve BOX_STATE_CONFIG.'
    case "$explicit" in *','*|*$'\n'*) die 'Invalid BOX_STATE_CONFIG path.';; esac
    box_assert_outside_project "$explicit" 'State configuration'
    if [[ -n "${host_uid:-}" ]]; then
      box_assert_owner_mode "$explicit" 'State configuration' nowrite
    fi
    printf '%s' "$explicit"
    return 0
  fi
  box_plan_directory "$(dirname -- "$implicit")" >/dev/null || return 1
  if [[ ! -e "$implicit" && ! -L "$implicit" ]]; then return 0; fi
  [[ ! -L "$implicit" && -f "$implicit" && -r "$implicit" ]] || die 'Unsafe default state configuration.'
  implicit=$(box_realpath -e -- "$implicit") || die 'Cannot resolve state configuration.'
  box_assert_outside_project "$implicit" 'State configuration'
  if [[ -n "${host_uid:-}" ]]; then
    box_assert_owner_mode "$implicit" 'State configuration' nowrite
  fi
  printf '%s' "$implicit"
}

# Parse and validate state.toml, printing KEY=value lines:
#   schema_version, default_scope (maybe empty), <id>.scope (maybe empty).
# Dies on unsupported schema, wrong types, empty strings, unknown keys.
# Usage: box_auth_parse_config <file>
box_auth_parse_config() {
  local file=${1:-}
  [[ -n "$file" ]] || return 0
  box_config_validate "$file" toml || return 1
  BOX_TOOL=$BOX_TOOL python3 -I - "$file" "$box_tool_ids" <<'PY' || die 'Invalid state configuration.'
import sys, tomllib
path, ids = sys.argv[1], sys.argv[2].split()
with open(path, "rb") as f:
    try:
        data = tomllib.load(f)
    except ValueError:
        sys.exit(1)
allowed_top = {"schema_version", "auth"}
for k in data:
    if k not in allowed_top:
        sys.exit(1)
schema = data.get("schema_version", 1)
if type(schema) is not int or schema != 1:
    sys.exit(1)
result = [f"schema_version={schema}"]
auth = data.get("auth", {})
if not isinstance(auth, dict):
    sys.exit(1)
allowed_auth = {"default_scope", "harnesses"}
for k in auth:
    if k not in allowed_auth:
        sys.exit(1)
default = auth.get("default_scope")
if default is None:
    result.append("default_scope=")
else:
    if not isinstance(default, str) or default not in ("global", "project"):
        sys.exit(1)
    result.append(f"default_scope={default}")
harnesses = auth.get("harnesses", {})
if not isinstance(harnesses, dict):
    sys.exit(1)
for hid, table in harnesses.items():
    if hid not in ids:
        sys.exit(1)
    if not isinstance(table, dict):
        sys.exit(1)
    for k in table:
        if k != "scope":
            sys.exit(1)
    scope = table.get("scope")
    if scope is None:
        result.append(f"{hid}.scope=")
        continue
    if not isinstance(scope, str) or scope not in ("global", "project"):
        sys.exit(1)
    result.append(f"{hid}.scope={scope}")
for hid in ids:
    if hid not in harnesses:
        result.append(f"{hid}.scope=")
print("\n".join(result))
PY
}

# Resolve effective auth scope for a harness with documented precedence:
#   harness env > common env > harness config > common config > registry fallback.
# Env names derive from the registry git_prefix (<PREFIX>_AUTH_SCOPE).
# All supplied values are validated before resolution, including shadowed ones.
# Prints scope and source on two lines from one validated policy snapshot.
# Usage: result=$(box_auth_policy_result <harness>)
box_auth_policy_result() {
  local id=${1:-}
  box_require_tool "$id"
  if [[ -n "${BOX_AUTH_TRANSITION+x}" ]]; then
    case "$BOX_AUTH_TRANSITION" in fresh|use-existing) ;; *) die 'BOX_AUTH_TRANSITION must be fresh or use-existing.' ;; esac
  fi
  if [[ -n "${BOX_AUTH_RUNTIME+x}" ]]; then
    case "$BOX_AUTH_RUNTIME" in runsc|runc) ;; *) die 'BOX_AUTH_RUNTIME must be runsc or runc.' ;; esac
  fi
  local gpfx harness_var harness_val common_val cfg_file
  local harness_is_set=0 common_is_set=0
  gpfx=$(box_tool_field "$id" git_prefix)
  harness_var="${gpfx}_AUTH_SCOPE"
  # Indirect reads without harness literals. Track set-ness separately so a
  # literal "__unset__" value can never masquerade as unset.
  # shellcheck disable=SC2086
  if [[ -n "${!harness_var+x}" ]]; then harness_is_set=1; harness_val=${!harness_var}; else harness_val=""; fi
  if [[ -n "${BOX_AUTH_SCOPE+x}" ]]; then common_is_set=1; common_val=$BOX_AUTH_SCOPE; else common_val=""; fi
  local supplied_id supplied_var
  for supplied_id in $box_tool_ids; do
    supplied_var="$(box_tool_field "$supplied_id" git_prefix)_AUTH_SCOPE"
    if [[ -n "${!supplied_var+x}" ]]; then
      box_auth_valid_scope "${!supplied_var}" || die 'Invalid supplied harness auth scope (expected global or project).'
    fi
  done
  cfg_file=$(box_auth_config_file) || return 1
  local cfg_default_is_set=0 cfg_harness_is_set=0 cfg_default="" cfg_harness=""
  if [[ -n "$cfg_file" ]]; then
    local parsed line key val
    parsed=$(box_auth_parse_config "$cfg_file") || return 1
    while IFS= read -r line; do
      key=${line%%=*}; val=${line#*=}
      case "$key" in
        default_scope) if [[ -n "$val" ]]; then cfg_default_is_set=1; cfg_default=$val; fi ;;
        "$id.scope") if [[ -n "$val" ]]; then cfg_harness_is_set=1; cfg_harness=$val; fi ;;
      esac
    done <<<"$parsed"
    # Validate shadowed config values even when overridden by env.
    if ((cfg_default_is_set)); then
      box_auth_valid_scope "$cfg_default" || die 'Invalid auth scope in state configuration.'
    fi
    if ((cfg_harness_is_set)); then
      box_auth_valid_scope "$cfg_harness" || die 'Invalid auth scope in state configuration.'
    fi
  fi
  # Validate env values including shadowed lower precedence.
  if ((harness_is_set)); then
    [[ -n "$harness_val" ]] || die 'Auth scope must not be empty.'
    box_auth_valid_scope "$harness_val" || die 'Invalid auth scope (expected global or project).'
  fi
  if ((common_is_set)); then
    [[ -n "$common_val" ]] || die 'Auth scope must not be empty.'
    box_auth_valid_scope "$common_val" || die 'Invalid auth scope (expected global or project).'
  fi
  # Validate registry fallback.
  local fallback
  fallback=$(box_state_field "$id" auth default_scope)
  box_auth_valid_scope "$fallback" || die 'Invalid registry auth fallback.'
  # Select the value and its source from the same parse.
  local scope source
  if ((harness_is_set)); then scope=$harness_val; source="env:$harness_var"
  elif ((common_is_set)); then scope=$common_val; source=env:BOX_AUTH_SCOPE
  elif ((cfg_harness_is_set)); then scope=$cfg_harness; source="config:$cfg_file#harness"
  elif ((cfg_default_is_set)); then scope=$cfg_default; source="config:$cfg_file#default"
  else scope=$fallback; source=registry-fallback
  fi
  printf '%s\n%s' "$scope" "$source"
}

# Compatibility readers for callers that need only one policy field.
box_auth_policy_resolve() {
  local result
  result=$(box_auth_policy_result "${1:-}") || return 1
  printf '%s' "${result%%$'\n'*}"
}
box_auth_policy_source() {
  local result
  result=$(box_auth_policy_result "${1:-}") || return 1
  printf '%s' "${result#*$'\n'}"
}

# Canonical auth root R. Validates without creation.
# Usage: box_auth_root
box_auth_root() {
  local raw=""
  if [[ -n "${BOX_AUTH_ROOT+x}" ]]; then
    raw=${BOX_AUTH_ROOT}
    [[ -n "$raw" ]] || die 'BOX_AUTH_ROOT must not be empty.'
  else
    raw=$HOME/.config/box/auth
  fi
  [[ "$raw" == /* && "$raw" != *','* && "$raw" != *$'\n'* ]] || die 'Invalid BOX_AUTH_ROOT.'
  local planned
  planned=$(box_plan_directory "$raw") || return 1
  box_assert_project_disjoint "$planned" 'auth root'
  printf '%s' "$planned"
}

# State index directory (non-secret discovery metadata, never deletion authority).
box_auth_index_dir() {
  if box_test_in_test_mode; then
    local troot ns
    troot=$(box_test_task_root) || return 1
    ns=$(box_test_validate_ns) || return 1
    printf '%s/%s/state-index' "$troot" "$ns"
  else
    printf '%s/.config/box/state-index' "$HOME"
  fi
}

# This inode survives removal/recreation of the canonical object. Keep it
# outside the removable directory so a waiting launcher cannot lock a retired
# inode. Local locks are retained too for compatibility with existing clients.
box_auth_stable_lock() {
  local digest
  digest=$(printf '%s' "$1" | sha256sum) || return 1
  printf '%s/locks/auth-%s.lock' "$(box_auth_index_dir)" "${digest%% *}"
}

box_auth_open_stable_lock() {
  local path=$1
  box_prepare_directory "$(dirname -- "$path")" 700 >/dev/null || return 1
  [[ ! -L "$path" ]] || die 'Redirected stable auth lock.'
  if [[ ! -e "$path" ]]; then
    (umask 077; set -o noclobber; : >"$path") 2>/dev/null || [[ -f "$path" ]] || return 1
  fi
  [[ -f "$path" && ! -L "$path" ]] || die 'Unsafe stable auth lock.'
  box_assert_owner_mode "$path" 'Stable auth lock' creds
}

# Canonical auth object directory for (harness, scope, uid, project-hash?).
# Single production/test formula home: test mode delegates to the
# disposable test resolver so only one path formula exists per domain.
# Usage: box_auth_object_dir <harness> <scope> <uid> [project-hash]
box_auth_object_dir() {
  local id=${1:-} scope=${2:-} uid=${3:-} hash=${4:-}
  box_require_tool "$id"
  box_auth_valid_scope "$scope" || die 'Invalid auth scope.'
  [[ "$uid" =~ ^[0-9]+$ ]] || die 'Invalid auth UID.'
  ((10#$uid != 0)) || die 'Run as your normal non-root host user.'
  if box_test_in_test_mode; then
    local troot ns
    troot=$(box_test_task_root) || return 1
    ns=$(box_test_validate_ns) || return 1
    # Delegate to the single test formula (no duplicated path logic).
    box_test_auth_dir "$id" "$ns" "$uid" "$scope" "$hash" || return 1
    return 0
  else
    local rroot
    rroot=$(box_auth_root) || return 1
    if [[ "$scope" == global ]]; then
      printf '%s/%s/u%s/global' "$rroot" "$id" "$uid"
    else
      [[ "$hash" =~ ^[0-9a-f]{20}$ ]] || die 'Invalid project hash for project auth.'
      printf '%s/%s/u%s/projects/%s' "$rroot" "$id" "$uid" "$hash"
    fi
  fi
}

# Ensure an auth object directory with 700 dirs and 600 files.
# Creates identity.json (non-secret), credentials.json (empty/tombstone when
# fresh), lease.json (idle) and a stable lock inode (never replaced).
# Usage: box_auth_ensure_object <dir> <harness> <scope> <uid> [hash]
box_auth_ensure_object() {
  local dir=${1:-} id=${2:-} scope=${3:-} uid=${4:-} hash=${5:-}
  [[ -n "$dir" && -n "$id" && -n "$scope" && -n "$uid" ]] || die 'Internal error: missing auth object arguments.'
  box_require_tool "$id"
  local stable_lock ensure_fd held=0 held_path
  stable_lock=$(box_auth_stable_lock "$dir") || return 1
  [[ ! -e "$stable_lock.removal.json" && ! -L "$stable_lock.removal.json" ]] \
    || die 'Interrupted auth removal; rerun the exact state-remove operation before reuse.'
  for held_path in "${BOX_AUTH_STABLE_PATHS[@]}"; do
    [[ "$held_path" != "$stable_lock" ]] || held=1
  done
  if (( ! held )); then
    box_auth_open_stable_lock "$stable_lock" || return 1
    exec {ensure_fd}>>"$stable_lock" || return 1
    flock -n "$ensure_fd" || die 'Auth identity is busy.'
  fi
  box_plan_directory "$dir" >/dev/null || return 1
  box_prepare_directory "$dir" 700 >/dev/null || return 1
  local adapter schema existing_leaf
  for existing_leaf in identity.json credentials.json lease.json lock; do
    if [[ -e "$dir/$existing_leaf" || -L "$dir/$existing_leaf" ]]; then
      [[ ! -L "$dir/$existing_leaf" && -f "$dir/$existing_leaf" ]] || die 'Unsafe existing auth metadata.'
      box_assert_owner_mode "$dir/$existing_leaf" 'Auth object file' creds
    fi
  done
  adapter=$(box_state_field "$id" auth adapter)
  schema=$(box_state_field "$id" auth schema_version)
  if [[ ! -e "$dir/identity.json" ]]; then
    python3 -I - "$dir/identity.json" "$id" "$scope" "$uid" "$hash" "$adapter" "$schema" <<'PY' || die 'Cannot write auth identity.'
import json, sys
path, hid, scope, uid, h, adapter, schema = sys.argv[1:8]
doc = {"harness": hid, "scope": scope, "uid": int(uid), "adapter": adapter, "schema_version": int(schema)}
if scope == "project":
    doc["project_hash"] = h
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, separators=(",", ":"))
    f.write("\n")
PY
    chmod 600 -- "$dir/identity.json" || die 'Cannot secure auth identity.'
  fi
  if [[ ! -e "$dir/credentials.json" ]]; then
    python3 -I - "$dir/credentials.json" "$id" <<'PY' || die 'Cannot init auth envelope.'
import json, sys
path, hid = sys.argv[1], sys.argv[2]
with open(path, "w", encoding="utf-8") as f:
    json.dump({"schema_version": 1, "harness": hid, "adapter_schema": 1, "revision": 0, "tombstone": True, "payload": None}, f, separators=(",", ":"))
    f.write("\n")
PY
    chmod 600 -- "$dir/credentials.json" || die 'Cannot secure auth envelope.'
  fi
  if [[ ! -e "$dir/lease.json" ]]; then
    printf '{"state":"idle"}\n' >"$dir/lease.json" || die 'Cannot write auth lease.'
    chmod 600 -- "$dir/lease.json" || die 'Cannot secure auth lease.'
  fi
  if [[ ! -e "$dir/lock" ]]; then
    : >"$dir/lock" || die 'Cannot create auth lock.'
    chmod 600 -- "$dir/lock" || die 'Cannot secure auth lock.'
  fi
  jq -e --arg h "$id" --arg scope "$scope" --argjson uid "$uid" --arg hash "$hash" \
    --arg adapter "$adapter" --argjson schema "$schema" \
    '.harness == $h and .scope == $scope and .uid == $uid and .adapter == $adapter and .schema_version == $schema and
     (if $scope == "project" then .project_hash == $hash else (has("project_hash") | not) end)' \
    "$dir/identity.json" >/dev/null || die 'Auth metadata does not match resolved identity.'
  jq -e 'type == "object" and (.state == "idle" or
    (.state == "active" and (.projection | type == "string" and length > 0) and
     (.projection_lock | type == "string" and length > 0)))' "$dir/lease.json" >/dev/null \
    || die 'Invalid auth lease; manual recovery required.'
  # Harden existing metadata rather than silently repairing secrets.
  box_assert_owner_mode "$dir" 'Auth object' dir700
  for f in identity.json credentials.json lease.json lock; do
    [[ ! -L "$dir/$f" && -f "$dir/$f" ]] || die "Unsafe auth object file: $f"
    box_assert_owner_mode "$dir/$f" 'Auth object file' creds
  done
  # Retain discovery of past roots even after BOX_AUTH_ROOT changes.
  # This index grants no deletion authority; removal revalidates identities.
  if ! box_test_in_test_mode; then
    local roots_index
    roots_index="$(box_auth_index_dir)/auth-roots"
    box_prepare_directory "$roots_index" 700 >/dev/null || return 1
    python3 -I - "$roots_index" "$(box_auth_root)" <<'ROOTS' || die 'Cannot record auth root.'
import hashlib, os, stat, sys, tempfile
index, root = sys.argv[1:]
path = os.path.join(index, hashlib.sha256(root.encode()).hexdigest() + ".root")
if os.path.lexists(path):
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o600:
        raise ValueError("unsafe root record")
    if open(path, encoding="utf-8").read() != root + "\n":
        raise ValueError("conflicting root record")
else:
    fd, tmp = tempfile.mkstemp(prefix=".root.", dir=index)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(root + "\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
ROOTS
  fi
  if [[ -n "${ensure_fd:-}" ]]; then exec {ensure_fd}>&-; fi
}

# Deterministic lock ordering helper: print sorted lock paths.
# Usage: box_auth_sorted_locks <path...>
box_auth_sorted_locks() {
  printf '%s\n' "$@" | LC_ALL=C sort -u
}

# Acquire the same stable inodes for launch and operational transactions.
# Call in a subshell for operations so every error releases both descriptors.
box_auth_lock_pair() {
  local auth_dir=$1 proj_lock=$2 lock
  command -v flock >/dev/null 2>&1 || die 'flock is required for auth transactions.'
  local stable fd
  local -a stable_paths=()
  stable_paths+=("$(box_auth_stable_lock "$auth_dir")")
  if [[ "$proj_lock" == */lock && "$proj_lock" != "$auth_dir/lock" ]]; then
    stable_paths+=("$(box_auth_stable_lock "${proj_lock%/lock}")")
  fi
  BOX_AUTH_STABLE_FDS=()
  BOX_AUTH_STABLE_PATHS=()
  while IFS= read -r stable; do
    box_auth_open_stable_lock "$stable" || return 1
    exec {fd}>>"$stable" || return 1
    flock -n "$fd" || die 'Auth identity is busy.'
    BOX_AUTH_STABLE_FDS+=("$fd")
    BOX_AUTH_STABLE_PATHS+=("$stable")
  done < <(box_auth_sorted_locks "${stable_paths[@]}")
  while IFS= read -r lock; do
    box_plan_directory "$(dirname -- "$lock")" >/dev/null || return 1
    [[ ! -L "$lock" ]] || die 'Redirected auth transaction lock.'
    if [[ ! -e "$lock" ]]; then
      (umask 077; set -o noclobber; : >"$lock") 2>/dev/null || [[ -f "$lock" ]] || die 'Cannot create transaction lock.'
    fi
    [[ -f "$lock" && ! -L "$lock" ]] || die 'Unsafe auth transaction lock.'
    box_assert_owner_mode "$lock" 'Auth transaction lock' creds
    if [[ "$lock" == "$auth_dir/lock" ]]; then
      exec {BOX_AUTH_FD}>>"$lock" || die 'Cannot open auth lock.'
      flock -n "$BOX_AUTH_FD" || die 'Auth identity is busy.'
    else
      exec {BOX_AUTH_PROJ_FD}>>"$lock" || die 'Cannot open projection lock.'
      flock -n "$BOX_AUTH_PROJ_FD" || die 'Projection store is busy.'
    fi
  done < <(box_auth_sorted_locks "$auth_dir/lock" "$proj_lock")
}

box_auth_release_stable_locks() {
  local fd
  for fd in "${BOX_AUTH_STABLE_FDS[@]}"; do exec {fd}>&-; done
  BOX_AUTH_STABLE_FDS=()
  BOX_AUTH_STABLE_PATHS=()
}

# Publish lease metadata durably without truncating the previous checkpoint.
box_auth_write_lease() {
  python3 -I - "$@" <<'LEASE' || die 'Cannot publish auth lease.'
import json, os, sys, tempfile
path, state = sys.argv[1:3]
if state == "idle":
    # The durable pending checkpoint must outlive canonical publication.
    with open(os.path.join(os.path.dirname(path), "credentials.json"), "rb") as f:
        os.fsync(f.fileno())
with open(path, encoding="utf-8") as f:
    doc = json.load(f)
if doc.get("state") not in ("active", "idle"):
    raise ValueError("invalid lease state")
doc["state"] = state
if state == "active":
    doc.update(projection=sys.argv[3], projection_lock=sys.argv[4], phase="reserved")
else:
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
LEASE
}

# Reserve one active writer per auth identity plus its native projection lock.
# Fails promptly when busy (no indefinite wait). Records lease active with
# the authoritative projection coordinate: the native data path when given
# (file harnesses pass their auth.json; volume-backed stores pass a
# `volume:<name>` descriptor since the database itself is not a host path),
# else the projection lock path.
# Usage: box_auth_lease_reserve <auth-dir> <projection-lock-path> [projection-data-path]
box_auth_lease_reserve() {
  local auth_dir=${1:-} proj_lock=${2:-} proj_data=${3:-$2}
  [[ -n "$auth_dir" && -n "$proj_lock" && -n "$proj_data" ]] || die 'Internal error: missing lease arguments.'
  [[ -f "$auth_dir/lock" && -f "$auth_dir/lease.json" ]] || die 'Unknown auth identity.'
  command -v jq >/dev/null 2>&1 || die 'jq is required for auth lease reservation.'
  command -v flock >/dev/null 2>&1 || die 'flock is required for auth lease reservation.'
  box_auth_lock_pair "$auth_dir" "$proj_lock" || return 1
  # Refuse when a previous lease is still active: recover first. jq is
  # mandatory here; a missing parser must never look like an idle lease.
  if jq -e '.state == "active"' -- "$auth_dir/lease.json" >/dev/null 2>&1; then
    if [[ -n "${BOX_AUTH_PROJ_FD:-}" ]]; then exec {BOX_AUTH_PROJ_FD}>&-; unset BOX_AUTH_PROJ_FD; fi
    if [[ -n "${BOX_AUTH_FD:-}" ]]; then exec {BOX_AUTH_FD}>&-; unset BOX_AUTH_FD; fi
    box_auth_release_stable_locks
    die 'Auth lease is already active; recover it before launching.'
  fi
  box_auth_write_lease "$auth_dir/lease.json" active "$proj_data" "$proj_lock" || return 1
  chmod 600 -- "$auth_dir/lease.json"
}

# Mark lease idle and release reservation fds.
# Usage: box_auth_lease_release <auth-dir>
box_auth_lease_release() {
  local auth_dir=${1:-}
  [[ -n "$auth_dir" ]] || die 'Internal error: missing lease dir.'
  box_auth_write_lease "$auth_dir/lease.json" idle || return 1
  chmod 600 -- "$auth_dir/lease.json"
  rm -f -- "$auth_dir/collection-pending.json" || return 1
  if [[ -n "${BOX_AUTH_PROJ_FD:-}" ]]; then exec {BOX_AUTH_PROJ_FD}>&-; unset BOX_AUTH_PROJ_FD; fi
  if [[ -n "${BOX_AUTH_FD:-}" ]]; then exec {BOX_AUTH_FD}>&-; unset BOX_AUTH_FD; fi
  box_auth_release_stable_locks
}

# Recover an interrupted projection: the recorded native projection is
# authoritative until collected. A `volume:<name>` coordinate needs an
# explicit database export (never auto-opens a live volume). A missing
# filesystem projection during required recovery is an error, never
# permission to restore stale credentials.
# Usage: box_auth_recover <auth-dir>
box_auth_recover() {
  local auth_dir=${1:-}
  [[ -n "$auth_dir" ]] || die 'Internal error: missing auth dir.'
  [[ -f "$auth_dir/lease.json" ]] || die 'Unknown auth identity.'
  command -v jq >/dev/null 2>&1 || die 'jq is required for auth recovery.'
  jq -e '.state == "active"' -- "$auth_dir/lease.json" >/dev/null 2>&1 \
    || { printf '%s: auth lease is idle; nothing to recover.\n' "$BOX_TOOL" >&2; return 0; }
  local proj
  proj=$(jq -r '.projection // empty' -- "$auth_dir/lease.json") || die 'Cannot read auth lease.'
  [[ -n "$proj" ]] || die 'Active lease lacks a recorded projection.'
  case "$proj" in
    volume:*) die 'Volume-backed projection needs an explicit database export for recovery (never auto-opens a live volume).' ;;
  esac
  [[ -e "$proj" || -d "$proj" ]] || die 'Missing projection during required recovery.'
  printf '%s: recovered projection at %s (collect before reuse).\n' "$BOX_TOOL" "$proj" >&2
}

# Guard explicit auth removal: exact identity required, no globs/prefixes,
# never while active/unrecovered. Prints the inventoried paths.
# Usage: box_auth_guard_remove <auth-dir>
box_auth_guard_remove() {
  local auth_dir=${1:-}
  [[ -n "$auth_dir" ]] || die 'Refusing removal of an empty auth path.'
  case "$auth_dir" in *'*'*|*'?'*|*'['*) die 'Refusing wildcard auth removal.';; esac
  local removal_journal identity_file
  removal_journal="$(box_auth_stable_lock "$auth_dir").removal.json"
  identity_file="$auth_dir/identity.json"
  if [[ -e "$removal_journal" || -L "$removal_journal" ]]; then
    [[ ! -L "$removal_journal" && -f "$removal_journal" ]] || die 'Unsafe removal checkpoint.'
    box_assert_owner_mode "$removal_journal" 'Removal checkpoint' creds
    identity_file=$removal_journal
  else
  [[ -f "$auth_dir/identity.json" && -f "$auth_dir/credentials.json" && -f "$auth_dir/lease.json" && -f "$auth_dir/lock" ]] \
    || die 'Refusing removal outside an exact auth identity.'
  fi
  command -v jq >/dev/null 2>&1 || die 'jq is required for auth removal guard.'
  local identity_id identity_scope identity_uid identity_hash expected
  identity_id=$(jq -er '.harness' "$identity_file") || die 'Invalid auth identity harness.'
  identity_scope=$(jq -er '.scope' "$identity_file") || die 'Invalid auth identity scope.'
  identity_uid=$(jq -er '.uid' "$identity_file") || die 'Invalid auth identity UID.'
  identity_hash=$(jq -r '.project_hash // empty' "$identity_file") || return 1
  [[ "$identity_uid" == "$(id -u)" ]] || die 'Foreign auth identity UID.'
  expected=$(box_auth_object_dir "$identity_id" "$identity_scope" "$identity_uid" "$identity_hash") || return 1
  [[ "$auth_dir" == "$expected" ]] || die 'Auth path does not match complete resolved identity.'
  if [[ "$identity_file" == "$removal_journal" ]]; then
    box_auth_removal_checkpoint inventory "$auth_dir" || return 1
    return 0
  fi
  # Inventory must be read-only: ensure_object creates missing metadata,
  # hardens directories and writes discovery records.
  box_plan_directory "$auth_dir" >/dev/null || return 1
  box_assert_owner_mode "$auth_dir" 'Auth object' dir700
  local leaf adapter schema
  for leaf in identity.json credentials.json lease.json lock; do
    [[ ! -L "$auth_dir/$leaf" && -f "$auth_dir/$leaf" ]] || die 'Unsafe auth object file.'
    box_assert_owner_mode "$auth_dir/$leaf" 'Auth object file' creds
  done
  adapter=$(box_state_field "$identity_id" auth adapter)
  schema=$(box_state_field "$identity_id" auth schema_version)
  jq -e --arg adapter "$adapter" --argjson schema "$schema" \
    '.adapter == $adapter and .schema_version == $schema' "$auth_dir/identity.json" >/dev/null \
    || die 'Auth metadata does not match the adapter contract.'
  jq -e 'type == "object" and (.state == "idle" or .state == "active")' \
    "$auth_dir/lease.json" >/dev/null || die 'Invalid auth lease; recover first.'
  if jq -e '.state == "active"' -- "$auth_dir/lease.json" >/dev/null 2>&1; then
    die 'Refusing removal of an active auth lease; recover first.'
  fi
  if [[ -e "$auth_dir/collection-pending.json" ]]; then
    die 'Refusing removal of pending auth collection; recover first.'
  fi
  if [[ -f "$auth_dir/migration-journal.json" ]]; then
    jq -e '.stage == "complete"' "$auth_dir/migration-journal.json" >/dev/null \
      || die 'Refusing removal of interrupted migration; recover first.'
  fi
  python3 -I - "$auth_dir" <<'INVENTORY' || die 'Unexpected or unsafe auth artifacts; resolve before removal.'
import os, stat, sys
root = sys.argv[1]
allowed = {"identity.json", "credentials.json", "lease.json", "lock", "migration.json",
           "migration-journal.json", "rollback-credentials.json", "legacy-auth-rollback.json"}
entries = sorted(os.listdir(root))
for name in entries:
    st = os.lstat(os.path.join(root, name))
    if name not in allowed or not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) not in (0o400, 0o600):
        raise ValueError("unsafe auth artifact")
for name in entries:
    print(os.path.join(root, name))
INVENTORY
}

# Call only while all stable/local identity locks are held. Journal metadata
# never authorizes a different path: guard_remove re-resolves its complete
# harness/UID/scope identity before this code inspects remaining members.
box_auth_removal_checkpoint() {
  local phase=$1 dir=$2 journal
  journal="$(box_auth_stable_lock "$dir").removal.json"
  python3 -I - "$phase" "$dir" "$journal" "${BOX_AUTH_REMOVE_FAULT:-}" <<'REMOVAL' || die 'Auth removal checkpoint failed; rerun the same exact removal after resolving the refusal.'
import hashlib, json, os, stat, sys, tempfile
phase, root, journal, fault = sys.argv[1:]
allowed = {"identity.json", "credentials.json", "lease.json", "lock", "migration.json",
           "migration-journal.json", "rollback-credentials.json", "legacy-auth-rollback.json"}
required = {"identity.json", "credentials.json", "lease.json", "lock"}

def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)

def signature(path):
    st = os.lstat(path)
    if (not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1
            or stat.S_IMODE(st.st_mode) not in (0o400, 0o600)):
        raise ValueError("unsafe removal member")
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    return {"sha256": digest, "mode": stat.S_IMODE(st.st_mode),
            "device": st.st_dev, "inode": st.st_ino}

if os.path.lexists(journal):
    signature(journal)
    with open(journal, encoding="utf-8") as f:
        doc = json.load(f)
    if (doc.get("operation") != "box-auth-remove-v1" or doc.get("path") != root
            or doc.get("uid") != os.getuid() or doc.get("adapter") != "harnesses/" + doc.get("harness", "") + "/auth.sh"
            or doc.get("schema_version") != 1 or not isinstance(doc.get("members"), dict)
            or not required <= doc["members"].keys() or not doc["members"].keys() <= allowed):
        raise ValueError("invalid removal checkpoint")
else:
    if phase != "prepare":
        raise ValueError("missing removal checkpoint")
    with open(os.path.join(root, "identity.json"), encoding="utf-8") as f:
        doc = json.load(f)
    names = set(os.listdir(root))
    if not required <= names or not names <= allowed:
        raise ValueError("unexpected removal members")
    doc.update(operation="box-auth-remove-v1", path=root,
               members={name: signature(os.path.join(root, name)) for name in sorted(names)})
    fd, tmp = tempfile.mkstemp(prefix=".removal-", dir=os.path.dirname(journal))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(doc, f, separators=(",", ":"))
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, journal)
        sync_dir(os.path.dirname(journal))
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)

remaining = []
if os.path.lexists(root):
    st = os.lstat(root)
    if (not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid()
            or stat.S_IMODE(st.st_mode) != 0o700 or os.path.realpath(root) != root):
        raise ValueError("unsafe removal directory")
    remaining = sorted(os.listdir(root))
    for name in remaining:
        if name not in doc["members"]:
            raise ValueError("unrecorded removal member")
        path = os.path.join(root, name)
        if phase == "inventory":
            # Metadata planning never reads credentials, including while a
            # removal checkpoint is pending. Execution verifies byte digests.
            info = os.lstat(path)
            expected = doc["members"][name]
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1
                    or stat.S_IMODE(info.st_mode) != expected["mode"]
                    or info.st_dev != expected["device"] or info.st_ino != expected["inode"]):
                raise ValueError("removal member metadata changed")
        elif signature(path) != doc["members"][name]:
            raise ValueError("removal member changed since publication")
if phase == "inventory":
    for name in remaining:
        print(os.path.join(root, name))
    print(journal)
elif phase == "execute":
    # Keep the original identity until every other member has been retired.
    ordered = sorted(remaining, key=lambda name: name == "identity.json")
    for index, name in enumerate(ordered, 1):
        path = os.path.join(root, name)
        if signature(path) != doc["members"][name]:
            raise ValueError("removal member changed before deletion")
        os.unlink(path)
        sync_dir(root)
        if fault == "delete-" + str(index):
            raise RuntimeError("injected removal interruption")
    if os.path.exists(root):
        os.rmdir(root)
        sync_dir(os.path.dirname(root))
    if fault == "directory":
        raise RuntimeError("injected removal interruption")
    os.unlink(journal)
    sync_dir(os.path.dirname(journal))
elif phase != "prepare":
    raise ValueError("unknown removal phase")
if phase == "prepare" and fault == "publication":
    raise RuntimeError("injected removal interruption")
REMOVAL
}

# Effective auth plan for dry-run: non-secret metadata only, no credential
# reads, DB opens, locks, writes, migration or Docker contact.
# Usage: box_auth_plan <harness> <uid> <project-hash>
box_auth_plan() {
  local id=${1:-} uid=${2:-} hash=${3:-}
  box_require_tool "$id"
  local scope source dir policy
  policy=$(box_auth_policy_result "$id") || return 1
  scope=${policy%%$'\n'*}
  source=${policy#*$'\n'}
  if [[ "$scope" == global ]]; then
    dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else
    dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1
  fi
  printf 'Auth scope: %s\nAuth policy source: %s\nAuth identity: %s/u%s/%s\nCanonical auth directory: %s\n' \
    "$scope" "$source" "$id" "$uid" "$scope" "$dir"
}

# Validate one canonical envelope without creating or opening a native store.
# Coordinates and header authority are checked before semantic adapter validation.
box_auth_verify_envelope() (
  local id=$1 envelope=$2 bundle=${3:-${BUNDLE_DIR:-${script_dir:-}}} adapter
  [[ -n "$bundle" ]] || bundle=$(dirname -- "$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")")")
  python3 -I - "$bundle/lib/host-fs.py" "$envelope" "$id" <<'VERIFY' || return 1
import importlib.util, sys
try:
    spec = importlib.util.spec_from_file_location("host_fs", sys.argv[1])
    fs = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fs)
    doc = fs.read_json(sys.argv[2])
    if (set(doc) != {"schema_version", "harness", "adapter_schema", "revision", "tombstone", "payload"}
            or type(doc["schema_version"]) is not int or doc["schema_version"] != 1
            or doc["harness"] != sys.argv[3]
            or type(doc["adapter_schema"]) is not int or doc["adapter_schema"] != 1
            or type(doc["revision"]) is not int or doc["revision"] < 0
            or type(doc["tombstone"]) is not bool
            or (doc["tombstone"] and doc["payload"] is not None)
            or (not doc["tombstone"] and type(doc["payload"]) is not dict)):
        raise ValueError("invalid envelope header")
except (OSError, ValueError, TypeError, KeyError):
    print("Auth envelope integrity validation refused.", file=sys.stderr)
    sys.exit(1)
VERIFY
  adapter=$(box_state_field "$id" auth adapter) || return 1
  # Prevent an inherited adapter capability from selecting another validator.
  unset -f box_adapter_verify_envelope
  # shellcheck disable=SC1090
  source "$bundle/$adapter"
  declare -F box_adapter_verify_envelope >/dev/null || return 1
  box_adapter_verify_envelope "$envelope"
)

# Install a canonical envelope into its native projection via the declared
# adapter (no harness branch: adapter path comes from the registry).
# Usage: box_auth_install_projection <harness> <auth-dir> <native-path> [bundle-dir]
box_auth_install_projection() {
  local id=${1:-} auth_dir=${2:-} native=${3:-} bundle=${4:-}
  box_require_tool "$id"
  [[ -n "$auth_dir" && -n "$native" ]] || die 'Internal error: missing projection arguments.'
  local adapter
  adapter=$(box_state_field "$id" auth adapter)
  [[ -n "$adapter" ]] || die 'Internal error: missing auth adapter.'
  if [[ -z "$bundle" ]]; then
    if [[ -n "${script_dir:-}" ]]; then bundle=$script_dir;
    elif [[ -n "${BUNDLE_DIR:-}" ]]; then bundle=$BUNDLE_DIR;
    else bundle=$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")"); bundle=$(dirname -- "$bundle"); fi
  fi
  [[ -f "$bundle/$adapter" ]] || die "Missing auth adapter: $adapter"
  # shellcheck disable=SC1090 # registry-declared adapter path
  source "$bundle/$adapter"
  box_supervisor_phase "$auth_dir" preparing || die 'Cannot record projection preparation.'
  box_adapter_install "$auth_dir/credentials.json" "$native" || die 'Cannot install auth projection.'
  box_supervisor_phase "$auth_dir" projected || die 'Cannot record installed projection.'
  # Record preparation before native mutation is already reflected in the
  # lease; identity stays non-secret and value-free.
}

# A failed/terminated Docker CLI can leave its container running. Collection
# must preserve the authoritative projection unless Engine exit is established.
box_auth_collection_stopped() {
  local dir=$1 holders
  [[ "${BOX_AUTH_CONTAINER_ATTEMPTED:-0}" != 1 ]] || {
    holders=$("${docker_cmd[@]}" ps -q --filter "volume=$dir") || {
      printf '%s: Cannot establish container exit; auth projection preserved for recovery.\n' "$BOX_TOOL" >&2
      return 1
    }
    [[ -z "$holders" ]] || {
      printf '%s: Container remains active; auth projection preserved for recovery.\n' "$BOX_TOOL" >&2
      return 1
    }
  }
}

# Collect a native projection back into its canonical envelope, then scrub
# only the projection. Logout (native removal) exports a tombstone.
# Usage: box_auth_collect_projection <harness> <auth-dir> <native-path> [bundle-dir]
box_auth_collect_projection() {
  local id=${1:-} auth_dir=${2:-} native=${3:-} bundle=${4:-}
  box_require_tool "$id"
  [[ -n "$auth_dir" && -n "$native" ]] || die 'Internal error: missing collect arguments.'
  local adapter tmp
  adapter=$(box_state_field "$id" auth adapter)
  if [[ -z "$bundle" ]]; then
    if [[ -n "${script_dir:-}" ]]; then bundle=$script_dir;
    elif [[ -n "${BUNDLE_DIR:-}" ]]; then bundle=$BUNDLE_DIR;
    else bundle=$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")"); bundle=$(dirname -- "$bundle"); fi
  fi
  # shellcheck disable=SC1090 # registry-declared adapter path
  source "$bundle/$adapter"
  tmp=$(mktemp "$auth_dir/.credentials.XXXXXX") || die 'Cannot stage auth commit.'
  box_adapter_collect "$native" "$tmp" || { rm -f -- "$tmp"; die 'Cannot collect auth projection.'; }
  # Validate envelope shape before publishing (no secret output).
  command -v jq >/dev/null 2>&1 || die 'jq is required for auth collection.'
  jq -e --arg h "$id" 'type == "object" and .schema_version == 1 and .harness == $h and (.tombstone | type == "boolean")' \
    -- "$tmp" >/dev/null 2>&1 || { rm -f -- "$tmp"; die 'Invalid collected auth envelope.'; }
  # Bump revision atomically without overwriting a concurrent winner: the
  # lease guarantees a single writer, so a plain publish is atomic here.
  local rev
  rev=$(jq -r '.revision // 0' -- "$auth_dir/credentials.json" 2>/dev/null || printf '0')
  [[ "$rev" =~ ^[0-9]+$ ]] || rev=0
  jq --argjson rev "$((rev + 1))" '.revision = $rev' -- "$tmp" >"$tmp.rev" || { rm -f -- "$tmp" "$tmp.rev"; die 'Cannot revision auth envelope.'; }
  chmod 600 -- "$tmp.rev" || { rm -f -- "$tmp" "$tmp.rev"; die 'Cannot secure auth envelope.'; }
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
  mv -f -- "$tmp.rev" "$auth_dir/credentials.json" || { rm -f -- "$tmp" "$tmp.rev"; die 'Cannot commit auth envelope.'; }
  rm -f -- "$tmp"
  box_adapter_scrub "$native" || die 'Cannot scrub native projection.'
}

# Migration gate for live launches: refuse when legacy credentials exist
# without a completed migration record. Dry-run callers use the non-reading
# variant (coordinates only). Returns 0 when launch may proceed.
# Usage: box_auth_migration_gate <harness> <auth-dir> <legacy-native-path> <migration-record>
box_auth_migration_gate() {
  local id=${1:-} auth_dir=${2:-} legacy=${3:-} record=${4:-}
  box_require_tool "$id"
  [[ -n "$auth_dir" && -n "$legacy" && -n "$record" ]] || die 'Internal error: missing migration gate arguments.'
  command -v jq >/dev/null 2>&1 || die 'jq is required for migration gate.'
  if [[ -f "$record" ]]; then return 0; fi
  local has_legacy=0 has_canonical=0
  if [[ -e "$legacy" || -L "$legacy" ]]; then
    # Non-secret presence check only; contents are read by explicit migration.
    if [[ -f "$legacy" && -s "$legacy" ]]; then has_legacy=1; fi
    if [[ -d "$legacy" ]]; then has_legacy=1; fi
  fi
  if [[ -f "$auth_dir/credentials.json" ]]; then
    if jq -e '.tombstone == false' -- "$auth_dir/credentials.json" >/dev/null 2>&1; then has_canonical=1; fi
  fi
  if ((has_legacy)) && (( ! has_canonical )); then
    die "Legacy auth exists without migration (harness $id): run 'make -C box auth-migrate HARNESS=$id' or 'box-auth --migrate $id', or acknowledge a fresh identity with 'make -C box auth-init HARNESS=$id'."
  fi
  return 0
}

# Dry-run migration/transition report: non-secret metadata only, no
# credential reads, DB opens, locks, writes, migration or Docker contact.
# Reports prospective canonical location, legacy coordinates, and whether a
# migration record or scope transition is still required.
# Usage: box_auth_dryrun_report <harness> <uid> <project-hash> <legacy-path>
box_auth_dryrun_report() {
  local id=${1:-} uid=${2:-} hash=${3:-} legacy=${4:-}
  box_require_tool "$id"
  local scope dir binding record
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then
    dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else
    dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1
  fi
  binding=$(box_auth_binding_file "$id" "$hash") || return 1
  record="$dir/migration.json"
  printf 'Migration required: %s\nLegacy candidate: %s\n' \
    "$([ -f "$record" ] && printf 'no (record present)' || printf 'yes-if-legacy-present (run auth-migrate|auth-init)')" \
    "${legacy:-none}"
  if [[ -f "$binding" && ! -L "$binding" ]]; then
    local acknowledged
    acknowledged=$(sed -n '1p' -- "$binding" 2>/dev/null || printf '')
    if [[ "$acknowledged" == "$dir" ]]; then
      printf 'Transition required: no (identity acknowledged)\n'
    else
      printf 'Transition required: yes (recorded %s != selected %s; set BOX_AUTH_TRANSITION=fresh|use-existing or auth-copy)\n' \
        "${acknowledged:-unknown}" "$dir"
    fi
  else
    printf 'Transition required: no (first acknowledgment records automatically on live launch)\n'
  fi
}

# Binding file recording the last acknowledged auth identity for one
# physical project/harness. Non-secret discovery metadata, never deletion
# authority. Path: <index>/bindings/<harness>/<project-hash>.
# Usage: box_auth_binding_file <harness> <project-hash>
box_auth_binding_file() {
  local id=${1:-} hash=${2:-} idx
  box_require_tool "$id"
  [[ "$hash" =~ ^[0-9a-f]{20}$ ]] || die 'Internal error: invalid project hash for auth binding.'
  idx=$(box_auth_index_dir) || return 1
  printf '%s/bindings/%s/%s' "$idx" "$id" "$hash"
}

# Publish acknowledgments without predictable temporary paths or torn writes.
box_auth_write_binding() {
  local binding=$1 identity=$2 physical=$3
  python3 -I - "$binding" "$identity" "$physical" <<'BINDING' || die 'Cannot publish auth binding.'
import os, stat, sys, tempfile
from pathlib import Path
path = Path(sys.argv[1])
for parent in (path.parent, *path.parent.parents):
    if not stat.S_ISDIR(parent.lstat().st_mode):
        raise ValueError("redirected binding parent")
if path.exists() or path.is_symlink():
    info = path.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600):
        raise ValueError("unsafe binding")
if any("\n" in value for value in sys.argv[2:]):
    raise ValueError("invalid binding coordinates")
fd, tmp = tempfile.mkstemp(prefix=".binding.", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(sys.argv[2] + "\n" + sys.argv[3] + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, path)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
BINDING
}

# Scope-change acknowledgment plan. Compares the last acknowledged auth
# identity for (harness, project-hash) against the currently selected
# identity. First acknowledgment records automatically; a change requires
# an explicit transition choice via BOX_AUTH_TRANSITION (fresh|use-existing)
# or an explicit auth-copy. Never copies, merges, overwrites, or deletes
# credentials implicitly, and never infers acknowledgment from elapsed
# time or from an empty store once a binding exists. The binding also
# retains the full physical project path: two different paths with the same
# truncated hash fail instead of sharing state.
# Usage: box_auth_transition_plan <harness> <uid> <project-hash> [project-path]
box_auth_transition_plan() {
  local id=${1:-} uid=${2:-} hash=${3:-} proj=${4:-${project:-}}
  box_require_tool "$id"
  [[ "$uid" =~ ^[0-9]+$ ]] || die 'Internal error: invalid auth UID.'
  ((10#$uid != 0)) || die 'Run as your normal non-root host user.'
  [[ "$hash" =~ ^[0-9a-f]{20}$ ]] || die 'Internal error: invalid project hash.'
  local scope dir binding acknowledged recorded_proj choice
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then
    dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else
    dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1
  fi
  binding=$(box_auth_binding_file "$id" "$hash") || return 1
  box_plan_directory "$(dirname -- "$binding")" >/dev/null || return 1
  if [[ ! -e "$binding" && ! -L "$binding" ]]; then
    box_plan_directory "$(dirname -- "$binding")" >/dev/null || return 1
    box_prepare_directory "$(dirname -- "$binding")" 700 >/dev/null || return 1
    box_auth_write_binding "$binding" "$dir" "${proj:-unknown}" || return 1
    return 0
  fi
  [[ ! -L "$binding" && -f "$binding" ]] || die 'Unsafe auth binding.'
  box_assert_owner_mode "$binding" 'Auth binding' creds
  [[ "$(stat -c %h -- "$binding")" == 1 ]] || die 'Unsafe shared auth binding.'
  acknowledged=$(sed -n '1p' -- "$binding") || die 'Cannot read auth binding.'
  recorded_proj=$(sed -n '2p' -- "$binding") || die 'Cannot read auth binding.'
  [[ -n "$acknowledged" ]] || die 'Invalid auth binding.'
  if [[ -n "$proj" && -n "$recorded_proj" && "$recorded_proj" != unknown && "$recorded_proj" != "$proj" ]]; then
    die 'Project hash collision: two physical paths share one truncated hash; refusing to share state.'
  fi
  [[ "$acknowledged" == "$dir" ]] && return 0
  choice=${BOX_AUTH_TRANSITION:-}
  case "$choice" in
    use-existing)
      box_auth_write_binding "$binding" "$dir" "${proj:-$recorded_proj}" || return 1
      return 0 ;;
    fresh)
      if [[ -f "$dir/credentials.json" ]] && command -v jq >/dev/null 2>&1; then
        jq -e '.tombstone == true' -- "$dir/credentials.json" >/dev/null 2>&1 \
          || die 'Refusing fresh transition over a non-empty auth destination (use auth-copy or use-existing).'
      fi
      box_auth_write_binding "$binding" "$dir" "${proj:-$recorded_proj}" || return 1
      return 0 ;;
    *)
      die "Auth scope change requires an explicit transition (harness $id): set BOX_AUTH_TRANSITION=fresh|use-existing, or run an explicit 'make -C box auth-copy HARNESS=$id ...'. Unrelated project state is retained; nothing was copied."
      ;;
  esac
}

# Shared live preparation: resolve policy before creating directories,
# contacting Docker, inspecting native credentials, acquiring locks, or
# preparing projections. Ensures the canonical object, records the
# scope-change acknowledgment, enforces the migration gate (when a native
# path is given), reserves auth + projection locks in deterministic order,
# and installs the projection (when a native path is given). Prints the
# canonical auth directory. Callers hold the reservation across the client
# run and collect/scrub/release afterwards (file harnesses host-side,
# OpenCode container-side via the entrypoint supervisor).
# Usage: box_auth_prepare <harness> <uid> <project-hash> <projection-lock> [native-path] [bundle-dir] [projection-desc]
box_auth_prepare() {
  local id=${1:-} uid=${2:-} hash=${3:-} proj_lock=${4:-} native=${5:-} bundle=${6:-} desc=${7:-${5:-$4}}
  box_require_tool "$id"
  [[ -n "$uid" && -n "$hash" && -n "$proj_lock" ]] || die 'Internal error: missing auth prepare arguments.'
  local scope dir
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then
    dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else
    dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1
  fi
  box_auth_ensure_object "$dir" "$id" "$scope" "$uid" "$hash" || return 1
  box_auth_transition_plan "$id" "$uid" "$hash" || return 1
  if [[ -n "$native" ]]; then
    box_auth_migration_gate "$id" "$dir" "$native" "$dir/migration.json" || return 1
  fi
  box_auth_lease_reserve "$dir" "$proj_lock" "$desc" || return 1
  if [[ -n "$native" ]]; then
    box_auth_install_projection "$id" "$dir" "$native" "$bundle" || return 1
  fi
  printf '%s' "$dir"
}
