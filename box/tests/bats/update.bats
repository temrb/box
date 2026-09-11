# update.bats — update-pins.sh one-command updater.
# Fetch paths use the BOX_UPDATE_* seed seam so these tests need no network;
# live fetch is exercised manually against the real endpoints.
load helpers

unset_seed_pins() {
  unset BOX_UPDATE_MUSE_VERSION BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_MUSE_SHA256_ARM64
  unset BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_NPM_INTEGRITY
  unset BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64 BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64
}

# Seed pins equal to the bundle pins (network-free no-op renders "up to date").
seed_current_pins() {
  unset_seed_pins
  BOX_UPDATE_MUSE_VERSION=$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)
  BOX_UPDATE_MUSE_SHA256_AMD64=$(box_print_pin "$BUNDLE_DIR" MUSE_SHA256_AMD64)
  BOX_UPDATE_MUSE_SHA256_ARM64=$(box_print_pin "$BUNDLE_DIR" MUSE_SHA256_ARM64)
  BOX_UPDATE_OPENCODE_VERSION=$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)
  BOX_UPDATE_OPENCODE_NPM_INTEGRITY=$(box_print_pin "$BUNDLE_DIR" OPENCODE_NPM_INTEGRITY)
  BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64=$(box_print_pin "$BUNDLE_DIR" OPENCODE_NPM_INTEGRITY_LINUX_X64)
  BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64=$(box_print_pin "$BUNDLE_DIR" OPENCODE_NPM_INTEGRITY_LINUX_ARM64)
  export BOX_UPDATE_MUSE_VERSION BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_MUSE_SHA256_ARM64
  export BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_NPM_INTEGRITY
  export BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64 BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64
}

# Seed pins for a synthetic newer release (valid formats, network-free apply).
seed_synthetic_pins() {
  unset_seed_pins
  BOX_UPDATE_MUSE_VERSION='9.9.9-R999.9'
  BOX_UPDATE_MUSE_SHA256_AMD64='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  BOX_UPDATE_MUSE_SHA256_ARM64='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  BOX_UPDATE_OPENCODE_VERSION='9.9.9'
  BOX_UPDATE_OPENCODE_NPM_INTEGRITY='sha512-AAAAAAAAAAAAAAAAAAAAAA=='
  BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64='sha512-BBBBBBBBBBBBBBBBBBBBBB=='
  BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64='sha512-CCCCCCCCCCCCCCCCCCCCCC=='
  export BOX_UPDATE_MUSE_VERSION BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_MUSE_SHA256_ARM64
  export BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_NPM_INTEGRITY
  export BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64 BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64
}

@test "update prints usage and rejects unknown flags" {
  unset_seed_pins
  run bash "$BUNDLE_DIR/update-pins.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: update-pins.sh"* ]]
  run bash "$BUNDLE_DIR/update-pins.sh" --bogus
  [ "$status" -ne 0 ]
}

@test "update --check with explicit current versions changes nothing" {
  unset_seed_pins
  before_muse=$(sha256sum -- "$BUNDLE_DIR/version-muse.env")
  before_opencode=$(sha256sum -- "$BUNDLE_DIR/version-opencode.env")
  run bash "$BUNDLE_DIR/update-pins.sh" --check \
    --muse "$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)" \
    --opencode "$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
  [ "$(sha256sum -- "$BUNDLE_DIR/version-muse.env")" = "$before_muse" ]
  [ "$(sha256sum -- "$BUNDLE_DIR/version-opencode.env")" = "$before_opencode" ]
}

@test "update --check with current seeds reports up to date" {
  seed_current_pins
  run bash "$BUNDLE_DIR/update-pins.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Muse: "*"(up to date)"* ]]
  [[ "$output" == *"OpenCode: "*"(up to date)"* ]]
}

@test "update rejects seed/flag conflicts and partial seeds" {
  seed_current_pins
  run bash "$BUNDLE_DIR/update-pins.sh" --check --muse '9.9.9-R999.9'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Conflicting Muse pins"* ]]
  unset BOX_UPDATE_MUSE_SHA256_ARM64
  run bash "$BUNDLE_DIR/update-pins.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"Partial Muse seed"* ]]
  seed_current_pins
  run bash "$BUNDLE_DIR/update-pins.sh" --check --opencode '9.9.9'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Conflicting OpenCode pins"* ]]
  unset BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64
  run bash "$BUNDLE_DIR/update-pins.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"Partial OpenCode seed"* ]]
}

@test "update rejects trailing args after --" {
  unset_seed_pins
  run bash "$BUNDLE_DIR/update-pins.sh" --check -- --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Takes no positional arguments"* ]]
}

@test "update reloads pins before the in-process build" {
  # Regression: box_load_all_pins caches per bundle dir, so the full-mode
  # build after the rewrite must re-parse or it tags/labels stale pins.
  run grep -F 'box_reload_all_pins "$bundle_dir"' "$BUNDLE_DIR/update-pins.sh"
  [ "$status" -eq 0 ]
  reload_line=$(grep -Fn 'box_reload_all_pins' "$BUNDLE_DIR/update-pins.sh" | head -n1 | cut -d: -f1)
  build_line=$(grep -Fn 'box_build_image muse' "$BUNDLE_DIR/update-pins.sh" | head -n1 | cut -d: -f1)
  [ -n "$reload_line" ] && [ -n "$build_line" ]
  [ "$reload_line" -lt "$build_line" ]
}

@test "pins reloader re-parses after a version-file rewrite" {
  unset project
  bundle_muse=$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)
  bundle_amd64=$(box_print_pin "$BUNDLE_DIR" MUSE_SHA256_AMD64)
  bundle_arm64=$(box_print_pin "$BUNDLE_DIR" MUSE_SHA256_ARM64)
  copy="$TEST_TMP/bundle"
  cp -r -- "$BUNDLE_DIR" "$copy"
  box_load_all_pins "$copy"
  [ "$MUSE_VERSION" = "$bundle_muse" ]
  printf '# test\nMUSE_VERSION=9.9.9-R999.9\nMUSE_SHA256_AMD64=%s\nMUSE_SHA256_ARM64=%s\n' \
    "$bundle_amd64" "$bundle_arm64" >"$copy/version-muse.env"
  # Cached load still sees the old pins; the reloader sees the rewrite.
  box_load_all_pins "$copy"
  [ "$MUSE_VERSION" = "$bundle_muse" ]
  box_reload_all_pins "$copy"
  [ "$MUSE_VERSION" = "9.9.9-R999.9" ]
}

@test "update rejects URL-unsafe explicit versions without fetching" {
  unset_seed_pins
  run bash "$BUNDLE_DIR/update-pins.sh" --check --muse '1.0;evil'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid muse version"* ]]
  run bash "$BUNDLE_DIR/update-pins.sh" --check --opencode '../evil'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid opencode version"* ]]
}

@test "update --pins-only applies seeded pins in a copied bundle" {
  if [ "$(id -u)" -eq 0 ]; then skip 'update refuses root before mutation'; fi
  seed_synthetic_pins
  copy="$TEST_TMP/bundle"
  cp -r -- "$BUNDLE_DIR" "$copy"
  run bash "$copy/update-pins.sh" --pins-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  grep -Fq 'MUSE_VERSION=9.9.9-R999.9' -- "$copy/version-muse.env"
  grep -Fq 'OPENCODE_VERSION=9.9.9' -- "$copy/version-opencode.env"
  grep -Fq "NODE_VERSION=$(box_print_pin "$BUNDLE_DIR" NODE_VERSION)" -- "$copy/version-opencode.env"
  grep -Fq "NODESOURCE_FINGERPRINT=$(box_print_pin "$BUNDLE_DIR" NODESOURCE_FINGERPRINT)" -- "$copy/version-opencode.env"
  run bash "$copy/gen-pins.sh" --check
  [ "$status" -eq 0 ]
  run bash "$copy/gen-verify.sh" --check
  [ "$status" -eq 0 ]
  run bash "$copy/check-pins.sh"
  [ "$status" -eq 0 ]
  run bats "$copy/tests/bats/pins.bats" "$copy/tests/bats/version.bats"
  [ "$status" -eq 0 ]
}

@test "update fails closed on a bad seed with the bundle untouched" {
  seed_synthetic_pins
  BOX_UPDATE_MUSE_SHA256_AMD64='xyz'
  export BOX_UPDATE_MUSE_SHA256_AMD64
  copy="$TEST_TMP/bundle"
  cp -r -- "$BUNDLE_DIR" "$copy"
  before=$(sha256sum -- "$copy/version-muse.env" "$copy/version-opencode.env")
  run bash "$copy/update-pins.sh" --pins-only
  [ "$status" -ne 0 ]
  [ "$(sha256sum -- "$copy/version-muse.env" "$copy/version-opencode.env")" = "$before" ]
  run grep -F '9.9.9' -- "$copy/tests/bats/pins.bats"
  [ "$status" -ne 0 ]
}
