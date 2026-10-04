load helpers

@test "interrupt kills and reaps a TERM-resistant client and reports stop failure" {
  run timeout 8 bash -c '
    BOX_TOOL=test
    source "$1/lib/docker.sh"
    docker_cmd=(false)
    container=fixture
    bash -c '\''trap "" TERM; echo ready >"$1"; while :; do sleep 0.1; done'\'' _ "$2" &
    pid=$!
    echo "$pid" >"$3"
    while [[ ! -e $2 ]]; do sleep 0.05; done
    box_interrupt_client TERM 143 "$pid"
  ' _ "$BUNDLE_DIR" "$TEST_TMP/ready" "$TEST_TMP/pid"
  [ "$status" -eq 143 ]
  [[ "$output" == *"could not stop container fixture"* ]]
  ! kill -0 "$(cat "$TEST_TMP/pid")" 2>/dev/null
}
