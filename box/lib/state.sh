# shellcheck shell=bash
# box/lib/state.sh — authoritative state identity/location resolver.
# Extends _BOX_STATES without replacing it. Produces exact descriptors for
# explicitly requested states; callers must not rebuild names.
# Requires lib/preflight.sh (die, box_realpath) + lib/tools.sh (registry).
# Never branches on harness names: dispatch is registry-driven (state class,
# scope, kind, root, adapter). Workspace discovery stays in launcher.sh;
# pass its physical-root result into this resolver.
# shellcheck disable=SC2034,SC2154 # context globals cross files.
[[ -n "${_BOX_STATE_LOADED:-}" ]] && return 0
_BOX_STATE_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

_state_src=${BASH_SOURCE[0]}
if command -v realpath >/dev/null 2>&1; then
  _state_src=$(realpath -- "$_state_src" 2>/dev/null || printf '%s' "$_state_src")
elif command -v readlink >/dev/null 2>&1; then
  _state_src=$(readlink -f -- "$_state_src" 2>/dev/null || printf '%s' "$_state_src")
fi
_state_dir=$(dirname -- "$_state_src")
unset _state_src
# shellcheck source=lib/tools.sh
source "$_state_dir/tools.sh"
# shellcheck source=lib/test-state.sh
source "$_state_dir/test-state.sh"
# shellcheck source=lib/config-file.sh
source "$_state_dir/config-file.sh"
# shellcheck source=lib/auth.sh
source "$_state_dir/auth.sh"
unset _state_dir

# Pure physical-project hash: first 20 hex of SHA256(path). No mutation.
# Usage: box_state_project_hash <physical-path>
box_state_project_hash() {
  local path=${1:-} full
  [[ -n "$path" ]] || die 'Internal error: missing project path for hashing.'
  if [[ "${2:-}" == historical ]]; then
    [[ "$path" == /* ]] || die 'Historical physical project must be absolute.'
    path=$(box_realpath -m -- "$path") || die 'Cannot resolve historical physical project.'
  else
    path=$(box_realpath -e -- "$path") || die 'Cannot resolve physical project path.'
  fi
  full=$(printf '%s' "$path" | sha256sum) || die 'Cannot hash project path.'
  full=${full%% *}
  [[ "$full" =~ ^[0-9a-f]{64}$ ]] || die 'Cannot hash project path.'
  printf '%s' "${full:0:20}"
}

# Validate numeric UID/GID (nonzero). Pure.
box_state_validate_uid_gid() {
  local uid=${1:-} gid=${2:-}
  [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || die 'Internal error: UID/GID must be numeric.'
  ((10#$uid != 0 && 10#$gid != 0)) || die 'Run as your normal non-root host user.'
}

# Context: validated harness, UID/GID, physical project, execution domain.
# Sets globals: BOX_STATE_HARNESS/UID/GID/PROJECT/PROJECT_HASH/DOMAIN/NS/TASK_ROOT.
# Usage: box_state_context <harness> <uid> <gid> <project-path> <production|test> [ns] [task-root]
box_state_context() {
  local harness=${1:-} uid=${2:-} gid=${3:-} proj=${4:-} domain=${5:-}
  local ns=${6:-${BOX_TEST_STATE_NS:-}} task_root=${7:-${BOX_TEST_TASK_ROOT:-}}
  box_require_tool "$harness"
  box_state_validate_uid_gid "$uid" "$gid"
  [[ -n "$proj" ]] || die 'Internal error: missing project path.'
  if [[ "${8:-}" == historical ]]; then
    [[ "$proj" == /* ]] || die 'Historical physical project must be absolute.'
    proj=$(box_realpath -m -- "$proj") || die 'Cannot resolve historical project path.'
  else
    proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
  fi
  case "$domain" in production|test) ;; *) die 'Internal error: unknown state domain.';; esac
  if [[ "$domain" == test ]]; then
    box_test_validate_ns "$ns" >/dev/null
    [[ -n "$task_root" ]] || die 'BOX_TEST_TASK_ROOT is required alongside BOX_TEST_STATE_NS.'
    [[ -d "$task_root" ]] || die 'BOX_TEST_TASK_ROOT must be an existing disposable directory.'
  fi
  case "$proj" in *','*|*$'\n'*) die 'Invalid physical project path.';; esac
  BOX_STATE_HARNESS=$harness
  BOX_STATE_UID=$uid
  BOX_STATE_GID=$gid
  BOX_STATE_PROJECT=$proj
  BOX_STATE_PROJECT_HASH=$(box_state_project_hash "$proj" "${8:-}")
  BOX_STATE_DOMAIN=$domain
  BOX_STATE_NS=$ns
  BOX_STATE_TASK_ROOT=$task_root
}

# Production volume name: <prefix>-u<uid>-g<gid>-<hash>. Pure.
# Usage: box_state_volume_name <harness> <uid> <gid> <project-hash>
box_state_volume_name() {
  local harness=${1:-} uid=${2:-} gid=${3:-} hash=${4:-} prefix
  box_require_tool "$harness"
  box_state_validate_uid_gid "$uid" "$gid"
  [[ "$hash" =~ ^[0-9a-f]{20}$ ]] || die 'Internal error: invalid project hash.'
  prefix=$(box_tool_field "$harness" state_prefix)
  if [[ -n "${5:-}" ]]; then
    local state declared=0
    for state in $(box_tool_field "$harness" states); do
      [[ "$(box_state_field "$harness" "$state" volume_prefix)" != "$5" ]] || declared=1
    done
    ((declared)) || die 'Undeclared historical volume prefix.'
    prefix=$5
  fi
  [[ "$prefix" =~ ^[a-z][a-z0-9-]*$ ]] || die 'Internal error: invalid state prefix.'
  printf '%s-u%s-g%s-%s' "$prefix" "$uid" "$gid" "$hash"
}

# Resolve one state descriptor. Requires box_state_context globals.
# Prints KEY=value lines (machine-readable, non-secret only).
# Keys: domain harness state class scope uid gid project_hash project
#       path runtime adapter schema_volume volume.
# Usage: box_state_resolve <state-name>
box_state_resolve() {
  local state=${1:-}
  [[ -n "$state" ]] || die 'Internal error: missing state name.'
  [[ -n "${BOX_STATE_HARNESS:-}" && -n "${BOX_STATE_UID:-}" && -n "${BOX_STATE_GID:-}" ]] \
    || die 'Internal error: state context is unset.'
  box_require_tool "$BOX_STATE_HARNESS"
  local project=$BOX_STATE_PROJECT
  local class scope kind root override runtime adapter schema leaf volume_prefix
  class=$(box_state_field "$BOX_STATE_HARNESS" "$state" class)
  scope=$(box_state_field "$BOX_STATE_HARNESS" "$state" scope)
  kind=$(box_state_field "$BOX_STATE_HARNESS" "$state" kind)
  root=$(box_state_field "$BOX_STATE_HARNESS" "$state" root)
  override=$(box_state_field "$BOX_STATE_HARNESS" "$state" override)
  runtime=$(box_state_field "$BOX_STATE_HARNESS" "$state" runtime)
  adapter=$(box_state_field "$BOX_STATE_HARNESS" "$state" adapter)
  schema=$(box_state_field "$BOX_STATE_HARNESS" "$state" schema_version)
  leaf=$(box_state_field "$BOX_STATE_HARNESS" "$state" leaf)
  volume_prefix=$(box_state_field "$BOX_STATE_HARNESS" "$state" volume_prefix)
  local eff_scope="$scope" path="" volume=""
  if [[ "$class" == auth ]]; then
    # Effective scope comes from the shared policy resolver (no harness branch).
    # Single auth-path formula lives in box_auth_object_dir; test-domain
    # dispatch happens there via BOX_TEST_* so no second copy exists here.
    # shellcheck source=lib/auth.sh
    eff_scope=$(box_auth_policy_resolve "$BOX_STATE_HARNESS")
    if [[ "$BOX_STATE_DOMAIN" == test ]]; then
      BOX_TEST_STATE_NS=$BOX_STATE_NS BOX_TEST_TASK_ROOT=$BOX_STATE_TASK_ROOT \
        path=$(box_auth_object_dir "$BOX_STATE_HARNESS" "$eff_scope" "$BOX_STATE_UID" "$BOX_STATE_PROJECT_HASH") || return 1
      # box_auth_object_dir validates the hash even for global; global ignores it.
    else
      if [[ "$eff_scope" == global ]]; then
        path=$(box_auth_object_dir "$BOX_STATE_HARNESS" "$eff_scope" "$BOX_STATE_UID") || return 1
      else
        path=$(box_auth_object_dir "$BOX_STATE_HARNESS" "$eff_scope" "$BOX_STATE_UID" "$BOX_STATE_PROJECT_HASH") || return 1
      fi
    fi
  else
    if [[ "$kind" == volume ]]; then
      if [[ "$BOX_STATE_DOMAIN" == test ]]; then
        box_test_validate_ns "$BOX_STATE_NS" >/dev/null
        volume=$(box_test_volume "$BOX_STATE_HARNESS" "$BOX_STATE_NS" "$BOX_STATE_UID" "$BOX_STATE_GID")
        path="volume:$volume"
      else
        volume=$(box_state_volume_name "$BOX_STATE_HARNESS" "$BOX_STATE_UID" "$BOX_STATE_GID" "$BOX_STATE_PROJECT_HASH" "$volume_prefix")
        path="volume:$volume"
      fi
    else
      # Bind states: resolve via declared root/override (storage mechanics,
      # never harness names). Global roots resolve under $HOME; project roots
      # resolve under the configured state root plus the project hash.
      local base=""
      local raw=""
      # First override token wins when set; otherwise the registry root.
      local tok
      for tok in $override; do
        [[ -n "${!tok+x}" ]] || continue
        [[ -n "${!tok}" ]] || die 'Native state root override must not be empty.'
        local candidate
        candidate=$(box_plan_directory "${!tok}") || return 1
        [[ -z "$raw" || "$raw" == "$candidate" ]] || die 'Native state root aliases must agree.'
        raw=$candidate
      done
      if [[ -n "$raw" ]]; then
        base=$raw
      else
        base=$(box_plan_directory "$HOME/$root") || return 1
      fi
      if [[ "$scope" == global ]]; then
        path=$base
      else
        path="$base/$BOX_STATE_PROJECT_HASH${leaf:+/$leaf}"
        if [[ "$BOX_STATE_DOMAIN" == test && -n "$leaf" ]]; then
          local troot
          troot=$(box_test_task_root "${BOX_STATE_TASK_ROOT:-}") || return 1
          path=$(BOX_TEST_TASK_ROOT="$troot" BOX_TEST_STATE_NS="$BOX_STATE_NS" box_test_native_home "$leaf") || return 1
        fi
      fi
    fi
  fi
  printf 'domain=%s\nharness=%s\nstate=%s\nclass=%s\nscope=%s\nuid=%s\ngid=%s\nproject_hash=%s\nproject=%s\npath=%s\nruntime=%s\nadapter=%s\nschema_version=%s\nvolume=%s\n' \
    "$BOX_STATE_DOMAIN" "$BOX_STATE_HARNESS" "$state" "$class" "$eff_scope" \
    "$BOX_STATE_UID" "$BOX_STATE_GID" "$BOX_STATE_PROJECT_HASH" "$BOX_STATE_PROJECT" \
    "$path" "$runtime" "$adapter" "$schema" "$volume"
}

# Validate a descriptor file/lines without mutation. Dies on mismatch.
# Usage: box_state_validate_descriptor <descriptor-file>
box_state_validate_descriptor() {
  local file=${1:-}
  [[ -n "$file" && -f "$file" ]] || die 'Internal error: missing descriptor file.'
  command -v python3 >/dev/null 2>&1 || die 'Python3 is required for descriptor validation.'
  python3 -I - "$file" <<'PY' || die 'Invalid state descriptor.'
import sys
want = {"domain","harness","state","class","scope","uid","gid","project_hash","project","path","runtime","adapter","schema_version","volume"}
got = {}
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        if "=" not in line:
            sys.exit(1)
        k, v = line.split("=", 1)
        if k in got:
            sys.exit(1)
        got[k] = v
if set(got) != want:
    sys.exit(1)
if got["domain"] not in ("production","test"):
    sys.exit(1)
if got["class"] not in ("auth","non-auth"):
    sys.exit(1)
if got["class"] == "auth" and got["scope"] not in ("global","project"):
    sys.exit(1)
if not got["uid"].isdigit() or int(got["uid"]) == 0:
    sys.exit(1)
if not got["gid"].isdigit() or int(got["gid"]) == 0:
    sys.exit(1)
if got["scope"] == "project" or got["class"] == "non-auth":
    if len(got["project_hash"]) != 20 or any(c not in "0123456789abcdef" for c in got["project_hash"]):
        sys.exit(1)
if "\n" in got["path"] or "," in got["path"]:
    sys.exit(1)
if not got["path"]:
    sys.exit(1)
PY
}

# Authorize an explicit operation against exact descriptors.
# Usage: box_state_guard_operation <op> <descriptor-file>...
# Ops: migrate copy init recover reset remove plan.
box_state_guard_operation() {
  local op=${1:-}
  [[ -n "$op" ]] || die 'Internal error: missing operation.'
  shift
  case "$op" in migrate|copy|init|recover|reset|remove|plan) ;; *) die "Unknown state operation: $op";; esac
  (($# > 0)) || die 'Internal error: missing descriptors for operation.'
  local d
  for d in "$@"; do
    box_state_validate_descriptor "$d" || return 1
    [[ -n "${BOX_STATE_HARNESS:-}" ]] || die 'State context is required for authorization.'
    local state expected
    state=$(sed -n 's/^state=//p' "$d")
    expected=$(box_state_resolve "$state") || return 1
    [[ "$(cat -- "$d")" == "$expected" ]] || die 'Descriptor does not match the resolved complete state identity.'

  done
}


# Live-launch discovery records are non-secret. Each record retains the
# resolver context and declared root overrides; inventory re-resolves it.
box_state_record_native() {
  local id=$1 domain=production state descriptor index variable value
  box_test_in_test_mode && domain="test"
  box_state_context "$id" "$host_uid" "$host_gid" "$project" "$domain" "" "" "${2:-}"
  index="$(box_auth_index_dir)/native/$id"
  # Complete read-only root/alias validation before any discovery mutation.
  for state in $(box_tool_field "$id" states); do
    [[ "$(box_state_field "$id" "$state" class)" == non-auth ]] || continue
    box_state_resolve "$state" >/dev/null || return 1
  done
  box_plan_directory "$index" >/dev/null || return 1
  if [[ -d "$index" ]]; then box_assert_owner_mode "$index" 'Native discovery index' dir700; fi
  box_prepare_directory "$index" 700 >/dev/null || return 1
  for state in $(box_tool_field "$id" states); do
    [[ "$(box_state_field "$id" "$state" class)" == non-auth ]] || continue
    descriptor=$(box_state_resolve "$state") || return 1
    local -a overrides=()
    for variable in $(box_state_field "$id" "$state" override); do
      value=${!variable:-}
      [[ -z "$value" ]] || overrides+=("$variable=$value")
    done
    python3 -I - "${BASH_SOURCE[0]%/*}/host-fs.py" "$index" "$descriptor" "${overrides[@]}" <<'RECORD' || die 'Cannot record native state descriptor.'
import hashlib, importlib.util, os, sys
spec = importlib.util.spec_from_file_location('host_fs', sys.argv[1])
fs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fs)
index, raw = sys.argv[2:4]
d = dict(line.split("=", 1) for line in raw.splitlines())
name = hashlib.sha256((d["state"] + "\n" + d["path"] + "\n" + d["project_hash"]).encode()).hexdigest() + ".json"
path = os.path.join(index, name)
doc = {"descriptor": d, "overrides": dict(x.split("=", 1) for x in sys.argv[4:]), "fixture_project": "BOX_TEST_PROJECT_HASH" in os.environ}
if os.path.lexists(path):
    old = fs.read_json(path, required_mode=0o600)
    if (set(old) != {"descriptor", "overrides", "fixture_project"} or
            type(old['descriptor']) is not dict or type(old['overrides']) is not dict or
            type(old['fixture_project']) is not bool):
        raise ValueError('unsupported discovery record')
    if old["descriptor"]["project"] != d["project"]:
        raise ValueError("project identity collision")
    if old == doc:
        sys.exit(0)
fs.write_json(path, doc)
RECORD
  done
}

# A reset checkpoint covers both the native home and volume. Block launches
# until the same reset is resumed, including after either store was removed.
box_state_guard_reset() {
  local id=$1 uid=$2 gid=$3 hash=$4 checkpoint
  checkpoint="$(box_auth_index_dir)/removals/$id.json"
  [[ ! -e "$checkpoint" && ! -L "$checkpoint" ]] || die 'Interrupted full state removal; resume state-remove FULL=1 before launching.'
  checkpoint="$(box_auth_index_dir)/resets/$id-u$uid-g$gid-$hash.json"
  [[ ! -e "$checkpoint" && ! -L "$checkpoint" ]] \
    || die 'Interrupted project reset; rerun project-reset with the original scope/root and KEEP_AUTH setting before launching.'
}


box_state_lock_launch() {
  local lock
  lock="$(box_auth_index_dir)/locks/lifecycle-$1.lock"
  box_auth_open_stable_lock "$lock" || return 1
  exec {BOX_STATE_LAUNCH_FD}>>"$lock" || return 1
  flock -sn "$BOX_STATE_LAUNCH_FD" || die 'State lifecycle operation is busy.'
}

# Machine-readable CLI for Python/native consumers.
# Usage: state.sh <context|resolve|validate|guard|project-hash|volume> ...
box_state_cli() {
  local sub=${1:-}
  [[ -n "$sub" ]] || die 'Usage: state.sh <context|resolve|validate|guard|project-hash|volume> ...'
  shift
  case "$sub" in
    describe) [[ $# -eq 6 ]] || die 'Usage: state.sh describe <harness> <uid> <gid> <project> <domain> <state>'; box_state_context "${@:1:5}"; box_state_resolve "$6" ;;
    context) [[ $# -ge 5 ]] || die 'Usage: state.sh context <harness> <uid> <gid> <project> <domain> [ns] [task-root]'; box_state_context "$@" ;;
    resolve) [[ $# -eq 1 ]] || die 'Usage: state.sh resolve <state>'; box_state_resolve "$@" ;;
    validate) [[ $# -eq 1 ]] || die 'Usage: state.sh validate <descriptor>'; box_state_validate_descriptor "$@" ;;
    guard) box_state_guard_operation "$@" ;;
    project-hash) [[ $# -eq 1 ]] || die 'Usage: state.sh project-hash <path>'; box_state_project_hash "$@" ;;
    volume) [[ $# -eq 4 ]] || die 'Usage: state.sh volume <harness> <uid> <gid> <hash>'; box_state_volume_name "$@" ;;
    *) die "Unknown state command: $sub" ;;
  esac
}

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  box_state_cli "$@"
fi
