# shellcheck shell=bash
box_harness_validate() {
  local bundle=$1 artifact
  source "$bundle/lib/config-file.sh"
  for artifact in $(box_tool_field muse artifacts); do
    box_config_validate "$bundle/$(box_artifact_field muse "$artifact" source)" "$(box_artifact_field muse "$artifact" format)"
  done
  jq -e 'type == "object" and .schema_version == 1 and .approval_mode == "on-request" and .approval_judge == true and .telemetry.enabled == false and .api.base_url == "https://api.meta.ai/v1" and (.model|type == "string" and length > 0)' "$bundle/harnesses/muse/config/settings.json" >/dev/null || die 'Unsupported Muse startup policy.'
}
