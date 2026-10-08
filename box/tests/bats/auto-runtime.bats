# auto-runtime.bats — stubbed unit tests for the probe-gated AUTO runtime
# (box_probe_runsc_dns / box_auto_runtime /
# box_maybe_auto_runtime in lib/launcher.sh). No daemon contact: the
# docker CLI and timeout are stubbed per test, so DNS-healthy, DNS-broken,
# and fail-closed paths all run offline. Live-daemon coverage stays in
# split.bats (skipped without a daemon).
load helpers

# Stub the docker CLI so the probe runs without a daemon.
# _stub_docker <run_rc>: info/image/network inspects succeed; `run` exits
# <run_rc> and records its -c script to $STUB_C_FILE.
_stub_docker() {
  STUB_RUN_RC=$1
  STUB_C_FILE="$TEST_TMP/probe-cmd.txt"
  rm -f -- "$STUB_C_FILE"
  export STUB_RUN_RC STUB_C_FILE
  docker_cmd=(stub_docker)
}
stub_docker() {
  printf '%s\n' "$*" >>"$STUB_C_FILE.args"
  case "${1:-}" in
    info|image|network) return 0 ;;
    run)
      local prev= arg
      for arg in "$@"; do
        if [[ "$prev" == "-c" ]]; then printf '%s' "$arg" >"$STUB_C_FILE"; fi
        if [[ "$prev" == "--cidfile" && "${STUB_NO_CID:-0}" == 0 ]]; then
          printf '%s\n' "${STUB_CID:-$(printf '%064d' 1)}" >"$arg"
        fi
        prev=$arg
      done
      return "$STUB_RUN_RC" ;;
    *) return 0 ;;
  esac
}
# Faithful timeout stub: drop the duration, run the command.
timeout() { [[ "$1" != --kill-after=* ]] || shift; shift; "$@"; }

@test "probe bounds resources and removes only its recorded container after timeout" {
  _stub_docker 124
  run box_probe_runsc_dns some-image:0 some-net example.com
  [ "$status" -eq 124 ]
  calls=$(cat "$STUB_C_FILE.args")
  [[ "$calls" == *"--memory=$BOX_CONTAINER_MEMORY --memory-swap=$BOX_CONTAINER_MEMORY"* ]]
  [[ "$calls" == *"--cpus=$BOX_CONTAINER_CPUS --pids-limit=$BOX_CONTAINER_PIDS"* ]]
  [[ "$calls" == *"rm -f -- $(printf '%064d' 1)"* ]]
}

@test "probe cancellation never selects fallback" {
  _stub_docker 143
  run box_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK 'this run' example.com
  [ "$status" -eq 143 ]
  [[ "$output" != *auto-selecting* ]]
}

@test "probe startup failure without an ID never removes another container" {
  _stub_docker 125
  STUB_NO_CID=1
  run box_probe_runsc_dns some-image:0 some-net example.com
  [ "$status" -eq 125 ]
  [[ "$(cat "$STUB_C_FILE.args")" != *"rm -f"* ]]
}

@test "probe refuses malformed cleanup IDs" {
  _stub_docker 124
  STUB_CID=unrelated-container
  run box_probe_runsc_dns some-image:0 some-net example.com
  [ "$status" -eq 124 ]
  [[ "$(cat "$STUB_C_FILE.args")" != *"rm -f"* ]]
}

@test "probe restores caller signal traps after completion" {
  _stub_docker 0
  trap ':' TERM HUP
  before=$(trap -p TERM HUP)
  box_probe_runsc_dns some-image:0 some-net example.com
  [ "$(trap -p TERM HUP)" = "$before" ]
  trap - TERM HUP
}

@test "probe passes explicit hosts to the container shell" {
  _stub_docker 0
  run box_probe_runsc_dns some-image:0 some-net foo.example.com bar.example.com
  [ "$status" -eq 0 ]
  [[ "$(cat -- "$STUB_C_FILE")" == *"getent hosts foo.example.com"* ]]
  [[ "$(cat -- "$STUB_C_FILE")" == *"getent hosts bar.example.com"* ]]
}

@test "probe fails closed without hosts (launchers pass registry probe_hosts)" {
  _stub_docker 0
  run box_probe_runsc_dns some-image:0 some-net
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing DNS probe hosts"* ]]
  [ ! -e "$STUB_C_FILE" ]
}

@test "probe rejects a hostile host instead of injecting it" {
  _stub_docker 0
  run box_probe_runsc_dns some-image:0 some-net 'evil.example.com;id'
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid DNS probe host"* ]]
  [ ! -e "$STUB_C_FILE" ]
}

@test "auto-runtime stays on runsc when DNS is healthy" {
  _stub_docker 0
  runtime_args=(--runtime=runsc)
  fallback_requested=0
  explicit_runsc=0
  box_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK 'this run' host.example.com >"$TEST_TMP/out.txt" 2>&1
  [ "$?" -eq 0 ]
  [ ! -s "$TEST_TMP/out.txt" ]
  [ "${runtime_args[*]}" = "--runtime=runsc" ]
  [ "$fallback_requested" -eq 0 ]
}







@test "auto-runtime honors explicit --runsc without probing" {
  _stub_docker 1
  runtime_args=(--runtime=runsc)
  fallback_requested=0
  explicit_runsc=1
  box_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK 'this run' >"$TEST_TMP/out.txt" 2>&1
  [ "$?" -eq 0 ]
  [ ! -s "$TEST_TMP/out.txt" ]
  [ ! -e "$STUB_C_FILE" ]
  [ "${runtime_args[*]}" = "--runtime=runsc" ]
}

@test "maybe-gate skips the probe under dry-run, fallback, shell, and runsc" {
  _stub_docker 1
  local guard
  for guard in dry_run fallback_requested shell_mode explicit_runsc; do
    dry_run=0; fallback_requested=0; shell_mode=0; explicit_runsc=0
    printf -v "$guard" 1
    runtime_args=(--runtime=runsc)
    box_maybe_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK 'this run' >"$TEST_TMP/out.txt" 2>&1
    [ "$?" -eq 0 ]
    [ ! -s "$TEST_TMP/out.txt" ]
    [ ! -e "$STUB_C_FILE" ]
    [ "${runtime_args[*]}" = "--runtime=runsc" ]
  done
}



@test "probe fails closed with remediation when the daemon is unavailable" {
  stub_fail_info() { case "${1:-}" in info) return 1 ;; *) return 0 ;; esac; }
  docker_cmd=(stub_fail_info)
  run box_probe_runsc_dns some-image:0 some-net example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"Local Docker Engine is unavailable"* ]]
}

@test "probe fails closed with remediation when the image is missing" {
  stub_fail_image() { case "${1:-}" in image) return 1 ;; *) return 0 ;; esac; }
  docker_cmd=(stub_fail_image)
  run box_probe_runsc_dns some-image:0 some-net example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"build it first"* ]]
}

@test "probe fails closed with remediation when the network is missing" {
  stub_fail_network() { case "${1:-}" in network) return 1 ;; *) return 0 ;; esac; }
  docker_cmd=(stub_fail_network)
  run box_probe_runsc_dns some-image:0 some-net example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"Create the dedicated network"* ]]
}

@test "classifier maps 1 and 2 to dns" {
  [ "$(box_classify_probe_rc 1)" = "dns" ]
  [ "$(box_classify_probe_rc 2)" = "dns" ]
}

@test "classifier maps 0, 124, 125, and other codes to startup" {
  # 0 documents "never passed on the success path": the success path returns
  # before classification, so 0 mapping to startup is unreachable by design.
  [ "$(box_classify_probe_rc 0)" = "startup" ]
  [ "$(box_classify_probe_rc 124)" = "startup" ]
  [ "$(box_classify_probe_rc 125)" = "startup" ]
  [ "$(box_classify_probe_rc 3)" = "startup" ]
  run box_classify_probe_rc
  [ "$status" -eq 0 ]
  [ "$output" = "startup" ]
}

@test "probe returns the raw container rc for classification" {
  _stub_docker 125
  run box_probe_runsc_dns some-image:0 some-net host.example.com
  [ "$status" -eq 125 ]
  _stub_docker 124
  run box_probe_runsc_dns some-image:0 some-net host.example.com
  [ "$status" -eq 124 ]
  _stub_docker 2
  run box_probe_runsc_dns some-image:0 some-net host.example.com
  [ "$status" -eq 2 ]
}







@test "auto-runtime kill-switch on rc=125 dies with startup remediation" {
  _stub_docker 125
  TEST_BOX_ALLOW_FALLBACK=0
  export TEST_BOX_ALLOW_FALLBACK
  run box_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK 'this run' host.example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to start or complete probe containers (exit 125)"* ]]
  [[ "$output" == *"fallback disabled via TEST_BOX_ALLOW_FALLBACK=0"* ]]
  [[ "$output" == *"runsc --version"* ]]
}



@test "default probe failure never selects runc for DNS startup timeout or signals" {
  local rc
  for rc in 1 2 3 124 125 129 130 137 143; do
    _stub_docker "$rc"
    runtime_args=(--runtime=runsc)
    fallback_requested=0
    explicit_runsc=0
    run box_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK 'this run' host.example.com
    [ "$status" -ne 0 ]
    [[ "$output" != *auto-selecting* ]]
    [[ "$(cat "$STUB_C_FILE.args")" != *--runtime=runc* ]]
    [ "$fallback_requested" -eq 0 ]
    [ "${runtime_args[*]}" = --runtime=runsc ]
  done
}

@test "default gate refuses DNS failure with explicit fallback remediation" {
  _stub_docker 1
  dry_run=0; fallback_requested=0; shell_mode=0; explicit_runsc=0
  run box_maybe_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK 'this run' host.example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *'refusing to start this run'* ]]
  [[ "$output" == *'explicitly select --docker-fallback'* ]]
}

@test "default runtime preserves login diagnostic context" {
  _stub_docker 1
  explicit_runsc=0
  run box_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK '' host.example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *'refusing to start `login`'* ]]
}

@test "offline diagnostics skip default DNS health checks" {
  _stub_docker 1
  dry_run=0; fallback_requested=0; shell_mode=0; explicit_runsc=0
  local network_required=0
  box_maybe_auto_runtime some-image:0 some-net TEST_BOX_ALLOW_FALLBACK 'this run' host.example.com
  [ ! -e "$STUB_C_FILE" ]
}

@test "launch tail classifies informational logout and login status commands as offline" {
  dry_run=1; fallback_requested=0; shell_mode=0; explicit_runsc=0
  runtime_args=(--runtime=runsc)
  image=fixture; tool_network=fixture; container=fixture
  identity_name=Test; identity_email=test@example.com
  local -a fixture_mounts=()
  fixture_tail() { args+=("$image" "$@"); }
  box_docker_exec() { return 0; }
  box_maybe_auto_runtime() { [ "$network_required" -eq "$expected_network" ]; }
  local command expected_network=0
  for command in --help --version help version logout status; do
    box_launch_epilogue codex 'this run' org.box.test fixture_mounts '' fixture_tail "$command"
  done
  box_launch_epilogue codex 'this run' org.box.test fixture_mounts '' fixture_tail login status
  expected_network=1
  box_launch_epilogue codex 'this run' org.box.test fixture_mounts '' fixture_tail login --device-auth
}

@test "invalid fallback selectors refuse before project preflight even when runsc is selected" {
  fallback_requested=0
  for value in '' invalid; do
    TEST_BOX_ALLOW_FALLBACK="$value" run box_check_fallback TEST_BOX_ALLOW_FALLBACK
    [ "$status" -ne 0 ]
  done
  box_project_identity() { printf 'project reached'; return 1; }
  BOX_C_ALLOW_FALLBACK=broken run box_launch_prologue muse
  [ "$status" -ne 0 ]
  [[ "$output" == *"BOX_C_ALLOW_FALLBACK must be 0 or 1"* ]]
  [[ "$output" != *"project reached"* ]]
}
