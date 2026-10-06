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
