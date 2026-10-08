load helpers

fake_state_docker() {
  mkdir -p "$TEST_TMP/bin"
  cat >"$TEST_TMP/bin/docker" <<'DOCKER'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_DOCKER_CALLS"
while [[ "$1" == --* ]]; do shift 2; done
case "$1 $2" in
  'ps -aq'|'ps -q') exit 0 ;;
  'volume ls') cat "$FAKE_VOLUMES" ;;
  'volume inspect')
    created=fixture
    if [[ -n "${FAKE_REPLACE_ON_RECHECK:-}" ]]; then
      if [[ -e "$FAKE_REPLACE_ON_RECHECK" ]]; then created=replaced
      else : >"$FAKE_REPLACE_ON_RECHECK"; fi
    fi
    printf '{"Name":"%s","CreatedAt":"%s","Driver":"local"}\n' "${@: -1}" "$created" ;;
  'volume rm') name=${@: -1}; sed -i "\\|^$name$|d" "$FAKE_VOLUMES" ;;
  *) exit 1 ;;
esac
DOCKER
  chmod 755 "$TEST_TMP/bin/docker"
  export PATH="$TEST_TMP/bin:$PATH" FAKE_VOLUMES="$TEST_TMP/volumes" FAKE_DOCKER_CALLS="$TEST_TMP/docker-calls"
  : >"$FAKE_VOLUMES"
}

@test "reset uses the isolated local Engine despite ambient Docker selectors" {
  fake_state_docker
  export DOCKER_HOST=tcp://foreign.invalid:2375 DOCKER_CONTEXT=foreign DOCKER_CONFIG="$TEST_TMP/foreign-config"
  run box_ops_reset codex "$project" --keep-auth --execute
  [ "$status" -eq 0 ]
  [[ "$(cat "$FAKE_DOCKER_CALLS")" == *'--host unix:///var/run/docker.sock'* ]]
  [[ "$(cat "$FAKE_DOCKER_CALLS")" != *'foreign.invalid'* ]]
  [ ! -e "$TEST_TMP/foreign-config" ]
}

@test "full removal preview includes unrecorded current native stores without writes" {
  h=$(box_state_project_hash "$project")
  export BOX_C_STATE_ROOT="$HOME/unrecorded-native"
  run box_ops_remove_full codex "$project"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Native state: production codex home $BOX_C_STATE_ROOT/$h/codex-home"* ]]
  [[ "$output" == *"Native state: production codex volume volume:box-c-u$host_uid-g$host_gid-$h"* ]]
  [[ "$output" == *"Installed state/metadata: $HOME/.config/box-c/config.toml.bak"* ]]
  [ ! -e "$(box_auth_index_dir)" ]
  [ ! -e "$BOX_C_STATE_ROOT" ]
}

@test "Make lifecycle execution requires one and rejects malformed boolean flags" {
  run make -C "$BUNDLE_DIR" state-remove HARNESS=codex PROJECT="$project" FULL=1 EXECUTE=0
  [ "$status" -eq 0 ]
  [[ "$output" == *'Dry run: FULL=1 EXECUTE=1'* ]]
  [ ! -e "$(box_auth_index_dir)" ]
  for target in state-remove project-reset uninstall-code; do
    run make -C "$BUNDLE_DIR" "$target" HARNESS=codex PROJECT="$project" EXECUTE=unexpected
    [ "$status" -ne 0 ]
    [[ "$output" == *'Lifecycle flags must be 0, 1, or omitted.'* ]]
    [ ! -e "$(box_auth_index_dir)" ]
  done
}

@test "reset resumes every deletion boundary and refuses changed keep-auth options" {
  fake_state_docker
  h=$(box_state_project_hash "$project")
  volume=$(box_state_volume_name codex "$host_uid" "$host_gid" "$h")
  home_path="$HOME/.config/box-c/projects/$h/codex-home"
  for fault in home volume auth; do
    mkdir -p -m 700 "$home_path"
    printf fixture >"$home_path/history.jsonl"
    printf '%s\n' "$volume" >"$FAKE_VOLUMES"
    BOX_STATE_RESET_FAULT=$fault run box_ops_reset codex "$project" --keep-auth --execute
    [ "$status" -ne 0 ]
    run box_state_guard_reset codex "$host_uid" "$host_gid" "$h"
    [ "$status" -ne 0 ]
    run box_ops_reset codex "$project" --execute
    [ "$status" -ne 0 ]
    run box_ops_reset codex "$project" --keep-auth --execute
    [ "$status" -eq 0 ]
    [ ! -e "$home_path" ]
    [ ! -s "$FAKE_VOLUMES" ]
    run box_state_guard_reset codex "$host_uid" "$host_gid" "$h"
    [ "$status" -eq 0 ]
  done
}

@test "native inventory re-resolves historical roots and refuses a transplanted descriptor" {
  project_hash=$(box_state_project_hash "$project")
  export BOX_C_STATE_ROOT="$HOME/old-native"
  box_state_record_native codex
  unset BOX_C_STATE_ROOT
  box_state_record_native codex
  run python3 -I "$BUNDLE_DIR/lib/state-inventory.py" "$BUNDLE_DIR" "$(box_auth_index_dir)" codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/old-native/$project_hash/codex-home"* ]]
  f=$(rg -l 'old-native' "$(box_auth_index_dir)/native/codex")
  jq '.descriptor.path = "/unrelated"' "$f" >"$TEST_TMP/changed"
  cp "$TEST_TMP/changed" "$f"
  run python3 -I "$BUNDLE_DIR/lib/state-inventory.py" "$BUNDLE_DIR" "$(box_auth_index_dir)" codex
  [ "$status" -ne 0 ]
}

@test "full state removal resumes after auth and native stages and includes inactive roots" {
  fake_state_docker
  project_hash=$(box_state_project_hash "$project")
  volume=$(box_state_volume_name codex "$host_uid" "$host_gid" "$project_hash")
  export BOX_C_STATE_ROOT="$HOME/old-native"
  box_state_record_native codex
  old_home="$BOX_C_STATE_ROOT/$project_hash/codex-home"
  mkdir -p -m 700 "$old_home"
  printf history >"$old_home/history.jsonl"
  unset BOX_C_STATE_ROOT
  new_home="$HOME/.config/box-c/projects/$project_hash/codex-home"
  mkdir -p -m 700 "$new_home"
  printf history >"$new_home/history.jsonl"
  box_state_record_native codex
  dir=$(box_auth_object_dir codex global "$host_uid")
  box_auth_ensure_object "$dir" codex global "$host_uid" "$project_hash"
  printf '%s\n' "$volume" >"$FAKE_VOLUMES"
  BOX_STATE_REMOVE_FAULT=auth run box_ops_remove_full codex "$project" --execute
  [ "$status" -ne 0 ]
  [ -f "$old_home/history.jsonl" ]
  BOX_STATE_REMOVE_FAULT=native run box_ops_remove_full codex "$project" --execute
  [ "$status" -ne 0 ]
  [ ! -e "$old_home" ]
  [ ! -e "$new_home" ]
  run box_ops_remove_full codex "$project" --execute
  [ "$status" -eq 0 ]
  [ ! -e "$dir" ]
  [ ! -e "$(box_auth_index_dir)/removals/codex.json" ]
}

@test "exact member recovery refuses changed or shared files and preserves unlisted files" {
  mkdir -m 700 "$TEST_TMP/members"
  first="$TEST_TMP/members/first"
  second="$TEST_TMP/members/second"
  printf first >"$first"
  printf unrelated >"$second"
  run python3 -I "$BUNDLE_DIR/lib/state-members.py" "$TEST_TMP/members/journal" "$first"
  [ "$status" -eq 0 ]
  [ ! -e "$first" ]
  [ -f "$second" ]
  printf replacement >"$first"
  run python3 -I "$BUNDLE_DIR/lib/state-members.py" "$TEST_TMP/members/journal" "$first"
  [ "$status" -ne 0 ]
  [ -f "$first" ]
}

@test "project-qualified test fixtures share auth but isolate native homes and volumes" {
  export BOX_TEST_STATE_NS=t-aaaabbbbcccc BOX_TEST_TASK_ROOT="$PROJ_ROOT"
  export BOX_TEST_PROJECT_HASH=$(box_state_project_hash "$project")
  first_volume=$(box_test_volume codex "$BOX_TEST_STATE_NS" "$host_uid" "$host_gid")
  first_home=$(box_test_codex_home)
  first_auth=$(box_test_auth_dir codex "$BOX_TEST_STATE_NS" "$host_uid" global)
  mkdir -m 700 "$PROJ_ROOT/other"
  export BOX_TEST_PROJECT_HASH=$(box_state_project_hash "$PROJ_ROOT/other")
  [ "$first_volume" != "$(box_test_volume codex "$BOX_TEST_STATE_NS" "$host_uid" "$host_gid")" ]
  [ "$first_home" != "$(box_test_codex_home)" ]
  [ "$first_auth" = "$(box_test_auth_dir codex "$BOX_TEST_STATE_NS" "$host_uid" global)" ]
  run box_test_guard_cleanup "$first_volume" codex "$BOX_TEST_STATE_NS" "$host_uid" "$host_gid"
  [ "$status" -ne 0 ]
}

@test "full removal resumes after deleting discovery metadata" {
  fake_state_docker
  project_hash=$(box_state_project_hash "$project")
  box_state_record_native codex
  BOX_STATE_REMOVE_FAULT=metadata run box_ops_remove_full codex "$project" --execute
  [ "$status" -ne 0 ]
  run box_ops_remove_full codex "$project" --execute
  [ "$status" -eq 0 ]
}

@test "code-only uninstall preserves templates credentials native state and unrelated code" {
  mkdir -p -m 700 "$HOME/.local/bin/harnesses/codex" "$HOME/.local/bin/lib" "$HOME/.config/box-c"
  printf installed >"$HOME/.local/bin/box-c"
  printf unrelated >"$HOME/.local/bin/unrelated"
  printf unrelated >"$HOME/.local/bin/lib/unrelated.sh"
  printf config >"$HOME/.config/box-c/config.toml"
  printf provider >"$HOME/providers.env"
  chmod 600 "$HOME/providers.env"
  ln -s box-c "$HOME/.local/bin/box"
  run box_ops_uninstall_code codex --execute
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/box-c" ]
  [ ! -L "$HOME/.local/bin/box" ]
  [ -f "$HOME/.local/bin/unrelated" ]
  [ -f "$HOME/.local/bin/lib/unrelated.sh" ]
  [ -f "$HOME/.config/box-c/config.toml" ]
  [ -f "$HOME/providers.env" ]
}

@test "empty disposable selectors never fall back to production identities" {
  BOX_TEST_STATE_NS='' BOX_TEST_TASK_ROOT='' run box_auth_object_dir codex global "$host_uid"
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.config/box/auth" ]
}

@test "explicit historical discovery resolves a removed physical project without creating it" {
  missing="$PROJ_ROOT/former-project"
  BOX_TOOL=inventory BUNDLE_DIR="$BUNDLE_DIR" run bash "$BUNDLE_DIR/lib/auth-ops.sh" discover codex "$missing" --historical
  [ "$status" -eq 0 ]
  [ ! -e "$missing" ]
  run python3 -I "$BUNDLE_DIR/lib/state-inventory.py" "$BUNDLE_DIR" "$(box_auth_index_dir)" codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"$missing"* ]]
}

@test "completed full removal recovery never deletes a newly recreated volume" {
  fake_state_docker
  project_hash=$(box_state_project_hash "$project")
  volume=$(box_state_volume_name codex "$host_uid" "$host_gid" "$project_hash")
  printf '%s\n' "$volume" >"$FAKE_VOLUMES"
  BOX_STATE_REMOVE_FAULT=completion run box_ops_remove_full codex "$project" --execute
  [ "$status" -ne 0 ]
  [ ! -s "$FAKE_VOLUMES" ]
  printf '%s\n' "$volume" >"$FAKE_VOLUMES"
  run box_ops_remove_full codex "$project" --execute
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_VOLUMES")" = "$volume" ]
}

@test "reset and full removal preserve a volume replaced after transaction preparation" {
  fake_state_docker
  h=$(box_state_project_hash "$project")
  volume=$(box_state_volume_name codex "$host_uid" "$host_gid" "$h")
  export FAKE_REPLACE_ON_RECHECK="$TEST_TMP/inspected"
  for operation in reset full; do
    printf '%s\n' "$volume" >"$FAKE_VOLUMES"
    : >"$FAKE_DOCKER_CALLS"
    if [[ "$operation" == reset ]]; then
      run box_ops_reset codex "$project" --keep-auth --execute
    else
      # Separate the full-removal transaction from the unfinished reset.
      export BOX_C_STATE_ROOT="$HOME/full-native"
      mkdir -m 700 "$PROJ_ROOT/full-project"
      project="$PROJ_ROOT/full-project"
      h=$(box_state_project_hash "$project")
      volume=$(box_state_volume_name codex "$host_uid" "$host_gid" "$h")
      printf '%s\n' "$volume" >"$FAKE_VOLUMES"
      rm -f -- "$FAKE_REPLACE_ON_RECHECK"
      run box_ops_remove_full codex "$project" --execute
    fi
    [ "$status" -ne 0 ]
    [[ "$output" == *'volume was replaced before deletion'* ]]
    [ "$(cat "$FAKE_VOLUMES")" = "$volume" ]
    ! rg -q 'volume rm' "$FAKE_DOCKER_CALLS"
  done
}

@test "volume deletion verification refuses absent authority and corrupt identity without changing checkpoint" {
  journal="$TEST_TMP/volume-checkpoint.json"
  identity='{"Name":"fixture-volume","CreatedAt":"original","Driver":"local"}'
  run python3 -I "$BUNDLE_DIR/lib/state-transaction.py" prepare --journal "$journal" \
    --root '' --harness codex --uid "$host_uid" --gid "$host_gid" --project-hash abc \
    --volume fixture-volume --volume-identity "$identity"
  [ "$status" -eq 0 ]
  before=$(sha256sum "$journal")
  for candidate in '' '[]' '{' '{"Name":"fixture-volume","Name":"fixture-volume"}' \
    '{"Name":"fixture-volume","CreatedAt":"replacement","Driver":"local"}'; do
    run python3 -I "$BUNDLE_DIR/lib/state-transaction.py" verify-volume --journal "$journal" \
      --volume-identity "$candidate"
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$journal")" = "$before" ]
  done
  run python3 -I "$BUNDLE_DIR/lib/state-transaction.py" verify-volume --journal "$journal" \
    --volume-identity "$identity"
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$journal")" = "$before" ]
  jq 'del(.volume_identity)' "$journal" >"$TEST_TMP/without-authority"
  cp "$TEST_TMP/without-authority" "$journal"
  before=$(sha256sum "$journal")
  run python3 -I "$BUNDLE_DIR/lib/state-transaction.py" verify-volume --journal "$journal" \
    --volume-identity "$identity"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$journal")" = "$before" ]
}

@test "historical volume descriptors are explicit and cannot target another harness family" {
  h=$(box_state_project_hash "$project")
  box_state_context opencode "$host_uid" "$host_gid" "$project" production
  run box_state_resolve legacy-v1
  [ "$status" -eq 0 ]
  [[ "$output" == *"volume=box-o-u$host_uid-g$host_gid-$h"* ]]
  _BOX_STATES[opencode,legacy-v1,volume_prefix]=box-c
  run box_validate_registry "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"collides"* ]]
}

@test "invalid native roots refuse discovery before creating an index" {
  BOX_C_STATE_ROOT=relative run box_state_record_native codex
  [ "$status" -ne 0 ]
  [ ! -e "$(box_auth_index_dir)" ]
}
