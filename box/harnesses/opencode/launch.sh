# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # wrapper-owned globals
usage() {
  # Invoked-name identity: `box` is a symlink to one launcher, so usage
  # prints the name it was called as instead of a hardcoded canonical.
  local invoked=${0##*/}
  cat <<EOF
Usage: $invoked [--dry-run] [--shell [bash arguments...]] [OpenCode arguments...]
       $invoked --docker-fallback [same arguments...]
       $invoked --runsc [same arguments...]
Set BOX_O_ALLOW_FALLBACK=0 to disable the fallback entirely.
EOF
  box_usage_common_flags
  if [[ "$invoked" == box ]]; then
    cat <<'EOF'
`box` is the setup-managed default (currently box-o). Re-run setup.sh with
--default <id> to switch it persistently.
EOF
  fi
}

box_parse_launcher_args "$@"
set -- "${launcher_rest[@]}"

box_launch_prologue opencode

# Parse literal KEY=value entries; never source the credentials file.
# Duplicate keys are rejected before any credentials are exported.
# Shared providers file (see setup.sh); fail-closed except --dry-run.
# The shared allowlist comes from lib/config.sh (BOX_CRED_KEYS). OpenCode forwards zero manual keys (pure /connect
# via the native SQLite store on /persist); the parse below only enforces shared-file
# hygiene (unknown keys hard-FAIL).
credentials=${BOX_O_ENV_FILE:-$HOME/.config/box/providers.env}
# shellcheck disable=SC2086 # word-splitting BOX_CRED_KEYS into allowlist args is intentional.
box_load_credentials "$credentials" "$dry_run" $BOX_CRED_KEYS
# Prepare the isolated CLI only after read-only credential validation.
box_docker_cli "$HOME/.config/$(box_tool_field opencode config_dir)/docker-cli"

launch_mounts=(--env XDG_CONFIG_HOME=/persist/config
  --mount "type=bind,src=$project,dst=/workspace,bind-recursive=disabled,bind-propagation=rprivate"
  # Client preferences are writable siblings in the per-project v2 volume.
  --mount "type=volume,src=$volume,dst=/persist"
  --mount "type=bind,src=$config,dst=/persist/config/opencode/opencode.json,readonly"
  --env "GIT_AUTHOR_NAME=$identity_name" --env "GIT_COMMITTER_NAME=$identity_name"
  --env "GIT_AUTHOR_EMAIL=$identity_email" --env "GIT_COMMITTER_EMAIL=$identity_email"
  --env GIT_CONFIG_GLOBAL=/dev/null --env GIT_CONFIG_NOSYSTEM=1
  --env OPENCODE_DISABLE_AUTOUPDATE=1)
# Pure /connect: the opencode registry forward set is empty, so this no-ops.
launch_forward="$(box_tool_field opencode forward_keys)"
# OpenCode has no inner bubblewrap sandbox, so unlike box-m there is no
# --disable-sandbox-style bypass flag to inject here.
opencode_launch_tail() {
  if ((shell_mode)); then args+=(--entrypoint=/usr/local/bin/box-opencode --env BOX_OPENCODE_SHELL=1); fi
  args+=("$image" "$@")
}
box_launch_epilogue opencode 'this run' org.opencode.box launch_mounts "$launch_forward" opencode_launch_tail "$@"
