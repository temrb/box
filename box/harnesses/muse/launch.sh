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

# Check explicit runtime selection before the independent automatic DNS probe.
# Honor the kill-switch and report the selected fallback.
box_check_fallback BOX_M_ALLOW_FALLBACK

# Tool identity comes from the registry; only the BOX_M_* env override names
# stay literal (user-facing API).
tool_network=$(box_tool_field muse network)
box_project_identity "$tool_network"

config_raw=${BOX_M_CONFIG:-$HOME/.config/$(box_tool_field muse config_dir)/$(box_tool_field muse config_file)}
config=$(box_resolve_config "$config_raw")
# shellcheck source=lib/config-file.sh
source "$script_dir/lib/config-file.sh"
box_directory_configs muse

# Pinned Muse Code release; the single source rewritten by the update procedure.
# BOX_M_VERSION_FILE overrides the default only for testing; the
# installed default stays $HOME/.config/box-m/version-muse.env.
version_file=${BOX_M_VERSION_FILE:-$HOME/.config/$(box_tool_field muse config_dir)/$(box_tool_field muse version_file)}
# shellcheck disable=SC2046 # word-splitting registry pin_keys into allowlist args is intentional.
box_load_version_file "$version_file" "$(box_tool_field muse version_format)" $(box_tool_field muse pin_keys)
# SHAs are validated by box_load_version_file in lib/preflight.sh (threaded
# via lib/pins.sh), recorded in image labels (see Dockerfile --target muse),
# and compared at run by box_assert_image; only the version feeds the image tag.
file_version=$box_file_version

# Shared per-field identity: selected prefix, other registered prefixes, then global Git.
box_git_identity BOX_M

# Tag from the already-parsed config-file version: the installed layout
# (~/.local/bin) has no bundle version files, so the bundle-loading tag
# helper cannot run here. Same single source the label assert compares.
image=${BOX_M_IMAGE:-$(box_image_tag_for_version muse "$file_version" "$host_uid" "$host_gid")}

# Global auth and trust persist; preferences use a private launch snapshot.
muse_persist_raw=${BOX_M_PERSIST_DIR:-$HOME/.config/$(box_tool_field muse config_dir)/muse-config}
muse_persist_dir=$(box_plan_directory "$muse_persist_raw")
box_plan_docker_cli "$HOME/.config/$(box_tool_field muse config_dir)/docker-cli" >/dev/null
box_assert_native_cache "$muse_persist_dir/auth.json"
if [[ -e "$muse_persist_dir/settings.json" || -L "$muse_persist_dir/settings.json" ]]; then
  [[ ! -L "$muse_persist_dir/settings.json" && -f "$muse_persist_dir/settings.json" ]] || die 'Invalid live Muse settings.'
  box_assert_owner_mode "$muse_persist_dir/settings.json" 'Live Muse settings' nowrite

fi
jq -e 'has("approval_mode") and has("approval_judge") and (.telemetry | has("enabled")) and (.api | has("base_url"))' "$config" >/dev/null || die 'Muse seed lacks enforced safety keys.'
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

# AUTO runtime for tool runs (shared probe in lib/launcher.sh): probe
# container DNS under runsc first, stay on gVisor when healthy, else
# auto-select the hardened-runc fallback with a single NOTICE plus the
# standard fallback WARNING (never silent). The healthy path stays on runsc
# with no output change (it still pays one probe-container round trip):
# the gate skips the probe under --dry-run (no daemon contact; show the
# default-runtime command), explicit --docker-fallback/--runsc, and --shell
# runs (explicit-only diagnostics path). With BOX_M_ALLOW_FALLBACK=0
# a failed probe fails closed with remediation instead of a run that would
# fail opaquely inside (device flow `transport error`, TUI
# `failed to fetch model catalog`).
if (( ! shell_mode )) && (( $# == 1 )) && [[ "${1:-}" == login ]]; then
  # shellcheck disable=SC2016 # backticks in the context are an intentional literal.
  context='`login`'
else
  context='this run'
fi
# shellcheck disable=SC2046 # word-splitting registry probe_hosts into host args is intentional.
box_maybe_auto_runtime "$image" "$tool_network" BOX_M_ALLOW_FALLBACK "$context" $(box_tool_field muse probe_hosts)

# shellcheck disable=SC2054 # elements are space-separated; commas live inside quoted --tmpfs values.
args=(run --rm --init --interactive --pull=never --name "$container"
  --label org.meta.muse.box=true
  --label org.box.tool=muse
  "${runtime_args[@]}" --user "$host_uid:$host_gid")
# Shared hardened base (lib/run.sh): containment/resource/network/workdir in
# canonical order (previously copied per launcher and drifted).
box_base_args "$tool_network"
args+=(--mount "type=bind,src=$project,dst=/workspace,bind-recursive=disabled,bind-propagation=rprivate"
  # Writable auth/trust parent with a read-only preference overlay.
  --mount "type=bind,src=$muse_persist_dir,dst=/home/box/.config/muse,bind-recursive=disabled,bind-propagation=rprivate"
  --mount "type=bind,src=${settings_snapshot:-$config},dst=/home/box/.config/muse/settings.json,readonly"
  --mount "type=volume,src=$volume,dst=/persist"
  --env "GIT_AUTHOR_NAME=$identity_name" --env "GIT_COMMITTER_NAME=$identity_name"
  --env "GIT_AUTHOR_EMAIL=$identity_email" --env "GIT_COMMITTER_EMAIL=$identity_email"
  --env GIT_CONFIG_GLOBAL=/dev/null --env GIT_CONFIG_NOSYSTEM=1
  --env MUSE_NO_AUTO_UPDATE=1)
# Runtime signal for the verify harness CapBnd grading (FAIL on runc, WARNING
# on runsc): derived from the final runtime selection above (probe may have
# switched it to runc). Has a `=value` so dry-run NAME-only shape checks skip it.
box_runtime_signal
# --tty only for real interactive runs: --dry-run output stays deterministic
# regardless of whether stdout is a terminal.
box_maybe_tty

# Pass the registry forward_keys into the container by variable name without
# exposing secrets on argv. Only the Muse key is forwarded (least privilege).
# Shared forwarder (lib/run.sh): NAME-only, skipped
# when unset.
# shellcheck disable=SC2046 # word-splitting registry forward_keys is intentional.
box_forward_keys $(box_tool_field muse forward_keys)
# Terminal capability forwarding (same NAME-only helper): the TUI resolves
# color depth from host terminal variables, and `docker run -t` alone leaves
# them unset in-container. Non-secret; skipped when unset.
# shellcheck disable=SC2086 # word-splitting BOX_TERMINAL_KEYS is intentional.
box_forward_keys $BOX_TERMINAL_KEYS

# Opt-in supplementary host groups; automatic forwarding of all host groups
# would broaden access to host-mounted content without a deliberate choice.
box_extra_gids BOX_M_EXTRA_GIDS

if ((shell_mode)); then
  args+=(--entrypoint=/bin/bash)
  args+=("$image" "$@")
else
  # Pass an OS-containment bypass so Muse Code delegates syscall/FS isolation
  # to outer Docker/gVisor rather than failing its inner bubblewrap
  # user-namespace probe. Approvals stay on (settings.json approval_mode).
  # Flag-name fallback: override via BOX_M_INNER_FLAG if upstream
  # renames --disable-sandbox; set empty to disable the automatic bypass.
  # Probe inside the container with `muse --help | grep -qi sandbox` when
  # upgrading; --version/--help/-h and the auth subcommands (login/logout/auth)
  # as the first tool argument never get the bypass. See box_muse_bypass
  # in harnesses/muse/native.sh (full-$@ opt-out scan, $1-only denylist; keep login
  # invocations bare: `box-m login`).
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

# Preflight host environment checks (warns on explicit image overrides).
image_override=0
[[ -n "${BOX_M_IMAGE:-}" ]] && image_override=1
box_docker_exec muse "$tool_network" "$image_override"
