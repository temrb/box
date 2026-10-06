# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # public wrapper and shared libraries own globals
usage() {
  local invoked=${0##*/}
  cat <<USAGE
Usage: $invoked [--dry-run] [--runsc|--docker-fallback] [Codex arguments...]
       $invoked [launcher flags] --shell [bash arguments...]
       $invoked login                  (ChatGPT device login)
       $invoked login --with-api-key   (explicit providers.env key import)
Project homes: ~/.config/box-c/projects/<physical-project-hash>/
Override the protected root with BOX_C_STATE_ROOT; disable fallback with
BOX_C_ALLOW_FALLBACK=0. Set BOX_C_AUTH=api to forward OPENAI_API_KEY explicitly.
USAGE
  box_usage_common_flags
}
box_parse_launcher_args "$@"
set -- "${launcher_rest[@]}"
box_launch_prologue codex
if [[ -n "${BOX_C_STATE_ROOT:-}" && -n "${BOX_C_STATE_DIR:-}" && "$BOX_C_STATE_ROOT" != "$BOX_C_STATE_DIR" ]]; then
  die 'BOX_C_STATE_ROOT and legacy BOX_C_STATE_DIR must agree when both are set.'
fi
state_root=$(box_plan_directory "${BOX_C_STATE_ROOT:-${BOX_C_STATE_DIR:-$HOME/$(box_state_field codex home root)}}")
codex_home=$(box_plan_directory "$state_root/$project_hash/codex-home")
if [[ -d "$codex_home" ]]; then box_assert_owner_mode "$codex_home" 'Codex home' dir700; fi
box_plan_docker_cli "$HOME/.config/$(box_tool_field codex config_dir)/docker-cli" >/dev/null
# Auth/health checks run on live runs only: --dry-run never checks auth.
if (( ! dry_run )); then box_assert_native_cache "$codex_home/auth.json"; fi
if [[ -e "$codex_home/config.toml" || -L "$codex_home/config.toml" ]]; then
  [[ ! -L "$codex_home/config.toml" && -f "$codex_home/config.toml" ]] || die 'Invalid live Codex configuration.'
  box_assert_owner_mode "$codex_home/config.toml" 'Live Codex configuration' nowrite
  box_config_validate "$codex_home/config.toml" toml
fi
credentials=${BOX_C_ENV_FILE:-$HOME/.config/box/providers.env}
# shellcheck disable=SC2086 # shared allowlist intentionally split
box_load_credentials "$credentials" "$dry_run" $BOX_CRED_KEYS
api_login=0
if (( ! shell_mode )) && [[ "${1:-}" == login && "${2:-}" == --with-api-key ]]; then
  (($# == 2)) || die 'Explicit API-key login takes no additional arguments.'
  api_login=1
elif (( ! shell_mode )) && [[ "${1:-}" == login && $# == 1 ]]; then
  set -- login --device-auth
fi
case "${BOX_C_AUTH:-chatgpt}" in chatgpt|api) ;; *) die 'BOX_C_AUTH must be chatgpt or api.';; esac
if (( ! dry_run )); then
  if ((api_login)); then [[ -n "${OPENAI_API_KEY:-}" ]] || die 'Explicit API-key login requires OPENAI_API_KEY in providers.env.'; fi
  box_prepare_directory "$state_root" 700 >/dev/null
  box_prepare_directory "$codex_home" 700 >/dev/null
  [[ ! -L "$codex_home/.box-launch.lock" ]] || die 'Redirected Codex lock.'
  exec {preferences_lock}>"$codex_home/.box-launch.lock"
  flock -x "$preferences_lock" || die 'Cannot lock Codex home.'
  box_backup_preferences "$codex_home/config.toml"
  if [[ -f "$codex_home/config.toml" ]]; then
    # Preserve native trust records only; all preferences inherit live defaults.
    trust_config=$(box_config_toml_subtree "$codex_home/config.toml" projects trust_level) \
      || die 'Cannot preserve Codex trust records.'
    box_write_if_changed "$codex_home/config.toml" "$trust_config" 'Codex trust records'
  fi
  flock -u "$preferences_lock"
  exec {preferences_lock}>&-
fi
box_docker_cli "$HOME/.config/$(box_tool_field codex config_dir)/docker-cli"
launch_mounts=(--mount "type=bind,src=$project,dst=/workspace,bind-recursive=disabled,bind-propagation=rprivate"
  --mount "type=bind,src=$codex_home,dst=/home/box/.codex,bind-recursive=disabled,bind-propagation=rprivate"
  --mount "type=volume,src=$volume,dst=/persist"
  --mount "type=bind,src=$config,dst=/etc/codex/config.toml,readonly"
  --env CODEX_HOME=/home/box/.codex
  --env "GIT_AUTHOR_NAME=$identity_name" --env "GIT_COMMITTER_NAME=$identity_name"
  --env "GIT_AUTHOR_EMAIL=$identity_email" --env "GIT_COMMITTER_EMAIL=$identity_email"
  --env GIT_CONFIG_GLOBAL=/dev/null --env GIT_CONFIG_NOSYSTEM=1)
launch_forward=""
if ((api_login)) || [[ "${BOX_C_AUTH:-chatgpt}" == api ]]; then
  launch_forward="$(box_tool_field codex forward_keys)"
fi
codex_launch_tail() {
  if ((shell_mode)); then
    args+=(--entrypoint=/bin/bash "$image" "$@")
  elif ((api_login)); then
    # Literal script: the secret is supplied by NAME and enters login via stdin.
    # shellcheck disable=SC2016
    args+=(--entrypoint=/bin/bash "$image" -c 'printf "%s" "$OPENAI_API_KEY" | codex login --with-api-key')
  else
    args+=("$image" "$@")
  fi
}
box_launch_epilogue codex 'this run' org.openai.codex.box launch_mounts "$launch_forward" codex_launch_tail "$@"
