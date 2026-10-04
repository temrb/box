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

# Check explicit runtime selection before the independent automatic DNS probe.
# Honor the kill-switch and report the selected fallback.
box_check_fallback BOX_O_ALLOW_FALLBACK

# Tool identity comes from the registry; only the BOX_O_* env override names
# stay literal (user-facing API).
tool_network=$(box_tool_field opencode network)
box_project_identity box-o-v2

config_raw=${BOX_O_CONFIG:-$HOME/.config/$(box_tool_field opencode config_dir)/$(box_tool_field opencode config_file)}
config=$(box_resolve_config "$config_raw")
# shellcheck source=lib/config-file.sh
source "$script_dir/lib/config-file.sh"
box_directory_configs opencode

# Pinned OpenCode release; the single source rewritten by the update procedure.
# BOX_O_VERSION_FILE overrides the default only for testing; the
# installed default stays $HOME/.config/box-o/version-opencode.env.
version_file=${BOX_O_VERSION_FILE:-$HOME/.config/$(box_tool_field opencode config_dir)/$(box_tool_field opencode version_file)}
# shellcheck disable=SC2046 # word-splitting registry pin_keys into allowlist args is intentional.
box_load_version_file "$version_file" "$(box_tool_field opencode version_format)" $(box_tool_field opencode pin_keys)
# Integrity pins are validated by box_load_version_file in lib/preflight.sh
# (threaded via lib/pins.sh), recorded in image labels (see Dockerfile
# --target opencode), and compared at run by box_assert_image; only the
# version feeds the tag.
file_version=$box_file_version

# Shared per-field identity: selected prefix, other registered prefixes, then global Git.
box_git_identity BOX_O

# Tag from the already-parsed config-file version: the installed layout
# (~/.local/bin) has no bundle version files, so the bundle-loading tag
# helper cannot run here. Same single source the label assert compares.
image=${BOX_O_IMAGE:-$(box_image_tag_for_version opencode "$file_version" "$host_uid" "$host_gid")}

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

# AUTO runtime for tool runs (shared probe in lib/launcher.sh): probe
# container DNS under runsc first (generic registry egress — runsc
# embedded-DNS breakage is total, so the default-path host proves generic
# DNS health),
# stay on gVisor when healthy, else auto-select the hardened-runc fallback
# with a single NOTICE plus the standard fallback WARNING (never silent).
# The gate skips the probe under --dry-run, explicit --docker-fallback/
# --runsc, and --shell runs (explicit-only diagnostics path); with
# BOX_O_ALLOW_FALLBACK=0 a failed probe fails closed.
# shellcheck disable=SC2046 # word-splitting registry probe_hosts into host args is intentional.
box_maybe_auto_runtime "$image" "$tool_network" BOX_O_ALLOW_FALLBACK 'this run' $(box_tool_field opencode probe_hosts)

# shellcheck disable=SC2054 # elements are space-separated; commas live inside quoted --tmpfs values.
args=(run --rm --init --interactive --pull=never --name "$container"
  --label org.opencode.box=true
  --label org.box.tool=opencode
  "${runtime_args[@]}" --user "$host_uid:$host_gid")
# Shared hardened base (lib/run.sh): containment/resource/network/workdir in
# canonical order (previously copied per launcher and drifted).
box_base_args "$tool_network"
args+=(--env XDG_CONFIG_HOME=/persist/config
  --mount "type=bind,src=$project,dst=/workspace,bind-recursive=disabled,bind-propagation=rprivate"
  # Client preferences are writable siblings in the per-project v2 volume.
  --mount "type=volume,src=$volume,dst=/persist"
  --mount "type=bind,src=$config,dst=/persist/config/opencode/opencode.json,readonly"
  --env "GIT_AUTHOR_NAME=$identity_name" --env "GIT_COMMITTER_NAME=$identity_name"
  --env "GIT_AUTHOR_EMAIL=$identity_email" --env "GIT_COMMITTER_EMAIL=$identity_email"
  --env GIT_CONFIG_GLOBAL=/dev/null --env GIT_CONFIG_NOSYSTEM=1
  --env OPENCODE_DISABLE_AUTOUPDATE=1)
# Runtime signal for the verify harness CapBnd grading (FAIL on runc, WARNING
# on runsc). Has a `=value` so dry-run NAME-only shape checks skip it.
box_runtime_signal
# --tty only for real interactive runs: --dry-run output stays deterministic
# regardless of whether stdout is a terminal.
box_maybe_tty
# Forward registry keys into the container by variable name without
# exposing secrets on argv or in dry-run output (pure /connect: the opencode
# registry set is empty, so this no-ops). Shared forwarder (lib/run.sh).
# shellcheck disable=SC2046 # word-splitting registry forward_keys is intentional.
box_forward_keys $(box_tool_field opencode forward_keys)
# Terminal capability forwarding (same NAME-only helper): the TUI resolves
# color depth from host terminal variables, and `docker run -t` alone leaves
# them unset in-container. Non-secret; skipped when unset.
# shellcheck disable=SC2086 # word-splitting BOX_TERMINAL_KEYS is intentional.
box_forward_keys $BOX_TERMINAL_KEYS
# Opt-in supplementary host groups; automatic forwarding of all host groups
# would broaden access to host-mounted content without a deliberate choice.
box_extra_gids BOX_O_EXTRA_GIDS
# OpenCode has no inner bubblewrap sandbox, so unlike box-m there is no
# --disable-sandbox-style bypass flag to inject here.
if ((shell_mode)); then args+=(--entrypoint=/usr/local/bin/box-opencode --env BOX_OPENCODE_SHELL=1); fi
args+=("$image" "$@")

# Stop on unavailable prerequisites; no pulls, privilege escalation, or fallback.
# Warns on explicit image overrides.
image_override=0
[[ -n "${BOX_O_IMAGE:-}" ]] && image_override=1
box_docker_exec opencode "$tool_network" "$image_override"
