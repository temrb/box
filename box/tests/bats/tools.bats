# tools.bats — lib/tools.sh registry contract: stable ids, complete rows,
# fail-closed lookup, well-formed pin/label wiring, and (transitional)
# parity with the frozen lib/config.sh copies.
load helpers

@test "registry ids keep the stable core in order" {
  # Membership + relative order of the stable core (insertion-safe: new
  # tools may join without touching this test; reordering the core fails).
  [[ " $box_tool_ids " == *" muse "* ]]
  [[ " $box_tool_ids " == *" opencode "* ]]
  [[ "$box_tool_ids" == *muse*opencode* ]]
}

@test "registry rows are complete (known empties allowed)" {
  for id in $box_tool_ids; do
    for field in $box_tool_fields; do
      # Pure /connect ships no model and forwards no keys: these two
      # opencode fields are empty by design (every other field non-empty).
      # `run` pins the lookup status: a bare $(...) would mask a die.
      case "$id/$field" in
        opencode/model|opencode/forward_keys)
          run box_tool_field "$id" "$field"
          [ "$status" -eq 0 ] || { echo "missing field: $id/$field"; return 1; }
          [ -z "$output" ] || { echo "expected empty: $id/$field"; return 1; }
          continue ;;
      esac
      val=$(box_tool_field "$id" "$field")
      [ -n "$val" ] || { echo "empty field: $id/$field"; return 1; }
    done
  done
}

@test "registry id guard accepts members and rejects the rest" {
  run box_require_tool muse
  [ "$status" -eq 0 ]
  run box_require_tool opencode
  [ "$status" -eq 0 ]
  run box_require_tool bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool id"* ]]
  run box_require_tool ''
  [ "$status" -ne 0 ]
}

@test "registry launcher reverse lookup maps launchers to ids" {
  [ "$(box_tool_id_for_launcher box-m)" = "muse" ]
  [ "$(box_tool_id_for_launcher box-o)" = "opencode" ]
  run box_tool_id_for_launcher box-bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown launcher"* ]]
  run box_tool_id_for_launcher ''
  [ "$status" -ne 0 ]
}

@test "registry lookup fails closed on unknown id or field" {
  run box_tool_field bogus network
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool id"* ]]
  run box_tool_field muse bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool field"* ]]
  run box_tool_field '' network
  [ "$status" -ne 0 ]
  run box_tool_field muse ''
  [ "$status" -ne 0 ]
}

@test "registry muse row carries the pinned identity" {
  [ "$(box_tool_field muse launcher)" = "box-m" ]
  [ "$(box_tool_field muse image_prefix)" = "box-m" ]
  [ "$(box_tool_field muse network)" = "box-m" ]
  [ "$(box_tool_field muse config_dir)" = "box-m" ]
  [ "$(box_tool_field muse config_file)" = "settings.json" ]
  [ "$(box_tool_field muse version_file)" = "version-muse.env" ]
  [ "$(box_tool_field muse dockerfile_target)" = "muse" ]
  [ "$(box_tool_field muse version_format)" = "sha-pinned" ]
  [ "$(box_tool_field muse model)" = "muse-spark-1.3" ]
  [ "$(box_tool_field muse api_base_url)" = "https://api.meta.ai/v1" ]
  [ "$(box_tool_field muse probe_hosts)" = "auth.meta.com api.meta.ai" ]
  [ "$(box_tool_field muse forward_keys)" = "MUSE_CODE_API_KEY" ]
  [ "$(box_tool_field muse pin_keys)" = "MUSE_VERSION MUSE_SHA256_AMD64 MUSE_SHA256_ARM64" ]
  [ "$(box_tool_field muse display)" = "Muse" ]
  [ "$(box_tool_field muse config_base_path)" = ".api.base_url" ]
  [ "$(box_tool_field muse pin_model)" = "0" ]
  [ "$(box_tool_field muse git_prefix)" = "BOX_M" ]
}

@test "registry opencode row carries the pinned identity" {
  [ "$(box_tool_field opencode launcher)" = "box-o" ]
  [ "$(box_tool_field opencode image_prefix)" = "box-o" ]
  [ "$(box_tool_field opencode network)" = "box-o" ]
  [ "$(box_tool_field opencode config_dir)" = "box-o" ]
  [ "$(box_tool_field opencode config_file)" = "opencode.json" ]
  [ "$(box_tool_field opencode version_file)" = "version-opencode.env" ]
  [ "$(box_tool_field opencode dockerfile_target)" = "opencode" ]
  [ "$(box_tool_field opencode version_format)" = "npm-pinned" ]
  run box_tool_field opencode model
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(box_tool_field opencode api_base_url)" = "https://registry.npmjs.org/opencode-ai" ]
  [ "$(box_tool_field opencode probe_hosts)" = "registry.npmjs.org" ]
  run box_tool_field opencode forward_keys
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(box_tool_field opencode pin_keys)" = "OPENCODE_VERSION OPENCODE_NPM_INTEGRITY OPENCODE_NPM_INTEGRITY_LINUX_X64 OPENCODE_NPM_INTEGRITY_LINUX_ARM64 NODE_VERSION NODESOURCE_FINGERPRINT" ]
  [ "$(box_tool_field opencode display)" = "OpenCode" ]
  [ "$(box_tool_field opencode config_base_path)" = ".permission.external_directory" ]
  [ "$(box_tool_field opencode pin_model)" = "0" ]
  [ "$(box_tool_field opencode git_prefix)" = "BOX_O" ]
}

@test "registry generator fields are well-formed" {
  for id in $box_tool_ids; do
    pin_model=$(box_tool_field "$id" pin_model)
    [[ "$pin_model" == 0 || "$pin_model" == 1 ]] \
      || { echo "pin_model not 0/1: $id"; return 1; }
    base_path=$(box_tool_field "$id" config_base_path)
    [[ "$base_path" == .* ]] || { echo "base path not dotted: $id"; return 1; }
  done
}

@test "registry label pairs reference declared pins and sane label keys" {
  for id in $box_tool_ids; do
    pins=" $(box_tool_field "$id" pin_keys) "
    for pair in $(box_tool_field "$id" label_pins); do
      pin=${pair%%:*}
      key=${pair#*:}
      [[ -n "$pin" && -n "$key" && "$pair" == *:* && "$key" != *:* ]] \
        || { echo "malformed pair: $id/$pair"; return 1; }
      [[ "$pins" == *" $pin "* ]] \
        || { echo "label pin not declared: $id/$pin"; return 1; }
      [[ "$key" != *[[:space:]]* ]] \
        || { echo "label key has whitespace: $id/$key"; return 1; }
    done
  done
}

