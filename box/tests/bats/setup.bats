# setup.bats — setup.sh CLI contract (parse-only paths; full installer runs
# need a daemon and live in manual validation, not here).
load helpers

@test "setup.sh --help lists the registry flags and ids" {
  run bash "$BUNDLE_DIR/setup.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--only <id>"* ]]
  [[ "$output" == *"--default <id>"* ]]
  [[ "$output" == *"Known tool ids: $box_tool_ids"* ]]
}

@test "setup.sh old per-tool flags fail with a migration hint" {
  run bash "$BUNDLE_DIR/setup.sh" --only-m
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --only <id>"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --only-o
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --only <id>"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --default-muse
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --default <id>"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --default-opencode
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --default <id>"* ]]
}

@test "setup.sh rejects unknown tool ids and missing values" {
  run bash "$BUNDLE_DIR/setup.sh" --only bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool id"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --default bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool id"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --only
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a tool id"* ]]
  run bash "$BUNDLE_DIR/setup.sh" --default
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a tool id"* ]]
}

@test "setup.sh still rejects unknown flags and positionals" {
  run bash "$BUNDLE_DIR/setup.sh" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
  run bash "$BUNDLE_DIR/setup.sh" some-positional
  [ "$status" -ne 0 ]
  [[ "$output" == *"no positional arguments"* ]]
}
