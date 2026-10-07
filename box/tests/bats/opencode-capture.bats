load helpers

prepare_capture() {
  copy="$TEST_TMP/bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  mkdir -p "$HOME/.local/bin" "$HOME/.cache"
  cat >"$HOME/.local/bin/box-o" <<'STUB'
#!/bin/bash
cat "$HOME/debug.json"
STUB
  chmod +x "$HOME/.local/bin/box-o"
  jq '[{path:"/persist/config/opencode/opencode.json", info:.}]' "$BUNDLE_DIR/harnesses/opencode/config/opencode.json" >"$HOME/debug.json"
  printf 'previous artifact\n' >"$copy/harnesses/opencode/validation/resolved-config.json"
}

@test "capture validates v2 source records and redacts before artifact replacement" {
  prepare_capture
  jq '.[0].info.providers={fixture:{apiKey:"synthetic-secret",nested:{token:"synthetic-token"}}}' "$HOME/debug.json" >"$TEST_TMP/debug.json"
  mv "$TEST_TMP/debug.json" "$HOME/debug.json"
  run bash "$copy/harnesses/opencode/capture-validation.sh"
  [ "$status" -eq 0 ]
  run jq -e '.providers.fixture.apiKey == "validation-placeholder" and .providers.fixture.nested.token == "validation-placeholder" and .default_agent == "plan" and .update == "disable"' "$copy/harnesses/opencode/validation/resolved-config.json"
  [ "$status" -eq 0 ]
  run bash "$copy/harnesses/opencode/capture-validation.sh" --check
  [ "$status" -eq 0 ]
}

@test "capture refuses missing malformed reordered or changed source without replacing evidence" {
  prepare_capture
  cp "$HOME/debug.json" "$TEST_TMP/valid.json"
  for defect in missing malformed order rule agent update required; do
    case "$defect" in
      missing) printf '[]\n' >"$HOME/debug.json" ;;
      malformed) printf '{invalid\n' >"$HOME/debug.json" ;;
      order) jq '.[0].info.permissions |= reverse' "$TEST_TMP/valid.json" >"$HOME/debug.json" ;;
      rule) jq '.[0].info.permissions[1].effect="allow"' "$TEST_TMP/valid.json" >"$HOME/debug.json" ;;
      agent) jq '.[0].info.default_agent="build"' "$TEST_TMP/valid.json" >"$HOME/debug.json" ;;
      update) jq '.[0].info.update="auto"' "$TEST_TMP/valid.json" >"$HOME/debug.json" ;;
      required) jq 'del(.[0].info.permissions)' "$TEST_TMP/valid.json" >"$HOME/debug.json" ;;
    esac
    for mode in write check; do
      flags=(); [ "$mode" != check ] || flags=(--check)
      run bash "$copy/harnesses/opencode/capture-validation.sh" "${flags[@]}"
      [ "$status" -ne 0 ]
      [ "$(cat "$copy/harnesses/opencode/validation/resolved-config.json")" = 'previous artifact' ]
    done
  done
}

@test "disposable capture output leaves checkout evidence untouched" {
  prepare_capture
  before=$(sha256sum "$copy/harnesses/opencode/validation/"*)
  run bash "$copy/harnesses/opencode/capture-validation.sh" --output-dir "$TEST_TMP/evidence"
  [ "$status" -eq 0 ]
  [ -s "$TEST_TMP/evidence/resolved-config.json" ]
  [ -s "$TEST_TMP/evidence/config-stderr.txt" ]
  [ "$before" = "$(sha256sum "$copy/harnesses/opencode/validation/"*)" ]
}

@test "capture derives an isolated sub-namespace through the real resolver" {
  prepare_capture
  # Recording stub launcher: proves the real script propagates a
  # `<ns>-cap-<8hex>` sub-namespace (not the parent, not production).
  cat >"$HOME/.local/bin/box-o" <<'STUB'
#!/bin/bash
printf '%s\n' "${BOX_TEST_STATE_NS:-<unset>}" >>"$HOME/seen-ns.log"
printf '%s\n' "${BOX_TEST_TASK_ROOT:-<unset>}" >>"$HOME/seen-root.log"
cat "$HOME/debug.json"
STUB
  chmod +x "$HOME/.local/bin/box-o"
  # Task root lives under the real-home project parent (never /tmp: /tmp/*
  # is denylisted for real launcher projects, same as native task roots
  # under $HOME/.box-native.XXXXXX).
  taskroot="$PROJ_ROOT/taskroot"
  mkdir -p "$taskroot"
  export BOX_TEST_TASK_ROOT="$taskroot" BOX_TEST_STATE_NS=t-abcdef123456
  rm -f "$HOME/seen-ns.log" "$HOME/seen-root.log"
  run bash "$copy/harnesses/opencode/capture-validation.sh" --output-dir "$TEST_TMP/evidence"
  [ "$status" -eq 0 ]
  seen_ns=$(cat "$HOME/seen-ns.log")
  [[ "$seen_ns" =~ ^t-abcdef123456-cap-[0-9a-f]{8}$ ]]
  [ "$(cat "$HOME/seen-root.log")" = "$taskroot" ]
  # The parent-NS volume is untouched: only the capture sub-namespace ran.
  [[ "$seen_ns" != t-abcdef123456 ]]
  unset BOX_TEST_TASK_ROOT BOX_TEST_STATE_NS
}

@test "capture fails closed on a malformed test namespace" {
  prepare_capture
  taskroot="$PROJ_ROOT/taskroot"
  mkdir -p "$taskroot"
  export BOX_TEST_TASK_ROOT="$taskroot" BOX_TEST_STATE_NS='../evil'
  run bash "$copy/harnesses/opencode/capture-validation.sh" --output-dir "$TEST_TMP/evidence"
  [ "$status" -ne 0 ]
  unset BOX_TEST_TASK_ROOT BOX_TEST_STATE_NS
}

@test "capture fails when owned volume cleanup fails" {
  prepare_capture
  mkdir -p "$TEST_TMP/bin" "$HOME/.config/box-o/docker-cli"
  chmod 700 "$HOME/.config/box-o/docker-cli"
  printf '{}\n' >"$HOME/.config/box-o/docker-cli/config.json"
  chmod 600 "$HOME/.config/box-o/docker-cli/config.json"
  cat >"$TEST_TMP/bin/docker" <<'STUB'
#!/bin/bash
shift 4
case "$1 $2" in
  'ps -aq') exit 0 ;;
  'volume ls') cat "$HOME/capture-volume" ;;
  'volume rm') exit 23 ;;
  *) exit 99 ;;
esac
STUB
  chmod +x "$TEST_TMP/bin/docker"
  cat >"$HOME/.local/bin/box-o" <<'STUB'
#!/bin/bash
BOX_TOOL=test
source "$CAPTURE_BUNDLE/lib/test-state.sh"
box_test_volume opencode "$BOX_TEST_STATE_NS" "$(id -u)" "$(id -g)" >"$HOME/capture-volume"
cat "$HOME/debug.json"
STUB
  chmod +x "$HOME/.local/bin/box-o"
  # Replace only Docker transport in the disposable bundle; exercise the
  # real capture trap and namespace authorization against a failing daemon.
  cat >>"$copy/lib/docker.sh" <<'STUB'
box_docker_cli() { docker_cmd=("$CAPTURE_DOCKER" --config ignored --host ignored); }
STUB
  export CAPTURE_BUNDLE="$copy" CAPTURE_DOCKER="$TEST_TMP/bin/docker"
  export BOX_TEST_TASK_ROOT="$PROJ_ROOT" BOX_TEST_STATE_NS=t-abcdef123456
  run bash "$copy/harnesses/opencode/capture-validation.sh" --output-dir "$TEST_TMP/evidence"
  [ "$status" -ne 0 ]
  [[ "$output" == *'capture cleanup failed'* ]] || { printf '%s\n' "$output"; return 1; }
}
