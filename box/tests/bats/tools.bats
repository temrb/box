# tools.bats — lib/tools.sh registry contract: stable ids, complete rows,
# fail-closed lookup, and well-formed pin/label wiring.
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
      # A model or forwarding set may intentionally be absent in any tool.
      # `run` pins the lookup status: a bare $(...) would mask a die.
      case "$field" in
        forward_keys|install_adapter)
          run box_tool_field "$id" "$field"
          [ "$status" -eq 0 ] || { echo "missing field: $id/$field"; return 1; }
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
  [ "$(jq -r .model "$BUNDLE_DIR/harnesses/muse/config/settings.json")" = "muse-spark-1.3" ]
  [ "$(jq -r .api.base_url "$BUNDLE_DIR/harnesses/muse/config/settings.json")" = "https://api.meta.ai/v1" ]
  [ "$(box_tool_field muse probe_hosts)" = "auth.meta.com api.meta.ai" ]
  [ "$(box_tool_field muse forward_keys)" = "MUSE_CODE_API_KEY" ]
  [ "$(box_tool_field muse pin_keys)" = "MUSE_VERSION MUSE_SHA256_AMD64 MUSE_SHA256_ARM64" ]
  [ "$(box_tool_field muse display)" = "Muse" ]
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
  [ "$(box_tool_field opencode version_format)" = "sha-pinned" ]
  [ "$(box_tool_field opencode probe_url)" = "https://opencode.ai" ]
  [ "$(box_tool_field opencode probe_hosts)" = "opencode.ai" ]
  run box_tool_field opencode forward_keys
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(box_tool_field opencode pin_keys)" = "OPENCODE_VERSION OPENCODE_SHA256_AMD64 OPENCODE_SHA256_ARM64" ]
  [ "$(box_tool_field opencode display)" = "OpenCode" ]
  [ "$(box_tool_field opencode git_prefix)" = "BOX_O" ]
}

@test "registry artifacts and adapters validate recursively" {
  run box_validate_registry "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
  [ "$(box_tool_field codex launcher)" = box-c ]
  [ "$(box_artifact_field codex policy role)" = managed-image ]
  [ "$(box_artifact_field codex config lifecycle)" = refresh-live ]
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
