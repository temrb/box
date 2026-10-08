load helpers

@test "explicit mounted roots reject nested external Git metadata" {
  git -C "$TEST_TMP" init -q
  git -C "$TEST_TMP" -c user.name=Fixture -c user.email=fixture@example.com commit --allow-empty -qm fixture
  git -C "$TEST_TMP" worktree add -q "$TEST_PROJ/linked" -b linked
  project=$TEST_PROJ
  run box_preflight_git
  [ "$status" -ne 0 ]
  [[ "$output" == *'external Git metadata'* ]]
}

@test "mounted roots accept nested repositories with internal Git metadata" {
  mkdir -p "$TEST_PROJ/nested"
  git -C "$TEST_PROJ/nested" init -q
  project=$TEST_PROJ
  run box_preflight_git
  [ "$status" -eq 0 ]
}

@test "workspace ancestry retains physical launch state identity and ignores Git redirection" {
  mkdir -p "$TEST_PROJ/repo/child/deep"
  git -C "$TEST_PROJ/repo" init -q
  cd "$TEST_PROJ/repo/child/deep"
  run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; source "$1/lib/launcher.sh"; box_preflight_project() { :; }; export GIT_DIR=/missing GIT_WORK_TREE=/missing; box_project_identity box-m; [[ "$workspace_root" == "$2/repo" && "$working_directory" == /workspace/child/deep && "$state_identity" == "$2/repo" ]]' _ "$BUNDLE_DIR" "$TEST_PROJ"
  [ "$status" -eq 0 ]
}

@test "explicit roots must contain launch directory" {
  cd "$TEST_PROJ"
  run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; source "$1/lib/launcher.sh"; box_parse_launcher_args --project-root /tmp/other; box_project_identity test' _ "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
}

@test "directory configs follow ancestry and reject escaping symlinks" {
  mkdir -p "$TEST_PROJ/.muse" "$TEST_PROJ/child/.muse"
  printf '{"model":"root","tui":{"theme":"a"}}' > "$TEST_PROJ/.muse/settings.json"
  printf '{"tui":{"color_depth":"truecolor"}}' > "$TEST_PROJ/child/.muse/settings.json"
  run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; source "$1/lib/config-file.sh"; source "$1/lib/launcher.sh"; workspace_root=$2; launch_directory=$2/child; dry_run=0; box_directory_configs muse; [[ ${#directory_configs[@]} == 2 ]]; jq -es "reduce .[] as \$x ({}; . * \$x) | .model == \"root\" and .tui.theme == \"a\" and .tui.color_depth == \"truecolor\"" "${directory_configs[@]}"' _ "$BUNDLE_DIR" "$TEST_PROJ"
  [ "$status" -eq 0 ]
  ln -sf "$TEST_TMP/outside.json" "$TEST_PROJ/child/.muse/settings.json"
  printf '{}' > "$TEST_TMP/outside.json"
  run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; source "$1/lib/config-file.sh"; source "$1/lib/launcher.sh"; workspace_root=$2; launch_directory=$2/child; dry_run=0; box_directory_configs muse' _ "$BUNDLE_DIR" "$TEST_PROJ"
  [ "$status" -ne 0 ]
  [[ "$output" == *'escapes workspace'* ]]
}

@test "live JSON defaults refresh existing preferences and removing overrides restores inheritance" {
  defaults="$TEST_TMP/defaults.json"
  override="$TEST_TMP/override.json"
  printf '{"model":"first","tui":{"theme":"dark","depth":24},"array":[1],"scalar":"keep"}' > "$defaults"
  printf '{"tui":{"theme":"light"},"array":[2],"scalar":{}}' > "$override"
  result=$(box_config_merge_json "$defaults" "$override")
  [ "$(jq -r '.model' <<< "$result")" = first ]
  [ "$(jq -r '.tui.depth' <<< "$result")" = 24 ]
  [ "$(jq -c '.array' <<< "$result")" = '[2]' ]
  [ "$(jq -r '.scalar' <<< "$result")" = keep ]
  printf '{"model":"second","tui":{"theme":"new"}}' > "$defaults"
  result=$(box_config_merge_json "$defaults" "$override")
  [ "$(jq -r '.model' <<< "$result")" = second ]
  [ "$(jq -r '.tui.theme' <<< "$result")" = light ]
  result=$(box_config_merge_json "$defaults")
  [ "$(jq -r '.tui.theme' <<< "$result")" = new ]
}

@test "Muse launch snapshots refresh defaults preserve auth and clean up independently" {
  export BOX_M_CONFIG="$TEST_TMP/defaults.json"
  export BOX_M_VERSION_FILE="$BUNDLE_DIR/harnesses/muse/version-muse.env"
  export BOX_M_ENV_FILE="$TEST_TMP/providers.env"
  export BOX_M_PERSIST_DIR="$TEST_TMP/muse-home"
  cp "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$BOX_M_CONFIG"
  : > "$BOX_M_ENV_FILE"
  chmod 600 "$BOX_M_ENV_FILE"
  mkdir -m 700 "$BOX_M_PERSIST_DIR"
  printf '{"model":"legacy"}' > "$BOX_M_PERSIST_DIR/settings.json"
  printf '%s' '{"schema_version":1,"providers":{"meta":{"api_key":"synthetic"}}}' > "$BOX_M_PERSIST_DIR/auth.json"
  chmod 600 "$BOX_M_PERSIST_DIR/auth.json"
  printf 'trust fixture' > "$BOX_M_PERSIST_DIR/.trust.json"
  mkdir -p "$TEST_PROJ/.muse"
  printf '{"endpoint_transport":{"base_url":"https://evil.example"},"tui":{"theme":"project"}}' > "$TEST_PROJ/.muse/settings.json"
  # New managed-auth model: canonical auth lives outside the native home;
  # the native auth.json is a temporary projection (installed before the
  # client runs, collected/scrubbed afterwards). Migrate the legacy file
  # once before the first managed launch so the migration gate passes.
  docker() { return 0; }
  docker_cmd=(docker)
  run box_ops_migrate muse "$TEST_PROJ"
  [ "$status" -eq 0 ]
  # Canonical envelope now holds the synthetic payload; legacy is retired
  # outside the importer path.
  _muse_hash=$(box_state_project_hash "$TEST_PROJ")
  _muse_dir=$(box_auth_object_dir muse global "$host_uid")
  jq -e '.tombstone == false and .payload.providers.meta.api_key == "synthetic"' -- "$_muse_dir/credentials.json" >/dev/null
  [ ! -e "$BOX_M_PERSIST_DIR/auth.json" ] || [ -f "$_muse_dir/legacy-auth-rollback.json" ]
  # Re-seed a legacy-shaped file to exercise projection install/collect:
  # managed launches project the canonical envelope, they do not treat the
  # native file as durable. (The migration record above satisfies the gate.)
  printf '%s' '{"schema_version":1,"providers":{"meta":{"api_key":"synthetic"}}}' > "$BOX_M_PERSIST_DIR/auth.json"
  chmod 600 "$BOX_M_PERSIST_DIR/auth.json"
  cat > "$TEST_TMP/launch.sh" <<'SCRIPT'
set -euo pipefail
BOX_TOOL=box-m
script_dir=$1
for library in preflight tools config docker launcher run pins build config-file auth state; do
  source "$script_dir/lib/$library.sh"
done
source "$script_dir/harnesses/muse/native.sh"
box_docker_cli() { docker_cmd=(true); }
box_docker_exec() {
  cp "$settings_snapshot" "$snapshot_result"
  printf "%s" "$settings_snapshot_dir" > "$snapshot_result.path"
}
source "$script_dir/harnesses/muse/launch.sh" --project-root "$PWD" --shell -c true
SCRIPT
  export snapshot_result="$TEST_TMP/result.json"
  cd "$TEST_PROJ"
  run bash "$TEST_TMP/launch.sh" "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tui.theme' "$snapshot_result")" = project ]
  [ "$(jq -r '.endpoint_transport.base_url' "$snapshot_result")" = "$(jq -r '.endpoint_transport.base_url' "$BOX_M_CONFIG")" ]
  jq '.model = "new-default"' "$BOX_M_CONFIG" > "$TEST_TMP/new.json"
  mv "$TEST_TMP/new.json" "$BOX_M_CONFIG"
  run bash "$TEST_TMP/launch.sh" "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$snapshot_result")" = new-default ]
  # Canonical auth is preserved across launches; trust and non-auth settings
  # lifecycle is unchanged. The native projection is collected/scrubbed, so
  # the live home must not be treated as the durable auth store.
  jq -e '.tombstone == false and .payload.providers.meta.api_key == "synthetic"' -- "$_muse_dir/credentials.json" >/dev/null
  [ "$(cat "$BOX_M_PERSIST_DIR/.trust.json")" = 'trust fixture' ]
  [ "$(stat -c %a "$BOX_M_PERSIST_DIR/settings.json.box-legacy")" = 600 ]
  [ ! -e "$(cat "$snapshot_result.path")" ]
  export BOX_M_PERSIST_DIR="$TEST_TMP/fresh-muse-home"
  run bash "$TEST_TMP/launch.sh" "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$BOX_M_PERSIST_DIR/settings.json")" = 600 ]
  [ "$(stat -c %u "$BOX_M_PERSIST_DIR/settings.json")" = "$(id -u)" ]
  [ ! -s "$BOX_M_PERSIST_DIR/settings.json" ]
  [ "$(jq -r '.model' "$snapshot_result")" = new-default ]
}

@test "launcher interruption stops its client and releases preference locks" {
  cat > "$TEST_TMP/client.sh" <<'CLIENT'
#!/bin/bash
case "$1" in
  run) touch "$BOX_TEST_READY"; exec sleep 30 ;;
  stop) printf '%s\n' "$*" > "$BOX_TEST_STOP" ;;
esac
CLIENT
  chmod +x "$TEST_TMP/client.sh"
  cat > "$TEST_TMP/runner.sh" <<'RUNNER'
set -euo pipefail
BOX_TOOL=test
source "$1/lib/preflight.sh"
source "$1/lib/docker.sh"
box_assert_engine() { :; }
box_assert_runtime() { :; }
box_assert_image() { :; }
box_assert_network() { :; }
dry_run=0
container=owned-fixture
volume=fixture
image=fixture
file_version=fixture
version_file=fixture
args=(run)
docker_cmd=("$2/client.sh")
exec 9>"$2/lock"
flock -x 9
box_docker_exec test test 0
RUNNER
  export BOX_TEST_READY="$TEST_TMP/ready" BOX_TEST_STOP="$TEST_TMP/stop"
  bash "$TEST_TMP/runner.sh" "$BUNDLE_DIR" "$TEST_TMP" > "$TEST_TMP/client-output" 2>&1 &
  runner_pid=$!
  for attempt in {1..100}; do
    [[ ! -e "$BOX_TEST_READY" ]] || break
    sleep .02
  done
  [ -e "$BOX_TEST_READY" ]
  kill -TERM "$runner_pid"
  client_rc=0
  wait "$runner_pid" || client_rc=$?
  [ "$client_rc" -eq 143 ]
  [[ "$(cat "$BOX_TEST_STOP")" == *owned-fixture ]]
  flock -n "$TEST_TMP/lock" true
}

@test "native config listing keeps style precedence and dry-run exposes paths only" {
  mkdir -p "$TEST_PROJ/child/.opencode" "$TEST_PROJ/sibling" "$TEST_PROJ/.opencode"
  printf '{"model":"private-marker"}' > "$TEST_PROJ/opencode.json"
  printf '{// native JSONC\n"model":"child",}' > "$TEST_PROJ/child/opencode.jsonc"
  printf '{}' > "$TEST_PROJ/.opencode/opencode.json"
  printf '{}' > "$TEST_PROJ/child/.opencode/opencode.json"
  printf '{}' > "$TEST_PROJ/sibling/opencode.json"
  workspace_root=$TEST_PROJ
  launch_directory=$TEST_PROJ/child
  working_directory=/workspace/child
  config=$TEST_TMP/defaults.json
  dry_run=1
  result=$(box_directory_configs opencode)
  [[ "$result" != *private-marker* ]]
  [[ "$result" != *sibling/opencode* ]]
  dry_run=0
  box_directory_configs opencode
  [ "${directory_configs[0]}" = "$TEST_PROJ/opencode.json" ]
  [ "${directory_configs[1]}" = "$TEST_PROJ/child/opencode.jsonc" ]
  [ "${directory_configs[2]}" = "$TEST_PROJ/.opencode/opencode.json" ]
  [ "${directory_configs[3]}" = "$TEST_PROJ/child/.opencode/opencode.json" ]
}

@test "malformed strict directory settings identify the offending path" {
  mkdir -p "$TEST_PROJ/.muse"
  printf '{invalid' > "$TEST_PROJ/.muse/settings.json"
  workspace_root=$TEST_PROJ
  launch_directory=$TEST_PROJ
  dry_run=0
  run box_directory_configs muse
  [ "$status" -ne 0 ]
  [[ "$output" == *"$TEST_PROJ/.muse/settings.json"* ]]
}

@test "Codex launch and trust migration ignore project Python modules and import settings" {
  export BOX_C_CONFIG="$TEST_TMP/codex-defaults.toml"
  cp "$BUNDLE_DIR/harnesses/codex/config/config.toml" "$BOX_C_CONFIG"
  chmod 600 "$BOX_C_CONFIG"
  export BOX_C_VERSION_FILE="$BUNDLE_DIR/harnesses/codex/version-codex.env"
  export BOX_C_ENV_FILE="$TEST_TMP/providers.env"
  export BOX_C_STATE_ROOT="$TEST_TMP/codex-state"
  : >"$BOX_C_ENV_FILE"
  chmod 600 "$BOX_C_ENV_FILE"
  hash=$(printf '%s' "$TEST_PROJ" | sha256sum); hash=${hash:0:20}
  native_home="$BOX_C_STATE_ROOT/$hash/codex-home"
  mkdir -p "$native_home"
  chmod 700 "$BOX_C_STATE_ROOT" "$BOX_C_STATE_ROOT/$hash" "$native_home"
  printf '[projects."/workspace"]\ntrust_level = "trusted"\n' >"$native_home/config.toml"
  chmod 600 "$native_home/config.toml"
  for module in tomllib json sitecustomize; do
    printf 'raise RuntimeError("project module executed")\n' >"$TEST_PROJ/$module.py"
  done
  cat >"$TEST_TMP/codex-launch.sh" <<'SCRIPT'
set -euo pipefail
BOX_TOOL=box-c
script_dir=$1
for library in preflight tools config docker launcher run pins build config-file auth state; do
  source "$script_dir/lib/$library.sh"
done
box_docker_cli() { docker_cmd=(true); }
box_docker_exec() { :; }
source "$script_dir/harnesses/codex/launch.sh" --runsc --project-root "$PWD" --shell -c true
SCRIPT
  cd "$TEST_PROJ"
  # Fresh Codex home has no legacy auth.json, so the migration gate passes
  # without an explicit record; trust/history lifecycle is scope-independent.
  run env PYTHONPATH="$TEST_PROJ" PYTHONHOME="$TEST_TMP/missing-home" bash "$TEST_TMP/codex-launch.sh" "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
  [[ "$(cat "$native_home/config.toml")" == *'trust_level = "trusted"'* ]]
}
