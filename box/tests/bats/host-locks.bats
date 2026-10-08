load helpers

@test "ordered host lock sets contend nonblockingly and preserve stable authority" {
  run python3 -I "$BUNDLE_DIR/tests/native/host-locks-test.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Ran 7 tests'* ]]
}
