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
       $invoked login  (runsc by default; failed startup or DNS refuses launch)
Select --docker-fallback explicitly for hardened-runc compatibility.
Set BOX_M_ALLOW_FALLBACK=0 to prohibit that explicit selection.
Set BOX_M_INNER_FLAG=--new-flag (or empty) if upstream renames --disable-sandbox.
Auth scope is configurable (global|project) via BOX_AUTH_SCOPE,
BOX_M_AUTH_SCOPE or ~/.config/box/state.toml; native config home stays
under ~/.config/box-m/muse-config/ (override via BOX_M_PERSIST_DIR) and
trust/settings refresh each launch.
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
box_state_guard_reset muse "$host_uid" "$host_gid" "$project_hash"

# Auth identity is declarative (registry + policy), never the home path.
# No credential reads, DB opens, locks or writes here: dry-run reports
# non-secret planning metadata only.
muse_auth_policy=$(box_auth_policy_result muse)
muse_auth_scope=${muse_auth_policy%%$'\n'*}
muse_auth_source=${muse_auth_policy#*$'\n'}
if [[ "$muse_auth_scope" == global ]]; then
  muse_auth_dir=$(box_auth_object_dir muse global "$host_uid")
  muse_auth_projection="$muse_auth_dir"
else
  muse_auth_dir=$(box_auth_object_dir muse project "$host_uid" "$project_hash")
  muse_auth_projection="$muse_auth_dir"
fi

if box_test_in_test_mode; then
  # Phase-S test namespace: test runs use the disposable test HOME, so a
  # production persist-dir override must never leak into test runs.
  [[ -z "${BOX_M_PERSIST_DIR:-}" ]] || die 'BOX_M_PERSIST_DIR must be unset in test-namespace runs.'
fi

# Native config home (non-auth); canonical auth lives in muse_auth_dir.
# Trust and preferences stay here; auth.json is a temporary projection.
muse_persist_raw=${BOX_M_PERSIST_DIR:-$HOME/.config/$(box_tool_field muse config_dir)/muse-config}
muse_persist_dir=$(box_plan_directory "$muse_persist_raw")
if box_test_in_test_mode; then
  # The derived global home must also live under the disposable task root
  # and off production roots; otherwise a misconfigured HOME would silently
  # select production state. Fails closed without Docker/lock/auth contact.
  box_test_guard_bind_root "$muse_persist_dir"
fi
box_plan_docker_cli "$HOME/.config/$(box_tool_field muse config_dir)/docker-cli" >/dev/null
if ((dry_run)); then
  printf 'Execution domain: %s\n' "$([ -n "${BOX_TEST_STATE_NS:-}" ] && printf 'test' || printf 'production')"
  printf 'Auth scope: %s\nAuth policy source: %s\nCanonical auth directory: %s\nNative projection: %s/auth.json\nNon-auth home: %s\nNon-auth volume: %s\n' \
    "$muse_auth_scope" "$muse_auth_source" "$muse_auth_dir" "$muse_persist_dir" "$muse_persist_dir" "$volume"
  box_auth_dryrun_report muse "$host_uid" "$project_hash" "$muse_persist_dir/auth.json"
fi
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
# Preserve the public provider-file name; the pinned binary consumes
# META_API_KEY. Never forward an ambient native key or print either value.
unset META_API_KEY
if (( ! dry_run )) && [[ -n "${MUSE_CODE_API_KEY+x}" ]]; then
  export META_API_KEY=$MUSE_CODE_API_KEY
fi
if (( ! dry_run )); then box_state_lock_launch muse; fi
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
# Managed auth: canonical store is authoritative while idle; the native
# auth.json is a temporary projection collected on exit.
box_auth_ensure_object "$muse_auth_dir" muse "$muse_auth_scope" "$host_uid" "$project_hash"
box_auth_transition_plan muse "$host_uid" "$project_hash" "$project"
box_auth_migration_gate muse "$muse_auth_dir" "$muse_persist_dir/auth.json" "$muse_auth_dir/migration.json"
box_auth_lease_reserve "$muse_auth_dir" "$muse_persist_dir/.box-projection.lock" "$muse_persist_dir/auth.json"
box_auth_install_projection muse "$muse_auth_dir" "$muse_persist_dir/auth.json" "$script_dir"
# Keep snapshots outside every writable container bind, including the shared home.
settings_snapshot_dir=$(TMPDIR=/tmp box_mktemp_dir box-m-settings) || die 'Cannot create settings snapshot directory.'
settings_snapshot=$settings_snapshot_dir/settings.json
muse_cleanup() {
  local rc=$?
  rm -f -- "$settings_snapshot"
  rmdir -- "$settings_snapshot_dir" 2>/dev/null || true
  if [[ -n "${muse_auth_dir:-}" && -f "$muse_auth_dir/lease.json" ]]; then
    if grep -q '"state":"active"' -- "$muse_auth_dir/lease.json" 2>/dev/null; then
      box_auth_collection_stopped "${muse_auth_dir}" || exit 1
      box_auth_collect_projection muse "$muse_auth_dir" "$muse_persist_dir/auth.json" "$script_dir"
      box_auth_lease_release "$muse_auth_dir"
    fi
  fi
  return "$rc"
}
trap muse_cleanup EXIT
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
  # Writable native home (projection) with a read-only preference overlay.
  --mount "type=bind,src=$muse_persist_dir,dst=/home/box/.config/muse,bind-recursive=disabled,bind-propagation=rprivate"
  --mount "type=bind,src=${settings_snapshot:-$config},dst=/home/box/.config/muse/settings.json,readonly"
  --mount "type=volume,src=$volume,dst=/persist"
  --mount "type=bind,src=$muse_auth_dir,dst=/run/box-auth,bind-recursive=disabled,bind-propagation=rprivate"
  --env "GIT_AUTHOR_NAME=$identity_name" --env "GIT_COMMITTER_NAME=$identity_name"
  --env "GIT_AUTHOR_EMAIL=$identity_email" --env "GIT_COMMITTER_EMAIL=$identity_email"
  --env GIT_CONFIG_GLOBAL=/dev/null --env GIT_CONFIG_NOSYSTEM=1
  --env MUSE_NO_AUTO_UPDATE=1)
launch_forward="$(box_tool_field muse forward_keys)"
muse_launch_tail() {
  args+=(--env TBH_CREDENTIAL_BACKEND=file)
  box_forward_keys META_API_KEY
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
