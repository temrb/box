# pins.bats — lib/pins.sh single pin home (Phase 5).
load helpers

@test "pins loader exposes every pin from the bundle" {
  unset project
  box_load_all_pins "$BUNDLE_DIR"
  # Format regexes mirror the strict version parser (lib/preflight.sh) —
  # well-formedness, never bundle literals, so bumps never touch this file.
  # ("Actually reads values" is proven by version.bats synthetic fixtures.)
  [[ "$MUSE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]
  [[ "$MUSE_SHA256_AMD64" =~ ^[0-9a-f]{64}$ ]]
  [[ "$MUSE_SHA256_ARM64" =~ ^[0-9a-f]{64}$ ]]
  [[ "$OPENCODE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "$OPENCODE_SHA256_AMD64" =~ ^[0-9a-f]{64}$ ]]
  [[ "$OPENCODE_SHA256_ARM64" =~ ^[0-9a-f]{64}$ ]]
  # Printer/loader consistency over the registry: every pin prints exactly
  # the loaded global.
  for id in $box_tool_ids; do
    for pin in $(box_tool_field "$id" pin_keys); do
      [ -n "${!pin:-}" ] || { echo "empty pin: $pin"; return 1; }
      [ "$(box_print_pin "$BUNDLE_DIR" "$pin")" = "${!pin:-}" ] \
        || { echo "printer/loader disagree: $pin"; return 1; }
    done
  done
}

@test "pins printer round-trips every pin name" {
  unset project
  for id in $box_tool_ids; do
    for pin in $(box_tool_field "$id" pin_keys); do
      val=$(box_print_pin "$BUNDLE_DIR" "$pin")
      [ -n "$val" ] || { echo "empty pin: $pin"; return 1; }
    done
  done
  [[ "$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]
  [[ "$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "$(box_print_pin "$BUNDLE_DIR" OPENCODE_SHA256_AMD64)" =~ ^[0-9a-f]{64}$ ]]
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
  [[ "$block" == *"$(box_print_pin "$BUNDLE_DIR" CODEX_VERSION)"* ]]
}

@test "shared pin asserts cover no-default ARGs and delegation" {
  run box_assert_no_default_args "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
  run box_assert_build_delegation "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
}

@test "stage pins reject missing ARG, label-only consumption and extra digests" {
  copy="$TEST_TMP/Dockerfile-pins"
  cp "$BUNDLE_DIR/Dockerfile" "$copy"
  sed -i '/^ARG MUSE_VERSION$/d' "$copy"
  run box_assert_stage_pins "$copy"
  [ "$status" -ne 0 ]
  cp "$BUNDLE_DIR/Dockerfile" "$copy"
  python3 - "$copy" <<'PYINNER'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
out = []
for line in p.read_text().splitlines(keepends=True):
    s = line.lstrip()
    if s.startswith("#") or s.startswith("LABEL") or s.startswith("ARG "):
        out.append(line)
    else:
        out.append(line.replace("$MUSE_VERSION", "REMOVED").replace("${MUSE_VERSION", "REMOVED"))
p.write_text("".join(out))
PYINNER
  run box_assert_stage_pins "$copy"
  [ "$status" -ne 0 ]
  cp "$BUNDLE_DIR/Dockerfile" "$copy"
  printf 'FROM debian:trixie-slim@sha256:0000000000000000000000000000000000000000000000000000000000000000 AS extra\n' >>"$copy"
  run box_docker_base_digest "$copy"
  [ "$status" -ne 0 ]
}

@test "dockerfile repeats SHELL per-stage with none before first FROM" {
  run box_assert_shell_placement "$BUNDLE_DIR/Dockerfile"
  [ "$status" -eq 0 ]
}
