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
box_state_guard_reset opencode "$host_uid" "$host_gid" "$project_hash"

# Auth scope is declarative (registry + policy). The mixed SQLite database
# stays project-scoped on /persist; canonical auth lives in the resolved
# object and is projected via the SQLite adapter (container-side).
opencode_auth_policy=$(box_auth_policy_result opencode)
opencode_auth_scope=${opencode_auth_policy%%$'\n'*}
opencode_auth_source=${opencode_auth_policy#*$'\n'}
if [[ "$opencode_auth_scope" == global ]]; then
  opencode_auth_dir=$(box_auth_object_dir opencode global "$host_uid")
else
  opencode_auth_dir=$(box_auth_object_dir opencode project "$host_uid" "$project_hash")
fi
if ((dry_run)); then
  printf 'Execution domain: %s\n' "$([ -n "${BOX_TEST_STATE_NS:-}" ] && printf 'test' || printf 'production')"
  printf 'Auth scope: %s\nAuth policy source: %s\nCanonical auth directory: %s\nNative projection: volume %s (/persist/data/opencode/opencode/opencode.db)\nNon-auth volume: %s\n' \
    "$opencode_auth_scope" "$opencode_auth_source" "$opencode_auth_dir" "$volume" "$volume"
  box_auth_dryrun_report opencode "$host_uid" "$project_hash" "volume:$volume (/persist/data/opencode/opencode/opencode.db; explicit --db-path export required for migration)"
fi

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
if (( ! dry_run )); then box_state_lock_launch opencode; fi
box_docker_cli "$HOME/.config/$(box_tool_field opencode config_dir)/docker-cli"
if (( ! dry_run )); then
  # Canonical auth object + lease. The SQLite projection itself is installed
  # and collected inside the container (entrypoint) where /persist is
  # available; the host only reserves the identity and mounts it at
  # /run/box-auth. Selection sidecars stay in project state.
  box_auth_ensure_object "$opencode_auth_dir" opencode "$opencode_auth_scope" "$host_uid" "$project_hash"
  box_auth_transition_plan opencode "$host_uid" "$project_hash" "$project"
  # Volume-backed legacy gate uses non-secret metadata only; the database is
  # opened only by explicit migration, never by ordinary launch planning.
  _opencode_index=$(box_auth_index_dir) || die 'Cannot resolve auth index.'
  box_prepare_directory "$_opencode_index/locks" 700 >/dev/null
  box_auth_lease_reserve "$opencode_auth_dir" "$_opencode_index/locks/$volume.lock" "volume:$volume"
  unset _opencode_index
  opencode_cleanup() {
    local rc=$? holders
    if jq -e '.state == "active" and .phase == "reserved"' -- "$opencode_auth_dir/lease.json" >/dev/null 2>&1; then
      # No native mutation began. Before a Docker attempt, the host alone
      # owns this reservation; afterwards require a successful liveness query.
      if [[ "${BOX_AUTH_CONTAINER_ATTEMPTED:-0}" == 0 ]]; then
        box_auth_lease_release "$opencode_auth_dir" || rc=1
      elif holders=$("${docker_cmd[@]}" ps -q --filter "volume=$opencode_auth_dir") && [[ -z "$holders" ]]; then
        box_auth_lease_release "$opencode_auth_dir" || rc=1
      fi
    fi
    return "$rc"
  }
  trap opencode_cleanup EXIT
  # NOTE: the entrypoint owns collection/scrub inside the container; the host
  # trap below only preserves the lease on interrupt. Idle marking happens
  # after successful container collection (see entrypoint).
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
fi

launch_mounts=(--env XDG_CONFIG_HOME=/persist/config
  --mount "type=bind,src=$project,dst=/workspace,bind-recursive=disabled,bind-propagation=rprivate"
  # Client preferences are writable siblings in the per-project v2 volume.
  --mount "type=volume,src=$volume,dst=/persist"
  --mount "type=bind,src=$config,dst=/persist/config/opencode/opencode.json,readonly"
  --mount "type=bind,src=$opencode_auth_dir,dst=/run/box-auth,bind-recursive=disabled,bind-propagation=rprivate"
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
