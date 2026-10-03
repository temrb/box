# shellcheck shell=bash
# box/lib/launcher.sh — argument parsing, fallback policy, project
# identity, supplementary GIDs, persistent config dirs, and the runsc DNS
# probe. Requires lib/preflight.sh (die, BOX_TOOL, box_realpath);
# never executed directly.
# shellcheck disable=SC2034,SC2154 # launcher-owned globals (runtime_args,
# launcher_rest, docker_cmd, ...) are set/consumed across the launcher and
# lib files; standalone analysis cannot see that.

[[ -n "${_BOX_LAUNCHER_LOADED:-}" ]] && return 0
_BOX_LAUNCHER_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# These deduplicate the argument loop, project identity, supplementary-GID
# handling, and the dry-run/assert/exec tail. Callers must define usage()
# before box_parse_launcher_args (it is invoked for --help/-h).

# Parse flags shared by all launchers. Sets globals: runtime_args (array),
# fallback_requested, explicit_runsc, dry_run, shell_mode, launcher_rest (array with the
# remaining args). Launcher flags (--docker-fallback, --runsc, --dry-run) must precede
# --shell: anything after --shell is shell/tool passthrough, so a launcher
# flag appearing there is a hard ordering error (fail-closed rather than
# silently swallowed). Callers continue with: set -- "${launcher_rest[@]}"
box_parse_launcher_args() {
  runtime_args=(--runtime=runsc)
  fallback_requested=0
  explicit_runsc=0
  dry_run=0
  shell_mode=0
  launcher_rest=()
  while (($#)); do
    case "$1" in
      --docker-fallback) runtime_args=(--runtime=runc); fallback_requested=1; explicit_runsc=0; shift ;;
      --runsc) runtime_args=(--runtime=runsc); fallback_requested=0; explicit_runsc=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --shell) shell_mode=1; shift; break ;;
      --help|-h) usage; exit 0 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  if ((shell_mode)); then
    # A launcher flag in the first position after --shell is almost certainly
    # a misordered launcher flag (it would otherwise be swallowed as shell
    # passthrough). Deeper positions are left alone: shell/tool commands may
    # legitimately contain such strings (e.g. `opencode --dry-run`).
    case "${1:-}" in
      --docker-fallback|--runsc|--dry-run)
        die "Place launcher flags before --shell: '$1' after --shell would be passed to the shell." ;;
    esac
  fi
  launcher_rest=("$@")
}

# Enforce the explicit-fallback kill-switch and print the downgrade WARNING.
# Usage: box_check_fallback <ALLOW_ENV_NAME>
# (e.g. box_check_fallback BOX_M_ALLOW_FALLBACK)
box_check_fallback() {
  local allow_env=${1:-}
  [[ -n "$allow_env" ]] || die 'Internal error: missing fallback env name.'
  if ((fallback_requested)); then
    # shellcheck disable=SC2086
    [[ "${!allow_env:-1}" != "0" ]] \
      || die "Hardened-runc fallback disabled via ${allow_env}=0."
    printf '%s: WARNING: using explicit hardened-runc fallback (no gVisor syscall interposition).\n' "$BOX_TOOL" >&2
  fi
}

# Resolve project/UID/GID, run the project preflight, and derive the
# per-project volume and container names. Container names use $RANDOM +
# timestamp only (no host PID leak via docker ps).
# Usage: box_project_identity <tool-prefix>  (e.g. box_project_identity box-m)
# Sets globals: project, host_uid, host_gid, project_hash, volume, container.
box_project_identity() {
  local prefix=${1:-} hash_full box_now
  [[ -n "$prefix" ]] || die 'Internal error: missing tool prefix.'
  project=$(pwd -P) || die 'Cannot resolve project directory.'
  host_uid=$(id -u) || die 'Cannot determine UID.'
  host_gid=$(id -g) || die 'Cannot determine GID.'
  box_preflight_project
  # Split off sha256sum's "  -" trailer instead of slicing blindly.
  hash_full=$(printf '%s' "$project" | sha256sum) \
    || die 'Cannot hash project path.'
  hash_full=${hash_full%% *}
  [[ "$hash_full" =~ ^[0-9a-f]{64}$ ]] || die 'Cannot hash project path.'
  project_hash=${hash_full:0:20}
  volume="${prefix}-u${host_uid}-g${host_gid}-${project_hash}"
  box_now=$(date +%s) || die 'Cannot generate container name.'
  container="${prefix}-u${host_uid}-${RANDOM}${RANDOM}${RANDOM}-${box_now}"
  case "$container" in *[!A-Za-z0-9_.-]*) die 'Internal error: invalid container name.';; esac
}

# Validate an opt-in supplementary-GID list and append --group-add flags to a
# caller-owned array (nameref, defaults to `args`). GID 0 is rejected: it is
# the root group on the bind mount.
# Usage: box_extra_gids <ENV_NAME> [ARRAY_NAME]
# (e.g. box_extra_gids BOX_M_EXTRA_GIDS)
box_extra_gids() {
  local env_name=${1:-} array_name=${2:-args} raw extra_gid
  local -a gid_list=()
  local -n gids_out="$array_name"
  [[ -n "$env_name" ]] || die 'Internal error: missing extra-GIDs env name.'
  raw=${!env_name:-}
  [[ -n "$raw" ]] || return 0
  [[ "$raw" =~ ^[0-9]+(,[0-9]+)*$ ]] \
    || die "$env_name must be comma-separated numeric GIDs."
  IFS=, read -r -a gid_list <<<"$raw"
  for extra_gid in "${gid_list[@]}"; do
    ((10#$extra_gid != 0)) || die "$env_name must not include GID 0."
    # Docker validates later, but fail closed here on values the kernel can
    # never hold (2^32-1 is -1/invalid; leading zeros stay decimal via 10#).
    ((10#$extra_gid <= 4294967294)) || die "$env_name GID out of range: $extra_gid."
    gids_out+=(--group-add "$extra_gid")
  done
}

box_ensure_persistent_config_dir() {
  # Tested shared helper for non-launcher consumers (config.bats). Launchers
  # intentionally use box_plan_directory + guarded box_prepare_directory
  # directly so --dry-run can plan without mutation and live runs can seed
  # between the two steps; behavior matches this helper's plan-then-prepare.
  local path
  path=$(box_plan_directory "$1") || return 1
  if [[ "${dry_run:-0}" == 0 ]]; then box_prepare_directory "$path" 700; else printf '%s' "$path"; fi
}

# Exclusive hard-link publication: concurrent launchers cannot replace a winner.
# Existing empty files are user state. Legacy empty JSON reseeding belongs to Muse.
box_seed_writable_config() (
  local src=${1:-} dest=${2:-} tmp
  [[ ! -L "$src" && ! -L "$dest" ]] || die 'Refusing symlink in seed-config paths.'
  [[ -f "$src" && -r "$src" ]] || die 'Invalid seed-config source.'
  [[ ! -e "$dest" || -f "$dest" ]] || die 'Seed-config destination must be a regular file.'
  if [[ ! -e "$dest" ]]; then
    tmp=$(mktemp "${dest%/*}/.box-seed.XXXXXX") || die 'Cannot stage seed.'
    trap 'rm -f -- "$tmp"' EXIT
    install -m "${3:-644}" -- "$src" "$tmp" || die 'Cannot stage seed.'
    ln -- "$tmp" "$dest" 2>/dev/null || [[ -f "$dest" && ! -L "$dest" ]] || die 'Cannot publish seed.'
  fi
  box_assert_owner_mode "$dest" 'Live configuration' nowrite
  [[ -w "$dest" ]] || die 'Seed-config destination is not writable.'
)

# Atomic compare-and-write primitive used by native package adapters (single "merge + write-if-changed" home; the jq
# native merges stay per-caller, the no-op compare + write lives here).
# No-op (no rewrite, mtime untouched) when the destination already holds
# <merged> (modulo the trailing newline added on write). Otherwise writes
# atomically via mktemp in the destination dir + rename (never truncates the
# live file, unlike `printf >"$dest"`), preserving the destination mode via
# chmod --reference. Manual cleanup (no trap) so caller EXIT traps are never
# cleared.
# Usage: box_write_if_changed <dest> <merged> <write-context>
# (e.g. box_write_if_changed "$dest" "$merged" "enforced settings")
box_write_if_changed() {
  local dest=${1:-} merged=${2:-} context=${3:-settings}
  [[ -n "$dest" ]] || die 'Internal error: missing write-if-changed destination.'
  local current tmp_dest dest_dir
  current=$(cat -- "$dest") || die "Cannot read persisted settings: $dest"
  [[ "$current" == "$merged" ]] && return 0
  dest_dir=$(dirname -- "$dest") || die "Cannot write $context: $dest"
  tmp_dest=$(mktemp "$dest_dir/.box-write.XXXXXX") || die "Cannot write $context: $dest"
  if ! printf '%s\n' "$merged" >"$tmp_dest"; then
    rm -f -- "$tmp_dest" || true
    die "Cannot write $context: $dest"
  fi
  chmod --reference="$dest" -- "$tmp_dest" \
    || { rm -f -- "$tmp_dest" || true; die "Cannot write $context: $dest"; }
  mv -f -- "$tmp_dest" "$dest" \
    || { rm -f -- "$tmp_dest" || true; die "Cannot write $context: $dest"; }
}

# Classify a probe-container exit code into a verdict string. Pure: prints
# `dns` or `startup` to stdout and never dies, so it is safe in $(...)
# captures (die there would exit only the subshell — same caveat as
# box_require_tool in lib/tools.sh). Takes ${1:-} with a safe default so
# `set -u` callers cannot fail.
# Mapping rule: 1/2 → `dns`, every other code → `startup`. Evidence: rc=2 is
# the proven genuine-DNS signal (fast ~0.4s, steady both tools); rc=1 is the
# repo's established stubbed-DNS convention; rc=125 is the proven runsc
# startup failure (`OCI runtime start failed`). Anything else (notably
# timeout-124) is by construction not proven resolution failure — genuine DNS
# failure returns in ~0.4s, so a timeout proves nothing about resolution —
# and must not wear the DNS NOTICE. rc=0 maps to `startup` only as a
# never-passed default: the success path returns before classification.
# See specs/handoff-probe.md.
# Usage: verdict=$(box_classify_probe_rc "$probe_rc")
box_classify_probe_rc() {
  local rc=${1:-}
  case "$rc" in
    1|2) printf 'dns' ;;
    *) printf 'startup' ;;
  esac
}

# Probe container DNS under runsc for caller-supplied hosts (required: each
# launcher passes its registry probe_hosts, so shared code holds no per-tool
# default).
# Daemon/image/network problems fail closed with remediation (they are NOT a
# probe verdict): only the container run itself yields a classifiable rc, so
# callers never misroute a broken setup into the runc fallback.
# Hosts are charset-validated (no injection into the probe shell). Uses
# globals docker_cmd, host_uid, host_gid. Returns the raw `timeout`/`docker
# run` rc (0 healthy; 1/2 in-container resolution failure; 125 startup
# failure; 124 timeout); callers classify via `box_classify_probe_rc` — the
# rc alone is not a DNS verdict.
# Usage: box_probe_runsc_dns <image> <network> <host...>
box_cleanup_dns_probe() {
  local probe_dir=$1 probe_cid
  shift
  if [[ -s "$probe_dir/cid" ]]; then
    read -r probe_cid < "$probe_dir/cid" || true
    if [[ "$probe_cid" =~ ^[0-9a-f]{64}$ ]]; then
      timeout --kill-after=2 5 "$@" rm -f -- "$probe_cid" >/dev/null 2>&1 ||
        printf '%s: WARNING: DNS probe cleanup failed for container %s; inspect and remove it explicitly.\n' "$BOX_TOOL" "$probe_cid" >&2
    fi
  fi
  rm -rf -- "$probe_dir"
}

box_probe_runsc_dns() {
  local image=${1:-} network=${2:-}
  [[ -n "$image" && -n "$network" ]] || die 'Internal error: missing DNS probe arguments.'
  shift 2
  (($# > 0)) || die 'Internal error: missing DNS probe hosts.'
  : "${BOX_DNS_PROBE_TIMEOUT:?caller must source lib/config.sh before lib/launcher.sh}"
  # shellcheck disable=SC2016 # '$host_uid/$host_gid' are intentional literals in this message.
  [[ -n "${host_uid:-}" && -n "${host_gid:-}" ]] || die 'Internal error: $host_uid/$host_gid unset.'
  local -a hosts=("$@")
  "${docker_cmd[@]}" info >/dev/null 2>&1 \
    || die 'Local Docker Engine is unavailable.'
  "${docker_cmd[@]}" image inspect -- "$image" >/dev/null 2>&1 \
    || die "Cannot inspect probe image $image; build it first."
  "${docker_cmd[@]}" network inspect -- "$network" >/dev/null 2>&1 \
    || die 'Create the dedicated network using the setup instructions.'
  local probe_cmd='' probe_host
  for probe_host in "${hosts[@]}"; do
    [[ "$probe_host" =~ ^[A-Za-z0-9.-]+$ ]] || die 'Internal error: invalid DNS probe host.'
    probe_cmd+="getent hosts $probe_host >/dev/null 2>&1 && "
  done
  probe_cmd=${probe_cmd% && }
  local probe_rc=0 probe_dir
  probe_dir=$(box_mktemp_dir box-dns-probe) || die 'Cannot create DNS probe tracking directory.'
  # Docker records the newly created container ID before starting it. Never
  # remove by a shared name or label: concurrent probes own different IDs.
  # Trap the calling shell itself: an extra subshell would orphan the probe
  # when only the launcher PID receives TERM. Save shell-generated trap code
  # in the private tracking directory; never evaluate external input.
  trap -p INT TERM HUP > "$probe_dir/traps"
  trap 'box_cleanup_dns_probe "$probe_dir" "${docker_cmd[@]}"; exit 130' INT
  trap 'box_cleanup_dns_probe "$probe_dir" "${docker_cmd[@]}"; exit 143' TERM
  trap 'box_cleanup_dns_probe "$probe_dir" "${docker_cmd[@]}"; exit 129' HUP
  timeout --kill-after=2 "$BOX_DNS_PROBE_TIMEOUT" "${docker_cmd[@]}" run --rm --pull=never --runtime=runsc \
    --cidfile "$probe_dir/cid" \
    --user "$host_uid:$host_gid" --cap-drop=ALL --security-opt=no-new-privileges \
    --memory="$BOX_CONTAINER_MEMORY" --memory-swap="$BOX_CONTAINER_MEMORY" \
    --cpus="$BOX_CONTAINER_CPUS" --pids-limit="$BOX_CONTAINER_PIDS" \
    --ipc=private --cgroupns=private --log-driver=none \
    --read-only --network="$network" --entrypoint=/bin/bash "$image" \
    -c "$probe_cmd" \
    >/dev/null 2>&1 || probe_rc=$?
  trap - INT TERM HUP
  # shellcheck disable=SC1091 # generated by trap -p above, private directory
  source "$probe_dir/traps"
  box_cleanup_dns_probe "$probe_dir" "${docker_cmd[@]}"
  return "$probe_rc"
}

# AUTO runtime: probe container DNS under runsc first, stay on gVisor when
# healthy, else auto-select hardened runc with a single NOTICE plus the
# standard fallback WARNING (never silent). The probe rc is classified via
# box_classify_probe_rc: 1/2 → DNS NOTICE, any other nonzero → startup NOTICE
# naming the exit code; both heal identically, only the words differ. With
# <allow_env>=0 a failed probe fails closed with remediation instead of
# launching a run that would fail opaquely inside (e.g. `device flow transport
# error` for the Muse device flow, `failed to fetch model catalog` for TUI
# runs; startup verdicts add runsc/Engine version checks). The optional
# <context> names the run in both messages (default '`login`'); callers pass
# probe hosts after it (required: each launcher passes its registry
# probe_hosts).
# Honors explicit --runsc (no probe, stay on gVisor). Callers must skip
# calling under --dry-run (no daemon contact), explicit --docker-fallback,
# and --shell runs (explicit-only diagnostics path); see
# box_maybe_auto_runtime for that gate. Sets globals: runtime_args,
# fallback_requested.
# Usage: box_auto_runtime <image> <network> <ALLOW_ENV_NAME> [context] <host...>
# (e.g. box_auto_runtime "$image" box-m BOX_M_ALLOW_FALLBACK 'this run' auth.meta.com)
box_auto_runtime() {
  # shellcheck disable=SC2016 # backticks in the default context are an intentional literal.
  local image=${1:-} network=${2:-} allow_env=${3:-} context=${4:-'`login`'}
  [[ -n "$image" && -n "$network" && -n "$allow_env" && -n "$context" ]] || die 'Internal error: missing auto-runtime arguments.'
  local -a probe_hosts=("${@:5}")
  ((explicit_runsc == 0)) || return 0
  local probe_rc=0
  box_probe_runsc_dns "$image" "$network" "${probe_hosts[@]}" || probe_rc=$?
  # Cancellation is user intent, never evidence for starting a fallback run.
  case "$probe_rc" in 129|130|143) exit "$probe_rc" ;; esac
  ((probe_rc == 0)) && return 0
  local verdict
  verdict=$(box_classify_probe_rc "$probe_rc")
  # shellcheck disable=SC2086
  if [[ "${!allow_env:-1}" == "0" ]]; then
    case "$verdict" in
      dns) die "runsc container DNS unreachable and fallback disabled via ${allow_env}=0; refusing to start $context." ;;
      *) die "runsc failed to start or complete probe containers (exit $probe_rc) and fallback disabled via ${allow_env}=0; refusing to start $context (check 'runsc --version', the daemon log, and runsc/Engine version compatibility)." ;;
    esac
  fi
  case "$verdict" in
    dns)
      printf '%s: NOTICE: container DNS unreachable under runsc; auto-selecting hardened-runc fallback for %s.\n' "$BOX_TOOL" "$context" >&2
      ;;
    *)
      printf '%s: NOTICE: runsc failed to start or complete probe containers (exit %s); auto-selecting hardened-runc fallback for %s.\n' "$BOX_TOOL" "$probe_rc" "$context" >&2
      ;;
  esac
  runtime_args=(--runtime=runc)
  fallback_requested=1
  box_check_fallback "$allow_env"
}

# Shared AUTO-runtime gate for tool/TUI runs (all launchers). Skips the
# probe unless this is a live run with no explicit runtime choice: --dry-run
# (no daemon contact), --docker-fallback, --runsc, and --shell runs (the
# explicit-only diagnostic/verify path) all return unchanged. Otherwise
# delegates to box_auto_runtime, so a broken runsc DNS heals to
# hardened runc with NOTICE + WARNING while the healthy path stays on runsc
# with no output change (it still pays one probe-container round trip).
# Reads globals dry_run, fallback_requested, shell_mode, explicit_runsc.
# Usage: box_maybe_auto_runtime <image> <network> <ALLOW_ENV_NAME> [context] [host...]
box_maybe_auto_runtime() {
  ((dry_run == 0)) && ((fallback_requested == 0)) && ((shell_mode == 0)) && ((explicit_runsc == 0)) || return 0
  box_auto_runtime "$@"
}
