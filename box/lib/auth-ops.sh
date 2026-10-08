# shellcheck shell=bash
# shellcheck disable=SC2030,SC2031 # operational subshells intentionally isolate resolver/host globals.
# box/lib/auth-ops.sh — resolver-backed operational entrypoint for
# migration/copy/init/recovery and lifecycle inventories.
# Never allows a test transaction to name a production source/destination.
# All operations resolve exact descriptors through lib/state.sh + lib/auth.sh
# and operate on those paths only: no globs, no loose prefixes, no
# enumeration of unrelated projects. Journal stages:
#   planned → staged → destination-committed → verified → source-retired → complete
# Source is preserved until destination verification succeeds; rollback
# restores only explicitly recorded targets and never merges stores.
[[ -n "${_BOX_AUTH_OPS_LOADED:-}" ]] && return 0
_BOX_AUTH_OPS_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

_ops_src=${BASH_SOURCE[0]}
if command -v realpath >/dev/null 2>&1; then
  _ops_src=$(realpath -- "$_ops_src" 2>/dev/null || printf '%s' "$_ops_src")
elif command -v readlink >/dev/null 2>&1; then
  _ops_src=$(readlink -f -- "$_ops_src" 2>/dev/null || printf '%s' "$_ops_src")
fi
_ops_dir=$(dirname -- "$_ops_src")
unset _ops_src
# shellcheck source=lib/state.sh
source "$_ops_dir/state.sh"
unset _ops_dir

# Transaction journal stages.
box_ops_journal_path() {
  printf '%s/migration-journal.json' "$1"
}

box_ops_write_journal() {
  local dir=${1:-} stage=${2:-} src=${3:-} dst=${4:-}
  [[ -n "$dir" && -n "$stage" ]] || die 'Internal error: missing journal arguments.'
  case "$stage" in planned|staged|destination-committed|verified|source-retired|complete) ;; *)
    die 'Internal error: unknown journal stage.' ;;
  esac
  python3 -I - "$dir/migration-journal.json" "$stage" "$src" "$dst" <<'PY' || die 'Cannot write migration journal.'
import json, os, tempfile, sys
path, stage, src, dst = sys.argv[1:5]
fd, tmp = tempfile.mkstemp(prefix=".journal.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump({"stage": stage, "source": src, "destination": dst}, f, separators=(",", ":"))
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
  chmod 600 -- "$dir/migration-journal.json" || die 'Cannot secure migration journal.'
}

# Guard: test transactions must never name production paths.
box_ops_guard_test_domain() {
  if box_test_in_test_mode; then
    for p in "$@"; do
      case "$p" in
        "$BOX_TEST_TASK_ROOT"/*) ;;
        volume:box-test-*) ;;
        *) die 'Test transactions must stay inside the disposable task root.' ;;
      esac
    done
  fi
}

# Resolve the canonical auth directory for (harness, project-path) under the
# current policy. Prints the directory. No mutation.
# Usage: box_ops_auth_dir <harness> <project-path>
box_ops_auth_dir() {
  local id=${1:-} proj=${2:-}
  box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Internal error: missing project path.'
  local uid hash scope
  uid=$(id -u) || die 'Cannot determine UID.'
  ((10#$uid != 0)) || die 'Run as your normal non-root host user.'
  proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
  hash=$(box_state_project_hash "$proj") || return 1
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then
    box_auth_object_dir "$id" "$scope" "$uid" || return 1
  else
    box_auth_object_dir "$id" "$scope" "$uid" "$hash" || return 1
  fi
}

# Resolve the legacy native source for (harness, project-path).
# Dispatches to the registry-declared adapter's legacy-source helper so
# shared code never branches on harness names: storage mechanics live in
# harnesses/<id>/auth.sh as box_adapter_legacy_source.
# Prints the path (which may not exist → fresh). Dies on unsafe paths.
# Usage: box_ops_legacy_source <harness> <project-path> [db-path]
box_ops_legacy_source() {
  local id=${1:-} proj=${2:-} db=${3:-}
  box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Internal error: missing project path.'
  proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
  local hash adapter bundle
  hash=$(box_state_project_hash "$proj") || return 1
  adapter=$(box_state_field "$id" auth adapter)
  [[ -n "$adapter" ]] || die 'Internal error: missing auth adapter.'
  bundle=${BUNDLE_DIR:-${script_dir:-}}
  if [[ -z "$bundle" ]]; then bundle=$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")"); bundle=$(dirname -- "$bundle"); fi
  [[ -f "$bundle/$adapter" ]] || die "Missing auth adapter: $adapter"
  # shellcheck disable=SC1090 # registry-declared adapter path
  source "$bundle/$adapter"
  local legacy
  if [[ -n "$db" ]]; then
    legacy=$(box_adapter_legacy_source "$proj" "$hash" "$db") || die 'Invalid legacy auth source.'
  else
    legacy=$(box_adapter_legacy_source "$proj" "$hash") || die 'Invalid legacy auth source (OpenCode needs an explicit --db-path export; never auto-opens a live volume).'
  fi
  if [[ "$legacy" == volume:* ]]; then
    local domain=production descriptor
    box_test_in_test_mode && domain="test"
    box_state_context "$id" "$(id -u)" "$(id -g)" "$proj" "$domain"
    descriptor=$(box_state_resolve volume) || return 1
    [[ "$legacy" == "$(sed -n 's/^path=//p' <<<"$descriptor")" && -n "$(box_state_field "$id" auth volume_adapter)" ]] || die 'Legacy volume differs from its exact descriptor.'
    printf '%s' "$legacy"
    return 0
  fi
  [[ "$legacy" == /* ]] || die 'Invalid legacy auth source (must be absolute).'
  case "$legacy" in *','*|*$'\n'*) die 'Invalid legacy auth source path.';; esac
  # Validate containment without creation; the plan step never reads secrets.
  box_plan_directory "$(dirname -- "$legacy")" >/dev/null || return 1
  printf '%s' "$legacy"
}


box_ops_prepare_docker() {
  command -v docker >/dev/null 2>&1 || die 'Docker is required to establish stopped clients before auth state operations.'
  if [[ -z "${docker_cmd[*]:-}" ]]; then
    local bundle
    bundle=${BUNDLE_DIR:-$(dirname -- "$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")")")}
    # shellcheck source=lib/docker.sh
    source "$bundle/lib/docker.sh"
    box_docker_cli "$(box_auth_index_dir)/docker-cli" || return 1
  fi
}

box_ops_require_stopped() {
  box_ops_prepare_docker || return 1
  local coordinate holders
  for coordinate in "$@"; do
    coordinate=${coordinate#volume:}
    holders=$("${docker_cmd[@]}" ps -q --filter "volume=$coordinate") || die 'Cannot check dependent container liveness.'
    [[ -z "$holders" ]] || die 'Stop dependent clients/services before operating on auth state.'
  done
}

box_ops_check_destination_raw() {
  python3 -I - "$1" "$2" <<'COMPATIBLE'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    source = json.load(f)
with open(sys.argv[2], encoding="utf-8") as f:
    destination = json.load(f)
if destination.get("tombstone") is not True and (source.get("tombstone") is not False or source.get("payload") != destination.get("payload")):
    sys.exit(1)
COMPATIBLE
}

box_ops_check_destination() {
  box_ops_check_destination_raw "$@" || die 'Auth destination conflict; no accounts were merged or overwritten.'
}


# Called while host auth/projection locks are held. The helper opens the
# resolved native volume inside its pinned image, without host DB exports.
box_ops_volume_helper() {
  local id=$1 proj=$2 dir=$3 coordinate=$4 operation=$5 bundle
  local runtime=${BOX_AUTH_RUNTIME-runsc} gpfx vf adapter native_path version image holders
  case "$runtime" in runsc|runc) ;; *) die 'BOX_AUTH_RUNTIME must be runsc or runc.' ;; esac
  [[ "$coordinate" == volume:* ]] || die 'Contained auth requires an exact volume descriptor.'
  adapter=$(box_state_field "$id" auth volume_adapter)
  native_path=$(box_state_field "$id" auth native_projection)
  [[ -n "$adapter" && -n "$native_path" ]] || die 'Harness has no qualified contained auth adapter.'
  bundle=${BUNDLE_DIR:-${script_dir:-}}
  [[ -n "$bundle" ]] || bundle=$(dirname -- "$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")")")
  # shellcheck source=lib/build.sh
  source "$bundle/lib/build.sh"
  gpfx=$(box_tool_field "$id" git_prefix)
  vf="${gpfx}_VERSION_FILE"
  vf=${!vf:-$HOME/.config/$(box_tool_field "$id" config_dir)/$(box_tool_field "$id" version_file)}
  # shellcheck disable=SC2046 # registry allowlist
  box_load_version_file "$vf" "$(box_tool_field "$id" version_format)" $(box_tool_field "$id" pin_keys)
  version=$box_file_version
  image=$(box_image_tag_for_version "$id" "$version" "$(id -u)" "$(id -g)")
  box_docker_cli "$(box_auth_index_dir)/docker-cli"
  box_assert_engine
  local fallback_requested=0
  [[ "$runtime" != runc ]] || fallback_requested=1
  box_assert_runtime
  box_assert_image "$image" "$version" "$vf" "$id" 0
  local volumes
  volumes=$("${docker_cmd[@]}" volume ls -q) || die 'Cannot establish native volume existence.'
  printf '%s\n' "$volumes" | grep -Fxq -- "${coordinate#volume:}" || die 'Native source volume is absent; use auth-init for a fresh identity.'
  box_ops_require_stopped "$dir" "$coordinate" || return 1
  if [[ "$operation" == migrate ]]; then
    box_auth_write_lease "$dir/lease.json" active "$coordinate" "$(box_auth_index_dir)/locks/${coordinate#volume:}.lock" || return 1
  fi
  local rc=0
  "${docker_cmd[@]}" run --rm --init --interactive --pull=never --runtime="$runtime" \
    --user "$(id -u):$(id -g)" --network none --cap-drop=ALL --security-opt=no-new-privileges \
    --read-only --pids-limit 256 --memory 1g --memory-swap 1g --cpus 2 --ulimit nofile=1024:1024 --ulimit core=0 \
    --tmpfs /tmp:rw,nosuid,nodev,mode=1777 --tmpfs /home/box/.cache:rw,nosuid,nodev,mode=700 \
    --mount "type=volume,src=${coordinate#volume:},dst=/persist" \
    --mount "type=bind,src=$dir,dst=/run/box-auth,bind-recursive=disabled,bind-propagation=rprivate" \
    --entrypoint python3 "$image" -I "/usr/local/bin/box-${adapter##*/}" "$operation" \
      --auth-dir /run/box-auth --db "$native_path" --source "$coordinate" --host-auth-dir "$dir" \
      --sidecar /persist/state/"$id"/box-auth-selection.json || rc=$?
  if jq -e '.state == "active" and .phase == "reserved"' -- "$dir/lease.json" >/dev/null 2>&1; then
    holders=$("${docker_cmd[@]}" ps -q --filter "volume=$dir") || return 1
    if [[ -z "$holders" ]]; then box_auth_lease_release "$dir" || return 1; fi
  fi
  ((rc == 0)) || die 'Contained auth operation failed; prepared projections/transactions require auth-recover.'
}

# Atomic publish: stage file beside the destination, flush, publish without
# overwriting an existing winner, reopen and verify, record revision.
# Usage: box_ops_publish_envelope <staged-envelope> <auth-dir>
box_ops_publish_envelope() {
  local staged=${1:-} dir=${2:-}
  [[ -n "$staged" && -n "$dir" ]] || die 'Internal error: missing publish arguments.'
  [[ -f "$staged" ]] || die 'Missing staged auth envelope.'
  command -v jq >/dev/null 2>&1 || die 'jq is required for auth migration.'
  local rev dest_tmp
  rev=$(jq -r '.revision // 0' -- "$dir/credentials.json" 2>/dev/null || printf '0')
  [[ "$rev" =~ ^[0-9]+$ ]] || rev=0
  dest_tmp="$dir/.credentials.publish.$$"
  jq --argjson rev "$((rev + 1))" '.revision = $rev' -- "$staged" >"$dest_tmp" || die 'Cannot revision auth envelope.'
  chmod 600 -- "$dest_tmp" || die 'Cannot secure auth envelope.'
  python3 -I - "$dest_tmp" <<'PY' || die 'Cannot flush staged auth envelope.'
import os, sys
path = sys.argv[1]
with open(path, "rb") as f:
    f.read()
    os.fsync(f.fileno())
d = os.path.dirname(os.path.abspath(path))
fd = os.open(d, os.O_RDONLY)
try:
    os.fsync(fd)
finally:
    os.close(fd)
PY
  if [[ -f "$dir/credentials.json" ]] && jq -e '.tombstone == false' -- "$dir/credentials.json" >/dev/null 2>&1; then
    if ! box_ops_check_destination_raw "$dest_tmp" "$dir/credentials.json"; then
      rm -f -- "$dest_tmp"
      die 'Auth destination conflict: refusing to overwrite an existing non-empty destination.'
    fi
    rm -f -- "$dest_tmp"
    return 0
  fi
  mv -f -- "$dest_tmp" "$dir/credentials.json" || die 'Cannot commit auth envelope.'
  jq -e 'type == "object" and .schema_version == 1 and (.tombstone | type == "boolean")' \
    -- "$dir/credentials.json" >/dev/null 2>&1 || die 'Committed auth envelope failed verification.'
}

# Migrate legacy native auth → selected canonical identity with an atomic
# journal. Preserves the source until destination verification succeeds,
# keeps a protected rollback copy outside native importer paths, then
# retires legacy auth from its active importer path and records migration.
# Usage: box_ops_migrate <harness> <project-path> [--db-path PATH]
box_ops_migrate() (
  local id=${1:-} proj=${2:-} db=""
  case "${BOX_AUTH_RUNTIME-runsc}" in runsc|runc) ;; *) die 'BOX_AUTH_RUNTIME must be runsc or runc.' ;; esac
  box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Usage: auth-migrate HARNESS=<id> PROJECT=<path> [DB_PATH=<file>]'
  shift 2
  while (($#)); do
    case "$1" in
      --db-path) [[ $# -ge 2 ]] || die '--db-path requires a path.'; db=$2; shift 2 ;;
      --db-path=*) db=${1#--db-path=}; shift ;;
      *) die "Unknown migrate argument: $1" ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || die 'jq is required for auth migration.'
  local uid gid hash scope dir legacy staged rollback volume
  uid=$(id -u) || die 'Cannot determine UID.'
  gid=$(id -g) || die 'Cannot determine GID.'
  proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
  hash=$(box_state_project_hash "$proj") || return 1
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1; fi
  box_ops_guard_test_domain "$dir" "$proj"
  legacy=$(box_ops_legacy_source "$id" "$proj" "$db") || return 1
  box_ops_guard_test_domain "$legacy"
  box_state_lock_launch "$id" || return 1
  box_state_guard_reset "$id" "$uid" "$(id -g)" "$hash"
  box_auth_ensure_object "$dir" "$id" "$scope" "$uid" "$hash" || return 1
  local projection_lock
  projection_lock="$(dirname -- "$legacy")/.box-projection.lock"
  if [[ -n "$db" || "$legacy" == volume:* ]]; then
    local projection_domain=production projection_descriptor
    box_test_in_test_mode && projection_domain="test"
    box_state_context "$id" "$uid" "$gid" "$proj" "$projection_domain"
    projection_descriptor=$(box_state_resolve volume) || return 1
    projection_lock="$(box_auth_index_dir)/locks/$(sed -n 's/^volume=//p' <<<"$projection_descriptor").lock"
    box_prepare_directory "$(dirname -- "$projection_lock")" 700 >/dev/null || return 1
  fi
  box_auth_lock_pair "$dir" "$projection_lock" || return 1
  if [[ -e "$dir/migration-journal.json" || -e "$dir/collection-pending.json" ]]; then
    die 'Recover the recorded transaction before migrating.'
  fi
  if [[ -f "$dir/migration.json" ]]; then die 'Auth identity already has a completed migration record.'; fi
  if jq -e '.state == "active"' -- "$dir/lease.json" >/dev/null 2>&1; then
    die 'Auth lease is active; recover it before migrating.'
  fi
  local domain=production descriptor
  box_test_in_test_mode && domain="test"
  box_state_context "$id" "$uid" "$gid" "$proj" "$domain"
  descriptor=$(box_state_resolve volume) || return 1
  volume=$(sed -n 's/^volume=//p' <<<"$descriptor")
  box_ops_require_stopped "$volume" "$dir" || return 1
  if [[ "$legacy" == volume:* ]]; then
    box_ops_volume_helper "$id" "$proj" "$dir" "$legacy" migrate || return 1
    box_auth_transition_plan "$id" "$uid" "$hash" "$proj" || return 1
    return 0
  fi
  box_ops_require_stopped "$(dirname -- "$legacy")" || return 1
  local adapter bundle
  adapter=$(box_state_field "$id" auth adapter)
  bundle=${BUNDLE_DIR:-${script_dir:-}}
  if [[ -z "$bundle" ]]; then bundle=$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")"); bundle=$(dirname -- "$bundle"); fi
  [[ -f "$bundle/$adapter" ]] || die "Missing auth adapter: $adapter"
  # shellcheck disable=SC1090 # registry-declared adapter path
  source "$bundle/$adapter"
  box_adapter_validate "$legacy" || die 'Legacy auth store failed validation; refusing migration.'
  staged=$(mktemp "$dir/.migration-stage.XXXXXX") || die 'Cannot stage migration.'
  trap 'rm -f -- "$staged"' EXIT
  box_adapter_export "$legacy" "$staged" || die 'Cannot export legacy auth.'
  box_ops_check_destination "$staged" "$dir/credentials.json" || return 1
  box_ops_write_journal "$dir" planned "$legacy" "$dir" || return 1
  box_ops_write_journal "$dir" staged "$legacy" "$dir" || return 1
  rollback="$dir/rollback-credentials.json"
  if [[ -f "$dir/credentials.json" ]]; then cp -p -- "$dir/credentials.json" "$rollback" || die 'Cannot preserve rollback copy.'; chmod 600 -- "$rollback" || die 'Cannot secure rollback copy.'; fi
  box_ops_publish_envelope "$staged" "$dir" || return 1
  rm -f -- "$staged"
  box_ops_write_journal "$dir" destination-committed "$legacy" "$dir" || return 1
  box_adapter_validate "$legacy" >/dev/null || die 'Source changed during migration; destination verified, source retained.'
  box_ops_write_journal "$dir" verified "$legacy" "$dir" || return 1
  box_adapter_retire "$legacy" "$dir/legacy-auth-rollback.json" || die 'Cannot retire legacy auth.'
  box_ops_write_journal "$dir" source-retired "$legacy" "$dir" || return 1
  python3 -I - "$dir/migration.json" "$legacy" "$dir" <<'PY' || die 'Cannot record migration.'
import json, sys
path, src, dst = sys.argv[1:4]
with open(path, "w", encoding="utf-8") as f:
    json.dump({"mode": "migrated", "source": src, "destination": dst}, f, separators=(",", ":"))
    f.write("\n")
PY
  chmod 600 -- "$dir/migration.json" || die 'Cannot secure migration record.'
  box_auth_transition_plan "$id" "$uid" "$hash" "$proj" >/dev/null || return 1
  box_ops_write_journal "$dir" complete "$legacy" "$dir" || return 1
  printf 'Migrated %s auth for %s to %s\n' "$id" "$proj" "$dir"
)

# Copy one explicitly selected canonical source → destination. No
# enumeration, no merge, no overwrite of a differing destination.
# Usage: box_ops_copy <harness> <src-scope> [src-hash] <dst-scope> [dst-hash]
box_ops_copy() (
  local id=${1:-} src_scope=${2:-} src_hash=${3:-} dst_scope=${4:-} dst_hash=${5:-}
  local acknowledge_project="" acknowledge_hash="" acknowledge_binding=""
  [[ $# -ge 5 ]] || die 'Auth copy requires explicit source and destination coordinates.'
  shift 5
  while (($#)); do
    case "$1" in
      --project) [[ $# -ge 2 ]] || die '--project requires a physical project.'; acknowledge_project=$2; shift 2 ;;
      *) die "Unknown copy argument: $1" ;;
    esac
  done
  box_require_tool "$id"
  box_auth_policy_resolve "$id" >/dev/null || return 1
  box_auth_valid_scope "$src_scope" || die 'Invalid copy source scope.'
  box_auth_valid_scope "$dst_scope" || die 'Invalid copy destination scope.'
  command -v jq >/dev/null 2>&1 || die 'jq is required for auth copy.'
  local uid src dst
  uid=$(id -u) || die 'Cannot determine UID.'
  if [[ "$src_scope" == global ]]; then src=$(box_auth_object_dir "$id" "$src_scope" "$uid") || return 1
  else [[ "$src_hash" =~ ^[0-9a-f]{20}$ ]] || die 'Invalid copy source project hash.'; src=$(box_auth_object_dir "$id" "$src_scope" "$uid" "$src_hash") || return 1; fi
  if [[ "$dst_scope" == global ]]; then dst=$(box_auth_object_dir "$id" "$dst_scope" "$uid") || return 1
  else [[ "$dst_hash" =~ ^[0-9a-f]{20}$ ]] || die 'Invalid copy destination project hash.'; dst=$(box_auth_object_dir "$id" "$dst_scope" "$uid" "$dst_hash") || return 1; fi
  [[ "$src" != "$dst" ]] || die 'Copy source and destination are identical.'
  if [[ -n "$acknowledge_project" ]]; then
    acknowledge_project=$(box_realpath -e -- "$acknowledge_project") || return 1
    acknowledge_hash=$(box_state_project_hash "$acknowledge_project") || return 1
    [[ "$(box_auth_policy_resolve "$id")" == "$dst_scope" ]] || die 'Copy acknowledgment requires the selected destination scope.'
    [[ "$dst_scope" == global || "$acknowledge_hash" == "$dst_hash" ]] || die 'Copy acknowledgment project does not match destination.'
    box_ops_guard_test_domain "$acknowledge_project"
    acknowledge_binding=$(box_auth_binding_file "$id" "$acknowledge_hash") || return 1
    box_plan_directory "$(dirname -- "$acknowledge_binding")" >/dev/null || return 1
    if [[ -e "$acknowledge_binding" || -L "$acknowledge_binding" ]]; then
      [[ ! -L "$acknowledge_binding" && -f "$acknowledge_binding" && "$(stat -c %h -- "$acknowledge_binding")" == 1 ]] || die 'Unsafe copy acknowledgment binding.'
      box_assert_owner_mode "$acknowledge_binding" 'Copy acknowledgment binding' creds
      local bound_project
      bound_project=$(sed -n '2p' -- "$acknowledge_binding") || return 1
      [[ -z "$bound_project" || "$bound_project" == unknown || "$bound_project" == "$acknowledge_project" ]] || die 'Project hash collision in copy acknowledgment.'
    fi
  fi
  box_ops_guard_test_domain "$src" "$dst"
  for d in "$src" "$dst"; do
    [[ -f "$d/identity.json" && -f "$d/credentials.json" && -f "$d/lease.json" && -f "$d/lock" ]] \
      || die "Copy endpoint is not an exact auth identity: $d"
  done
  box_state_lock_launch "$id" || return 1
  [[ ! -e "$(box_auth_index_dir)/removals/$id.json" ]] || die 'Interrupted full removal; resume it before auth-copy.'
  box_auth_ensure_object "$src" "$id" "$src_scope" "$uid" "$src_hash" || return 1
  box_auth_ensure_object "$dst" "$id" "$dst_scope" "$uid" "$dst_hash" || return 1
  local first second
  first=$src second=$dst
  [[ "$src" < "$dst" ]] || { first=$dst; second=$src; }
  box_auth_lock_pair "$first" "$second/lock" || return 1
  jq -e '.state == "active"' -- "$src/lease.json" >/dev/null 2>&1 && die 'Copy source lease is active; recover first.'
  jq -e '.state == "active"' -- "$dst/lease.json" >/dev/null 2>&1 && die 'Copy destination lease is active; recover first.'
  jq -e --arg h "$id" 'type == "object" and .schema_version == 1 and .harness == $h and (.tombstone | type == "boolean")' \
    -- "$src/credentials.json" >/dev/null 2>&1 || die 'Copy source envelope is invalid.'
  for d in "$src" "$dst"; do
    [[ ! -e "$d/collection-pending.json" ]] || die 'Recover pending collection before copying.'
    if [[ -e "$d/migration-journal.json" ]]; then
      jq -e '.stage == "complete"' "$d/migration-journal.json" >/dev/null || die 'Recover interrupted migration before copying.'
    fi
  done
  box_auth_verify_envelope "$id" "$src/credentials.json" || die 'Unsupported source auth payload.'
  box_auth_verify_envelope "$id" "$dst/credentials.json" || die 'Unsupported destination auth payload.'
  box_ops_require_stopped "$src" "$dst" || return 1
  box_ops_check_destination "$src/credentials.json" "$dst/credentials.json" || return 1
  box_ops_write_journal "$dst" planned "$src" "$dst" || return 1
  local staged rollback
  staged=$(mktemp "$dst/.copy-stage.XXXXXX") || die 'Cannot stage auth copy.'
  trap 'rm -f -- "$staged"' EXIT
  cp -p -- "$src/credentials.json" "$staged" || die 'Cannot stage copy.'
  chmod 600 -- "$staged" || die 'Cannot secure staged copy.'
  box_ops_write_journal "$dst" staged "$src" "$dst" || return 1
  rollback="$dst/rollback-credentials.json"
  if [[ -f "$dst/credentials.json" ]]; then cp -p -- "$dst/credentials.json" "$rollback" || die 'Cannot preserve rollback copy.'; chmod 600 -- "$rollback" || die 'Cannot secure rollback copy.'; fi
  box_ops_publish_envelope "$staged" "$dst" || return 1
  rm -f -- "$staged"
  box_ops_write_journal "$dst" destination-committed "$src" "$dst" || return 1
  box_ops_write_journal "$dst" verified "$src" "$dst" || return 1
  box_ops_write_journal "$dst" complete "$src" "$dst" || return 1
  if [[ -n "$acknowledge_binding" ]]; then
    box_prepare_directory "$(dirname -- "$acknowledge_binding")" 700 >/dev/null || return 1
    box_auth_write_binding "$acknowledge_binding" "$dst" "$acknowledge_project" || return 1
  fi
  printf 'Copied %s auth %s -> %s\nNOTE: copied OAuth refresh tokens may share a single-use lineage; prefer fresh login for independent long-lived accounts.\n' "$id" "$src" "$dst"
)

# Acknowledge a fresh identity without importing.
# Usage: box_ops_init <harness> <project-path>
box_ops_init() (
  local id=${1:-} proj=${2:-}
  box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Usage: auth-init HARNESS=<id> PROJECT=<path>'
  local uid hash scope dir
  uid=$(id -u) || die 'Cannot determine UID.'
  proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
  hash=$(box_state_project_hash "$proj") || return 1
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1; fi
  box_ops_guard_test_domain "$dir" "$proj"
  box_state_lock_launch "$id" || return 1
  box_state_guard_reset "$id" "$uid" "$(id -g)" "$hash"
  box_auth_ensure_object "$dir" "$id" "$scope" "$uid" "$hash" || return 1
  box_auth_lock_pair "$dir" "$dir/lock" || return 1
  jq -e '.state == "idle"' "$dir/lease.json" >/dev/null || die 'Recover the active auth lease before initializing.'
  [[ ! -e "$dir/collection-pending.json" ]] || die 'Recover pending collection before initializing.'
  if [[ -e "$dir/migration-journal.json" ]]; then
    jq -e '.stage == "complete"' "$dir/migration-journal.json" >/dev/null || die 'Recover interrupted migration before initializing.'
  fi
  jq -e '.tombstone == true and .payload == null' "$dir/credentials.json" >/dev/null || die 'Fresh initialization requires an empty auth identity.'
  local domain=production descriptor
  box_test_in_test_mode && domain="test"
  box_state_context "$id" "$uid" "$(id -g)" "$proj" "$domain"
  descriptor=$(box_state_resolve volume) || return 1
  box_ops_require_stopped "$dir" "$(sed -n 's/^volume=//p' <<<"$descriptor")" || return 1

  python3 -I - "$dir/migration.json" "$dir" <<'PY' || die 'Cannot record fresh identity.'
import json, sys
path, dst = sys.argv[1:3]
with open(path, "w", encoding="utf-8") as f:
    json.dump({"mode": "fresh", "destination": dst}, f, separators=(",", ":"))
    f.write("\n")
PY
  chmod 600 -- "$dir/migration.json" || die 'Cannot secure migration record.'
  BOX_AUTH_TRANSITION=use-existing box_auth_transition_plan "$id" "$uid" "$hash" "$proj" >/dev/null || return 1
  printf 'Initialized fresh %s auth at %s\n' "$id" "$dir"
)

# Resolve an interrupted lease/transaction: collect the recorded projection
# (authoritative for uncommitted updates) before another launch may import
# the previous canonical revision.
# Usage: box_ops_recover <harness> <project-path> [--native PATH] [--db-path PATH]
box_ops_recover() (
  local id=${1:-} proj=${2:-} native="" db=""
  case "${BOX_AUTH_RUNTIME-runsc}" in runsc|runc) ;; *) die 'BOX_AUTH_RUNTIME must be runsc or runc.' ;; esac
  box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Usage: auth-recover HARNESS=<id> PROJECT=<path> [--native <file>] [--db-path <file>]'
  shift 2
  while (($#)); do
    case "$1" in
      --native) [[ $# -ge 2 ]] || die '--native requires a path.'; native=$2; shift 2 ;;
      --native=*) native=${1#--native=}; shift ;;
      --db-path) [[ $# -ge 2 ]] || die '--db-path requires a path.'; db=$2; shift 2 ;;
      --db-path=*) db=${1#--db-path=}; shift ;;
      *) die "Unknown recover argument: $1" ;;
    esac
  done
  local uid hash scope dir target
  uid=$(id -u) || die 'Cannot determine UID.'
  proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
  hash=$(box_state_project_hash "$proj") || return 1
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1; fi
  box_ops_guard_test_domain "$dir" "$proj"
  command -v jq >/dev/null 2>&1 || die 'jq is required for auth recovery.'
  [[ -d "$dir" && -f "$dir/identity.json" ]] || die 'Unknown recovery identity.'
  box_state_lock_launch "$id" || return 1
  box_state_guard_reset "$id" "$uid" "$(id -g)" "$hash"
  box_auth_ensure_object "$dir" "$id" "$scope" "$uid" "$hash" || return 1
  local projection_lock recorded
  recorded=$(jq -r '.projection // empty' -- "$dir/lease.json") || die 'Cannot read auth lease.'
  projection_lock=$(jq -r '.projection_lock // empty' -- "$dir/lease.json") || die 'Cannot read auth lease.'
  if [[ -z "$projection_lock" ]]; then
    case "$recorded" in
      volume:*) projection_lock="$(box_auth_index_dir)/locks/${recorded#volume:}.lock" ;;
      /*) projection_lock="$(dirname -- "$recorded")/.box-projection.lock" ;;
      *) projection_lock="$dir/lock" ;;
    esac
  fi
  if [[ -z "$recorded" && -f "$dir/migration-journal.json" ]]; then
    local migration_source
    migration_source=$(jq -er '.source' "$dir/migration-journal.json") || die 'Invalid migration source.'
    if [[ -f "$migration_source/identity.json" ]]; then
      projection_lock="$migration_source/lock"
    elif [[ -n "$db" ]]; then
      projection_lock="$(box_auth_index_dir)/locks/$(box_state_volume_name "$id" "$uid" "$(id -g)" "$hash").lock"
    else
      projection_lock="$(dirname -- "$migration_source")/.box-projection.lock"
    fi
  fi
  box_ops_guard_test_domain "$projection_lock"
  box_auth_lock_pair "$dir" "$projection_lock" || return 1
  # A dead launcher may leave a live container; locks alone cannot prove exit.
  command -v docker >/dev/null 2>&1 || die 'Docker is required to establish stopped clients before recovery.'
  box_ops_prepare_docker || return 1
  local holders
  holders=$("${docker_cmd[@]}" ps -q --filter "volume=$dir") || die 'Cannot check recovery container liveness.'
  [[ -z "$holders" ]] || die 'Stop the live auth container before recovery.'
  case "$recorded" in
    volume:*) holders=$("${docker_cmd[@]}" ps -q --filter "volume=${recorded#volume:}") || die 'Cannot check projection liveness.'
      [[ -z "$holders" ]] || die 'Stop the live projection container before recovery.' ;;
  esac
  if jq -e '.state == "active" and .phase == "reserved"' -- "$dir/lease.json" >/dev/null 2>&1; then
    # A reservation that never started preparation has no native updates.
    # Verify container exit even in the disposable domain before releasing it.
    command -v docker >/dev/null 2>&1 || die 'Docker is required to recover a dead reservation.'
    local reservation_holders
    reservation_holders=$("${docker_cmd[@]}" ps -q --filter "volume=$dir") || die 'Cannot establish dead reservation liveness.'
    [[ -z "$reservation_holders" ]] || die 'Stop the live reserved container before recovery.'
    box_auth_lease_release "$dir" || return 1
    printf 'Recovered unused auth reservation at %s\n' "$dir"
    return 0
  fi
  if [[ "$recorded" == volume:* && -z "$native" && -z "$db" ]]; then
    local recovery_domain=production recovery_descriptor
    box_test_in_test_mode && recovery_domain="test"
    box_state_context "$id" "$uid" "$(id -g)" "$proj" "$recovery_domain"
    recovery_descriptor=$(box_state_resolve volume) || return 1
    if [[ "$recorded" != "$(sed -n 's/^path=//p' <<<"$recovery_descriptor")" ]]; then
      # Global auth survives project moves and GID changes. Its interrupted
      # source still belongs to the recorded historical native descriptor.
      local recovery_bundle recovery_records
      recovery_bundle=${BUNDLE_DIR:-${script_dir:-}}
      [[ -n "$recovery_bundle" ]] || recovery_bundle=$(dirname -- "$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")")")
      recovery_records=$(python3 -I "$recovery_bundle/lib/state-inventory.py" "$recovery_bundle" "$(box_auth_index_dir)" "$id") || return 1
      jq -e --arg path "$recorded" --arg uid "$uid" --arg domain "$recovery_domain" --arg scope "$scope" --arg hash "$hash" \
        'any(.[]; .descriptor.path == $path and .descriptor.uid == $uid and .descriptor.domain == $domain and ($scope == "global" or .descriptor.project_hash == $hash))' \
        <<<"$recovery_records" >/dev/null || die 'Recorded recovery volume has no exact re-resolved descriptor.'
    fi
    box_ops_volume_helper "$id" "$proj" "$dir" "$recorded" recover
    return $?
  fi
  if [[ -f "$dir/migration-journal.json" ]]; then
    local stage source destination adapter bundle
    stage=$(jq -er '.stage' "$dir/migration-journal.json") || die 'Invalid migration journal.'
    source=$(jq -er '.source' "$dir/migration-journal.json") || die 'Invalid migration source.'
    destination=$(jq -er '.destination' "$dir/migration-journal.json") || die 'Invalid migration destination.'
    [[ "$destination" == "$dir" ]] || die 'Migration journal names a different destination.'
    box_ops_guard_test_domain "$source"
    case "$stage" in
      complete) ;;
      planned|staged)
        # Nothing was retired. Discard the incomplete transaction marker;
        # the explicit operation can be retried without changing either store.
        rm -f -- "$dir/migration-journal.json" || return 1 ;;
      destination-committed|verified|source-retired)
        jq -e --arg h "$id" '.schema_version == 1 and .harness == $h and (.tombstone | type == "boolean")' \
          "$dir/credentials.json" >/dev/null || die 'Invalid committed migration destination.'
        box_auth_verify_envelope "$id" "$dir/credentials.json" || die 'Unsupported committed auth payload.'
        # A canonical copy never retires its source. A legacy migration
        # replays retirement idempotently, including a crash after rename.
        if [[ ! -f "$source/identity.json" ]]; then
          adapter=$(box_state_field "$id" auth adapter)
          bundle=${BUNDLE_DIR:-${script_dir:-}}
          [[ -n "$bundle" ]] || bundle=$(dirname -- "$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")")")
          # shellcheck disable=SC1090
          source "$bundle/$adapter"
          if [[ ! -f "$dir/legacy-auth-rollback.json" ]]; then
            box_adapter_validate "$source" || die 'Invalid retained migration source.'
            local recovered_stage
            recovered_stage=$(mktemp "$dir/.recover-migration.XXXXXX") || return 1
            box_adapter_export "$source" "$recovered_stage" || return 1
            box_ops_publish_envelope "$recovered_stage" "$dir" || return 1
            rm -f -- "$recovered_stage"
            box_adapter_retire "$source" "$dir/legacy-auth-rollback.json" || die 'Cannot finish migration retirement.'
          else
            box_adapter_scrub "$source" || die 'Cannot finish migration source scrub.'
          fi
          printf '{"mode":"migrated"}\n' >"$dir/migration.json"
          chmod 600 "$dir/migration.json"
        fi
        box_ops_write_journal "$dir" complete "$source" "$dir" || return 1 ;;
      *) die 'Unsupported migration journal stage.' ;;
    esac
  fi
  jq -e '.state == "active"' -- "$dir/lease.json" >/dev/null 2>&1 \
    || { printf 'Auth lease is idle; nothing to recover.\n'; return 0; }
  if [[ -n "$native" && -n "$db" ]]; then die 'Pass only one of --native or --db-path.'; fi
  target=${native:-$db}
  if [[ -z "$target" ]]; then
    # No explicit override: the recorded coordinate decides. Volume-backed
    # coordinates need an explicit database export; filesystem coordinates
    # are collected directly. Dispatch is on coordinate shape (storage
    # mechanics), never on harness names.
    target=$(jq -r '.projection // empty' -- "$dir/lease.json") || die 'Cannot read auth lease.'
    case "$target" in
      volume:*) die 'Volume-backed projection needs an explicit --db-path export for recovery (never auto-opens a live volume).' ;;
    esac
  fi
  if [[ -n "$native" && "$recorded" != "$native" ]]; then die 'Recovery native path differs from the recorded projection.'; fi
  box_ops_guard_test_domain "$target"
  [[ -n "$target" ]] || die 'Active lease lacks a projection coordinate.'
  local adapter bundle
  adapter=$(box_state_field "$id" auth adapter)
  bundle=${BUNDLE_DIR:-${script_dir:-}}
  if [[ -z "$bundle" ]]; then bundle=$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")"); bundle=$(dirname -- "$bundle"); fi
  if [[ -f "$dir/collection-pending.json" ]]; then
    jq -e --arg h "$id" '.schema_version == 1 and .harness == $h and (.tombstone | type == "boolean")' \
      "$dir/collection-pending.json" >/dev/null || die 'Invalid pending auth collection.'
    box_auth_verify_envelope "$id" "$dir/collection-pending.json" "$bundle" || die 'Unsupported pending auth collection; preserved for recovery.'
    cp -- "$dir/collection-pending.json" "$dir/.recovered-credentials" || return 1
    chmod 600 "$dir/.recovered-credentials" || return 1
    mv -f -- "$dir/.recovered-credentials" "$dir/credentials.json" || return 1
    # shellcheck disable=SC1090
    source "$bundle/$adapter"
    box_adapter_scrub "$target" || die 'Cannot finish projection scrub.'
  else
    [[ -e "$target" && ! -L "$target" ]] || die 'Missing projection during required recovery; no pending collection proves logout. Restore the authoritative native store before recovery.'
    box_auth_collect_projection "$id" "$dir" "$target" "$bundle" || die 'Recovery collection failed; projection remains authoritative.'
  fi
  box_auth_lease_release "$dir" || return 1
  printf 'Recovered %s auth at %s\n' "$id" "$dir"
)

# Non-secret lifecycle plan: effective descriptors for auth + non-auth
# volume/home states. No credential reads, DB opens, locks, or writes.
# Usage: box_ops_plan <harness> <project-path>
box_ops_plan() {
  local id=${1:-} proj=${2:-}
  box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Usage: state-plan HARNESS=<id> PROJECT=<path>'
  local uid gid hash scope dir volume
  uid=$(id -u) || die 'Cannot determine UID.'
  gid=$(id -g) || die 'Cannot determine GID.'
  proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
  hash=$(box_state_project_hash "$proj") || return 1
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1; fi
  local domain=production state
  box_test_in_test_mode && domain="test"
  box_state_context "$id" "$uid" "$gid" "$proj" "$domain"
  volume=$(box_state_resolve volume | sed -n 's/^volume=//p') || return 1
  printf 'Execution domain: %s\n' "$([ -n "${BOX_TEST_STATE_NS:-}" ] && printf 'test' || printf 'production')"
  printf 'Harness: %s\nProject: %s\nProject hash: %s\nAuth scope: %s\nAuth policy source: %s\nCanonical auth directory: %s\nNon-auth volume: %s\n' \
    "$id" "$proj" "$hash" "$scope" "$(box_auth_policy_source "$id")" "$dir" "$volume"
  for state in $(box_tool_field "$id" states); do
    box_state_resolve "$state" || return 1
  done
}

# Inventory exact auth objects for removal. Prints paths; deletes only with
# --execute after guarding each identity (refuses active leases, globs, and
# non-identities). Never removes global auth implicitly: project removal
# always targets the project-scoped identity for the given project, even
# when the effective scope is global (the global identity is reported as
# retained). Full inventories include inactive custom-root copies,
# rollback copies, journals, and recorded bindings — never globs.
# Usage: box_ops_remove_auth <harness> <project-path> [--execute]
box_ops_remove_auth() (
  local id=${1:-} proj=${2:-} execute=0 include_global=0 all_projects=0
  box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Usage: remove-auth HARNESS PROJECT [--include-global] [--execute] [--root PATH]'
  shift 2
  local -a roots=() dirs=() inventories=() lock_fds=()
  local root dir scope inv fd uid hash index record
  while (($#)); do
    case "$1" in
      --execute) execute=1; shift ;;
      --include-global) include_global=1; shift ;;
      --all-projects) all_projects=1; shift ;;
      --root) [[ $# -ge 2 ]] || die '--root requires a path.'; roots+=("$2"); shift 2 ;;
      *) die "Unknown remove argument: $1" ;;
    esac
  done
  uid=$(id -u)
  proj=$(box_realpath -e -- "$proj") || return 1
  hash=$(box_state_project_hash "$proj") || return 1
  if box_test_in_test_mode; then
    roots+=("$BOX_TEST_TASK_ROOT/$BOX_TEST_STATE_NS")
  else
    roots+=("$(box_auth_root)")
  fi
  if ! box_test_in_test_mode; then
    roots+=("$HOME/.config/box/auth")
    index="$(box_auth_index_dir)/auth-roots"
    if [[ -e "$index" ]]; then
      box_plan_directory "$index" >/dev/null || return 1
      box_assert_owner_mode "$index" 'Auth root index' dir700
      record=$(python3 -I - "$index" <<'ROOTS'
import hashlib, os, stat, sys
index = sys.argv[1]
for name in sorted(os.listdir(index)):
    path = os.path.join(index, name)
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o600:
        raise ValueError("unsafe root index")
    root = open(path, encoding="utf-8").read()
    if not root.endswith("\n") or "\n" in root[:-1]:
        raise ValueError("invalid root record")
    root = root[:-1]
    if name != hashlib.sha256(root.encode()).hexdigest() + ".root":
        raise ValueError("invalid root record identity")
    print(root)
ROOTS
      ) || die 'Unsafe historical auth root inventory.'
      while IFS= read -r root; do [[ -z "$root" ]] || roots+=("$root"); done <<<"$record"
    fi
  fi
  # Resolve each exact identity under each protected historical root.
  local -A seen=() object_roots=()
  for root in "${roots[@]}"; do
    box_ops_guard_test_domain "$root"
    root=$(BOX_AUTH_ROOT="$root" box_auth_root) || return 1
    local hashes="$hash" selected_hash project_shard
    if ((all_projects)); then
      project_shard=$(dirname -- "$(BOX_AUTH_ROOT="$root" box_auth_object_dir "$id" project "$uid" "$hash")") || return 1
      if [[ -e "$project_shard" || -L "$project_shard" ]]; then
        box_plan_directory "$project_shard" >/dev/null || return 1
        hashes=$(python3 -I - "$project_shard" <<'PROJECTS'
import os, re, stat, sys
root = sys.argv[1]
for name in sorted(os.listdir(root)):
    st = os.lstat(os.path.join(root, name))
    if not re.fullmatch(r"[0-9a-f]{20}", name) or not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        raise ValueError("unexpected project auth shard")
    print(name)
PROJECTS
        ) || die 'Unsafe full project auth inventory.'
      fi
      # A crash after rmdir still leaves the external checkpoint. Discover
      # its project hash, then resolve/validate it through the usual guard;
      # checkpoint coordinates alone never grant deletion authority.
      local removal_index removal_hashes
      removal_index="$(box_auth_index_dir)/locks"
      if [[ -e "$removal_index" || -L "$removal_index" ]]; then
        box_plan_directory "$removal_index" >/dev/null || return 1
        box_assert_owner_mode "$removal_index" 'Removal index' dir700
        removal_hashes=$(python3 -I - "$removal_index" "$project_shard" "$id" "$uid" <<'CHECKPOINTS'
import hashlib, json, os, re, stat, sys
index, root, harness, uid = sys.argv[1:]
for name in sorted(os.listdir(index)):
    if not re.fullmatch(r"auth-[0-9a-f]{64}\.lock\.removal\.json", name):
        continue
    path = os.path.join(index, name)
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) not in (0o400, 0o600):
        raise ValueError("unsafe removal checkpoint")
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    if doc.get("harness") != harness or doc.get("uid") != int(uid) or doc.get("scope") != "project":
        continue
    h = doc.get("project_hash", "")
    if not isinstance(h, str) or not re.fullmatch(r"[0-9a-f]{20}", h):
        raise ValueError("invalid checkpoint project")
    expected = os.path.join(root, h)
    if doc.get("path") != expected:
        continue
    if name != "auth-" + hashlib.sha256(expected.encode()).hexdigest() + ".lock.removal.json":
        raise ValueError("invalid checkpoint coordinate")
    print(h)
CHECKPOINTS
        ) || die 'Unsafe removal checkpoint discovery.'
        hashes=$(printf '%s\n%s\n' "$hashes" "$removal_hashes" | LC_ALL=C sort -u)
      fi
    fi
    for scope in project global; do
      if [[ "$scope" == global ]] && (( ! include_global )); then continue; fi
      while IFS= read -r selected_hash; do
      [[ -n "$selected_hash" || "$scope" == global ]] || continue
      dir=$(BOX_AUTH_ROOT="$root" box_auth_object_dir "$id" "$scope" "$uid" "$selected_hash") || return 1
      [[ -z "${seen[$dir]:-}" ]] || continue
      seen[$dir]=1
      [[ -e "$dir" || -L "$dir" || -e "$(box_auth_stable_lock "$dir").removal.json" ]] || continue
      box_plan_directory "$dir" >/dev/null || return 1
      dirs+=("$dir")
      object_roots[$dir]=$root
      done <<<"$hashes"
    done
  done
  if ((${#dirs[@]})); then
    mapfile -t dirs < <(box_auth_sorted_locks "${dirs[@]}")
  fi
  # Acquire permanent identity locks before the removable local locks. Both
  # classes have deterministic order, shared with launch/migrate/copy.
  if ((execute)); then
    local -a stable_paths=()
    for dir in "${dirs[@]}"; do stable_paths+=("$(box_auth_stable_lock "$dir")"); done
    if ((${#stable_paths[@]})); then
      while IFS= read -r inv; do
        box_auth_open_stable_lock "$inv" || return 1
        exec {fd}>>"$inv" || return 1
        flock -n "$fd" || die 'Auth identity is busy.'
        lock_fds+=("$fd")
      done < <(box_auth_sorted_locks "${stable_paths[@]}")
    fi
    for dir in "${dirs[@]}"; do
      if [[ ! -e "$dir/lock" && -f "$(box_auth_stable_lock "$dir").removal.json" ]]; then continue; fi
      [[ ! -L "$dir/lock" && -f "$dir/lock" ]] || die 'Unsafe removal lock.'
      box_assert_owner_mode "$dir/lock" 'Removal lock' creds
      exec {fd}>>"$dir/lock" || return 1
      flock -n "$fd" || die 'Auth identity is busy.'
      lock_fds+=("$fd")
    done
  fi
  for dir in "${dirs[@]}"; do
    inv=$(BOX_AUTH_ROOT="${object_roots[$dir]}" box_auth_guard_remove "$dir") || return 1
    inventories+=("$inv")
    printf '%s\n' "$inv"
  done
  ((include_global)) || printf 'Global auth retained; --include-global explicitly inventories it.\n'
  if ((execute)); then
    # Every identity passed before any deletion; held locks cover this transaction.
    command -v docker >/dev/null 2>&1 || die 'Docker is required to verify auth removal liveness.'
    box_ops_prepare_docker || return 1
    local holders
    for dir in "${dirs[@]}"; do
      holders=$("${docker_cmd[@]}" ps -q --filter "volume=$dir") || die 'Cannot verify auth removal container liveness.'
      [[ -z "$holders" ]] || die 'Stop live containers holding the auth identity before removal.'
    done
    for dir in "${dirs[@]}"; do box_auth_removal_checkpoint prepare "$dir" || return 1; done
    for dir in "${dirs[@]}"; do
      BOX_AUTH_ROOT="${object_roots[$dir]}" box_auth_guard_remove "$dir" >/dev/null || return 1
    done
    for dir in "${dirs[@]}"; do box_auth_removal_checkpoint execute "$dir" || return 1; done
  else
    printf 'Dry run: pass --execute to remove these exact auth objects.\n'
  fi
)

# Project reset inventory: project non-auth state (volume + home) plus the
# acknowledged project auth identity (unless --keep-auth). Global auth is
# never removed. Refuses when an active/unrecovered projection depends on
# the target. Prints exact descriptors; deletes only with --execute.
# Usage: box_ops_reset <harness> <project-path> [--keep-auth] [--execute]
box_ops_reset() (
  local id=${1:-} proj=${2:-} keep_auth=0 execute=0
  box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Usage: project-reset HARNESS=<id> PROJECT=<path> [--keep-auth] [--execute]'
  shift 2
  while (($#)); do
    case "$1" in --keep-auth) keep_auth=1; shift ;; --execute) execute=1; shift ;; *) die "Unknown reset argument: $1" ;; esac
  done
  command -v jq >/dev/null 2>&1 || die 'jq is required for project reset.'
  local uid gid hash scope dir volume
  uid=$(id -u) || die 'Cannot determine UID.'
  gid=$(id -g) || die 'Cannot determine GID.'
  proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
  hash=$(box_state_project_hash "$proj") || return 1
  scope=$(box_auth_policy_resolve "$id") || return 1
  if [[ "$scope" == global ]]; then dir=$(box_auth_object_dir "$id" "$scope" "$uid") || return 1
  else dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1; fi
  # Reset always targets the project-scoped auth identity for exactness;
  # the effective global identity is never removed by reset.
  local proj_auth_dir
  proj_auth_dir=$(box_auth_object_dir "$id" project "$uid" "$hash") || return 1
  volume=$(box_state_volume_name "$id" "$uid" "$gid" "$hash") || return 1
  if box_test_in_test_mode; then
    volume=$(box_test_volume "$id" "$BOX_TEST_STATE_NS" "$uid" "$gid") || return 1
  fi
  box_ops_guard_test_domain "$dir" "$proj" "$proj_auth_dir"
  # Validate existing native projection locks before creating auth locks or
  # opening any file for append. A name alone never authorizes a lock inode.
  local domain=production home_descriptor home_path="" candidate_lock
  box_test_in_test_mode && domain="test"
  box_state_context "$id" "$uid" "$gid" "$proj" "$domain"
  if [[ "$(box_state_field "$id" home scope 2>/dev/null)" == physical-project ]]; then
    home_descriptor=$(box_state_resolve home) || return 1
    home_path=$(printf '%s\n' "$home_descriptor" | sed -n 's/^path=//p')
    box_plan_directory "$home_path" >/dev/null || return 1
  fi
  for candidate_lock in "$dir/lock" "$proj_auth_dir/lock"     "$(box_auth_index_dir)/locks/$volume.lock" "${home_path:+$home_path/.box-projection.lock}"; do
    [[ -n "$candidate_lock" ]] || continue
    [[ -e "$candidate_lock" || -L "$candidate_lock" ]] || continue
    [[ ! -L "$candidate_lock" && -f "$candidate_lock" ]] || die 'Unsafe reset lock.'
    [[ "$(stat -c %u -- "$candidate_lock")" == "$uid" && "$(stat -c %h -- "$candidate_lock")" == 1 ]]       || die 'Unsafe reset lock ownership or shared inode.'
    case "$(stat -c %a -- "$candidate_lock")" in 600|400) ;; *) die 'Unsafe reset lock mode.' ;; esac
  done
  # Keep authorization and deletion in one locked transaction.
  local reset_auth_fd reset_project_fd reset_volume_fd reset_lock
  if ((execute)); then
    local reset_stable reset_fd
    local -a reset_stable_paths=()
    reset_stable_paths+=("$(box_auth_stable_lock "$dir")" "$(box_auth_stable_lock "$proj_auth_dir")")
    while IFS= read -r reset_stable; do
      box_auth_open_stable_lock "$reset_stable" || return 1
      exec {reset_fd}>>"$reset_stable" || return 1
      flock -n "$reset_fd" || die 'Auth identity is busy.'
    done < <(box_auth_sorted_locks "${reset_stable_paths[@]}")
    while IFS= read -r reset_lock; do
      [[ -e "$reset_lock" ]] || continue
      [[ ! -L "$reset_lock" && -f "$reset_lock" ]] || die 'Unsafe reset lock.'
      if [[ "$reset_lock" == "$dir/lock" ]]; then
        exec {reset_auth_fd}>>"$reset_lock"
        flock -n "$reset_auth_fd" || die 'Auth identity is busy.'
      elif [[ "$proj_auth_dir" != "$dir" ]]; then
        exec {reset_project_fd}>>"$reset_lock"
        flock -n "$reset_project_fd" || die 'Project auth identity is busy.'
      fi
    done < <(box_auth_sorted_locks "$dir/lock" "$proj_auth_dir/lock")
    reset_lock="$(box_auth_index_dir)/locks/$volume.lock"
    box_prepare_directory "$(dirname -- "$reset_lock")" 700 >/dev/null || return 1
    [[ ! -L "$reset_lock" ]] || die 'Unsafe reset projection lock.'
    box_auth_open_stable_lock "$reset_lock" || return 1
    exec {reset_volume_fd}>>"$reset_lock"
    flock -n "$reset_volume_fd" || die 'Project projection is busy.'
  fi
  if [[ -f "$proj_auth_dir/lease.json" ]] && jq -e '.state == "active"' -- "$proj_auth_dir/lease.json" >/dev/null 2>&1; then
      die 'Refusing reset: the project auth lease is active/unrecovered; recover first.'
    fi
    if [[ -f "$dir/lease.json" ]] && jq -e '.state == "active"' -- "$dir/lease.json" >/dev/null 2>&1; then
      die 'Refusing reset: the effective auth lease is active/unrecovered; recover first.'
    fi
  if [[ -n "$home_path" ]]; then
    if ((execute)) && [[ -d "$home_path" ]]; then
      local reset_home_fd
      [[ ! -L "$home_path/.box-projection.lock" ]] || die 'Unsafe home projection lock.'
      box_auth_open_stable_lock "$home_path/.box-projection.lock" || return 1
      exec {reset_home_fd}>>"$home_path/.box-projection.lock"
      flock -n "$reset_home_fd" || die 'Project home projection is busy.'
    fi
    printf '%s\n' "$home_descriptor"
  fi
  if ((execute)); then
    command -v docker >/dev/null 2>&1 || die 'Docker is required for project reset.'
    box_ops_prepare_docker || return 1
    local holders
    holders=$("${docker_cmd[@]}" ps -q --filter "volume=$volume") || die 'Cannot check reset container liveness.'
    [[ -z "$holders" ]] || die 'Stop clients before project reset.'
    if [[ -n "$home_path" ]]; then
      holders=$("${docker_cmd[@]}" ps -q --filter "volume=$home_path") || return 1
      [[ -z "$holders" ]] || die 'Stop clients holding the project home before reset.'
    fi
  fi
  printf 'Non-auth volume: volume:%s\n' "$volume"
  if (( ! keep_auth )); then
    if [[ -d "$proj_auth_dir" ]]; then
      box_auth_guard_remove "$proj_auth_dir" || return 1
    else
      printf 'No project auth at %s (global auth preserved).\n' "$proj_auth_dir"
    fi
  else
    printf 'Project auth retained (--keep-auth or global scope; global auth is never removed by reset).\n'
  fi
  if ((execute)); then
    local reset_journal reset_helper reset_stage reset_volume_identity
    reset_journal="$(box_auth_index_dir)/resets/$id-u$uid-g$gid-$hash.json"
    reset_helper="${BUNDLE_DIR:-$(dirname -- "$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")")")}/lib/state-transaction.py"
    box_prepare_directory "$(dirname -- "$reset_journal")" 700 >/dev/null || return 1
    local -a reset_opts=()
    ((keep_auth)) && reset_opts+=(--keep-auth)
    reset_volume_identity=$(box_ops_volume_identity "$volume" "${docker_cmd[@]}") || return 1
    python3 -I "$reset_helper" prepare --volume-identity "$reset_volume_identity" --journal "$reset_journal" --root "$home_path" \
      --harness "$id" --uid "$uid" --gid "$gid" --project-hash "$hash" --volume "$volume" \
      --auth "$proj_auth_dir" --domain "$domain" "${reset_opts[@]}" || return 1
    reset_stage=$(jq -r .stage -- "$reset_journal") || return 1
    if [[ "$reset_stage" == planned ]]; then
      python3 -I "$reset_helper" remove-home --journal "$reset_journal" || return 1
      [[ "${BOX_STATE_RESET_FAULT:-}" != home ]] || die 'Injected reset interruption after home removal.'
      python3 -I "$reset_helper" stage --journal "$reset_journal" --value home_removed || return 1
      reset_stage=home_removed
    fi
    if [[ "$reset_stage" == home_removed ]]; then
      # Query the exact volume inventory: missing after a crash is completion;
      # daemon/query failure never authorizes proceeding.
      reset_volume_identity=$(box_ops_volume_identity "$volume" "${docker_cmd[@]}") || return 1
      if [[ -n "$reset_volume_identity" ]]; then
        python3 -I "$reset_helper" verify-volume --journal "$reset_journal" \
          --volume-identity "$reset_volume_identity" || return 1
        "${docker_cmd[@]}" volume rm -- "$volume" || die 'Cannot remove project volume.'
      fi
      [[ "${BOX_STATE_RESET_FAULT:-}" != volume ]] || die 'Injected reset interruption after volume removal.'
      python3 -I "$reset_helper" stage --journal "$reset_journal" --value volume_removed || return 1
      reset_stage=volume_removed
    fi
    if [[ "$reset_stage" == volume_removed ]] && (( ! keep_auth )) && \
        [[ -d "$proj_auth_dir" || -e "$(box_auth_stable_lock "$proj_auth_dir").removal.json" ]]; then
      box_auth_guard_remove "$proj_auth_dir" >/dev/null || return 1
      box_auth_removal_checkpoint prepare "$proj_auth_dir" || return 1
      box_auth_removal_checkpoint execute "$proj_auth_dir" || return 1
    fi
    [[ "${BOX_STATE_RESET_FAULT:-}" != auth ]] || die 'Injected reset interruption after auth removal.'
    python3 -I "$reset_helper" stage --journal "$reset_journal" --value auth_removed || return 1
    python3 -I "$reset_helper" finish --journal "$reset_journal" || return 1
    printf 'Removed resolved project state.\n' 
  else
    printf 'Dry run: pass --execute to remove inventoried auth paths above.\n'
  fi
)


# Persistent volume names can be reused after removal. Check the Engine's
# creation identity against the checkpoint before deleting a surviving name.
box_ops_volume_identity() {
  local name=$1; shift
  [[ -n "$name" ]] || return 0
  local names metadata
  names=$("$@" volume ls -q) || die 'Cannot query exact volume inventory.'
  if ! printf '%s\n' "$names" | grep -Fxq -- "$name"; then return 0; fi
  metadata=$("$@" volume inspect --format '{{json .}}' -- "$name") || die 'Cannot inspect exact volume identity.'
  jq -ce --arg name "$name" 'select(.Name == $name and (.CreatedAt | type == "string" and length > 0) and (.Driver | type == "string" and length > 0)) | {Name,CreatedAt,Driver,Mountpoint,Scope}' <<<"$metadata" || die 'Invalid volume creation identity.'
}

# Full removal includes recorded inactive native roots, project volumes,
# both auth scopes/custom roots, rollback copies and discovery bindings.
# A harness lifecycle lock excludes all supervised live launchers. The
# durable outer inventory fixes the targets before any removal; each native
# store has a recoverable exact-member checkpoint. Code/provider removal
# remains explicit so state cleanup never implies deleting an external key.
box_ops_remove_full() (
  local id=${1:-} proj=${2:-} execute=0 provider="" code=0
  box_require_tool "$id"
  shift 2
  while (($#)); do
    case "$1" in
      --execute) execute=1; shift ;;
      --code) code=1; shift ;;
      --provider) [[ $# -ge 2 ]] || die '--provider requires an exact external file.'; provider=$2; shift 2 ;;
      *) die "Unknown full removal argument: $1" ;;
    esac
  done
  local bundle index records journal fd item state path volume root digest helper stage
  bundle=${BUNDLE_DIR:-$(dirname -- "$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")")")}
  index=$(box_auth_index_dir) || return 1
  helper="$bundle/lib/state-transaction.py"
  box_ops_plan "$id" "$proj" || return 1
  journal="$index/removals/$id.json"
  if [[ -n "$provider" && ( -e "$provider" || ! -f "$journal" ) ]]; then
    [[ "$provider" == /* && -f "$provider" && ! -L "$provider" ]] || die 'Provider removal requires an exact regular external file.'
    box_plan_directory "$(dirname -- "$provider")" >/dev/null || return 1
    box_assert_outside_project "$provider" 'Provider removal'
    box_assert_owner_mode "$provider" 'Provider removal' creds
    box_ops_guard_test_domain "$provider"
  fi
  if ((execute)); then
    box_auth_open_stable_lock "$index/locks/lifecycle-$id.lock" || return 1
    exec {fd}>>"$index/locks/lifecycle-$id.lock" || return 1
    flock -n "$fd" || die 'Harness has an active launcher or lifecycle operation.'
    BOX_STATE_OPERATION_FD=$fd
    # Record the currently resolved coordinates too; no prior launch is needed.
    local host_uid host_gid project
    host_uid=$(id -u); host_gid=$(id -g); project=$(box_realpath -e -- "$proj") || return 1
    if [[ ! -e "$journal" ]]; then box_state_record_native "$id" || return 1; fi
  fi
  local -a snapshot_opts=()
  if [[ -e "$journal" ]]; then snapshot_opts+=(--snapshot "$journal")
  else snapshot_opts+=(--current-project "$proj"); fi
  records=$(python3 -I "$bundle/lib/state-inventory.py" "$bundle" "$index" "$id" "${snapshot_opts[@]}") || return 1
  while IFS= read -r item; do
    local pending_reset
    pending_reset="$index/resets/$id-u$(jq -r .descriptor.uid <<<"$item")-g$(jq -r .descriptor.gid <<<"$item")-$(jq -r .descriptor.project_hash <<<"$item").json"
    [[ ! -e "$pending_reset" && ! -L "$pending_reset" ]] || die 'Resume interrupted project-reset before full state removal.'
  done < <(jq -c '.[]' <<<"$records")
  printf '%s\n' "$records" | jq -r '.[] | .descriptor | "Native state: \(.domain) \(.harness) \(.state) \(.path)"'
  box_ops_remove_auth "$id" "$proj" --all-projects --include-global || return 1
  ((code == 0)) || box_ops_uninstall_code "$id" || return 1
  [[ -z "$provider" ]] || printf 'External provider file: %s\n' "$provider"
  local -a members=()
  while IFS= read -r item; do
    members+=("$(jq -r .record <<<"$item")")
    members+=("$(box_auth_binding_file "$id" "$(jq -r .descriptor.project_hash <<<"$item")")")
  done < <(jq -c '.[]' <<<"$records")
  local cfg asset leaf
  cfg="$HOME/.config/$(box_tool_field "$id" config_dir)"
  for asset in $(box_tool_field "$id" artifacts); do
    leaf=$(box_artifact_field "$id" "$asset" installed)
    [[ -z "$leaf" ]] || members+=("$cfg/$leaf" "$cfg/$leaf.bak")
  done
  members+=("$cfg/$(box_tool_field "$id" version_file)" "$cfg/docker-cli/config.json" "$cfg/docker-cli/config.json.bak")
  [[ -z "$provider" ]] || members+=("$provider")
  printf 'Installed state/metadata: %s\n' "${members[@]}"
  if (( ! execute )); then printf 'Dry run: FULL=1 EXECUTE=1 removes this exact full inventory.\n'; return 0; fi
  # Use the isolated local Engine command, never ambient contexts/proxies.
  # shellcheck source=lib/docker.sh
  source "$bundle/lib/docker.sh"
  box_docker_cli "$index/docker-cli"
  journal="$index/removals/$id.json"
  box_prepare_directory "$(dirname -- "$journal")" 700 >/dev/null || return 1
  # The outer checkpoint survives all subtransactions. Its options and
  # descriptors must match on recovery; changing roots/flags is a refusal.
  python3 -I - "$journal" "$records" "$code" "$provider" "$(box_auth_root)" <<'CHECKPOINT' || die 'Full removal inventory changed; resume the original operation.'
import json, os, stat, sys, tempfile
path, records, code, provider, auth_root = sys.argv[1:]
doc = dict(format="box-full-removal-v1", records=json.loads(records), code=bool(int(code)), provider=provider, auth_root=auth_root)
if os.path.lexists(path):
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1:
        raise ValueError("unsafe full removal checkpoint")
    old = json.load(open(path, encoding="utf-8"))
    stage = old.pop("stage", None)
    if old != doc or stage not in (None, "native-complete"):
        raise ValueError("changed full removal inventory")
else:
    fd, tmp = tempfile.mkstemp(prefix=".removal.", dir=os.path.dirname(path))
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump(doc, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, path)
    fd = os.open(os.path.dirname(path), os.O_RDONLY | os.O_DIRECTORY)
    os.fsync(fd)
    os.close(fd)
CHECKPOINT
  # Persist completion before retiring subcheckpoints. A crash in final
  # cleanup must never inventory a newly recreated volume as the old target.
  finish_full_removal() {
    while IFS= read -r path; do
      digest=$(printf '%s' "$path" | sha256sum); digest=${digest%% *}
      if [[ -e "$index/removals/$id-$digest.json" ]]; then
        python3 -I "$helper" finish --journal "$index/removals/$id-$digest.json" || return 1
      fi
    done < <(jq -r 'unique_by(.descriptor.path)[].descriptor.path' <<<"$records")
    if ((code)); then box_ops_uninstall_code "$id" --execute || return 1; fi
    rm -f -- "$journal" "$index/removals/$id-members.json" || return 1
    python3 -I - "$index/removals" <<'FLUSH' || return 1
import os, sys
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(fd)
finally:
    os.close(fd)
FLUSH
    printf 'Removed full inventoried state for %s. Permanent lifecycle locks retained.\n' "$id"
  }
  if jq -e '.stage == "native-complete"' -- "$journal" >/dev/null 2>&1; then
    finish_full_removal
    return $?
  fi
  # Lock every native projection as well: migration/recovery operations
  # also use these inodes and may run without a launcher lifecycle lease.
  local native_fd native_lock
  local -a native_locks=()
  while IFS= read -r path; do
    case "$path" in
      volume:*) native_locks+=("$index/locks/${path#volume:}.lock") ;;
      *) [[ ! -d "$path" ]] || native_locks+=("$path/.box-projection.lock") ;;
    esac
  done < <(jq -r 'unique_by(.descriptor.path)[].descriptor.path' <<<"$records")
  if ((${#native_locks[@]})); then
    while IFS= read -r native_lock; do
      box_auth_open_stable_lock "$native_lock" || return 1
      exec {native_fd}>>"$native_lock" || return 1
      flock -n "$native_fd" || die 'Native state is busy; stop/recover it before full removal.'
    done < <(box_auth_sorted_locks "${native_locks[@]}")
  fi
  python3 -I "$bundle/lib/state-members.py" --prepare "$index/removals/$id-members.json" "${members[@]}" || return 1
  if ((code)); then box_ops_uninstall_code "$id" --prepare || return 1; fi
  # Validate every liveness query and all manifests before deleting any store.
  local holders
  while IFS= read -r item; do
    path=$(jq -r .descriptor.path <<<"$item")
    root=""; volume=""
    case "$path" in volume:*) volume=${path#volume:} ;; *) root=$path; box_plan_directory "$root" >/dev/null || return 1 ;; esac
    box_ops_guard_test_domain "$path"
    holders=$("${docker_cmd[@]}" ps -aq --filter "volume=${volume:-$root}") || die 'Cannot check full removal container liveness.'
    [[ -z "$holders" ]] || die 'Remove dependent containers before full state removal.'
    digest=$(printf '%s' "$path" | sha256sum); digest=${digest%% *}
    local volume_identity
    volume_identity=$(box_ops_volume_identity "$volume" "${docker_cmd[@]}") || return 1
    python3 -I "$helper" prepare --volume-identity "$volume_identity" --journal "$index/removals/$id-$digest.json" --root "$root" \
      --harness "$id" --uid "$(jq -r .descriptor.uid <<<"$item")" --gid "$(jq -r .descriptor.gid <<<"$item")" \
      --project-hash "$(jq -r .descriptor.project_hash <<<"$item")" --volume "$volume" \
      --domain "$(jq -r .descriptor.domain <<<"$item")" --keep-auth || return 1
  done < <(jq -c 'unique_by(.descriptor.path)[]' <<<"$records")
  # Auth refusal checks run before native deletion. The removal function
  # acquires exact identity locks, verifies liveness and resumes checkpoints.
  box_ops_remove_auth "$id" "$proj" --all-projects --include-global --execute || return 1
  [[ "${BOX_STATE_REMOVE_FAULT:-}" != auth ]] || die 'Injected full removal interruption after auth.'
  while IFS= read -r item; do
    path=$(jq -r .descriptor.path <<<"$item")
    digest=$(printf '%s' "$path" | sha256sum); digest=${digest%% *}
    local checkpoint
    checkpoint="$index/removals/$id-$digest.json"
    stage=$(jq -r .stage -- "$checkpoint") || return 1
    if [[ "$stage" == planned ]]; then
      python3 -I "$helper" remove-home --journal "$checkpoint" || return 1
      python3 -I "$helper" stage --journal "$checkpoint" --value home_removed || return 1
      stage=home_removed
    fi
    if [[ "$stage" == home_removed ]]; then
      volume=$(jq -r .volume -- "$checkpoint") || return 1
      if [[ -n "$volume" ]]; then
        volume_identity=$(box_ops_volume_identity "$volume" "${docker_cmd[@]}") || return 1
        if [[ -n "$volume_identity" ]]; then
          python3 -I "$helper" verify-volume --journal "$checkpoint" \
            --volume-identity "$volume_identity" || return 1
          "${docker_cmd[@]}" volume rm -- "$volume" || return 1
        fi
      fi
      python3 -I "$helper" stage --journal "$checkpoint" --value auth_removed || return 1
    fi
  done < <(jq -c 'unique_by(.descriptor.path)[]' <<<"$records")
  [[ "${BOX_STATE_REMOVE_FAULT:-}" != native ]] || die 'Injected full removal interruption after native state.'
  # Remove exact recorded discovery/binding files after their stores. Keep
  # permanent identity locks and root-discovery metadata for safe recreation.
  # Exact file transaction includes the optional external credentials.
  python3 -I "$bundle/lib/state-members.py" "$index/removals/$id-members.json" "${members[@]}" || return 1
  [[ "${BOX_STATE_REMOVE_FAULT:-}" != metadata ]] || die 'Injected full removal interruption after metadata.'
  python3 -I - "$journal" <<'COMPLETE' || return 1
import json, os, sys, tempfile
path = sys.argv[1]
with open(path, encoding="utf-8") as stream:
    doc = json.load(stream)
doc["stage"] = "native-complete"
fd, tmp = tempfile.mkstemp(prefix=".complete.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(doc, stream, sort_keys=True)
    stream.flush()
    os.fsync(stream.fileno())
os.replace(tmp, path)
fd = os.open(os.path.dirname(path), os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(fd)
finally:
    os.close(fd)
COMPLETE
  [[ "${BOX_STATE_REMOVE_FAULT:-}" != completion ]] || die 'Injected full removal interruption before checkpoint cleanup.'
  finish_full_removal

)

# Code-only uninstall enumerates registered code paths. Other bin/lib files,
# installed templates/pins and all native/auth/provider state are preserved.
box_ops_uninstall_code() (
  local id=${1:-} execute=${2:-} bundle base file relative index
  box_require_tool "$id"
  bundle=${BUNDLE_DIR:-$(dirname -- "$(dirname -- "$(box_realpath -e -- "${BASH_SOURCE[0]}")")")}
  base="$HOME/.local/bin"
  local -a members=("$base/$(box_tool_field "$id" launcher)")
  for file in "$bundle/harnesses/$id/"*.sh "$bundle/harnesses/$id/"*.py; do
    [[ -f "$file" ]] || continue
    relative=${file#"$bundle/"}; members+=("$base/$relative")
  done
  # Shared helpers can still serve another installed harness. Last uninstall
  # removes only filenames supplied by this package, leaving unknown files.
  local other remaining=0
  for other in $box_tool_ids; do
    [[ "$other" == "$id" || ! -e "$base/$(box_tool_field "$other" launcher)" ]] || remaining=1
  done
  if ((remaining == 0)); then
    for file in "$bundle/lib/"*.sh "$bundle/lib/"*.py; do
      [[ -f "$file" ]] || continue
      members+=("$base/lib/${file##*/}")
    done
  fi
  if [[ -L "$base/box" && "$(readlink -- "$base/box")" == "$(box_tool_field "$id" launcher)" ]]; then members+=("$base/box"); fi
  # Login wrapper belongs to the registry's first/default harness.
  [[ "$id" != "${box_tool_ids%% *}" ]] || members+=("$base/box-m-login")
  printf 'Installed code: %s\n' "${members[@]}"
  [[ "$execute" == --execute || "$execute" == --prepare ]] || return 0
  index=$(box_auth_index_dir) || return 1
  box_prepare_directory "$index/removals" 700 >/dev/null || return 1
  local lock code_fd
  lock="$index/locks/lifecycle-$id.lock"
  box_auth_open_stable_lock "$lock" || return 1
  if [[ -n "${BOX_STATE_OPERATION_FD:-}" ]]; then
    [[ "$(stat -Lc '%d:%i' -- "/proc/self/fd/$BOX_STATE_OPERATION_FD")" == "$(stat -c '%d:%i' -- "$lock")" ]] || die 'Invalid inherited lifecycle lock.'
    code_fd=$BOX_STATE_OPERATION_FD
  else
    exec {code_fd}>>"$lock" || return 1
  fi
  flock -n "$code_fd" || die 'Harness is active; stop it before uninstalling code.'
  local -a member_opts=()
  [[ "$execute" != --prepare ]] || member_opts+=(--prepare)
  BOX_STATE_DEFAULT_TARGET="$(box_tool_field "$id" launcher)" python3 -I "$bundle/lib/state-members.py" "${member_opts[@]}" "$index/removals/code-$id.json" "${members[@]}" || return 1
  [[ "$execute" != --prepare ]] || return 0
  rm -f -- "$index/removals/code-$id.json" || return 1
)

# CLI dispatcher for Make targets and operator use.
# Usage: auth-ops.sh <migrate|copy|init|recover|plan|remove-auth|reset> ...
box_ops_cli() {
  local sub=${1:-}
  [[ -n "$sub" ]] || die 'Usage: auth-ops.sh <migrate|copy|init|recover|plan|remove-auth|reset> ...'
  shift
  # Owner/mode guards compare against the invoking user; launchers set these
  # globals, but direct Make/operator invocations do not.
  if [[ -z "${host_uid:-}" ]]; then host_uid=$(id -u) || die 'Cannot determine UID.'; fi
  if [[ -z "${host_gid:-}" ]]; then host_gid=$(id -g) || die 'Cannot determine GID.'; fi
  ((10#$host_uid != 0 && 10#$host_gid != 0)) || die 'Run as your normal non-root host user.'
  case "$sub" in
    migrate|init|recover|plan|remove-auth|remove-full|reset)
      [[ $# -ge 2 ]] || die 'State operations require a harness and explicit physical project.'
      project=$(box_realpath -e -- "$2") || die 'Cannot resolve project.' ;;
  esac
  case "$sub" in
    migrate) box_ops_migrate "$@" ;;
    copy) box_ops_copy "$@" ;;
    init) box_ops_init "$@" ;;
    recover) box_ops_recover "$@" ;;
    plan) box_ops_plan "$@" ;;
    remove-auth) box_ops_remove_auth "$@" ;;
    reset) box_ops_reset "$@" ;;
    remove-full) box_ops_remove_full "$@" ;;
    uninstall-code) box_ops_uninstall_code "$@" ;;
    discover)
      [[ $# -eq 2 || ( $# -eq 3 && "$3" == --historical ) ]] || die 'Usage: discover HARNESS PROJECT [--historical]'
      local id=$1 historical=""
      [[ "${3:-}" != --historical ]] || historical=historical
      if [[ -n "$historical" ]]; then project=$(box_realpath -m -- "$2") || return 1
      else project=$(box_realpath -e -- "$2") || return 1; fi
      box_auth_policy_resolve "$id" >/dev/null || return 1
      box_state_record_native "$id" "$historical" ;;
    *) die "Unknown auth-ops command: $sub" ;;
  esac
}

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  box_ops_cli "$@"
fi
