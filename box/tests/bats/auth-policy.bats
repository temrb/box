# auth-policy.bats — declarative auth scope: registry fallbacks, documented
# precedence, and fail-closed validation. No Docker, no credential reads.
load helpers

_write_policy() {
  mkdir -p "$HOME/.config/box"
  printf '%s' "$1" >"$HOME/.config/box/state.toml"
  chmod 600 -- "$HOME/.config/box/state.toml"
}

@test "registry fallbacks preserve current behavior" {
  [ "$(box_state_field muse auth default_scope)" = "global" ]
  [ "$(box_state_field opencode auth default_scope)" = "project" ]
  [ "$(box_state_field codex auth default_scope)" = "project" ]
  unset BOX_AUTH_SCOPE BOX_M_AUTH_SCOPE BOX_O_AUTH_SCOPE BOX_C_AUTH_SCOPE BOX_STATE_CONFIG
  rm -f -- "$HOME/.config/box/state.toml"
  [ "$(box_auth_policy_resolve muse)" = "global" ]
  [ "$(box_auth_policy_resolve opencode)" = "project" ]
  [ "$(box_auth_policy_resolve codex)" = "project" ]
}

@test "every precedence combination resolves in documented order" {
  rm -f -- "$HOME/.config/box/state.toml"
  unset BOX_AUTH_SCOPE BOX_M_AUTH_SCOPE BOX_O_AUTH_SCOPE BOX_C_AUTH_SCOPE BOX_STATE_CONFIG
  # Common env beats registry fallback.
  BOX_AUTH_SCOPE=global run box_auth_policy_resolve codex
  [ "$status" -eq 0 ] && [ "$output" = "global" ]
  unset BOX_AUTH_SCOPE
  # Harness env beats common env.
  BOX_AUTH_SCOPE=global BOX_C_AUTH_SCOPE=project run box_auth_policy_resolve codex
  [ "$status" -eq 0 ] && [ "$output" = "project" ]
  unset BOX_AUTH_SCOPE BOX_C_AUTH_SCOPE
  # Config default beats fallback; harness config beats default.
  _write_policy $'[auth]\ndefault_scope = "global"\n'
  unset BOX_AUTH_SCOPE BOX_O_AUTH_SCOPE
  [ "$(box_auth_policy_resolve opencode)" = "global" ]
  _write_policy $'[auth]\ndefault_scope = "global"\n[auth.harnesses.opencode]\nscope = "project"\n'
  [ "$(box_auth_policy_resolve opencode)" = "project" ]
  # Harness env beats harness config.
  BOX_O_AUTH_SCOPE=global run box_auth_policy_resolve opencode
  [ "$status" -eq 0 ] && [ "$output" = "global" ]
  unset BOX_O_AUTH_SCOPE
  # Common env beats harness config.
  BOX_AUTH_SCOPE=project run box_auth_policy_resolve muse
  [ "$status" -eq 0 ] && [ "$output" = "project" ]
  unset BOX_AUTH_SCOPE
  rm -f -- "$HOME/.config/box/state.toml"
}

@test "set-but-empty and unknown scopes fail closed" {
  rm -f -- "$HOME/.config/box/state.toml"
  unset BOX_STATE_CONFIG
  BOX_AUTH_SCOPE= run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  BOX_AUTH_SCOPE=everywhere run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  unset BOX_AUTH_SCOPE
  BOX_M_AUTH_SCOPE= run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  unset BOX_M_AUTH_SCOPE
}

@test "shadowed invalid values are not hidden by valid overrides" {
  _write_policy $'[auth]\ndefault_scope = "bogus"\n'
  BOX_O_AUTH_SCOPE=project run box_auth_policy_resolve opencode
  [ "$status" -ne 0 ]
  unset BOX_O_AUTH_SCOPE
  _write_policy $'[auth]\ndefault_scope = "global"\n[auth.harnesses.opencode]\nscope = "bogus"\n'
  BOX_AUTH_SCOPE=project run box_auth_policy_resolve opencode
  [ "$status" -ne 0 ]
  unset BOX_AUTH_SCOPE
  rm -f -- "$HOME/.config/box/state.toml"
}

@test "invalid configuration shapes fail closed" {
  _write_policy $'schema_version = 2\n'
  run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  _write_policy $'[auth]\ndefault_scope = ""\n'
  run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  _write_policy $'[auth.harnesses.bogus]\nscope = "global"\n'
  run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  _write_policy $'[auth]\nunknown_key = "global"\n'
  run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  _write_policy $'[auth]\ndefault_scope = 1\n'
  run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  rm -f -- "$HOME/.config/box/state.toml"
}

@test "explicit missing config errors; implicit absence is valid" {
  rm -f -- "$HOME/.config/box/state.toml"
  unset BOX_AUTH_SCOPE BOX_M_AUTH_SCOPE
  BOX_STATE_CONFIG="$TEST_TMP/does-not-exist.toml" run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  unset BOX_STATE_CONFIG
  run box_auth_policy_resolve muse
  [ "$status" -eq 0 ]
}

@test "BOX_C_AUTH never selects persistence scope" {
  rm -f -- "$HOME/.config/box/state.toml"
  unset BOX_AUTH_SCOPE BOX_C_AUTH_SCOPE BOX_STATE_CONFIG
  BOX_C_AUTH=api run box_auth_policy_resolve codex
  [ "$status" -eq 0 ] && [ "$output" = "project" ]
  unset BOX_C_AUTH
}

@test "policy source labels each layer" {
  rm -f -- "$HOME/.config/box/state.toml"
  unset BOX_AUTH_SCOPE BOX_M_AUTH_SCOPE BOX_STATE_CONFIG
  [ "$(box_auth_policy_source muse)" = "registry-fallback" ]
  BOX_AUTH_SCOPE=project run box_auth_policy_source muse
  [ "$status" -eq 0 ] && [[ "$output" == "env:BOX_AUTH_SCOPE" ]]
  unset BOX_AUTH_SCOPE
  BOX_M_AUTH_SCOPE=project run box_auth_policy_source muse
  [ "$status" -eq 0 ] && [[ "$output" == "env:BOX_M_AUTH_SCOPE" ]]
  unset BOX_M_AUTH_SCOPE
}

@test "set-but-empty roots and literal sentinels fail closed" {
  rm -f -- "$HOME/.config/box/state.toml"
  unset BOX_STATE_CONFIG BOX_AUTH_ROOT BOX_AUTH_SCOPE BOX_M_AUTH_SCOPE
  BOX_STATE_CONFIG="" run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  unset BOX_STATE_CONFIG
  BOX_AUTH_ROOT="" run box_auth_root
  [ "$status" -ne 0 ]
  unset BOX_AUTH_ROOT
  BOX_AUTH_SCOPE="__unset__" run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  unset BOX_AUTH_SCOPE
  BOX_M_AUTH_SCOPE="__unset__" run box_auth_policy_resolve muse
  [ "$status" -ne 0 ]
  unset BOX_M_AUTH_SCOPE
}

@test "policy source validates shadowed invalid config" {
  _write_policy $'[auth]\ndefault_scope = "bogus"\n'
  BOX_O_AUTH_SCOPE=project run box_auth_policy_source opencode
  [ "$status" -ne 0 ]
  unset BOX_O_AUTH_SCOPE
  rm -f -- "$HOME/.config/box/state.toml"
}

@test "omitted scope in a known harness table inherits; schema booleans and floats fail" {
  _write_policy $'schema_version = 1\n[auth]\ndefault_scope = "project"\n[auth.harnesses.muse]\n'
  run box_auth_policy_resolve muse
  [ "$status" -eq 0 ]
  [ "$output" = project ]
  for value in true 1.0; do
    _write_policy "schema_version = $value"$'\n'
    run box_auth_policy_resolve muse
    [ "$status" -ne 0 ]
  done
}

@test "invalid unselected supplied harness scope is never hidden by a selected override" {
  BOX_C_AUTH_SCOPE=project BOX_O_AUTH_SCOPE=broken run box_auth_policy_resolve codex
  [ "$status" -ne 0 ]
}

@test "one policy snapshot reports matching scope and source for each layer" {
  run box_auth_policy_result muse
  [ "$status" -eq 0 ] && [ "$output" = $'global\nregistry-fallback' ]
  _write_policy $'[auth]\ndefault_scope = "project"\n'
  run box_auth_policy_result muse
  [ "$status" -eq 0 ] && [ "$output" = $'project\nconfig:'"$HOME/.config/box/state.toml#default" ]
  _write_policy $'[auth]\ndefault_scope = "project"\n[auth.harnesses.muse]\nscope = "global"\n'
  run box_auth_policy_result muse
  [ "$status" -eq 0 ] && [ "$output" = $'global\nconfig:'"$HOME/.config/box/state.toml#harness" ]
  BOX_AUTH_SCOPE=project run box_auth_policy_result muse
  [ "$status" -eq 0 ] && [ "$output" = $'project\nenv:BOX_AUTH_SCOPE' ]
  BOX_AUTH_SCOPE=project BOX_M_AUTH_SCOPE=global run box_auth_policy_result muse
  [ "$status" -eq 0 ] && [ "$output" = $'global\nenv:BOX_M_AUTH_SCOPE' ]
}

@test "default config ancestry refuses even when the file is absent" {
  mkdir -p "$HOME/.config/box"
  chmod 777 "$HOME/.config"
  run box_auth_policy_result muse
  [ "$status" -ne 0 ]
  [[ "$output" == *"Directory ancestor must not be group/other-writable"* ]]
  chmod 700 "$HOME/.config"
}

@test "default config refuses symlink parents and leaves foreign files unchanged" {
  mkdir -p "$TEST_TMP/foreign"
  printf 'sentinel' > "$TEST_TMP/foreign/marker"
  ln -s "$TEST_TMP/foreign" "$HOME/.config"
  run box_auth_policy_result muse
  [ "$status" -ne 0 ]
  [[ "$output" == *"Directory ancestor must not be a symlink"* ]]
  [ "$(cat "$TEST_TMP/foreign/marker")" = sentinel ]
  [ ! -e "$TEST_TMP/foreign/box" ]
}

@test "failed policy parsing emits no partial policy result" {
  _write_policy $'schema_version = 1\n[auth]\ndefault_scope = "global"\n[auth.harnesses.muse]\nscope = "bogus"\n'
  run bash -c 'BOX_TOOL=test; source "$1/lib/auth.sh"; box_auth_parse_config "$2" > "$3"' _ "$BUNDLE_DIR" "$HOME/.config/box/state.toml" "$TEST_TMP/parsed"
  [ "$status" -ne 0 ]
  [ ! -s "$TEST_TMP/parsed" ]
}

@test "duplicate TOML and unknown shadowed tables fail before policy output" {
  for content in $'[auth]\ndefault_scope = "global"\ndefault_scope = "project"\n' $'[auth.harnesses.muse]\nscope = "global"\n[auth.harnesses.unknown]\n'; do
    _write_policy "$content"
    BOX_M_AUTH_SCOPE=project run box_auth_policy_result muse
    [ "$status" -ne 0 ]
  done
}

@test "invalid transition and helper runtime selectors refuse even without a transition" {
  for value in '' invalid; do
    BOX_AUTH_TRANSITION="$value" run box_auth_policy_result muse
    [ "$status" -ne 0 ]
    BOX_AUTH_RUNTIME="$value" run box_auth_policy_result muse
    [ "$status" -ne 0 ]
  done
  BOX_AUTH_TRANSITION=fresh BOX_AUTH_RUNTIME=runsc run box_auth_policy_result muse
  [ "$status" -eq 0 ]
  BOX_AUTH_TRANSITION=use-existing BOX_AUTH_RUNTIME=runc run box_auth_policy_result muse
  [ "$status" -eq 0 ]
}
