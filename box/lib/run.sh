# shellcheck shell=bash
# box/lib/run.sh — shared `docker run` base for both launchers.
# Launchers keep only tool-specific deltas (persist-dir bind vs tmpfs,
# credential forwarding set, login auto-runtime). Requires lib/preflight.sh
# (die, BOX_TOOL); never executed directly.
# shellcheck disable=SC2034,SC2154 # caller-owned globals (args, runtime_args,
# host_uid/host_gid, identity_name/identity_email, ...) cross files.

[[ -n "${_BOX_RUN_LOADED:-}" ]] && return 0
_BOX_RUN_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Resolve + validate git identity from a primary env prefix with fallback,
# then host global git config inference.
# Usage: box_git_identity <PRIMARY> <FALLBACK>  (e.g. box_git_identity BOX_M BOX_O)
# Precedence per field (independent): ${PRIMARY}_GIT_* > ${FALLBACK}_GIT_* >
# `git config --global user.name/user.email` (that scope only; repo-local
# identity is intentionally ignored). Explicit env always wins; invalid
# inferred values count as missing. Prints a single NOTICE on stderr when
# inference supplies at least one field. Sets globals: identity_name,
# identity_email. Fails closed on missing, multi-line, or non-printable
# values (become --env + container git config).
# LC_ALL decision (explicit): [[:print:]] stays locale-dependent so Unicode
# author names keep working; determinism comes from the explicit newline,
# carriage-return, and control-character rejection (not from forcing LC_ALL=C).
box_git_identity() {
  local primary=${1:-} fallback=${2:-} name_var email_var fb_name_var fb_email_var
  local inferred_used_name=0 inferred_used_email=0 inferred_fields="" missing=""
  [[ -n "$primary" && -n "$fallback" ]] || die 'Internal error: missing git-identity prefixes.'
  name_var="${primary}_GIT_NAME"; email_var="${primary}_GIT_EMAIL"
  fb_name_var="${fallback}_GIT_NAME"; fb_email_var="${fallback}_GIT_EMAIL"
  # shellcheck disable=SC2086 # indirect expansion over constructed names is intentional.
  identity_name=${!name_var:-${!fb_name_var:-}}
  # shellcheck disable=SC2086
  identity_email=${!email_var:-${!fb_email_var:-}}
  if [[ -z "$identity_name" || -z "$identity_email" ]]; then
    box_infer_git_identity
    if [[ -z "$identity_name" && -n "$inferred_git_name" ]]; then
      identity_name=$inferred_git_name
      inferred_used_name=1
    fi
    if [[ -z "$identity_email" && -n "$inferred_git_email" ]]; then
      identity_email=$inferred_git_email
      inferred_used_email=1
    fi
    if ((inferred_used_name || inferred_used_email)); then
      if ((inferred_used_name && inferred_used_email)); then
        inferred_fields="GIT_NAME and GIT_EMAIL"
      elif ((inferred_used_name)); then
        inferred_fields="GIT_NAME"
      else
        inferred_fields="GIT_EMAIL"
      fi
      printf '%s: NOTICE: using git global identity for %s.\n' "$BOX_TOOL" "$inferred_fields" >&2
    fi
  fi
  if [[ -z "$identity_name" || -z "$identity_email" ]]; then
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
    die "Missing git identity (${missing}): export ${primary}_GIT_NAME=... ${primary}_GIT_EMAIL=... (or ${fallback}_GIT_NAME/${fallback}_GIT_EMAIL fallback), or set 'git config --global user.name' and 'git config --global user.email'."
  fi
  [[ "$identity_name" != *$'\n'* && "$identity_name" != *$'\r'* ]] \
    || die "${primary}_GIT_NAME must be a single line."
  [[ "$identity_email" != *$'\n'* && "$identity_email" != *$'\r'* ]] \
    || die "${primary}_GIT_EMAIL must be a single line."
  [[ "$identity_name" =~ ^[[:print:]]+$ && "$identity_email" =~ ^[[:print:]]+$ ]] \
    || die 'Git identity must be printable text without control characters.'
}

# Infer git identity from the host's global git config (shared by the
# launchers via box_git_identity above and by setup.sh advice). Reads
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
    --network="$network" --workdir=/workspace)
}

# Forward provider keys into the container by NAME only (never =value, never
# in dry-run output when unset). Callers pass the tool-specific set:
# muse forwards MUSE_CODE_API_KEY only (least privilege); opencode forwards
# nothing (pure /connect — empty registry set, no-op below). Appends to
# caller-owned `args`.
# Usage: box_forward_keys [<KEY...>]  (e.g. box_forward_keys MUSE_CODE_API_KEY)
box_forward_keys() {
  (($# > 0)) || return 0
  local key
  for key in "$@"; do
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 'Internal error: invalid forward-key entry.'
    # shellcheck disable=SC2086 # indirect check-then-forward by name is intentional.
    if [[ -n "${!key:-}" ]]; then args+=(--env "$key"); fi
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

# Compute the Muse inner-sandbox bypass flag for "$@" (full-$@ opt-out scan
# + $1-only denylist). Prints the flag (possibly empty) to stdout.
# Opt-out: any --disable-sandbox/=value, custom-flag/=value, or --yolo
# anywhere disables auto-inject. Denylist ($1-only): --version/--help/-h and
# auth subcommands login/logout/auth never get the bypass — keep login
# invocations bare (`box-m login`; `muse --verbose login` still gets
# the bypass by design since only $1 is inspected).
# Honors BOX_M_INNER_FLAG (empty disables). Fails closed on bad shape.
# Usage: box_muse_bypass "$@"  (call after arg parsing, before exec)
box_muse_bypass() {
  local flag=${BOX_M_INNER_FLAG---disable-sandbox} arg has_opt=0
  [[ -z "$flag" || "$flag" == --[!-]* ]] \
    || die 'BOX_M_INNER_FLAG must be empty or a --flag (e.g. --disable-sandbox).'
  [[ "$flag" != *[[:space:]]* ]] \
    || die 'BOX_M_INNER_FLAG must not contain whitespace.'
  for arg in "$@"; do
    case "$arg" in
      --disable-sandbox|--disable-sandbox=*|--yolo) has_opt=1 ;;
    esac
    if [[ -n "$flag" ]]; then
      case "$arg" in
        "$flag"|"$flag"=*) has_opt=1 ;;
      esac
    fi
  done
  if (( ! has_opt )) && [[ -n "$flag" ]] \
      && [[ "${1:-}" != "--version" && "${1:-}" != "--help" && "${1:-}" != "-h" \
        && "${1:-}" != "login" && "${1:-}" != "logout" && "${1:-}" != "auth" ]]; then
    printf '%s' "$flag"
  fi
}

# Shared --help flag block (launchers append tool-specific lines after).
# Usage: box_usage_common_flags
box_usage_common_flags() {
  cat <<'EOF'
Run from the project root. --dry-run prints arguments without contacting Docker.
--docker-fallback explicitly chooses hardened runc; --runsc explicitly chooses
gVisor (no probe). With neither flag, tool runs probe container DNS under
runsc first and auto-select hardened runc only when the probe fails (NOTICE
plus fallback WARNING; fail-closed under *_ALLOW_FALLBACK=0). --shell runs
never probe: they stay on the explicit runtime. Launcher flags (--dry-run,
--docker-fallback, --runsc) must precede --shell; flags after --shell are
passed to the shell and a launcher flag there is an error.
EOF
}
