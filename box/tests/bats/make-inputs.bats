# Operator values must reach operational commands as data, including dollars
# and shell metacharacters. A minimal bundle captures argv without state access.
load helpers

_make_transport_bundle() {
  transport="$TEST_TMP/bundle"
  mkdir -p "$transport/lib"
  cp "$BUNDLE_DIR/Makefile" "$transport/Makefile"
  cp "$BUNDLE_DIR/lib/tools.sh" "$transport/lib/tools.sh"
  cat > "$transport/lib/auth-ops.sh" <<'SH'
#!/bin/bash
python3 -I -c 'import json,os,sys; json.dump({"args":sys.argv[1:],"runtime":os.environ.get("BOX_AUTH_RUNTIME")},open(os.environ["MAKE_CAPTURE"],"w"))' "$@"
SH
  export MAKE_CAPTURE="$TEST_TMP/argv.json"
}

@test "Make transports quotes backticks dollars globs and newlines literally" {
  _make_transport_bundle
  local hostile
  hostile="$TEST_TMP/"'$(touch injected-dollar)`touch injected-backtick` "quoted" * ? [x]'
  hostile+=$'\nsecond line'
  run make --no-print-directory -s -C "$transport" state-plan HARNESS=codex "PROJECT=$hostile"
  [ "$status" -eq 0 ]
  EXPECTED_PROJECT="$hostile" python3 -I -c 'import json,os; assert json.load(open(os.environ["MAKE_CAPTURE"]))["args"] == ["plan","codex",os.environ["EXPECTED_PROJECT"]]'
  [ ! -e "$transport/injected-dollar" ]
  [ ! -e "$transport/injected-backtick" ]
}

@test "Make optional migration selectors and runtime remain literal data" {
  _make_transport_bundle
  local hostile='$(touch injected)`touch injected` "quoted"'
  run make --no-print-directory -s -C "$transport" auth-migrate HARNESS=codex PROJECT='/project with spaces' "DB_PATH=$hostile" "RUNTIME=$hostile"
  [ "$status" -eq 0 ]
  EXPECTED_SELECTOR="$hostile" python3 -I -c 'import json,os; v=json.load(open(os.environ["MAKE_CAPTURE"])); assert v["args"] == ["migrate","codex","/project with spaces","--db-path",os.environ["EXPECTED_SELECTOR"]]; assert v["runtime"] == os.environ["EXPECTED_SELECTOR"]'
  [ ! -e "$transport/injected" ]
}

@test "Make transports explicit Codex qualification artifacts as literal data" {
  _make_transport_bundle
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/python3" <<'SH'
#!/bin/bash
/usr/bin/python3 -I -c 'import json,os,sys; json.dump(sys.argv[1:],open(os.environ["MAKE_CAPTURE"],"w"))' "$@"
SH
  chmod 700 "$TEST_TMP/bin/python3"
  local hostile='$(touch injected)`touch injected` "quoted" package.tar.gz'
  PATH="$TEST_TMP/bin:$PATH" run make --no-print-directory -s -C "$transport" verify-native-auth-host MUSE_BINARY=/muse OPENCODE_BINARY=/opencode OPENCODE_ARCHIVE=/opencode.tar.gz "CODEX_BINARY=$hostile" "CODEX_ARCHIVE=$hostile"
  [ "$status" -eq 0 ]
  EXPECTED_ARTIFACT="$hostile" python3 -I -c 'import json,os; v=json.load(open(os.environ["MAKE_CAPTURE"])); assert v[2:6] == ["--binary",os.environ["EXPECTED_ARTIFACT"],"--archive",os.environ["EXPECTED_ARTIFACT"]]'
  [ ! -e "$transport/injected" ]
}
