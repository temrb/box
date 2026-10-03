@test "storage experiment fails on prerequisites and preserves move failure status" {
  run python3 "$BATS_TEST_DIRNAME/../native/resource-audit-test.py" WorkloadTests
  [ "$status" -eq 0 ]
}

@test "storage experiment reaps its client even when Docker cleanup fails" {
  run python3 "$BATS_TEST_DIRNAME/../native/resource-audit-test.py" CleanupTests
  [ "$status" -eq 0 ]
}
