# gen-verify.bats — Phase 4 generator: verify-*.sh == verify.d/ output.
# Expectations derive from the registry (3 shared + 5 per-tool sections),
# so new tools are covered without a test edit.
load helpers

@test "verify.d partials exist for every section" {
  for f in 10-workspace.sh 20-toolchain.sh 50-containment.sh; do
    [ -f "$BUNDLE_DIR/verify.d/$f" ] || { echo "missing partial: $f"; return 1; }
  done
  for id in $box_tool_ids; do
    for sec in 00-header 30-network 40-readiness 60-probe 99-footer; do
      [ -f "$BUNDLE_DIR/harnesses/$id/verify.d/$sec-$id.sh" ] || { echo "missing partial: $sec-$id.sh"; return 1; }
    done
  done
}

@test "generated harnesses match the checked-in files" {
  run bash "$BUNDLE_DIR/gen-verify.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "generated harnesses stay stdin-deliverable (no sourcing)" {
  for id in $box_tool_ids; do
    run grep -E "^[[:space:]]*(source|\.)[[:space:]]+" "$BUNDLE_DIR/verify-$id.sh"
    [ "$status" -ne 0 ] || { echo "verify-$id.sh sources code"; return 1; }
  done
}

@test "project command runs after containment gates (not in toolchain section)" {
  run grep -n 'bash -c "\$2"' "$BUNDLE_DIR/verify.d/20-toolchain.sh"
  [ "$status" -ne 0 ]
  run grep -n 'bash -c "\$2"' "$BUNDLE_DIR/verify.d/50-containment.sh"
  [ "$status" -eq 0 ]
}

@test "verify harness has one EXIT cleanup in the header (no re-arm chain)" {
  for id in $box_tool_ids; do
    count=$(grep -c '^[[:space:]]*trap box_cleanup EXIT' -- "$BUNDLE_DIR/verify-$id.sh")
    [ "$count" -eq 1 ] || { echo "verify-$id.sh: want 1 header trap, found $count"; return 1; }
    count=$(grep -c '^[[:space:]]*trap ' -- "$BUNDLE_DIR/verify-$id.sh")
    [ "$count" -eq 1 ] || { echo "verify-$id.sh: want exactly 1 trap line, found $count"; return 1; }
  done
  for f in 10-workspace.sh 20-toolchain.sh; do
    run grep -E '^[[:space:]]*trap ' -- "$BUNDLE_DIR/verify.d/$f"
    [ "$status" -ne 0 ] || { echo "$f re-arms the EXIT trap"; return 1; }
  done
  for id in $box_tool_ids; do
    run grep -E '^[[:space:]]*trap ' -- "$BUNDLE_DIR/harnesses/$id/verify.d/40-readiness-$id.sh"
    [ "$status" -ne 0 ] || { echo "40-readiness-$id.sh re-arms the EXIT trap"; return 1; }
  done
}

@test "generated harnesses keep section markers in ascending order" {
  for id in $box_tool_ids; do
    prev=0
    for sec in 1 2 3 4 5; do
      line=$(grep -n -m1 "=== $sec\." -- "$BUNDLE_DIR/verify-$id.sh" | cut -d: -f1)
      [ -n "$line" ] || { echo "verify-$id.sh: missing === $sec. marker"; return 1; }
      [ "$line" -gt "$prev" ] \
        || { echo "verify-$id.sh: === $sec. out of order (line $line after $prev)"; return 1; }
      prev=$line
    done
  done
}

@test "containment gates fail closed for root without a daemon (offline stubs)" {
  run bash -c '
    box_warnings=0
    id() { printf "0\n"; }
    uname() { printf "stub-kernel\n"; }
    capsh() { printf "Current: =\n"; }
    timeout() { shift; "$@"; }
    docker() { printf "stub docker must not run\n" >&2; return 125; }
    source "$1/verify.d/50-containment.sh"
  ' _ "$BUNDLE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: running as root"* ]]
}

@test "containment gates fail closed without capsh (offline stubs)" {
  run bash -c '
    box_warnings=0
    id() { printf "1000\n"; }
    uname() { printf "stub-kernel\n"; }
    timeout() { shift; "$@"; }
    docker() { printf "stub docker must not run\n" >&2; return 125; }
    command() {
      if [[ "${1:-}" == "-v" && "${2:-}" == capsh ]]; then return 1; fi
      builtin command "$@"
    }
    source "$1/verify.d/50-containment.sh"
  ' _ "$BUNDLE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: capsh not on PATH"* ]]
}

@test "toolchain section passes offline with stubbed discovery tools" {
  run bash -c '
    box_warnings=0
    git() { return 0; }
    rg() { return 0; }
    fd() { return 0; }
    find() { return 0; }
    cc() {
      local out="" prev="" a
      for a in "$@"; do
        if [[ "$prev" == "-o" ]]; then out="$a"; fi
        prev="$a"
      done
      printf "#!/bin/bash\necho \"C build/run: PASS\"\n" >"$out"
      chmod +x "$out"
    }
    source "$1/verify.d/20-toolchain.sh"
  ' _ "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Discovery & Git tools: PASS"* ]]
  [[ "$output" == *"C build/run: PASS"* ]]
}

@test "every registry config is validated (CONFIG_FILES parity)" {
  run make -C "$BUNDLE_DIR" -n verify-config
  [ "$status" -eq 0 ]
  for src in $(box_config_sources); do
    [[ "$output" == *"$src"* ]] \
      || { echo "$src missing from verify-config"; return 1; }
  done
}

@test "verify-config fails on a malformed registry config (bundle copy)" {
  command -v python3 >/dev/null || skip "no python3 (TOML validation needs 3.11+ tomllib)"
  command -v jq >/dev/null || skip "no jq (JSON validation needs jq)"
  copy="$TEST_TMP/bundle-malformed"
  rm -rf -- "$copy"
  cp -r -- "$BUNDLE_DIR" "$copy"
  chmod -R u+w -- "$copy"
  printf '{not valid json' >>"$copy/harnesses/muse/config/settings.json"
  run make -C "$copy" verify-config
  [ "$status" -ne 0 ]
  [[ "$output" == *"settings.json"* ]]
}

@test "partials carry tokens, generated harnesses carry resolved versions" {
  unset project
  for id in $box_tool_ids; do
    vkey=$(box_tool_field "$id" pin_keys); vkey=${vkey%% *}
    ver=$(box_print_pin "$BUNDLE_DIR" "$vkey")
    [ -n "$ver" ]
    run grep -Fq -- "@@${vkey}@@" "$BUNDLE_DIR/harnesses/$id/verify.d/40-readiness-$id.sh"
    [ "$status" -eq 0 ] || { echo "partial misses @@${vkey}@@ token"; return 1; }
    run grep -Fq -- "$ver" "$BUNDLE_DIR/harnesses/$id/verify.d/40-readiness-$id.sh"
    [ "$status" -ne 0 ] || { echo "partial leaks resolved version $ver"; return 1; }
    run grep -Fq -- "$ver" "$BUNDLE_DIR/verify-$id.sh"
    [ "$status" -eq 0 ] || { echo "generated verify-$id.sh misses $ver"; return 1; }
    run grep -Eq '@@[A-Z_]+@@' "$BUNDLE_DIR/verify-$id.sh"
    [ "$status" -ne 0 ] || { echo "generated verify-$id.sh leaks a token"; return 1; }
  done
}

@test "containment-only generation resolves headers without native readiness or network gates" {
  for id in $box_tool_ids; do
    run bash -p "$BUNDLE_DIR/gen-verify.sh" --containment "$id"
    [ "$status" -eq 0 ]
    [[ "$output" != *'@@'* ]]
    [[ "$output" == *'=== 1.'*'=== 2.'*'=== 5.'* ]]
    [[ "$output" != *'=== 3.'* && "$output" != *'=== 4.'* ]]
    printf '%s\n' "$output" > "$TEST_TMP/containment.sh"
    bash -n "$TEST_TMP/containment.sh"
    run bash -c 'id() { echo 0; }; source "$1"' _ "$TEST_TMP/containment.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *'FAIL: running as root'* ]]
    [[ "$output" != *'command not found'* ]]
  done
  run bash -p "$BUNDLE_DIR/gen-verify.sh" --containment unknown
  [ "$status" -ne 0 ]
  run bash -p "$BUNDLE_DIR/gen-verify.sh" --containment muse --extra
  [ "$status" -ne 0 ]
}
