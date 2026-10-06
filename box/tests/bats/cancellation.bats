load helpers

# Matrix for box_interrupt_client (lib/docker.sh): kill -s <signal>, bounded
# `docker stop`, TERM grace then KILL via box_terminate_client, exit <status>.
# docker_cmd doubles are external binaries (true/false) because the real
# `timeout` cannot invoke shell functions. No daemon contact in any test.

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

@test "interrupt with a clean stop stays silent and still reaps the client" {
  run timeout 8 bash -c '
    BOX_TOOL=test
    source "$1/lib/docker.sh"
    docker_cmd=(true)
    container=fixture
    bash -c '\''trap "" TERM; echo ready >"$1"; while :; do sleep 0.1; done'\'' _ "$2" &
    pid=$!
    echo "$pid" >"$3"
    while [[ ! -e $2 ]]; do sleep 0.05; done
    box_interrupt_client TERM 143 "$pid"
  ' _ "$BUNDLE_DIR" "$TEST_TMP/ready-ok" "$TEST_TMP/pid-ok"
  [ "$status" -eq 143 ]
  [[ "$output" != *"could not stop container"* ]]
  ! kill -0 "$(cat "$TEST_TMP/pid-ok")" 2>/dev/null
}

@test "interrupt on an already-dead client still exits with the signal status" {
  run timeout 8 bash -c '
    BOX_TOOL=test
    source "$1/lib/docker.sh"
    docker_cmd=(true)
    container=fixture
    sleep 0.01 &
    pid=$!
    echo "$pid" >"$2"
    wait "$pid"
    box_interrupt_client TERM 143 "$pid"
  ' _ "$BUNDLE_DIR" "$TEST_TMP/pid-dead"
  [ "$status" -eq 143 ]
  [[ "$output" != *"could not stop container"* ]]
  ! kill -0 "$(cat "$TEST_TMP/pid-dead")" 2>/dev/null
}

@test "interrupt delivers INT/HUP and maps them to 130/129" {
  for sigspec in "INT 130" "HUP 129"; do
    # shellcheck disable=SC2086 # intentional spec split
    set -- $sigspec
    run timeout 12 bash -c '
      # Monitor mode: async children of a non-interactive shell ignore SIGINT
      # on entry (untrappable), so INT delivery needs job control. The client
      # records the signal but ignores TERM, proving delivery before the
      # TERM-grace/KILL reap below.
      set -m
      BOX_TOOL=test
      source "$1/lib/docker.sh"
      docker_cmd=(true)
      container=fixture
      bash -c '\''trap "echo received >$2" $1; trap "" TERM; echo armed >$2; while :; do sleep 0.1; done'\'' _ "$2" "$4" &
      pid=$!
      echo "$pid" >"$3"
      while [[ ! -e $4 ]]; do sleep 0.05; done
      box_interrupt_client "$2" "$5" "$pid"
    ' _ "$BUNDLE_DIR" "$1" "$TEST_TMP/pid-$1" "$TEST_TMP/sig-$1" "$2"
    [ "$status" -eq "$2" ] || { echo "$1: want status $2, got $status"; return 1; }
    [ "$(cat "$TEST_TMP/sig-$1")" = received ] || { echo "$1: signal not delivered"; return 1; }
    ! kill -0 "$(cat "$TEST_TMP/pid-$1")" 2>/dev/null || { echo "$1: client not reaped"; return 1; }
  done
}
