# shellcheck shell=bash
box_harness_validate() {
  local bundle=$1 artifact
  source "$bundle/lib/config-file.sh"
  for artifact in $(box_tool_field codex artifacts); do
    box_config_validate "$bundle/$(box_artifact_field codex "$artifact" source)" "$(box_artifact_field codex "$artifact" format)"
  done
  python3 - "$bundle" <<'PYCODEX'
import json, pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1]) / "harnesses/codex"
seed = tomllib.loads((root / "config/config.toml").read_text())
req = tomllib.loads((root / "policy/requirements.toml").read_text())
expected = {"allowed_approval_policies": ["on-request"], "allowed_approvals_reviewers": ["user"], "default_permissions": ":danger-full-access", "allowed_permission_profiles": {":danger-full-access": True}, "cli_auth_credentials_store": "file", "check_for_update_on_startup": False, "sqlite_home": "/persist/state/codex"}
expected_seed = {"approval_policy": "on-request", "approvals_reviewer": "user", "default_permissions": ":danger-full-access", "cli_auth_credentials_store": "file", "check_for_update_on_startup": False, "sqlite_home": "/persist/state/codex"}
expected_full_seed = {"agents": {"default_subagent_model": "gpt-6-luna", "default_subagent_reasoning_effort": "max", "enabled": True, "max_concurrent_threads_per_session": 6}, "approval_policy": "on-request", "approvals_reviewer": "user", "check_for_update_on_startup": False, "cli_auth_credentials_store": "file", "default_permissions": ":danger-full-access", "model": "gpt-6.1-sol", "model_auto_compact_token_limit": 700000, "model_auto_compact_token_limit_scope": "total", "model_context_window": 1050000, "model_reasoning_effort": "low", "model_reasoning_summary": "concise", "personality": "pragmatic", "plan_mode_reasoning_effort": "high", "project_doc_max_bytes": 65536, "skills": {"max_context_tokens": 8000}, "sqlite_home": "/persist/state/codex", "tool_output_token_limit": 8000, "tools": {"web_search": {"context_size": "medium"}}, "tui": {"status_line": ["model", "reasoning", "used-tokens", "total-input-tokens", "total-output-tokens", "five-hour-limit", "weekly-limit", "context-remaining", "task-progress", "fast-mode"]}, "web_search": "live"}
if json.dumps(seed, sort_keys=True) != json.dumps(expected_full_seed, sort_keys=True):
    sys.exit("Unsupported Codex seed fields.")
if json.dumps(req, sort_keys=True) != json.dumps(expected, sort_keys=True) or any(seed.get(key) != value for key, value in expected_seed.items()):
    sys.exit("Unsupported Codex managed policy or seed")
PYCODEX
}
