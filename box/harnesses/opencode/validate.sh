# shellcheck shell=bash
box_harness_validate() {
  local bundle=$1 artifact
  source "$bundle/lib/config-file.sh"
  for artifact in $(box_tool_field opencode artifacts); do
    box_config_validate "$bundle/$(box_artifact_field opencode "$artifact" source)" "$(box_artifact_field opencode "$artifact" format)"
  done
  # Native v2 permissions: ordered array, last-match-wins. No lsp, no singular
  # permission, no bash/write/patch (v2 uses shell/edit). No image-owned deny
  # policy is shipped; ordinary permissions are configurable approval defaults.
  # shell intentionally falls through to allow: the *.env ask rules cover read/edit tools only.
  jq -e '
    .default_agent == "plan" and .update == "disable"
    and (has("lsp") | not) and (has("permission") | not)
    and (.permissions | type == "array" and length == 8)
    and .permissions[0] == {"action":"*","resource":"*","effect":"allow"}
    and .permissions[1] == {"action":"read","resource":"*.env","effect":"ask"}
    and .permissions[2] == {"action":"read","resource":"*.env.*","effect":"ask"}
    and .permissions[3] == {"action":"read","resource":"*.env.example","effect":"allow"}
    and .permissions[4] == {"action":"edit","resource":"*.env","effect":"ask"}
    and .permissions[5] == {"action":"edit","resource":"*.env.*","effect":"ask"}
    and .permissions[6] == {"action":"edit","resource":"*.env.example","effect":"allow"}
    and .permissions[7] == {"action":"external_directory","resource":"*","effect":"ask"}
  ' "$bundle/harnesses/opencode/config/opencode.json" >/dev/null || die 'Unsupported OpenCode v2 config/order.'
}
