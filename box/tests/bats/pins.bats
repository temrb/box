# pins.bats — lib/pins.sh single pin home (Phase 5).
load helpers

@test "pins loader exposes every pin from the bundle" {
  unset project
  box_load_all_pins "$BUNDLE_DIR"
  [ "$MUSE_VERSION" = "1.0.3-R2198.1" ]
  [[ "$MUSE_SHA256_AMD64" =~ ^[0-9a-f]{64}$ ]]
  [[ "$MUSE_SHA256_ARM64" =~ ^[0-9a-f]{64}$ ]]
  [ "$OPENCODE_VERSION" = "1.18.29" ]
  [[ "$OPENCODE_NPM_INTEGRITY" == sha512-* ]]
  [[ "$OPENCODE_NPM_INTEGRITY_LINUX_X64" == sha512-* ]]
  [[ "$OPENCODE_NPM_INTEGRITY_LINUX_ARM64" == sha512-* ]]
  [ "$NODE_VERSION" = "22.23.2-1nodesource1" ]
  [ "$NODESOURCE_FINGERPRINT" = "6F71F525282841EEDAF851B42F59B5F99B1BE0B4" ]
}

@test "pins printer round-trips every pin name" {
  unset project
  for id in $box_tool_ids; do
    for pin in $(box_tool_field "$id" pin_keys); do
      val=$(box_print_pin "$BUNDLE_DIR" "$pin")
      [ -n "$val" ] || { echo "empty pin: $pin"; return 1; }
    done
  done
  [ "$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)" = "1.0.3-R2198.1" ]
  [[ "$(box_print_pin "$BUNDLE_DIR" OPENCODE_NPM_INTEGRITY)" == *"==" ]]
}

@test "pins printer rejects unknown pin names" {
  unset project
  run box_print_pin "$BUNDLE_DIR" EVIL_PIN
  [ "$status" -ne 0 ]
}

@test "pins loader fails closed on a missing bundle dir" {
  unset project
  run box_load_all_pins "$TEST_TMP/no-such-dir"
  [ "$status" -ne 0 ]
}

@test "pin table matches gen-pins.sh output" {
  run bash "$BUNDLE_DIR/gen-pins.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "pin table contains every resolved pin" {
  block=$(box_pin_block "$BUNDLE_DIR/docs/architecture.md")
  [[ "$block" == *"$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)"* ]]
  [[ "$block" == *"$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)"* ]]
  [[ "$block" == *"$(box_print_pin "$BUNDLE_DIR" NODE_VERSION)"* ]]
  [[ "$block" == *"$(box_print_pin "$BUNDLE_DIR" NODESOURCE_FINGERPRINT)"* ]]
}

@test "shared pin asserts cover no-default ARGs, tarballs, and delegation" {
  run box_assert_no_default_args "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
  run box_assert_tarball_pins "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
  run box_assert_build_delegation "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
}

@test "dockerfile repeats SHELL per-stage with none before first FROM" {
  run box_assert_shell_placement "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
}
