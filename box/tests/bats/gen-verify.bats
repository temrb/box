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
      [ -f "$BUNDLE_DIR/verify.d/$sec-$id.sh" ] || { echo "missing partial: $sec-$id.sh"; return 1; }
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
    run grep -E '^[[:space:]]*trap ' -- "$BUNDLE_DIR/verify.d/40-readiness-$id.sh"
    [ "$status" -ne 0 ] || { echo "40-readiness-$id.sh re-arms the EXIT trap"; return 1; }
  done
}
