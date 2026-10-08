load helpers

@test "disposable storage artifact provenance and exact extraction preserve foreign members" {
  run python3 -I "$BUNDLE_DIR/tests/native/disposable-storage-test.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Ran 4 tests'* ]]
}

@test "disposable native Make target requires an explicit scratch parent" {
  unset BOX_TEST_PROJECT_ROOT
  run make -C "$BUNDLE_DIR" verify-native-auth-disposable
  [ "$status" -ne 0 ]
  [[ "$output" == *'existing private disposable scratch parent'* ]]
}
