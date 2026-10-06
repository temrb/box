load helpers

write_configs() {
  cfg_json="$TEST_TMP/preferences.json"
  cfg_toml="$TEST_TMP/preferences.toml"
  printf '%s\n' '{"approval_policy":"on-request","enabled":false,"empty":"","count":3,"api":{"base_url":"https://example.com"},"profiles":["default"]}' >"$cfg_json"
  cat >"$cfg_toml" <<'EOF'
approval_policy = "on-request"
enabled = false
empty = ""
count = 3
profiles = ["default"]
[api]
base_url = "https://example.com"
EOF
}

@test "JSON and TOML expose the same typed configuration values" {
  write_configs
  for cfg in "$cfg_json" "$cfg_toml"; do
    box_config_validate "$cfg"
    [ "$(box_config_get "$cfg" .approval_policy string)" = on-request ]
    [ "$(box_config_get "$cfg" .api.base_url string)" = https://example.com ]
    [ "$(box_config_get "$cfg" .enabled boolean)" = false ]
    [ "$(box_config_get "$cfg" .empty string)" = '' ]
    [ "$(box_config_get "$cfg" .count number)" = 3 ]
    [ "$(box_config_get "$cfg" .profiles array | jq -r '.[0]')" = default ]
    [ "$(box_config_get "$cfg" .api object | jq -r '.base_url')" = https://example.com ]
  done
}

@test "configuration extraction rejects missing keys, wrong types, and expressions" {
  write_configs
  for cfg in "$cfg_json" "$cfg_toml"; do
    for spec in '.missing string' '.api string' '.enabled number' '.count boolean' '.profiles object'; do
      read -r path kind <<<"$spec"
      run box_config_get "$cfg" "$path" "$kind"
      [ "$status" -ne 0 ]
    done
    run box_config_get "$cfg" '.count | .enabled' string
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported configuration path"* ]]
  done
}

@test "configuration validation rejects malformed input without echoing it" {
  for ext in json toml; do
    cfg="$TEST_TMP/bad.$ext"
    printf 'private-value malformed input\n' >"$cfg"
    run box_config_validate "$cfg"
    [ "$status" -ne 0 ]
    [[ "$output" != *private-value* ]]
  done
}

@test "TOML validation rejects duplicate keys" {
  cfg="$TEST_TMP/duplicate.toml"
  printf 'enabled = true\nenabled = false\n' >"$cfg"
  run box_config_validate "$cfg"
  [ "$status" -ne 0 ]
}

@test "JSON validation requires one object document" {
  cfg="$TEST_TMP/object.json"
  for body in '' '[]' 'null' '{} {}'; do
    printf '%s' "$body" >"$cfg"
    run box_config_validate "$cfg"
    [ "$status" -ne 0 ]
  done
}

@test "configuration parser reports missing Python TOML support clearly" {
  python3() { return 1; }
  run box_config_require_parser "$TEST_TMP/config.toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Python 3.11+ with tomllib"* ]]
}

@test "configuration parser rejects unsupported extensions" {
  run box_config_validate "$TEST_TMP/config.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported configuration extension"* ]]
}

@test "TOML helpers isolate project modules and inherited Python settings" {
  write_configs
  mkdir -p "$TEST_TMP/imports"
  for dir in "$TEST_PROJ" "$TEST_TMP/imports"; do
    for module in tomllib json sitecustomize; do
      printf 'raise RuntimeError("untrusted module executed")\n' >"$dir/$module.py"
    done
  done
  cd "$TEST_PROJ"
  export PYTHONPATH="$TEST_TMP/imports" PYTHONHOME="$TEST_TMP/missing-python-home"
  box_config_validate "$cfg_toml"
  [ "$(box_config_get "$cfg_toml" .approval_policy string)" = on-request ]
}
