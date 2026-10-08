# Synthetic host control-state races and preservation, without Docker/auth.
load helpers

@test "host filesystem primitives preserve foreign files across hostile coordinates and faults" {
  run python3 -I "$BUNDLE_DIR/tests/native/host-fs-test.py"
  [ "$status" -eq 0 ]
}
