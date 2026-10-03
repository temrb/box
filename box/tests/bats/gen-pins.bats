load helpers

@test "pin generator validates registered TOML artifacts with the configured model" {
  run bash "$BUNDLE_DIR/gen-pins.sh" --check
  [ "$status" -eq 0 ]
  run box_config_get "$BUNDLE_DIR/harnesses/codex/config/config.toml" .model string
  [ "$status" -eq 0 ]
  [ "$output" = gpt-6.1-sol ]
}

@test "pin generator skips Muse safety checks when Muse is removed" {
  copy="$TEST_TMP/bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  sed -i "s/box_tool_ids='muse opencode codex'/box_tool_ids='opencode codex'/" "$copy/lib/tools.sh"
  # Removing a harness also removes its records; orphan records are invalid.
  cat >>"$copy/lib/tools.sh" <<'REMOVE'
for _fixture_map in _BOX_TOOL_REGISTRY _BOX_ARTIFACTS _BOX_STATES; do
  declare -n _fixture_records="$_fixture_map"
  for _fixture_key in "${!_fixture_records[@]}"; do
    [[ "$_fixture_key" != muse,* ]] || unset '_fixture_records[$_fixture_key]'
  done
done
REMOVE
  rm "$copy/harnesses/muse/config/settings.json" "$copy/harnesses/muse/version-muse.env" "$copy/harnesses/muse/verify.d/40-readiness-muse.sh"
  run bash "$copy/gen-pins.sh"
  [ "$status" -eq 0 ]
  run bash "$copy/gen-pins.sh" --check
  [ "$status" -eq 0 ]
}

@test "pin generator derives version source names from the registry" {
  copy="$TEST_TMP/bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  sed -i "s/\[opencode,version_file\]='version-opencode.env'/[opencode,version_file]='version-fixture.env'/" "$copy/lib/tools.sh"
  sed -i 's@harnesses/opencode/version-opencode.env@harnesses/opencode/version-fixture.env@g' "$copy/lib/tools.sh"
  mv "$copy/harnesses/opencode/version-opencode.env" "$copy/harnesses/opencode/version-fixture.env"
  run bash "$copy/gen-pins.sh"
  [ "$status" -eq 0 ]
  grep -Fq '| OpenCode `OPENCODE_VERSION` (`version-fixture.env`)' "$copy/docs/architecture.md"
}
