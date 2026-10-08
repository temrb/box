# auth-lifecycle.bats — leases, recovery, removal guards, dry-run purity,
# and setup preservation. No Docker; synthetic fixtures only.
load helpers

@test "scope acknowledgments use private durable publication and reject shared bindings" {
  h=$(box_state_project_hash "$project")
  binding=$(box_auth_binding_file codex "$h")
  mkdir -p -m 700 "$(dirname "$binding")"
  printf foreign >"$TEST_TMP/foreign-binding"
  ln -s "$TEST_TMP/foreign-binding" "$binding.tmp.$$"
  box_auth_transition_plan codex "$host_uid" "$h" "$project"
  [ "$(cat "$TEST_TMP/foreign-binding")" = foreign ]
  [ "$(stat -c %a "$binding")" = 600 ]
  ln "$binding" "$PROJ_ROOT/shared-binding"
  BOX_AUTH_SCOPE=global BOX_AUTH_TRANSITION=use-existing run box_auth_transition_plan codex "$host_uid" "$h" "$project"
  [ "$status" -ne 0 ]
  [ "$(sed -n '1p' "$binding")" = "$(box_auth_object_dir codex project "$host_uid" "$h")" ]
}

# Explicit no-container oracle for synthetic storage tests. Cases that exercise
# liveness override this fixture; no runtime acceptance is inferred here.
docker() { return 0; }

_auth_dir_for() {
  local id=$1 scope=$2
  local h
  h=$(box_state_project_hash "$project")
  if [[ "$scope" == global ]]; then
    box_auth_object_dir "$id" "$scope" "$host_uid"
  else
    box_auth_object_dir "$id" "$scope" "$host_uid" "$h"
  fi
}

@test "auth objects are created with 700/600 metadata" {
  dir=$(_auth_dir_for muse global)
  box_auth_ensure_object "$dir" muse global "$host_uid" "$(box_state_project_hash "$project")"
  [ "$(stat -c %a -- "$dir")" = "700" ]
  for f in identity.json credentials.json lease.json lock; do
    [ "$(stat -c %a -- "$dir/$f")" = "600" ]
  done
  jq -e --arg h muse '.harness == $h and .schema_version == 1' -- "$dir/identity.json" >/dev/null
  jq -e '.tombstone == true' -- "$dir/credentials.json" >/dev/null
  jq -e '.state == "idle"' -- "$dir/lease.json" >/dev/null
}

@test "busy auth and projection locks fail promptly" {
  h=$(box_state_project_hash "$project")
  dir=$(_auth_dir_for codex project)
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  proj_lock="$TEST_TMP/proj.lock"
  box_auth_lease_reserve "$dir" "$proj_lock"
  run box_auth_lease_reserve "$dir" "$proj_lock"
  [ "$status" -ne 0 ]
  [[ "$output" == *"busy"* ]]
  box_auth_lease_release "$dir"
  box_auth_lease_reserve "$dir" "$proj_lock"
  box_auth_lease_release "$dir"
}

@test "lock order is deterministic" {
  [ "$(box_auth_sorted_locks /b /a /b)" = "$(printf '/a\n/b')" ]
}

@test "recovery is idle-quiet and refuses missing projections" {
  h=$(box_state_project_hash "$project")
  dir=$(_auth_dir_for codex project)
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  run box_auth_recover "$dir"
  [ "$status" -eq 0 ]
  proj_lock="$TEST_TMP/recover.lock"
  box_auth_lease_reserve "$dir" "$proj_lock"
  rm -f -- "$proj_lock"
  run box_auth_recover "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing projection"* ]]
  box_auth_lease_release "$dir"
}

@test "removal needs an exact idle identity, never globs" {
  h=$(box_state_project_hash "$project")
  dir=$(_auth_dir_for muse global)
  box_auth_ensure_object "$dir" muse global "$host_uid" "$h"
  run box_auth_guard_remove "$dir*"
  [ "$status" -ne 0 ]
  run box_auth_guard_remove "$TEST_TMP"
  [ "$status" -ne 0 ]
  run box_auth_guard_remove "$dir"
  [ "$status" -eq 0 ]
  proj_lock="$TEST_TMP/rm.lock"
  box_auth_lease_reserve "$dir" "$proj_lock"
  run box_auth_guard_remove "$dir"
  [ "$status" -ne 0 ]
  box_auth_lease_release "$dir"
}

@test "dry-run planning reads no credentials and writes nothing" {
  before=$(find "$HOME" -mindepth 1 2>/dev/null | sort)
  run box_auth_plan muse "$host_uid" "$(box_state_project_hash "$project")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Auth scope:"* ]]
  [[ "$output" != *"token"* ]]
  after=$(find "$HOME" -mindepth 1 2>/dev/null | sort)
  [ "$before" = "$after" ]
}

@test "setup preserves policy, journals, and indexes byte-for-byte" {
  policy="$HOME/.config/box/state.toml"
  mkdir -p -- "$(dirname -- "$policy")"
  printf 'schema_version = 1\n' >"$policy"
  chmod 600 -- "$policy"
  before=$(sha256sum -- "$policy")
  run box_install_state_policy "$policy"
  [ "$status" -eq 0 ]
  [ "$(sha256sum -- "$policy")" = "$before" ]
  [ "$(stat -c %a -- "$policy")" = "600" ]
}

@test "shared prepare wraps ensure, transition, reserve, and install" {
  h=$(box_state_project_hash "$project")
  docker() { return 0; }
  box_ops_init muse "$project" >/dev/null
  native="$TEST_TMP/prepared-auth.json"
  proj_lock="$TEST_TMP/prepared.lock"
  dir=$(box_auth_prepare muse "$host_uid" "$h" "$proj_lock" "$native" "$BUNDLE_DIR")
  [[ "$dir" == */muse/u"$host_uid"/global ]]
  # Fresh canonical identity installs a tombstone: no native projection yet.
  [ ! -e "$native" ]
  # A native login during the run is collected back on exit.
  printf '%s' '{"schema_version":1,"providers":{"meta":{"api_key":"synthetic"}}}' >"$native"
  box_auth_collect_projection muse "$dir" "$native" "$BUNDLE_DIR"
  box_auth_lease_release "$dir"
  jq -e '.payload.providers.meta.api_key == "synthetic"' -- "$dir/credentials.json" >/dev/null
  [ ! -e "$native" ]
}

@test "hash collision across physical paths fails instead of sharing" {
  h=$(box_state_project_hash "$project")
  box_auth_transition_plan muse "$host_uid" "$h" "$project"
  run box_auth_transition_plan muse "$host_uid" "$h" "$project-elsewhere"
  [ "$status" -ne 0 ]
  [[ "$output" == *"collision"* ]]
}

@test "scope change needs an explicit transition choice" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h" >/dev/null
  box_auth_transition_plan codex "$host_uid" "$h"
  BOX_AUTH_SCOPE=global run box_auth_transition_plan codex "$host_uid" "$h"
  [ "$status" -ne 0 ]
  BOX_AUTH_SCOPE=global BOX_AUTH_TRANSITION=use-existing run box_auth_transition_plan codex "$host_uid" "$h"
  [ "$status" -eq 0 ]
}

@test "dry-run report lists migration, transition and legacy without mutation" {
  h=$(box_state_project_hash "$project")
  before=$(find "$HOME" -mindepth 1 2>/dev/null | sort)
  run box_auth_dryrun_report muse "$host_uid" "$h" "$TEST_TMP/legacy-auth.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Migration required:"* ]]
  [[ "$output" == *"Transition required:"* ]]
  [[ "$output" == *"Legacy candidate:"* ]]
  after=$(find "$HOME" -mindepth 1 2>/dev/null | sort)
  [ "$before" = "$after" ]
}

@test "project removal inventories project auth even when effective scope is global" {
  h=$(box_state_project_hash "$project")
  proj_dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$proj_dir" codex project "$host_uid" "$h" >/dev/null
  BOX_AUTH_SCOPE=global run box_ops_remove_auth codex "$project"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$proj_dir/identity.json"* ]]
  [[ "$output" == *"Global auth retained"* ]]
}

@test "project reset removes resolved Codex home and volume while retaining auth" {
  h=$(box_state_project_hash "$project")
  home_path="$HOME/.config/box-c/projects/$h/codex-home"
  mkdir -p "$home_path"
  printf 'session-marker' >"$home_path/history.jsonl"
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  docker() {
    if [[ "$1" == volume && "$2" == ls ]]; then
      box_state_volume_name codex "$host_uid" "$host_gid" "$h"
    elif [[ "$1" == volume && "$2" == inspect ]]; then
      printf '{"Name":"%s","CreatedAt":"fixture","Driver":"local"}\n' "$volume"
    elif [[ "$1" == volume && "$2" == rm ]]; then
      printf '%s\n' "$4" >"$TEST_TMP/removed-volume"
    fi
  }
  export -f docker
  run box_ops_reset codex "$project" --keep-auth --execute
  [ "$status" -eq 0 ]
  [ ! -e "$home_path" ]
  [ -f "$dir/credentials.json" ]
  [ "$(cat "$TEST_TMP/removed-volume")" = "$(box_state_volume_name codex "$host_uid" "$host_gid" "$h")" ]
}

@test "keep-auth reset refuses an unrecovered lease" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  printf '{"state":"active"}\n' >"$dir/lease.json"
  run box_ops_reset codex "$project" --keep-auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"active/unrecovered"* ]]
}

@test "auth removal rejects metadata transplanted from a different harness" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  jq '.harness = "muse"' "$dir/identity.json" >"$TEST_TMP/identity"
  cp "$TEST_TMP/identity" "$dir/identity.json"
  run box_auth_guard_remove "$dir"
  [ "$status" -ne 0 ]
  [ -f "$dir/credentials.json" ]
}

@test "removal inventories historical custom roots and protected rollback copies" {
  h=$(box_state_project_hash "$project")
  old="$HOME/old-auth"
  current="$HOME/new-auth"
  dir=$(BOX_AUTH_ROOT="$old" box_auth_object_dir codex project "$host_uid" "$h")
  BOX_AUTH_ROOT="$old" box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  printf '{}' >"$dir/legacy-auth-rollback.json"
  chmod 600 "$dir/legacy-auth-rollback.json"
  BOX_AUTH_ROOT="$current" run box_ops_remove_auth codex "$project"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$dir/legacy-auth-rollback.json"* ]]
  BOX_AUTH_ROOT="$current" run box_ops_remove_auth codex "$project" --execute
  [ "$status" -eq 0 ]
  [ ! -e "$dir" ]
}

@test "unknown removal artifacts prevent partial deletion" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  printf 'recovery material' >"$dir/unknown-checkpoint"
  chmod 600 "$dir/unknown-checkpoint"
  run box_ops_remove_auth codex "$project" --execute
  [ "$status" -ne 0 ]
  [ -f "$dir/credentials.json" ]
  [ -f "$dir/unknown-checkpoint" ]
}

@test "invalid lease metadata never becomes an idle lease" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  printf '{}' >"$dir/lease.json"
  run box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  [ "$status" -ne 0 ]
  [ "$(cat "$dir/lease.json")" = '{}' ]
}

@test "fresh initialization refuses a busy identity" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  exec {fixture_fd}>>"$dir/lock"
  flock -n "$fixture_fd"
  run box_ops_init codex "$project"
  [ "$status" -ne 0 ]
  [ ! -e "$dir/migration.json" ]
  exec {fixture_fd}>&-
}

@test "all-project auth removal inventories both scopes and every exact project" {
  h=$(box_state_project_hash "$project")
  second=0123456789abcdefabcd
  first_dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  second_dir=$(box_auth_object_dir codex project "$host_uid" "$second")
  global_dir=$(box_auth_object_dir codex global "$host_uid")
  box_auth_ensure_object "$first_dir" codex project "$host_uid" "$h"
  box_auth_ensure_object "$second_dir" codex project "$host_uid" "$second"
  box_auth_ensure_object "$global_dir" codex global "$host_uid" ""
  run box_ops_remove_auth codex "$project" --all-projects --include-global
  [ "$status" -eq 0 ]
  [[ "$output" == *"$first_dir/identity.json"* ]]
  [[ "$output" == *"$second_dir/identity.json"* ]]
  [[ "$output" == *"$global_dir/identity.json"* ]]
  exec {fixture_fd}>>"$second_dir/lock"
  flock -n "$fixture_fd"
  run box_ops_remove_auth codex "$project" --all-projects --include-global --execute
  [ "$status" -ne 0 ]
  [ -f "$first_dir/credentials.json" ]
  [ -f "$global_dir/credentials.json" ]
  exec {fixture_fd}>&-
}

@test "removal inventory rejects unsafe modes without repairing metadata or discovery" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  chmod 755 "$dir"
  before=$(sha256sum "$dir/identity.json" "$dir/credentials.json" "$dir/lease.json")
  run box_auth_guard_remove "$dir"
  [ "$status" -ne 0 ]
  [ "$(stat -c %a "$dir")" = 755 ]
  [ "$(sha256sum "$dir/identity.json" "$dir/credentials.json" "$dir/lease.json")" = "$before" ]
}

@test "auth lock inode survives removal and recreation" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  stable=$(box_auth_stable_lock "$dir")
  before=$(stat -c '%d:%i' "$stable")
  run box_ops_remove_auth codex "$project" --execute
  [ "$status" -eq 0 ]
  [ ! -e "$dir" ]
  [ "$(stat -c '%d:%i' "$stable")" = "$before" ]
  exec {fixture_fd}>>"$stable"
  flock -n "$fixture_fd"
  run box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  [ "$status" -ne 0 ]
  [ ! -e "$dir" ]
  exec {fixture_fd}>&-
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  [ "$(stat -c '%d:%i' "$stable")" = "$before" ]
}

@test "permanent identity lock prevents removal before any object deletion" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  stable=$(box_auth_stable_lock "$dir")
  exec {fixture_fd}>>"$stable"
  flock -n "$fixture_fd"
  before=$(sha256sum "$dir/credentials.json")
  run box_ops_remove_auth codex "$project" --execute
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$dir/credentials.json")" = "$before" ]
  exec {fixture_fd}>&-
}

@test "auth removal recovers publication, member deletion and directory deletion interruptions" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  journal="$(box_auth_stable_lock "$dir").removal.json"
  printf 'unrelated bytes' >"$TEST_TMP/foreign"
  before=$(sha256sum "$TEST_TMP/foreign")
  for fault in publication delete-1 delete-4 directory; do
    box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
    BOX_AUTH_REMOVE_FAULT="$fault" run box_ops_remove_auth codex "$project" --execute
    [ "$status" -ne 0 ]
    [ -f "$journal" ]
    run box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
    [ "$status" -ne 0 ]
    run box_ops_remove_auth codex "$project" --execute
    [ "$status" -eq 0 ]
    [ ! -e "$dir" ]
    [ ! -e "$journal" ]
    [ "$(sha256sum "$TEST_TMP/foreign")" = "$before" ]
  done
}

@test "interrupted removal refuses changed members and preserves foreign state" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  BOX_AUTH_REMOVE_FAULT=publication run box_ops_remove_auth codex "$project" --execute
  [ "$status" -ne 0 ]
  printf 'changed recovery material' >"$dir/lock"
  printf 'unrelated bytes' >"$TEST_TMP/foreign"
  before=$(sha256sum "$dir/identity.json" "$dir/credentials.json" "$dir/lock" "$TEST_TMP/foreign")
  run box_ops_remove_auth codex "$project" --execute
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$dir/identity.json" "$dir/credentials.json" "$dir/lock" "$TEST_TMP/foreign")" = "$before" ]
}

@test "auth removal refuses live container dependencies before journal publication" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  before=$(sha256sum "$dir/identity.json" "$dir/credentials.json")
  docker() { printf 'synthetic-live-container\n'; }
  run box_ops_remove_auth codex "$project" --execute
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$dir/identity.json" "$dir/credentials.json")" = "$before" ]
  [ ! -e "$(box_auth_stable_lock "$dir").removal.json" ]
}

@test "all-project removal finds checkpoints after the canonical directory was deleted" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  BOX_AUTH_REMOVE_FAULT=directory run box_ops_remove_auth codex "$project" --execute
  [ "$status" -ne 0 ]
  [ ! -e "$dir" ]
  run box_ops_remove_auth codex "$project" --all-projects --execute
  [ "$status" -eq 0 ]
  [ ! -e "$(box_auth_stable_lock "$dir").removal.json" ]
}

@test "reset refuses redirected or shared projection locks before removing any state" {
  h=$(box_state_project_hash "$project")
  home_path="$HOME/.config/box-c/projects/$h/codex-home"
  mkdir -p "$home_path"
  printf 'session-marker' >"$home_path/history.jsonl"
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  printf 'foreign-lock' >"$PROJ_ROOT/foreign-lock"
  chmod 600 "$PROJ_ROOT/foreign-lock"
  docker() { printf 'called' >"$TEST_TMP/docker-called"; }
  export -f docker
  before=$(sha256sum "$home_path/history.jsonl" "$dir/credentials.json" "$PROJ_ROOT/foreign-lock")
  for kind in symlink hardlink mode; do
    case "$kind" in
      symlink) ln -s "$PROJ_ROOT/foreign-lock" "$home_path/.box-projection.lock" ;;
      hardlink) ln "$PROJ_ROOT/foreign-lock" "$home_path/.box-projection.lock" ;;
      mode) printf 'unsafe-lock' >"$home_path/.box-projection.lock"; chmod 666 "$home_path/.box-projection.lock" ;;
    esac
    run box_ops_reset codex "$project" --execute
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsafe reset lock"* ]]
    [ "$(sha256sum "$home_path/history.jsonl" "$dir/credentials.json" "$PROJ_ROOT/foreign-lock")" = "$before" ]
    [ ! -e "$TEST_TMP/docker-called" ]
    rm "$home_path/.box-projection.lock"
  done
}

@test "dead reserved lease recovers without touching the legacy projection or canonical bytes" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  native="$HOME/legacy-auth.json"
  printf '{"OPENAI_API_KEY":"synthetic-original"}\n' >"$native"
  chmod 600 "$native"
  before=$(sha256sum "$native" "$dir/credentials.json")
  box_auth_lease_reserve "$dir" "$HOME/projection.lock" "$native"
  exec {BOX_AUTH_PROJ_FD}>&-
  exec {BOX_AUTH_FD}>&-
  box_auth_release_stable_locks
  unset BOX_AUTH_PROJ_FD BOX_AUTH_FD
  docker() { return 0; }
  export -f docker
  run box_ops_recover codex "$project"
  [ "$status" -eq 0 ]
  [ "$before" = "$(sha256sum "$native" "$dir/credentials.json")" ]
  jq -e '.state == "idle" and (has("phase") | not)' "$dir/lease.json"
}

@test "failed Docker stop or liveness query preserves file projections for recovery" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  export BOX_AUTH_CONTAINER_ATTEMPTED=1
  docker_cmd=(bash -c 'exit 1')
  run box_auth_collection_stopped "$dir"
  [ "$status" -ne 0 ]
  docker_cmd=(bash -c 'printf live-container')
  run box_auth_collection_stopped "$dir"
  [ "$status" -ne 0 ]
  docker_cmd=(bash -c 'exit 0')
  run box_auth_collection_stopped "$dir"
  [ "$status" -eq 0 ]
}

@test "removal planning does not read credentials even with a pending checkpoint" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  docker() { return 0; }
  BOX_AUTH_REMOVE_FAULT=publication run box_ops_remove_auth codex "$project" --execute
  [ "$status" -ne 0 ]
  run python3 -I - "$BUNDLE_DIR" "$dir/credentials.json" "$project" <<'PY'
import ctypes, os, subprocess, sys
bundle, credential, project = sys.argv[1:]
libc = ctypes.CDLL(None, use_errno=True)
fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
assert fd >= 0
try:
    assert libc.inotify_add_watch(fd, credential.encode(), 1) >= 0  # IN_ACCESS
    subprocess.run(['bash', bundle + '/lib/auth-ops.sh', 'remove-auth', 'codex', project],
                   check=True, capture_output=True, text=True)
    try:
        events = os.read(fd, 4096)
    except BlockingIOError:
        events = b''
    assert not events, 'credential bytes were read during metadata planning'
finally:
    os.close(fd)
PY
  [ "$status" -eq 0 ]
}
