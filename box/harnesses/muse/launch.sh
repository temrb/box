# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # wrapper-owned globals
usage() {
  # Invoked-name identity: `box` is a symlink to this launcher, so usage
  # prints the name it was called as instead of a hardcoded canonical.
  local invoked=${0##*/}
  cat <<EOF
Usage: $invoked [--dry-run] [--shell [bash arguments...]] [Muse arguments...]
       $invoked --docker-fallback [same arguments...]
       $invoked --runsc [same arguments...]
       $invoked login  (auto runtime: probes runsc DNS, falls back only if needed;
       every tool run probes the same way — use --runsc to force gVisor)
Set BOX_M_ALLOW_FALLBACK=0 to disable the fallback entirely.
Set BOX_M_INNER_FLAG=--new-flag (or empty) if upstream renames --disable-sandbox.
Muse auth and trust (auth.json, .trust.json) persist
globally in ~/.config/box-m/muse-config/; settings refresh each launch
(override via BOX_M_PERSIST_DIR).
EOF
  box_usage_common_flags
  if [[ "$invoked" == box ]]; then
    cat <<'EOF'
`box` is the setup-managed default (currently box-m). Re-run setup.sh with
--default <id> to switch it persistently.
EOF
  fi
}

box_parse_launcher_args "$@"
set -- "${launcher_rest[@]}"

box_launch_prologue muse

# Global auth and trust persist; preferences use a private launch snapshot.
muse_persist_raw=${BOX_M_PERSIST_DIR:-$HOME/.config/$(box_tool_field muse config_dir)/muse-config}
muse_persist_dir=$(box_plan_directory "$muse_persist_raw")
box_plan_docker_cli "$HOME/.config/$(box_tool_field muse config_dir)/docker-cli" >/dev/null
# Auth/health checks run on live runs only: --dry-run never checks auth.
if (( ! dry_run )); then box_assert_native_cache "$muse_persist_dir/auth.json"; fi
if [[ -e "$muse_persist_dir/settings.json" || -L "$muse_persist_dir/settings.json" ]]; then
  [[ ! -L "$muse_persist_dir/settings.json" && -f "$muse_persist_dir/settings.json" ]] || die 'Invalid live Muse settings.'
  box_assert_owner_mode "$muse_persist_dir/settings.json" 'Live Muse settings' nowrite

fi
jq -e "$box_muse_enforced_jq" "$config" >/dev/null || die 'Muse seed lacks enforced safety keys.'
# Validate credentials and CLI destinations before preparing native state.
credentials=${BOX_M_ENV_FILE:-$HOME/.config/box/providers.env}
# shellcheck disable=SC2086 # shared allowlist intentionally split
box_load_credentials "$credentials" "$dry_run" $BOX_CRED_KEYS
box_docker_cli "$HOME/.config/$(box_tool_field muse config_dir)/docker-cli"
if (( ! dry_run )); then
box_prepare_directory "$muse_persist_dir" 700 >/dev/null
[[ ! -L "$muse_persist_dir/.box-migration.lock" ]] || die 'Redirected Muse migration lock.'
exec {migration_lock}>"$muse_persist_dir/.box-migration.lock"
flock -x "$migration_lock"
box_backup_preferences "$muse_persist_dir/settings.json"
# Create the overlay target as the user so Docker never creates a root-owned
# empty file inside the persistent bind. This stores no default preferences.
if [[ ! -e "$muse_persist_dir/settings.json" ]]; then
  (umask 077; set -o noclobber; : > "$muse_persist_dir/settings.json") || die 'Cannot create settings mount target.'
fi
flock -u "$migration_lock"
exec {migration_lock}>&-
# Keep snapshots outside every writable container bind, including the shared home.
settings_snapshot_dir=$(TMPDIR=/tmp box_mktemp_dir box-m-settings) || die 'Cannot create settings snapshot directory.'
settings_snapshot=$settings_snapshot_dir/settings.json
trap 'rm -f -- "$settings_snapshot"; rmdir -- "$settings_snapshot_dir"' EXIT
(umask 077; : > "$settings_snapshot") || die 'Cannot create settings snapshot.'
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
box_config_merge_json "$config" "${directory_configs[@]}" > "$settings_snapshot" || die 'Cannot merge Muse settings.'
box_enforce_safe_settings "$config" "$settings_snapshot"

fi

# AUTO context for the shared probe: `login` and tool runs probe alike.
# A failed probe fails closed here instead of a run that would fail opaquely
# inside (device flow `transport error`, TUI `failed to fetch model catalog`).
if (( ! shell_mode )) && (( $# == 1 )) && [[ "${1:-}" == login ]]; then
  # shellcheck disable=SC2016 # backticks in the context are an intentional literal.
  context='`login`'
else
  context='this run'
fi
launch_mounts=(--mount "type=bind,src=$project,dst=/workspace,bind-recursive=disabled,bind-propagation=rprivate"
  # Writable auth/trust parent with a read-only preference overlay.
  --mount "type=bind,src=$muse_persist_dir,dst=/home/box/.config/muse,bind-recursive=disabled,bind-propagation=rprivate"
  --mount "type=bind,src=${settings_snapshot:-$config},dst=/home/box/.config/muse/settings.json,readonly"
  --mount "type=volume,src=$volume,dst=/persist"
  --env "GIT_AUTHOR_NAME=$identity_name" --env "GIT_COMMITTER_NAME=$identity_name"
  --env "GIT_AUTHOR_EMAIL=$identity_email" --env "GIT_COMMITTER_EMAIL=$identity_email"
  --env GIT_CONFIG_GLOBAL=/dev/null --env GIT_CONFIG_NOSYSTEM=1
  --env MUSE_NO_AUTO_UPDATE=1)
launch_forward="$(box_tool_field muse forward_keys)"
muse_launch_tail() {
  if ((shell_mode)); then
    args+=(--entrypoint=/bin/bash)
    args+=("$image" "$@")
  else
    # Pass an OS-containment bypass so Muse Code delegates syscall/FS isolation
    # to outer Docker/gVisor rather than failing its inner bubblewrap
    # user-namespace probe. Approvals stay on (binary defaults on-request/on;
    # approval has no settings.json equivalent in the pinned release).
    # Flag-name fallback: override via BOX_M_INNER_FLAG if upstream
    # renames --disable-sandbox; set empty to disable the automatic bypass.
    # Probe inside the container with `muse --help | grep -qi sandbox` when
    # upgrading; --version/--help/-h and the auth subcommands (login/logout/auth)
    # as the first tool argument never get the bypass. See box_muse_bypass
    # in harnesses/muse/native.sh (full-$@ opt-out scan, $1-only denylist; keep login
    # invocations bare: `box-m login`).
    local muse_bypass
    muse_bypass=$(box_muse_bypass "$@")
    if [[ -n "$muse_bypass" ]]; then
      # The pinned CLI parses session subcommands before their flags.
      case "${1:-}" in
        exec|resume|serve) args+=("$image" "$1" "$muse_bypass" "${@:2}") ;;
        *) args+=("$image" "$muse_bypass" "$@") ;;
      esac
    else
      args+=("$image" "$@")
    fi
  fi
}
box_launch_epilogue muse "$context" org.meta.muse.box launch_mounts "$launch_forward" muse_launch_tail "$@"
