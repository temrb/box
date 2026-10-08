# Additive schema-2 primitives; synthetic fixtures do not qualify native cutover.
load helpers

@test "host-only auth store refuses competing authority and recovers durable SIGKILL boundaries" {
  run python3 -I "$BUNDLE_DIR/tests/native/auth-store-test.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Ran 14 tests'* ]]
}
