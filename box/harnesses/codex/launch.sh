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
box_check_fallback BOX_C_ALLOW_FALLBACK
tool_network=$(box_tool_field codex network)
box_project_identity "$tool_network"
config_raw=${BOX_C_CONFIG:-$HOME/.config/$(box_tool_field codex config_dir)/$(box_tool_field codex config_file)}
config=$(box_resolve_config "$config_raw")
# shellcheck source=lib/config-file.sh
source "$script_dir/lib/config-file.sh"
box_directory_configs codex
# Format prerequisites apply only to this TOML consumer.
box_config_validate "$config" toml
version_file=${BOX_C_VERSION_FILE:-$HOME/.config/$(box_tool_field codex config_dir)/$(box_tool_field codex version_file)}
# shellcheck disable=SC2046 # ordered registry keys intentionally split
box_load_version_file "$version_file" "$(box_tool_field codex version_format)" $(box_tool_field codex pin_keys)
file_version=$box_file_version
box_git_identity BOX_C
image=${BOX_C_IMAGE:-$(box_image_tag_for_version codex "$file_version" "$host_uid" "$host_gid")}
if [[ -n "${BOX_C_STATE_ROOT:-}" && -n "${BOX_C_STATE_DIR:-}" && "$BOX_C_STATE_ROOT" != "$BOX_C_STATE_DIR" ]]; then
  die 'BOX_C_STATE_ROOT and legacy BOX_C_STATE_DIR must agree when both are set.'
fi
state_root=$(box_plan_directory "${BOX_C_STATE_ROOT:-${BOX_C_STATE_DIR:-$HOME/$(box_state_field codex home root)}}")
codex_home=$(box_plan_directory "$state_root/$project_hash/codex-home")
if [[ -d "$codex_home" ]]; then box_assert_owner_mode "$codex_home" 'Codex home' dir700; fi
box_plan_docker_cli "$HOME/.config/$(box_tool_field codex config_dir)/docker-cli" >/dev/null
box_assert_native_cache "$codex_home/auth.json"
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
    trust_config=$(python3 -I - "$codex_home/config.toml" <<'TRUST'
import json, sys, tomllib
with open(sys.argv[1], 'rb') as f:
    data = tomllib.load(f)
for path, record in data.get('projects', {}).items():
    if isinstance(record, dict) and 'trust_level' in record:
        print('[projects.' + json.dumps(path, ensure_ascii=False) + ']')
        print('trust_level = ' + json.dumps(record['trust_level'], ensure_ascii=False))
TRUST
    ) || die 'Cannot preserve Codex trust records.'
    box_write_if_changed "$codex_home/config.toml" "$trust_config" 'Codex trust records'
  fi
fi
box_docker_cli "$HOME/.config/$(box_tool_field codex config_dir)/docker-cli"
# shellcheck disable=SC2046 # registry host list intentionally split
box_maybe_auto_runtime "$image" "$tool_network" BOX_C_ALLOW_FALLBACK 'this run' $(box_tool_field codex probe_hosts)
args=(run --rm --init --interactive --pull=never --name "$container"
  --label org.openai.codex.box=true --label org.box.tool=codex
  "${runtime_args[@]}" --user "$host_uid:$host_gid")
box_base_args "$tool_network"
args+=(--mount "type=bind,src=$project,dst=/workspace,bind-recursive=disabled,bind-propagation=rprivate"
  --mount "type=bind,src=$codex_home,dst=/home/box/.codex,bind-recursive=disabled,bind-propagation=rprivate"
  --mount "type=volume,src=$volume,dst=/persist"
  --mount "type=bind,src=$config,dst=/etc/codex/config.toml,readonly"
  --env CODEX_HOME=/home/box/.codex
  --env "GIT_AUTHOR_NAME=$identity_name" --env "GIT_COMMITTER_NAME=$identity_name"
  --env "GIT_AUTHOR_EMAIL=$identity_email" --env "GIT_COMMITTER_EMAIL=$identity_email"
  --env GIT_CONFIG_GLOBAL=/dev/null --env GIT_CONFIG_NOSYSTEM=1)
box_runtime_signal
box_maybe_tty
if ((api_login)) || [[ "${BOX_C_AUTH:-chatgpt}" == api ]]; then
  # shellcheck disable=SC2046
  box_forward_keys $(box_tool_field codex forward_keys)
fi
# shellcheck disable=SC2086
box_forward_keys $BOX_TERMINAL_KEYS
box_extra_gids BOX_C_EXTRA_GIDS
if ((shell_mode)); then
  args+=(--entrypoint=/bin/bash "$image" "$@")
elif ((api_login)); then
  # Literal script: the secret is supplied by NAME and enters login via stdin.
  # shellcheck disable=SC2016
  args+=(--entrypoint=/bin/bash "$image" -c 'printf "%s" "$OPENAI_API_KEY" | codex login --with-api-key')
else
  args+=("$image" "$@")
fi
image_override=0
[[ -n "${BOX_C_IMAGE:-}" ]] && image_override=1
box_docker_exec codex "$tool_network" "$image_override"
