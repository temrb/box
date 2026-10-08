# test-state.bats — Phase-S disposable test namespace (specs/plan.md §0 B0).
# Fail-closed resolver, bind-root, and cleanup guards. Naming validation is
# pure: no Docker contact, no namespace creation, no locks, no auth reads.
load helpers

_clear_test_ns() {
  unset BOX_TEST_STATE_NS BOX_TEST_TASK_ROOT BOX_TEST_REAL_HOME
  unset BOX_C_STATE_ROOT BOX_C_STATE_DIR BOX_M_PERSIST_DIR
}

_fake_docker() {
  # Prove naming/namespace validation never shells out to Docker: any
  # contact writes the sentinel and fails.
  DOCKER_SENTINEL="$TEST_TMP/docker-touched"
  rm -f -- "$DOCKER_SENTINEL"
  docker() { printf 'contact\n' >>"$DOCKER_SENTINEL"; return 99; }
  export -f docker
  mkdir -p "$TEST_TMP/fakebin"
  printf '#!/bin/bash\nprintf "contact\\n" >>"%s"\nexit 99\n' "$DOCKER_SENTINEL" >"$TEST_TMP/fakebin/docker"
  chmod +x "$TEST_TMP/fakebin/docker"
  PATH="$TEST_TMP/fakebin:$PATH"
}

_assert_no_docker() {
  [ ! -e "$DOCKER_SENTINEL" ]
}

@test "resolver maps every harness to exact test volumes, never production names" {
  _clear_test_ns
  _fake_docker
  ns=t-abcdef123456
  [ "$(box_test_volume muse "$ns" 1000 100)" = "box-test-t-abcdef123456-box-m-u1000-g100" ]
  [ "$(box_test_volume opencode "$ns" 1000 100)" = "box-test-t-abcdef123456-box-o-v2-u1000-g100" ]
  [ "$(box_test_volume codex "$ns" 1000 100)" = "box-test-t-abcdef123456-box-c-u1000-g100" ]
  run box_test_volume bogus "$ns" 1000 100
  [ "$status" -ne 0 ]
  # Zero UID/GID (including zero-padded) never yields a test identity.
  for zero in 0 00 000; do
    run box_test_volume muse "$ns" "$zero" 100
    [ "$status" -ne 0 ]
    run box_test_volume muse "$ns" 1000 "$zero"
    [ "$status" -ne 0 ]
  done
  _assert_no_docker
}

@test "missing namespace fails closed, never falls back" {
  _clear_test_ns
  _fake_docker
  run box_test_validate_ns
  [ "$status" -ne 0 ]
  [[ "$output" == *'BOX_TEST_STATE_NS is required'* ]]
  run box_test_volume muse '' 1000 100
  [ "$status" -ne 0 ]
  export BOX_TEST_STATE_NS=t-abcdef123456
  run box_test_volume muse '' 1000 100
  [ "$status" -ne 0 ]
  _assert_no_docker
}

@test "malformed namespaces fail closed" {
  _clear_test_ns
  _fake_docker
  for bad in '../x' '' 'ABC' 'Upper-Case' 'has space' 'a/b' '.' '..' 't-TOOLONG-0123456789abcdefABCDEF0123456789' '-leading-dash'; do
    run box_test_validate_ns "$bad"
    [ "$status" -ne 0 ] || { echo "accepted bad ns: $bad"; return 1; }
  done
  # 33 chars is overlong (max 32).
  run box_test_validate_ns 't-0000000000000000000000000000000'
  [ "$status" -ne 0 ]
  # 32 chars is the boundary and passes.
  run box_test_validate_ns 't-000000000000000000000000000000'
  [ "$status" -eq 0 ]
  _assert_no_docker
}

@test "partial test setup fails closed in both directions" {
  _clear_test_ns
  _fake_docker
  export BOX_TEST_STATE_NS=t-abcdef123456
  unset BOX_TEST_TASK_ROOT
  run box_test_require_vars
  [ "$status" -ne 0 ]
  [[ "$output" == *'BOX_TEST_TASK_ROOT is required'* ]]
  unset BOX_TEST_STATE_NS
  export BOX_TEST_TASK_ROOT="$TEST_TMP"
  run box_test_require_vars
  [ "$status" -ne 0 ]
  export BOX_TEST_STATE_NS='../evil'
  run box_test_require_vars
  [ "$status" -ne 0 ]
  export BOX_TEST_STATE_NS=t-abcdef123456
  export BOX_TEST_TASK_ROOT="$TEST_TMP/definitely-missing"
  run box_test_require_vars
  [ "$status" -ne 0 ]
  _assert_no_docker
}

@test "test mode engages only when test vars are set" {
  _clear_test_ns
  run box_test_in_test_mode
  [ "$status" -ne 0 ]
  export BOX_TEST_STATE_NS=t-abcdef123456
  run box_test_in_test_mode
  [ "$status" -eq 0 ]
  unset BOX_TEST_STATE_NS
  export BOX_TEST_TASK_ROOT="$TEST_TMP"
  run box_test_in_test_mode
  [ "$status" -eq 0 ]
}

@test "fresh namespaces are short, valid, and capture-safe" {
  _clear_test_ns
  _fake_docker
  ns=$(box_test_new_ns 0123456789ab)
  [ "$ns" = t-0123456789ab ]
  run box_test_validate_ns "$ns"
  [ "$status" -eq 0 ]
  ns=$(box_test_new_ns)
  [[ "$ns" =~ ^t-[0-9a-f]{12}$ ]]
  ((${#ns} <= 19)) || { echo "run ns too long for capture derivation"; return 1; }
  run box_test_new_ns 'not-hex'
  [ "$status" -ne 0 ]
  _assert_no_docker
}

@test "capture sub-namespaces derive through the same resolver" {
  _clear_test_ns
  _fake_docker
  [ "$(box_test_capture_ns t-abcdef123456 deadbeef)" = t-abcdef123456-cap-deadbeef ]
  sub=$(box_test_capture_ns t-abcdef123456)
  [[ "$sub" =~ ^t-abcdef123456-cap-[0-9a-f]{8}$ ]]
  run box_test_validate_ns "$sub"
  [ "$status" -eq 0 ]
  # A 20-char parent cannot fit <parent>-cap-<8hex> in 32 chars.
  run box_test_capture_ns t-012345678901234567
  [ "$status" -ne 0 ]
  run box_test_capture_ns '../evil' deadbeef
  [ "$status" -ne 0 ]
  run box_test_capture_ns t-abcdef123456 'not-hex!'
  [ "$status" -ne 0 ]
  _assert_no_docker
}

@test "cleanup guard authorizes only the exact owned identity" {
  _clear_test_ns
  _fake_docker
  ns=t-abcdef123456
  other=t-654321fedcba
  vol="box-test-$ns-box-o-v2-u1000-g100"
  run box_test_guard_cleanup "$vol" opencode "$ns" 1000 100
  [ "$status" -eq 0 ]
  # Production globals are never valid cleanup targets.
  for prod in box-c-u1000-g100 box-o-v2-u1000-g100 box-o-v2-u1000-g100-0123456789abcdefghij box-m-u1000-g100-0123456789abcdefghij; do
    run box_test_guard_cleanup "$prod" opencode "$ns" 1000 100
    [ "$status" -ne 0 ] || { echo "authorized production-shaped: $prod"; return 1; }
  done
  # Foreign coordinates all fail: wrong namespace, harness, uid, gid.
  run box_test_guard_cleanup "$vol" opencode "$other" 1000 100
  [ "$status" -ne 0 ]
  run box_test_guard_cleanup "$vol" codex "$ns" 1000 100
  [ "$status" -ne 0 ]
  run box_test_guard_cleanup "$vol" opencode "$ns" 1001 100
  [ "$status" -ne 0 ]
  run box_test_guard_cleanup "$vol" opencode "$ns" 1000 101
  [ "$status" -ne 0 ]
  run box_test_guard_cleanup '' opencode "$ns" 1000 100
  [ "$status" -ne 0 ]
  run box_test_guard_cleanup "$vol" opencode "$ns" 1000
  [ "$status" -ne 0 ]
  # A capture sub-namespace volume is authorized only by its own
  # coordinates, never by the parent (parent-NS globbing is forbidden).
  cap="box-test-$ns-cap-deadbeef-box-o-v2-u1000-g100"
  run box_test_guard_cleanup "$cap" opencode "$ns" 1000 100
  [ "$status" -ne 0 ]
  run box_test_guard_cleanup "$cap" opencode "$ns-cap-deadbeef" 1000 100
  [ "$status" -eq 0 ]
  _assert_no_docker
}

@test "bind-root guard keeps test roots under the task root and off production" {
  _clear_test_ns
  _fake_docker
  task="$TEST_TMP/taskroot"
  mkdir -p "$task/t-abcdef123456"
  fakehome="$TEST_TMP/fakehome"
  mkdir -p "$fakehome"
  export BOX_TEST_TASK_ROOT="$task" BOX_TEST_REAL_HOME="$fakehome"
  run box_test_guard_bind_root "$task/t-abcdef123456/codex-home"
  [ "$status" -eq 0 ]
  # Outside the task root fails.
  run box_test_guard_bind_root "$TEST_PROJ/stray"
  [ "$status" -ne 0 ]
  # Production defaults fail even when faked under the task root check.
  run box_test_guard_bind_root "$fakehome/.config/box-c/projects"
  [ "$status" -ne 0 ]
  run box_test_guard_bind_root "$fakehome/.config/box-c/global/codex-home"
  [ "$status" -ne 0 ]
  run box_test_guard_bind_root "$fakehome/.config/box-m/muse-config"
  [ "$status" -ne 0 ]
  # A task root inside a production tree fails closed too.
  export BOX_TEST_TASK_ROOT="$fakehome/.config/box-c/projects/nested-task"
  mkdir -p "$BOX_TEST_TASK_ROOT/t-abcdef123456"
  run box_test_guard_bind_root "$BOX_TEST_TASK_ROOT/t-abcdef123456/codex-home"
  [ "$status" -ne 0 ]
  _assert_no_docker
}

@test "state overrides must live under the task root in test runs" {
  _clear_test_ns
  _fake_docker
  task="$TEST_TMP/taskroot"
  mkdir -p "$task"
  export BOX_TEST_TASK_ROOT="$task" BOX_TEST_STATE_NS=t-abcdef123456
  run box_test_state_overrides_location_check
  [ "$status" -eq 0 ]
  # A leftover production Codex root fails closed.
  export BOX_C_STATE_ROOT="$TEST_TMP/production-root"
  run box_test_state_overrides_location_check
  [ "$status" -ne 0 ]
  # The sanctioned test root (inside the task root) passes.
  export BOX_C_STATE_ROOT="$task/t-abcdef123456"
  run box_test_state_overrides_location_check
  [ "$status" -eq 0 ]
  # A leftover production Muse persist dir fails closed.
  export BOX_M_PERSIST_DIR="$TEST_TMP/muse-prod"
  run box_test_state_overrides_location_check
  [ "$status" -ne 0 ]
  _assert_no_docker
}

@test "project identity uses test volumes in test mode and keeps the hash" {
  _clear_test_ns
  _fake_docker
  task="$TEST_TMP/taskroot"
  mkdir -p "$task"
  export BOX_TEST_TASK_ROOT="$task" BOX_TEST_STATE_NS=t-abcdef123456
  box_preflight_project() { :; }
  cd "$TEST_PROJ"
  box_project_identity box-o-v2
  [ "$volume" = "box-test-t-abcdef123456-box-o-v2-u${host_uid}-g${host_gid}" ]
  [[ "$project_hash" =~ ^[0-9a-f]{20}$ ]]
  # Partial setup fails closed instead of silently using production names.
  unset BOX_TEST_TASK_ROOT
  run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; source "$1/lib/launcher.sh"; box_preflight_project() { :; }; cd "$2" && box_project_identity box-o-v2' _ "$BUNDLE_DIR" "$TEST_PROJ"
  [ "$status" -ne 0 ]
  _assert_no_docker
}

@test "prefix reverse lookup stays registry-driven" {
  _clear_test_ns
  [ "$(box_test_id_for_prefix box-m)" = muse ]
  [ "$(box_test_id_for_prefix box-o-v2)" = opencode ]
  [ "$(box_test_id_for_prefix box-c)" = codex ]
  run box_test_id_for_prefix box-bogus
  [ "$status" -ne 0 ]
  run box_test_id_for_prefix ''
  [ "$status" -ne 0 ]
}

@test "test bind roots and overrides cannot escape through symlinks" {
  _clear_test_ns
  _fake_docker
  task="$TEST_TMP/taskroot"
  outside="$TEST_TMP/outside"
  mkdir -p "$task" "$outside"
  ln -s "$outside" "$task/escape"
  export BOX_TEST_TASK_ROOT="$task" BOX_TEST_REAL_HOME="$TEST_TMP/realhome"
  run box_test_guard_bind_root "$task/escape/codex-home"
  [ "$status" -ne 0 ]
  export BOX_C_STATE_ROOT="$task/escape"
  run box_test_state_overrides_location_check
  [ "$status" -ne 0 ]
  _assert_no_docker
}

@test "test volume resolver refuses unsafe registry prefixes" {
  _clear_test_ns
  box_tool_field() { printf '../invalid'; }
  run box_test_volume codex t-abcdef123456 1000 100
  [ "$status" -ne 0 ]
}

@test "bind guard accepts disposable Codex override while rejecting production aliases" {
  _clear_test_ns
  _fake_docker
  export BOX_TEST_TASK_ROOT="$TEST_TMP/task" BOX_TEST_REAL_HOME="$TEST_HOME"
  export BOX_C_STATE_ROOT="$BOX_TEST_TASK_ROOT/t-abcdef123456"
  mkdir -p "$BOX_C_STATE_ROOT"
  run box_test_guard_bind_root "$BOX_C_STATE_ROOT/codex-home"
  [ "$status" -eq 0 ]
  export BOX_TEST_TASK_ROOT="$TEST_HOME/.config/box-c/projects/task"
  export BOX_C_STATE_ROOT="$BOX_TEST_TASK_ROOT/t-abcdef123456"
  run box_test_guard_bind_root "$BOX_C_STATE_ROOT/codex-home"
  [ "$status" -ne 0 ]
  _assert_no_docker
}
