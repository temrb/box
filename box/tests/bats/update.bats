# update.bats — update-pins.sh one-command updater.
# Fetch paths use the BOX_UPDATE_* seed seam so these tests need no network;
# live fetch is exercised manually against the real endpoints.
load helpers

unset_seed_pins() {
  unset BOX_UPDATE_CODEX_VERSION BOX_UPDATE_CODEX_SHA256_AMD64 BOX_UPDATE_CODEX_SHA256_ARM64
  unset BOX_UPDATE_MUSE_VERSION BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_MUSE_SHA256_ARM64
  unset BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
}

# Seed pins equal to the bundle pins (network-free no-op renders "up to date").
seed_current_pins() {
  unset_seed_pins
  BOX_UPDATE_CODEX_VERSION=$(box_print_pin "$BUNDLE_DIR" CODEX_VERSION)
  BOX_UPDATE_CODEX_SHA256_AMD64=$(box_print_pin "$BUNDLE_DIR" CODEX_SHA256_AMD64)
  BOX_UPDATE_CODEX_SHA256_ARM64=$(box_print_pin "$BUNDLE_DIR" CODEX_SHA256_ARM64)
  export BOX_UPDATE_CODEX_VERSION BOX_UPDATE_CODEX_SHA256_AMD64 BOX_UPDATE_CODEX_SHA256_ARM64
  BOX_UPDATE_MUSE_VERSION=$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)
  BOX_UPDATE_MUSE_SHA256_AMD64=$(box_print_pin "$BUNDLE_DIR" MUSE_SHA256_AMD64)
  BOX_UPDATE_MUSE_SHA256_ARM64=$(box_print_pin "$BUNDLE_DIR" MUSE_SHA256_ARM64)
  BOX_UPDATE_OPENCODE_VERSION=$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)
  BOX_UPDATE_OPENCODE_SHA256_AMD64=$(box_print_pin "$BUNDLE_DIR" OPENCODE_SHA256_AMD64)
  BOX_UPDATE_OPENCODE_SHA256_ARM64=$(box_print_pin "$BUNDLE_DIR" OPENCODE_SHA256_ARM64)
  export BOX_UPDATE_MUSE_VERSION BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_MUSE_SHA256_ARM64
  export BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
}

# Seed pins for a synthetic newer release (valid formats, network-free apply).
# Uses alternate values when the bundle already carries the defaults (a
# rehearsal copy bumped to synthetics), so the seeded versions always differ
# from current and the apply tests stay meaningful in any bundle.
seed_synthetic_pins() {
  unset_seed_pins
  BOX_UPDATE_CODEX_VERSION=$(box_print_pin "$BUNDLE_DIR" CODEX_VERSION)
  BOX_UPDATE_CODEX_SHA256_AMD64=$(box_print_pin "$BUNDLE_DIR" CODEX_SHA256_AMD64)
  BOX_UPDATE_CODEX_SHA256_ARM64=$(box_print_pin "$BUNDLE_DIR" CODEX_SHA256_ARM64)
  export BOX_UPDATE_CODEX_VERSION BOX_UPDATE_CODEX_SHA256_AMD64 BOX_UPDATE_CODEX_SHA256_ARM64
  cur_muse=$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)
  cur_opencode=$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)
  [ -n "$cur_muse" ] && [ -n "$cur_opencode" ]
  if [ "$cur_muse" = '9.9.9-R999.9' ] || [ "$cur_opencode" = '9.9.9' ]; then
    BOX_UPDATE_MUSE_VERSION='8.8.8-R888.8'
    BOX_UPDATE_MUSE_SHA256_AMD64='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    BOX_UPDATE_MUSE_SHA256_ARM64='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
    BOX_UPDATE_OPENCODE_VERSION='8.8.8'
    BOX_UPDATE_OPENCODE_SHA256_AMD64='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
    BOX_UPDATE_OPENCODE_SHA256_ARM64='ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
  else
    BOX_UPDATE_MUSE_VERSION='9.9.9-R999.9'
    BOX_UPDATE_MUSE_SHA256_AMD64='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    BOX_UPDATE_MUSE_SHA256_ARM64='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    BOX_UPDATE_OPENCODE_VERSION='9.9.9'
    BOX_UPDATE_OPENCODE_SHA256_AMD64='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    BOX_UPDATE_OPENCODE_SHA256_ARM64='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  fi
  export BOX_UPDATE_MUSE_VERSION BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_MUSE_SHA256_ARM64
  export BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
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
  before_muse=$(sha256sum -- "$BUNDLE_DIR/harnesses/muse/version-muse.env")
  before_opencode=$(sha256sum -- "$BUNDLE_DIR/harnesses/opencode/version-opencode.env")
  run bash "$BUNDLE_DIR/update-pins.sh" --check \
    --muse "$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)" \
    --opencode "$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)" --codex "$(box_print_pin "$BUNDLE_DIR" CODEX_VERSION)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
  [ "$(sha256sum -- "$BUNDLE_DIR/harnesses/muse/version-muse.env")" = "$before_muse" ]
  [ "$(sha256sum -- "$BUNDLE_DIR/harnesses/opencode/version-opencode.env")" = "$before_opencode" ]
}

@test "update --check with current seeds reports up to date" {
  seed_current_pins
  run bash "$BUNDLE_DIR/update-pins.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Muse: "*"(up to date)"* ]]
  [[ "$output" == *"OpenCode: "*"(up to date)"* ]]
}

@test "update --check rejects a partial seed" {
  seed_current_pins
  unset BOX_UPDATE_OPENCODE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
  run bash "$BUNDLE_DIR/update-pins.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"Partial OpenCode seed"* ]]
}

@test "update detects and applies digest changes at the same version" {
  seed_current_pins
  BOX_UPDATE_MUSE_SHA256_AMD64=$(printf '%064d' 1)
  BOX_UPDATE_OPENCODE_SHA256_ARM64='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  export BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
  run bash "$BUNDLE_DIR/update-pins.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Muse: "*"pins changed: MUSE_SHA256_AMD64"* ]]
  [[ "$output" == *"OpenCode: "*"pins changed: OPENCODE_SHA256_ARM64"* ]]
  copy="$TEST_TMP/bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  run bash "$copy/update-pins.sh" --pins-only
  [ "$status" -eq 0 ]
  grep -Fxq "MUSE_SHA256_AMD64=$BOX_UPDATE_MUSE_SHA256_AMD64" "$copy/harnesses/muse/version-muse.env"
  grep -Fxq "OPENCODE_SHA256_ARM64=$BOX_UPDATE_OPENCODE_SHA256_ARM64" "$copy/harnesses/opencode/version-opencode.env"
}

@test "update validates malformed unchanged-version candidates in check and apply modes" {
  seed_current_pins
  BOX_UPDATE_MUSE_SHA256_AMD64=invalid
  export BOX_UPDATE_MUSE_SHA256_AMD64
  before=$(sha256sum "$BUNDLE_DIR/harnesses/muse/version-muse.env" "$BUNDLE_DIR/harnesses/opencode/version-opencode.env")
  for mode in --check --pins-only; do
    run bash "$BUNDLE_DIR/update-pins.sh" "$mode"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid MUSE_SHA256_AMD64"* ]]
  done
  [ "$(sha256sum "$BUNDLE_DIR/harnesses/muse/version-muse.env" "$BUNDLE_DIR/harnesses/opencode/version-opencode.env")" = "$before" ]
}

@test "update restores all pin consumers when generation fails and cleans temporary files" {
  seed_synthetic_pins
  copy="$TEST_TMP/bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  # Fails after the version files and generated harnesses have changed.
  printf 'malformed\n' >"$copy/harnesses/muse/config/settings.json"
  before=$(sha256sum "$copy/harnesses/muse/version-muse.env" "$copy/harnesses/opencode/version-opencode.env" "$copy/verify-muse.sh" "$copy/verify-opencode.sh" "$copy/docs/architecture.md")
  temp_dir="$TEST_TMP/update-temp"
  mkdir "$temp_dir"
  run env TMPDIR="$temp_dir" bash "$copy/update-pins.sh" --pins-only
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$copy/harnesses/muse/version-muse.env" "$copy/harnesses/opencode/version-opencode.env" "$copy/verify-muse.sh" "$copy/verify-opencode.sh" "$copy/docs/architecture.md")" = "$before" ]
  [ -z "$(find "$temp_dir" -mindepth 1 -print -quit)" ]
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
  unset BOX_UPDATE_OPENCODE_SHA256_ARM64
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
  build_line=$(grep -Fn 'box_build_image "$id"' "$BUNDLE_DIR/update-pins.sh" | head -n1 | cut -d: -f1)
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
    "$bundle_amd64" "$bundle_arm64" >"$copy/harnesses/muse/version-muse.env"
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
  # Bump-invariant files: readiness partials (tokens) and tests (no pin
  # literals) must survive the apply byte-identical.
  before=$(sha256sum -- "$copy/harnesses/muse/verify.d/40-readiness-muse.sh" "$copy/harnesses/opencode/verify.d/40-readiness-opencode.sh" \
    "$copy/tests/bats/pins.bats" "$copy/tests/bats/version.bats" "$copy/tests/bats/opencode-v2.bats")
  run bash "$copy/update-pins.sh" --pins-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  grep -Fq "MUSE_VERSION=$BOX_UPDATE_MUSE_VERSION" -- "$copy/harnesses/muse/version-muse.env"
  grep -Fq "OPENCODE_VERSION=$BOX_UPDATE_OPENCODE_VERSION" -- "$copy/harnesses/opencode/version-opencode.env"
  grep -Fq "OPENCODE_SHA256_AMD64=$BOX_UPDATE_OPENCODE_SHA256_AMD64" -- "$copy/harnesses/opencode/version-opencode.env"
  grep -Fq "OPENCODE_SHA256_ARM64=$BOX_UPDATE_OPENCODE_SHA256_ARM64" -- "$copy/harnesses/opencode/version-opencode.env"
  run grep -F "NODE_VERSION" -- "$copy/harnesses/opencode/version-opencode.env"
  [ "$status" -ne 0 ]
  [ "$(sha256sum -- "$copy/harnesses/muse/verify.d/40-readiness-muse.sh" "$copy/harnesses/opencode/verify.d/40-readiness-opencode.sh" \
    "$copy/tests/bats/pins.bats" "$copy/tests/bats/version.bats" "$copy/tests/bats/opencode-v2.bats")" = "$before" ]
  # Generated outputs carry the synthetic versions.
  grep -Fq "$BOX_UPDATE_MUSE_VERSION" -- "$copy/verify-muse.sh"
  grep -Fq "$BOX_UPDATE_OPENCODE_VERSION" -- "$copy/verify-opencode.sh"
  grep -Fq "\`$BOX_UPDATE_MUSE_VERSION\`" -- "$copy/docs/architecture.md"
  grep -Fq "\`$BOX_UPDATE_OPENCODE_VERSION\`" -- "$copy/docs/architecture.md"
  run bash "$copy/gen-pins.sh" --check
  [ "$status" -eq 0 ]
  run bash "$copy/gen-verify.sh" --check
  [ "$status" -eq 0 ]
  run bash "$copy/check-pins.sh"
  [ "$status" -eq 0 ]
  run bats "$copy/tests/bats/pins.bats" "$copy/tests/bats/version.bats" "$copy/tests/bats/opencode-v2.bats"
  [ "$status" -eq 0 ]
}

@test "update fails closed on a bad seed with the bundle untouched" {
  seed_synthetic_pins
  BOX_UPDATE_MUSE_SHA256_AMD64='xyz'
  export BOX_UPDATE_MUSE_SHA256_AMD64
  copy="$TEST_TMP/bundle"
  cp -r -- "$BUNDLE_DIR" "$copy"
  before=$(sha256sum -- "$copy/harnesses/muse/version-muse.env" "$copy/harnesses/opencode/version-opencode.env" \
    "$copy/harnesses/muse/verify.d/40-readiness-muse.sh" "$copy/harnesses/opencode/verify.d/40-readiness-opencode.sh" \
    "$copy/verify-muse.sh" "$copy/verify-opencode.sh" \
    "$copy/tests/bats/pins.bats" "$copy/tests/bats/version.bats")
  run bash "$copy/update-pins.sh" --pins-only
  [ "$status" -ne 0 ]
  [ "$(sha256sum -- "$copy/harnesses/muse/version-muse.env" "$copy/harnesses/opencode/version-opencode.env" \
    "$copy/harnesses/muse/verify.d/40-readiness-muse.sh" "$copy/harnesses/opencode/verify.d/40-readiness-opencode.sh" \
    "$copy/verify-muse.sh" "$copy/verify-opencode.sh" \
    "$copy/tests/bats/pins.bats" "$copy/tests/bats/version.bats")" = "$before" ]
  run grep -F '9.9.9' -- "$copy/tests/bats/pins.bats"
  [ "$status" -ne 0 ]
}

@test "concurrent update cannot roll back another updater's accepted pins" {
  seed_current_pins
  copy="$TEST_TMP/concurrent-bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  mv "$copy/gen-verify.sh" "$copy/gen-verify-real.sh"
  cat > "$copy/gen-verify.sh" <<'SH'
#!/bin/bash
if [[ ${AUDIT_FIRST:-0} == 1 ]]; then
  touch "$AUDIT_BARRIER/entered"
  while [[ ! -e "$AUDIT_BARRIER/release" ]]; do sleep .05; done
  exit 1
fi
exec bash "${BASH_SOURCE[0]%/*}/gen-verify-real.sh" "$@"
SH
  barrier="$TEST_TMP/barrier"; mkdir "$barrier"
  env AUDIT_FIRST=1 AUDIT_BARRIER="$barrier" BOX_UPDATE_MUSE_SHA256_AMD64="$(printf '%064d' 1)" \
    bash "$copy/update-pins.sh" --pins-only >"$TEST_TMP/first.log" 2>&1 &
  first=$!
  for _ in {1..200}; do [[ ! -e "$barrier/entered" ]] || break; sleep .05; done
  if [[ ! -e "$barrier/entered" ]]; then kill "$first"; wait "$first" || true; return 1; fi
  run env BOX_UPDATE_MUSE_SHA256_AMD64="$(printf '%064d' 2)" bash "$copy/update-pins.sh" --pins-only
  second_status=$status
  touch "$barrier/release"
  wait "$first" && first_status=0 || first_status=$?
  [ "$first_status" -ne 0 ]
  if [[ "$second_status" == 0 ]]; then
    grep -Fxq "MUSE_SHA256_AMD64=$(printf '%064d' 2)" "$copy/harnesses/muse/version-muse.env"
  else
    [[ "$output" == *"maintenance already running"* ]]
    cmp "$BUNDLE_DIR/harnesses/muse/version-muse.env" "$copy/harnesses/muse/version-muse.env"
  fi
  run bash "$copy/gen-verify-real.sh" --check
  [ "$status" -eq 0 ]
}

@test "TERM during generation rolls back pin consumers and permits retry" {
  seed_current_pins
  copy="$TEST_TMP/interrupted-bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  mv "$copy/gen-verify.sh" "$copy/gen-verify-real.sh"
  cat > "$copy/gen-verify.sh" <<'SH'
#!/bin/bash
kill -TERM "$PPID"
sleep .1
SH
  before=$(sha256sum "$copy/harnesses/muse/version-muse.env" "$copy/verify-muse.sh" "$copy/docs/architecture.md")
  run env BOX_UPDATE_MUSE_SHA256_AMD64="$(printf '%064d' 1)" bash "$copy/update-pins.sh" --pins-only
  [ "$status" -eq 143 ]
  [ "$(sha256sum "$copy/harnesses/muse/version-muse.env" "$copy/verify-muse.sh" "$copy/docs/architecture.md")" = "$before" ]
  mv "$copy/gen-verify-real.sh" "$copy/gen-verify.sh"
  run env BOX_UPDATE_MUSE_SHA256_AMD64="$(printf '%064d' 1)" bash "$copy/update-pins.sh" --pins-only
  [ "$status" -eq 0 ]
}
