# setup.bats — setup CLI and filesystem installation behavior without Docker.
load helpers

@test "setup.sh --help lists the registry flags and ids" {
  run bash "$BUNDLE_DIR/setup.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--only <id>"* ]]
  [[ "$output" == *"--default <id>"* ]]
  [[ "$output" == *"Known tool ids: $box_tool_ids"* ]]
}

@test "setup.sh old per-tool flags fail with a migration hint" {
  run bash "$BUNDLE_DIR/setup.sh" --only-m
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --only <id>"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --only-o
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --only <id>"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --default-muse
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --default <id>"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --default-opencode
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --default <id>"* ]]
}

@test "setup.sh rejects unknown tool ids and missing values" {
  run bash "$BUNDLE_DIR/setup.sh" --only bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool id"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --default bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool id"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --only
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a tool id"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --default
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a tool id"* ]]
}

@test "setup.sh still rejects unknown flags and positionals" {
  run bash "$BUNDLE_DIR/setup.sh" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
  run bash "$BUNDLE_DIR/setup.sh" some-positional
  [ "$status" -ne 0 ]
  [[ "$output" == *"no positional arguments"* ]]
}

@test "setup rejects arguments after -- before filesystem changes" {
  run bash "$BUNDLE_DIR/setup.sh" -- --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Takes no positional arguments"* ]]
  [ ! -e "$HOME/.config" ]
}

@test "setup validates bundle configurations before filesystem changes" {
  copy="$TEST_TMP/bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  printf 'malformed\n' >"$copy/harnesses/muse/config/settings.json"
  run bash "$copy/setup.sh" --skip-build
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid JSON configuration"* ]]
  [ ! -e "$HOME/.config" ]
}

@test "config installation preserves one customized backup and is idempotent" {
  dest="$TEST_TMP/settings.json"
  printf '{"model":"custom"}\n' >"$dest"
  chmod 600 "$dest"
  box_install_tool_config "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$dest"
  cmp "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$dest"
  [ "$(stat -c %a "$dest")" = 644 ]
  [ "$(cat "$dest.bak")" = '{"model":"custom"}' ]
  [ "$(stat -c %a "$dest.bak")" = 600 ]
  before=$(sha256sum "$dest.bak")
  box_install_tool_config "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$dest"
  [ "$(sha256sum "$dest.bak")" = "$before" ]
}

@test "config installation refuses destination and backup symlinks" {
  target="$TEST_TMP/untouched"
  printf 'keep\n' >"$target"
  dest="$TEST_TMP/settings.json"
  for link in "$dest" "$dest.bak"; do
    ln -s "$target" "$link"
    run box_install_tool_config "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$dest"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing to follow symlink"* ]]
    [ "$(cat "$target")" = keep ]
    rm "$link"
  done
}

@test "installed pins take precedence on setup reruns for every registry tool" {
  for id in $box_tool_ids; do
    src="$BUNDLE_DIR/$(box_tool_field "$id" version_source)"
    dest="$TEST_TMP/$(box_tool_field "$id" version_file)"
    box_install_version_pin "$src" "$dest"
    cmp "$src" "$dest"
    [ "$(stat -c %a "$dest")" = 644 ]
    printf '# installed preference\n' >>"$dest"
    before=$(sha256sum "$dest")
    box_install_version_pin "$src" "$dest"
    [ "$(sha256sum "$dest")" = "$before" ]
  done
}

@test "default launcher survives reruns and changes only on explicit selection" {
  dest="$TEST_TMP/box"
  [ "$(box_install_default "$dest")" = box-m ]
  [ "$(box_install_default "$dest" opencode)" = box-o ]
  [ "$(box_install_default "$dest")" = box-o ]
  [ "$(readlink "$dest")" = box-o ]
}

@test "default installation rejects collisions and unmanaged links" {
  dest="$TEST_TMP/box"
  printf 'keep\n' >"$dest"
  run box_install_default "$dest" muse
  [ "$status" -ne 0 ]
  [ "$(cat "$dest")" = keep ]
  rm "$dest"
  ln -s ../unmanaged "$dest"
  run box_install_default "$dest"
  [ "$status" -ne 0 ]
  [ "$(readlink "$dest")" = ../unmanaged ]
}

@test "provider installation preserves contents and accepted read-only mode" {
  dest="$TEST_TMP/providers.env"
  [ "$(box_install_provider_file "$dest")" = created ]
  [ "$(stat -c %a "$dest")" = 600 ]
  printf 'MUSE_CODE_API_KEY=fixture-value\n' >"$dest"
  chmod 400 "$dest"
  before=$(sha256sum "$dest")
  [ "$(box_install_provider_file "$dest")" = kept ]
  [ "$(sha256sum "$dest")" = "$before" ]
  [ "$(stat -c %a "$dest")" = 400 ]
  chmod 644 "$dest"
  box_install_provider_file "$dest" >/dev/null
  [ "$(stat -c %a "$dest")" = 600 ]
}

@test "provider installation rejects symlinks and directories" {
  target="$TEST_TMP/untouched"
  printf 'keep\n' >"$target"
  dest="$TEST_TMP/providers.env"
  ln -s "$target" "$dest"
  run box_install_provider_file "$dest"
  [ "$status" -ne 0 ]
  [ "$(cat "$target")" = keep ]
  rm "$dest"
  mkdir "$dest"
  run box_install_provider_file "$dest"
  [ "$status" -ne 0 ]
}

@test "incompatible installed pins reject setup before files or metadata change" {
  mkdir -p "$HOME/.config/box-o" "$HOME/.local/bin"
  printf 'OPENCODE_VERSION=1.18.34\nOPENCODE_NPM_INTEGRITY=legacy\n' >"$HOME/.config/box-o/version-opencode.env"
  printf '{"fixture":"custom"}\n' >"$HOME/.config/box-o/opencode.json"
  printf 'previous backup\n' >"$HOME/.config/box-o/opencode.json.bak"
  printf 'previous launcher\n' >"$HOME/.local/bin/box-o"
  before=$(find "$HOME" -printf '%P %m %u %g %T@\n' | sort; find "$HOME" -type f -exec sha256sum {} \; | sort)
  run bash "$BUNDLE_DIR/setup.sh" --skip-build
  [ "$status" -ne 0 ]
  [[ "$output" == *'Incompatible installed opencode pins'* ]]
  [[ "$output" == *'build-o'* ]]
  after=$(find "$HOME" -printf '%P %m %u %g %T@\n' | sort; find "$HOME" -type f -exec sha256sum {} \; | sort)
  [ "$before" = "$after" ]
}

@test "planning accepts valid differing v2 pins without replacing bundled values" {
  box_load_all_pins "$BUNDLE_DIR"
  original=$OPENCODE_VERSION
  cp "$BUNDLE_DIR/harnesses/opencode/version-opencode.env" "$TEST_TMP/pins.env"
  sed -i 's/^OPENCODE_VERSION=.*/OPENCODE_VERSION=2.0.7/' "$TEST_TMP/pins.env"
  before=$(sha256sum "$TEST_TMP/pins.env")
  box_plan_installed_pins opencode "$TEST_TMP/pins.env"
  box_install_version_pin "$BUNDLE_DIR/harnesses/opencode/version-opencode.env" "$TEST_TMP/pins.env"
  [ "$before" = "$(sha256sum "$TEST_TMP/pins.env")" ]
  [ "$OPENCODE_VERSION" = "$original" ]
}

@test "failed template write preserves the valid live configuration" {
  dest="$TEST_TMP/config.json"
  printf '{"valid":"custom"}\n' > "$dest"
  chmod 644 "$dest"
  before=$(sha256sum "$dest")
  install() {
    local target=${@: -1}
    printf 'partial' > "$target"
    return 1
  }
  run box_install_tool_config "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$dest"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$dest")" = "$before" ]
  run jq -e . "$dest"
  [ "$status" -eq 0 ]
  [ -z "$(find "$TEST_TMP" -name '.box-install.*' -print -quit)" ]
}

@test "interrupted template staging preserves configuration and cleans its stage" {
  dest="$TEST_TMP/config.json"
  printf '{"valid":"custom"}\n' > "$dest"
  chmod 644 "$dest"
  before=$(sha256sum "$dest")
  install() {
    printf partial > "${@: -1}"
    kill -TERM "$BASHPID"
  }
  run box_install_tool_config "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$dest"
  [ "$status" -eq 143 ]
  [ "$(sha256sum "$dest")" = "$before" ]
  [ -z "$(find "$TEST_TMP" -name '.box-install.*' -print -quit)" ]
}

@test "setup waits for the home lock before planning installed pins" {
  exec {lock_fd}<"$HOME"
  flock -x "$lock_fd"
  # Close the inherited lock descriptor so setup takes its own lock.
  (exec {lock_fd}<&-; exec bash "$BUNDLE_DIR/setup.sh" --skip-build) > "$TEST_TMP/setup.log" 2>&1 &
  installer=$!
  opened=0
  for (( attempt=0; attempt<200; attempt++ )); do
    for fd in /proc/"$installer"/fd/*; do
      if [[ "$(readlink "$fd")" == "$HOME" ]]; then opened=1; break; fi
    done
    (( opened )) && break
    sleep 0.05
  done
  # Change installed state while setup is waiting; it must plan after release.
  mkdir -p "$HOME/.config/box-o"
  printf 'OPENCODE_VERSION=1.18.34\nOPENCODE_NPM_INTEGRITY=legacy\n' > "$HOME/.config/box-o/version-opencode.env"
  flock -u "$lock_fd"
  exec {lock_fd}<&-
  wait "$installer" && installer_rc=0 || installer_rc=$?
  cat "$TEST_TMP/setup.log" >&2
  [ "$opened" -eq 1 ]
  [ "$installer_rc" -ne 0 ]
  [[ "$(cat "$TEST_TMP/setup.log")" == *'Incompatible installed opencode pins'* ]]
  [ ! -e "$HOME/.local" ]
}

# The concurrent-install test needs a reachable Docker Engine; it lives in
# tests/bats-live/setup-concurrent.bats (make test-live). tests/bats/ stays
# daemon-free so verify-static needs no daemon.

@test "state policy seeds versioned with no scopes and preserves reruns" {
  policy="$TEST_TMP/state.toml"
  run box_install_state_policy "$policy"
  [ "$status" -eq 0 ]
  [ "$output" = "created" ]
  [ "$(stat -c %a -- "$policy")" = "600" ]
  box_config_validate "$policy" toml
  run box_install_state_policy "$policy"
  [ "$status" -eq 0 ]
  [ "$output" = "kept" ]
  printf 'schema_version = 1\n\n[auth]\ndefault_scope = "project"\n' >"$policy"
  before=$(sha256sum -- "$policy")
  run box_install_state_policy "$policy"
  [ "$status" -eq 0 ]
  [ "$(sha256sum -- "$policy")" = "$before" ]
}

@test "state policy refuses symlinks and missing parents" {
  ln -s "$TEST_TMP/target" "$TEST_TMP/policy-link"
  run box_install_state_policy "$TEST_TMP/policy-link"
  [ "$status" -ne 0 ]
  run box_install_state_policy "$TEST_TMP/no-such-dir/state.toml"
  [ "$status" -ne 0 ]
}
