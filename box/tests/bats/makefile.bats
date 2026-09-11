# makefile.bats — Makefile contract: help/clean/setup targets, install
# removal, single build home (lib/build.sh delegation, no duplicated docker
# blocks or per-var pin parsing in the Makefile).
load helpers

@test "make help lists the main targets" {
  run make -C "$BUNDLE_DIR" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"build"* ]]
  [[ "$output" == *"setup"* ]]
  [[ "$output" == *"test"* ]]
  [[ "$output" == *"pin-check"* ]]
  [[ "$output" == *"pins"* ]]
  [[ "$output" == *"verify-generated"* ]]
  [[ "$output" == *"regen-validation"* ]]
  [[ "$output" == *"update"* ]]
  [[ "$output" == *"clean"* ]]
}

@test "make install is gone (renamed to setup)" {
  run make -C "$BUNDLE_DIR" -n install
  [ "$status" -ne 0 ]
}

@test "make setup dry-prints the installer" {
  run make -C "$BUNDLE_DIR" -n setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup.sh"* ]]
}

@test "build recipes delegate to the single lib/build.sh home (no duplicated docker blocks)" {
  run make -C "$BUNDLE_DIR" -n build-m
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/build.sh"* ]]
  [[ "$output" == *"box-m"* ]]
  run make -C "$BUNDLE_DIR" -n build-o
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/build.sh"* ]]
  [[ "$output" == *"box-o"* ]]
  # Stems resolve end-to-end to registry ids (offline).
  [ "$(box_tool_id_for_launcher box-m)" = "muse" ]
  [ "$(box_tool_id_for_launcher box-o)" = "opencode" ]
  # No duplicated docker build flags in the Makefile itself.
  run grep -F "build --pull" "$BUNDLE_DIR/Makefile"
  [ "$status" -ne 0 ]
}

@test "build and clean loop registry stems and ids (zero per-tool lines)" {
  run make -C "$BUNDLE_DIR" -n build
  [ "$status" -eq 0 ]
  [[ "$output" == *"box-m"* ]]
  [[ "$output" == *"box-o"* ]]
  run make -C "$BUNDLE_DIR" -n clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"--clean"* ]]
  [[ "$output" == *"muse opencode"* ]]
  run make -C "$BUNDLE_DIR" build-bogus
  [ "$status" -ne 0 ]
}

@test "lib/build.sh owns the isolated docker CLI + UID/GID pins + tags" {
  run grep -F "box_docker_cli" "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -eq 0 ]
  run grep -F -- "--build-arg HOST_UID=" "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -eq 0 ]
  run grep -F -- "--build-arg HOST_GID=" "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -eq 0 ]
  run bash "$BUNDLE_DIR/lib/build.sh" --tag muse
  [ "$status" -eq 0 ]
  [[ "$output" == *"-u$(id -u)-g$(id -g)"* ]]
}

@test "make preserves base64 padding in integrity pins (parsed, never cut)" {
  # Regression: `cut -d= -f2` silently dropped trailing `=` padding from
  # sha512 integrity pins, failing the Dockerfile npm-view asserts late.
  # Pins now load once per build inside lib/build.sh via lib/pins.sh (no cut
  # anywhere in the build path).
  expected=$(bash -c 'source "$0/lib/pins.sh" >/dev/null 2>&1 && box_print_pin "$0" OPENCODE_NPM_INTEGRITY' "$BUNDLE_DIR")
  [[ "$expected" == *"==" ]]
  run grep -F -- "$expected" "$BUNDLE_DIR/version-opencode.env"
  [ "$status" -eq 0 ]
  run grep -F "cut -d=" "$BUNDLE_DIR/Makefile"
  [ "$status" -ne 0 ]
  run grep -F "cut -d=" "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -ne 0 ]
}

@test "build home threads node pins and never parses with cut" {
  [[ " $(box_tool_field opencode pin_keys) " == *" NODE_VERSION "* ]]
  [[ " $(box_tool_field opencode pin_keys) " == *" NODESOURCE_FINGERPRINT "* ]]
  run grep -F 'box_tool_field "$tool" pin_keys' "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -eq 0 ]
  run grep -F -- '--build-arg "$pin=' "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -eq 0 ]
  run grep -F "cut -d=" "$BUNDLE_DIR/Makefile"
  [ "$status" -ne 0 ]
}

@test "build CLI fails closed on unknown tool ids" {
  run bash "$BUNDLE_DIR/lib/build.sh" bogus
  [ "$status" -ne 0 ]
  run bash "$BUNDLE_DIR/lib/build.sh" --tag bogus
  [ "$status" -ne 0 ]
  run bash "$BUNDLE_DIR/lib/build.sh" --clean bogus
  [ "$status" -ne 0 ]
  run bash "$BUNDLE_DIR/lib/build.sh" --tag
  [ "$status" -ne 0 ]
}

@test "make pins covers both pin gates over the one invariant" {
  run make -C "$BUNDLE_DIR" -n pins
  [ "$status" -eq 0 ]
  [[ "$output" == *"check-pins.sh"* ]]
  [[ "$output" == *"gen-pins.sh"* ]]
}

@test "regen-validation invokes the launcher via --shell -c (not -- passthrough)" {
  # M-1 pin: `box-o --shell -- opencode debug config` lands as
  # `bash -- opencode debug config` (exit 127: opencode treated as a script
  # file). The only correct shape is `--shell -c 'opencode debug config'`
  # (cf. troubleshooting.md); merely dropping `--` does not fix it.
  # The forbidden-shape grep skips comment lines so the explanatory comment
  # in regen-validation.sh may name the wrong shape.
  run grep -F -- "--shell -c 'opencode debug config'" "$BUNDLE_DIR/regen-validation.sh"
  [ "$status" -eq 0 ]
  run bash -c 'grep -v "^[[:space:]]*#" -- "$1" | grep -Fq -- "--shell -- opencode"' _ "$BUNDLE_DIR/regen-validation.sh"
  [ "$status" -ne 0 ]
}
