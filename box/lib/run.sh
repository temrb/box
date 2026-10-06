# shellcheck shell=bash
# box/lib/run.sh — shared `docker run` base for all launchers.
# Launchers keep only tool-specific deltas (persist-dir bind vs tmpfs,
# credential forwarding set, login auto-runtime). Requires lib/preflight.sh
# (die, BOX_TOOL); never executed directly.
# shellcheck disable=SC2034,SC2154 # caller-owned globals (args, runtime_args,
# host_uid/host_gid, identity_name/identity_email, ...) cross files.

[[ -n "${_BOX_RUN_LOADED:-}" ]] && return 0
_BOX_RUN_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Non-failing git-identity probe: same precedence as box_git_identity
# (selected prefix, other registered prefixes, global git inference).
# Usage: box_git_identity_probe <PRIMARY> [FALLBACK]
# Precedence per field (independent): ${PRIMARY}_GIT_* > ${FALLBACK}_GIT_* >
# other registered git prefixes in registry order > `git config --global`
# user.name/user.email via box_infer_git_identity (that scope only).
# Validity per field: non-empty, single line, printable; invalid counts as
# missing. Silent (no NOTICE); never dies. Sets globals: probe_git_name,
# probe_git_email (valid-only, empty when missing/invalid), probe_git_missing
# ("GIT_NAME"/"GIT_EMAIL"/"GIT_NAME and GIT_EMAIL", empty when complete),
# probe_git_hint (every prefix pair for setup todo), probe_git_inferred
# (which fields inference supplied, empty when none), probe_git_raw_name,
# probe_git_raw_email (unvalidated resolution for the dying wrapper).
# Returns 0 when complete and valid, 1 when incomplete.
# LC_ALL decision (explicit): [[:print:]] stays locale-dependent so Unicode
# author names keep working; determinism comes from the explicit newline,
# carriage-return, and control-character rejection (not from forcing LC_ALL=C).
box_git_identity_probe() {
  local primary=${1:-} fallback=${2:-} name_var email_var prefix id
  probe_git_name=''; probe_git_email=''; probe_git_missing=''; probe_git_hint=''; probe_git_inferred=''
  probe_git_raw_name=''; probe_git_raw_email=''
  for id in $box_tool_ids; do
    prefix=$(box_tool_field "$id" git_prefix)
    probe_git_hint+="${probe_git_hint:+ and/or }${prefix}_GIT_NAME/${prefix}_GIT_EMAIL"
  done
  if [[ -z "$primary" ]]; then
    probe_git_missing='GIT_NAME and GIT_EMAIL'
    return 1
  fi
  local -a prefixes=("$primary")
  if [[ -n "$fallback" ]]; then prefixes+=("$fallback"); fi
  for id in $box_tool_ids; do
    prefix=$(box_tool_field "$id" git_prefix)
    [[ "$prefix" == "$primary" || "$prefix" == "$fallback" ]] || prefixes+=("$prefix")
  done
  local name='' email=''
  for prefix in "${prefixes[@]}"; do
    name_var="${prefix}_GIT_NAME"; email_var="${prefix}_GIT_EMAIL"
    [[ -n "$name" ]] || name=${!name_var:-}
    [[ -n "$email" ]] || email=${!email_var:-}
  done
  local inferred_used_name=0 inferred_used_email=0
  if [[ -z "$name" || -z "$email" ]]; then
    box_infer_git_identity
    if [[ -z "$name" && -n "$inferred_git_name" ]]; then
      name=$inferred_git_name
      inferred_used_name=1
    fi
    if [[ -z "$email" && -n "$inferred_git_email" ]]; then
      email=$inferred_git_email
      inferred_used_email=1
    fi
    if ((inferred_used_name || inferred_used_email)); then
      if ((inferred_used_name && inferred_used_email)); then
        probe_git_inferred="GIT_NAME and GIT_EMAIL"
      elif ((inferred_used_name)); then
        probe_git_inferred="GIT_NAME"
      else
        probe_git_inferred="GIT_EMAIL"
      fi
    fi
  fi
  probe_git_raw_name=$name
  probe_git_raw_email=$email
  local valid_name=$name valid_email=$email
  if [[ "$valid_name" == *$'\n'* || "$valid_name" == *$'\r'* ]]; then valid_name=''; fi
  if [[ "$valid_email" == *$'\n'* || "$valid_email" == *$'\r'* ]]; then valid_email=''; fi
  if [[ -n "$valid_name" ]] && ! [[ "$valid_name" =~ ^[[:print:]]+$ ]]; then valid_name=''; fi
  if [[ -n "$valid_email" ]] && ! [[ "$valid_email" =~ ^[[:print:]]+$ ]]; then valid_email=''; fi
  probe_git_name=$valid_name
  probe_git_email=$valid_email
  if [[ -z "$valid_name" ]]; then
    probe_git_missing="GIT_NAME"
  fi
  if [[ -z "$valid_email" ]]; then
    if [[ -n "$probe_git_missing" ]]; then
      probe_git_missing+=" and GIT_EMAIL"
    else
      probe_git_missing="GIT_EMAIL"
    fi
  fi
  if [[ -n "$probe_git_missing" ]]; then return 1; fi
  return 0
}

# Dying wrapper over box_git_identity_probe: identical precedence, NOTICE,
# and die messages. Sets globals: identity_name, identity_email.
# Usage: box_git_identity <PRIMARY> [FALLBACK]  (e.g. box_git_identity BOX_M)
box_git_identity() {
  local primary=${1:-} fallback=${2:-}
  [[ -n "$primary" ]] || die 'Internal error: missing git-identity prefix.'
  if [[ -n "$fallback" ]]; then
    box_git_identity_probe "$primary" "$fallback" || true
  else
    box_git_identity_probe "$primary" || true
  fi
  identity_name=$probe_git_raw_name
  identity_email=$probe_git_raw_email
  if [[ -n "$probe_git_inferred" ]]; then
    printf '%s: NOTICE: using git global identity for %s.\n' "$BOX_TOOL" "$probe_git_inferred" >&2
  fi
  if [[ -z "$identity_name" || -z "$identity_email" ]]; then
    local missing=""
    if [[ -z "$identity_name" ]]; then
      missing="GIT_NAME"
    fi
    if [[ -z "$identity_email" ]]; then
      if [[ -n "$missing" ]]; then
        missing+=" and GIT_EMAIL"
      else
        missing="GIT_EMAIL"
      fi
    fi
    local fallback_clause=""
    if [[ -n "$fallback" ]]; then fallback_clause=" (or ${fallback}_GIT_NAME/${fallback}_GIT_EMAIL fallback)"; fi
    die "Missing git identity (${missing}): export ${primary}_GIT_NAME=... ${primary}_GIT_EMAIL=...${fallback_clause}, or set 'git config --global user.name' and 'git config --global user.email'."
  fi
  [[ "$identity_name" != *$'\n'* && "$identity_name" != *$'\r'* ]] \
    || die "${primary}_GIT_NAME must be a single line."
  [[ "$identity_email" != *$'\n'* && "$identity_email" != *$'\r'* ]] \
    || die "${primary}_GIT_EMAIL must be a single line."
  [[ "$identity_name" =~ ^[[:print:]]+$ && "$identity_email" =~ ^[[:print:]]+$ ]] \
    || die 'Git identity must be printable text without control characters.'
}

# Infer git identity from the host's global git config (shared by the
# launchers via box_git_identity and by setup.sh via the probe above). Reads
# --global scope only; repo-local user.name/email is intentionally ignored.
# Sets globals: inferred_git_name, inferred_git_email (each empty when
# unavailable or invalid). Never fails: a missing git binary, unset keys,
# and empty, multi-line, or non-printable values all yield empty output
# with exit 0. Same validity rules as box_git_identity (non-empty, single
# line, printable); name and email infer independently.
# Usage: box_infer_git_identity
box_infer_git_identity() {
  inferred_git_name=""; inferred_git_email=""
  command -v git >/dev/null 2>&1 || return 0
  local value
  # `|| true`: unset keys exit nonzero, which must not abort `set -e` callers.
  value=$(git config --global user.name 2>/dev/null || true)
  if [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    && [[ "$value" =~ ^[[:print:]]+$ ]]; then
    inferred_git_name=$value
  fi
  value=$(git config --global user.email 2>/dev/null || true)
  if [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    && [[ "$value" =~ ^[[:print:]]+$ ]]; then
    inferred_git_email=$value
  fi
  return 0
}

# Append the shared hardened `docker run` base to the caller-owned `args`
# array (defaults to `args`, override via 2nd param like box_extra_gids).
# Caller initializes `args` with (run --rm --init --interactive --pull=never
# --name + --labels + "${runtime_args[@]}" + --user); this appends the
# containment/resource/network/workdir base in canonical order.
# Resource limits come from lib/config.sh (single source); fail closed when
# the caller did not source it.
# Usage: box_base_args <network> [ARRAY_NAME]
box_base_args() {
  local network=${1:-} array_name=${2:-args}
  local -n base_out="$array_name"
  [[ -n "$network" ]] || die 'Internal error: missing base-args network.'
  : "${BOX_CONTAINER_MEMORY:?caller must source lib/config.sh before lib/run.sh}"
  : "${BOX_CONTAINER_CPUS:?caller must source lib/config.sh before lib/run.sh}"
  : "${BOX_CONTAINER_PIDS:?caller must source lib/config.sh before lib/run.sh}"
  # shellcheck disable=SC2016,SC2154 # $host_uid/$host_gid are intentional literals; the vars are launcher globals.
  [[ -n "${host_uid:-}" && -n "${host_gid:-}" ]] || die 'Internal error: $host_uid/$host_gid unset.'
  # shellcheck disable=SC2054 # elements are space-separated; commas live inside quoted --tmpfs values.
  base_out+=(--cap-drop=ALL --security-opt=no-new-privileges
    --ipc=private --cgroupns=private
    --hostname=box
    --log-opt max-size=10m --log-opt max-file=3
    --read-only
    --tmpfs /tmp:rw,nosuid,nodev,exec
    --tmpfs /run:rw,nosuid,nodev
    --tmpfs /var/tmp:rw,nosuid,nodev
    --tmpfs "/home/box/.cache:rw,nosuid,nodev,uid=$host_uid,gid=$host_gid,mode=700"
    --memory="$BOX_CONTAINER_MEMORY" --memory-swap="$BOX_CONTAINER_MEMORY" --cpus="$BOX_CONTAINER_CPUS" --pids-limit="$BOX_CONTAINER_PIDS"
    --network="$network" --workdir="${working_directory:-/workspace}")
}

# Forward keys into the container by NAME only (never =value, so dry-run
# output stays value-free). Two uses: provider keys (callers pass the
# tool-specific registry set — muse forwards MUSE_CODE_API_KEY only, least
# privilege; opencode forwards nothing, pure /connect, empty-set no-op) and
# host terminal keys (all launchers pass BOX_TERMINAL_KEYS so TUI
# color-depth detection matches the host terminal). A key is forwarded when
# SET, even when empty: the flag-shaped terminal keys (NO_COLOR,
# FORCE_COLOR, CLICOLOR_FORCE) are conventionally presence-meaningful, so a
# set-but-empty flag must survive the hop. Unset keys are skipped (under
# --dry-run the credential loader exports nothing, so no provider key is
# forwarded there). Appends to a caller-owned array via nameref (defaults to
# `args`, like box_extra_gids/box_base_args).
# Usage: box_forward_keys [--array ARRAY_NAME] [<KEY...>]
# (e.g. box_forward_keys MUSE_CODE_API_KEY; box_forward_keys --array custom FOO)
box_forward_keys() {
  local array_name=args
  if [[ "${1:-}" == "--array" ]]; then
    array_name=${2:-}
    [[ -n "$array_name" ]] || die 'Internal error: missing forward-keys array name.'
    shift 2 || die 'Internal error: missing forward-keys array name.'
  fi
  (($# > 0)) || return 0
  local -n fwd_out="$array_name"
  local key
  for key in "$@"; do
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 'Internal error: invalid forward-key entry.'
    # shellcheck disable=SC2086 # indirect check-then-forward by name is intentional.
    if [[ -n "${!key+x}" ]]; then fwd_out+=(--env "$key"); fi
  done
}

# Derive the BOX_RUNTIME signal from the final runtime selection and
# append it as --env BOX_RUNTIME=<runsc|runc> (has `=value` so dry-run
# NAME-only shape checks skip it). The verify harness grades CapBnd on it.
# Usage: box_runtime_signal  (reads global fallback_requested)
box_runtime_signal() {
  local runtime=runsc
  ((fallback_requested)) && runtime=runc
  args+=(--env "BOX_RUNTIME=$runtime")
}

# Append --tty only for real interactive runs so --dry-run output stays
# deterministic regardless of whether stdout is a terminal.
# Usage: box_maybe_tty  (reads globals dry_run)
box_maybe_tty() {
  if (( ! dry_run )) && [[ -t 0 && -t 1 ]]; then args+=(--tty); fi
}

# Shared --help flag block (launchers append tool-specific lines after).
# Usage: box_usage_common_flags
box_usage_common_flags() {
  cat <<'EOF'
Run from any project subdirectory. --project-root PATH selects a non-Git root. --dry-run prints arguments without contacting Docker.
--docker-fallback explicitly chooses hardened runc; --runsc explicitly chooses
gVisor (no probe). With neither flag, tool runs probe container DNS under
runsc first and auto-select hardened runc only when the probe fails (NOTICE
plus fallback WARNING; fail-closed under *_ALLOW_FALLBACK=0). --shell runs
never probe: they stay on the explicit runtime. Launcher flags (--dry-run,
--docker-fallback, --runsc) must precede --shell; flags after --shell are
passed to the shell and a launcher flag there is an error.
EOF
}

# Shared launch tail: auto-runtime → args → base → mounts → signals → keys →
# tail callback → exec. Adapters build data (a mounts array, a forward-names
# string, run context) and pass a tail callback for entrypoint/image
# assembly; template-method, no tool-name branches. The callback receives the
# tool args as its own "$@" (everything after the six params is forwarded).
# The probe runs container DNS under runsc first and auto-selects the
# hardened-runc fallback with NOTICE plus fallback WARNING (never silent);
# it skips under --dry-run, explicit runtime flags, and --shell runs, and
# fails closed under *_ALLOW_FALLBACK=0. Dry-run exits inside
# box_docker_exec (no early return here).
# Requires prologue globals (image, tool_network, identity_*) plus adapter-set
# launch data; lib/{tools,launcher,run,docker}.sh loaded (wrapper order).
# Usage: box_launch_epilogue <id> <context> <marker-label> <mounts-array> <forward-names> <tail-fn> [tool args...]
box_launch_epilogue() {
  local id=${1:-} context=${2:-} marker=${3:-} forward_names=${5:-} tail_fn=${6:-}
  local -n _epi_mounts=${4:-}
  box_require_tool "$id"
  [[ -n "$context" && -n "$marker" && -n "${4:-}" && -n "$tail_fn" ]] || die 'Internal error: missing epilogue arguments.'
  shift 6
  local gpfx img_var image_override
  gpfx=$(box_tool_field "$id" git_prefix)
  # shellcheck disable=SC2046 # word-splitting registry probe_hosts into host args is intentional.
  box_maybe_auto_runtime "$image" "$tool_network" "${gpfx}_ALLOW_FALLBACK" "$context" $(box_tool_field "$id" probe_hosts)
  # shellcheck disable=SC2054 # elements are space-separated; commas live inside quoted --tmpfs values.
  args=(run --rm --init --interactive --pull=never --name "$container"
    --label "$marker=true"
    --label org.box.tool="$id"
    "${runtime_args[@]}" --user "$host_uid:$host_gid")
  box_base_args "$tool_network"
  args+=("${_epi_mounts[@]}")
  box_runtime_signal
  box_maybe_tty
  # shellcheck disable=SC2086 # word-splitting pre-split forward names is intentional.
  box_forward_keys $forward_names
  # shellcheck disable=SC2086 # word-splitting BOX_TERMINAL_KEYS is intentional.
  box_forward_keys $BOX_TERMINAL_KEYS
  box_extra_gids "${gpfx}_EXTRA_GIDS"
  "$tail_fn" "$@"
  image_override=0
  img_var="${gpfx}_IMAGE"
  [[ -n "${!img_var:-}" ]] && image_override=1
  box_docker_exec "$id" "$tool_network" "$image_override"
}
