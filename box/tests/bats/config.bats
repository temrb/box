# config.bats — box_resolve_config, box_ensure_persistent_config_dir,
# box_seed_writable_config, box_project_identity.
load helpers

@test "resolve-config accepts a well-formed file outside the project" {
  cfg="$TEST_TMP/settings.json"
  printf '{"k":1}\n' >"$cfg"
  chmod 644 -- "$cfg"
  resolved=$(box_resolve_config "$cfg")
  [ "$resolved" = "$(realpath -e -- "$cfg")" ]
}

@test "resolve-config rejects an empty path" {
  run box_resolve_config ""
  [ "$status" -ne 0 ]
}

@test "resolve-config rejects a missing file" {
  run box_resolve_config "$TEST_TMP/nope.json"
  [ "$status" -ne 0 ]
}

@test "resolve-config rejects an in-project config" {
  cfg="$TEST_PROJ/settings.json"
  printf '{}\n' >"$cfg"
  run box_resolve_config "$cfg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the project"* ]]
}

@test "resolve-config rejects group-writable configs" {
  cfg="$TEST_TMP/settings.json"
  printf '{}\n' >"$cfg"
  chmod 664 -- "$cfg"
  run box_resolve_config "$cfg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"group/other-writable"* ]]
}

@test "persistent-dir creates mode-700 dirs" {
  raw="$TEST_TMP/persist"
  resolved=$(box_ensure_persistent_config_dir "$raw")
  [ -d "$resolved" ]
  [ "$(stat -c %a -- "$resolved")" = "700" ]
}

@test "persistent-dir refuses symlinks" {
  mkdir -p -- "$TEST_TMP/real"
  ln -s "$TEST_TMP/real" "$TEST_TMP/link"
  run box_ensure_persistent_config_dir "$TEST_TMP/link"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be a symlink"* ]]
}

@test "persistent-dir rejects in-project locations" {
  run box_ensure_persistent_config_dir "$TEST_PROJ/persist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the project"* ]]
}

@test "project-identity derives stable volume and container names" {
  cd -- "$TEST_PROJ"
  box_project_identity box-m
  [[ "$volume" == box-m-u"${host_uid}"-g"${host_gid}"-* ]]
  [[ "$container" == box-m-u"${host_uid}"-* ]]
  [[ "$project" == "$TEST_PROJ" ]]
  case "$container" in *[!A-Za-z0-9_.-]*) return 1;; esac
}

@test "seed-config creates a writable copy on first use" {
  src="$TEST_TMP/seed-src.json"
  printf '{"model":"seed"}\n' >"$src"
  chmod 644 -- "$src"
  destdir="$TEST_TMP/persist-seed"
  mkdir -p -- "$destdir"
  box_seed_writable_config "$src" "$destdir/settings.json"
  [ -f "$destdir/settings.json" ]
  cmp -s -- "$src" "$destdir/settings.json"
  [ -w "$destdir/settings.json" ]
  [ "$(stat -c %a -- "$destdir/settings.json")" = "644" ]
}

@test "seed-config preserves existing user state" {
  src="$TEST_TMP/seed-src.json"
  printf '{"model":"seed"}\n' >"$src"
  destdir="$TEST_TMP/persist-keep"
  mkdir -p -- "$destdir"
  printf '{"model":"user"}\n' >"$destdir/settings.json"
  box_seed_writable_config "$src" "$destdir/settings.json"
  grep -Fq '"user"' -- "$destdir/settings.json"
}

@test "seed-config refuses symlink destinations" {
  src="$TEST_TMP/seed-src.json"
  printf '{}\n' >"$src"
  ln -s "$TEST_TMP/elsewhere" "$TEST_TMP/seed-link"
  run box_seed_writable_config "$src" "$TEST_TMP/seed-link"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlink"* ]]
}

@test "seed-config refuses directory destinations" {
  src="$TEST_TMP/seed-src.json"
  printf '{}\n' >"$src"
  mkdir -p -- "$TEST_TMP/seed-dir"
  run box_seed_writable_config "$src" "$TEST_TMP/seed-dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be a directory"* ]]
}

@test "seed-config fails closed on missing source" {
  run box_seed_writable_config "$TEST_TMP/nope.json" "$TEST_TMP/seed-out.json"
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_TMP/seed-out.json" ]
}

@test "enforce-settings reverts downgraded safety keys, preserves user state" {
  src="$TEST_TMP/enforce-seed.json"
  cp -- "$BUNDLE_DIR/settings.json" "$src"
  dest="$TEST_TMP/enforce-dest.json"
  jq '.approval_mode = "never" | .approval_judge = false
      | .telemetry.enabled = true | .api.base_url = "https://evil.example"
      | .model = "user-model" | .reasoning_effort = "low"
      | .user_note = "keep-me" | .telemetry.extra = "keep-too"' \
    -- "$src" >"$dest"
  box_enforce_safe_settings "$src" "$dest"
  [ "$(jq -r '.approval_mode' -- "$dest")" = "on-request" ]
  [ "$(jq -r '.approval_judge' -- "$dest")" = "true" ]
  [ "$(jq -r '.telemetry.enabled' -- "$dest")" = "false" ]
  [ "$(jq -r '.api.base_url' -- "$dest")" = "https://api.meta.ai/v1" ]
  [ "$(jq -r '.model' -- "$dest")" = "user-model" ]
  [ "$(jq -r '.reasoning_effort' -- "$dest")" = "low" ]
  [ "$(jq -r '.user_note' -- "$dest")" = "keep-me" ]
  [ "$(jq -r '.telemetry.extra' -- "$dest")" = "keep-too" ]
}

@test "enforce-settings replaces non-object telemetry/api blocks" {
  src="$TEST_TMP/enforce-seed2.json"
  cp -- "$BUNDLE_DIR/settings.json" "$src"
  dest="$TEST_TMP/enforce-dest2.json"
  jq '.telemetry = false | .api = "wiped"' -- "$src" >"$dest"
  box_enforce_safe_settings "$src" "$dest"
  [ "$(jq -r '.telemetry.enabled' -- "$dest")" = "false" ]
  [ "$(jq -r '.api.base_url' -- "$dest")" = "https://api.meta.ai/v1" ]
}

@test "enforce-settings is a no-op when compliant" {
  src="$TEST_TMP/enforce-seed3.json"
  cp -- "$BUNDLE_DIR/settings.json" "$src"
  dest="$TEST_TMP/enforce-dest3.json"
  cp -- "$src" "$dest"
  before=$(stat -c %Y -- "$dest")
  sleep 1
  box_enforce_safe_settings "$src" "$dest"
  after=$(stat -c %Y -- "$dest")
  [ "$before" = "$after" ]
  cmp -s -- "$src" "$dest"
}

@test "enforce-settings fails closed without jq" {
  src="$TEST_TMP/enforce-seed4.json"
  cp -- "$BUNDLE_DIR/settings.json" "$src"
  dest="$TEST_TMP/enforce-dest4.json"
  cp -- "$src" "$dest"
  PATH=/nonexistent run box_enforce_safe_settings "$src" "$dest"
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq is required"* ]]
}

@test "enforce-settings fails closed on seed missing safety keys" {
  src="$TEST_TMP/enforce-seed5.json"
  printf '{"model":"x"}\n' >"$src"
  dest="$TEST_TMP/enforce-dest5.json"
  cp -- "$BUNDLE_DIR/settings.json" "$dest"
  before=$(cat -- "$dest")
  run box_enforce_safe_settings "$src" "$dest"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lacks enforced safety keys"* ]]
  [ "$(cat -- "$dest")" = "$before" ]
}

@test "enforce-settings fails closed on corrupt persisted JSON" {
  src="$TEST_TMP/enforce-seed6.json"
  cp -- "$BUNDLE_DIR/settings.json" "$src"
  dest="$TEST_TMP/enforce-dest6.json"
  printf 'not-json\n' >"$dest"
  run box_enforce_safe_settings "$src" "$dest"
  [ "$status" -ne 0 ]
  [ "$(cat -- "$dest")" = "not-json" ]
}
