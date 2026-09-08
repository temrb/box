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

# Parse flags shared by both launchers. Sets globals: runtime_args (array),
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

# Ensure a global persistent tool-config dir exists (e.g. Muse auth.json +
# .trust.json). Creates mode-700 if missing, repairs mode, refuses symlinks,
# enforces owner + outside-project, rejects commas/newlines (Docker mount).
# Prints the canonical path to stdout.
# Usage: resolved=$(box_ensure_persistent_config_dir "$raw")
# Reads globals: project (when set), host_uid, HOME.
box_ensure_persistent_config_dir() {
  local raw=${1:-} resolved
  [[ -n "$raw" ]] || die 'Empty persistent config path.'
  case "$raw" in *','*|*$'\n'*) die 'Persistent config path must not contain commas or newlines.';; esac
  [[ ! -L "$raw" ]] || die "Persistent config path must not be a symlink: $raw"
  [[ -n "${HOME:-}" ]] || die 'HOME is unset.'
  # shellcheck disable=SC2016 # '$host_uid' is an intentional literal in this message.
  [[ -n "${host_uid:-}" ]] || die 'Internal error: $host_uid is unset.'
  install -d -m 700 -- "$raw" \
    || die "Cannot create persistent config dir: $raw"
  chmod 700 -- "$raw" \
    || die "Cannot secure persistent config dir: $raw"
  resolved=$(box_realpath -e -- "$raw") || die 'Cannot resolve persistent config path.'
  case "$resolved" in *','*|*$'\n'*) die 'Invalid persistent config mount path.';; esac
  box_assert_outside_project "$resolved" 'Persistent config'
  box_assert_owner_mode "$resolved" 'Persistent config dir' dir700
  printf '%s' "$resolved"
}

# Seed a writable tool settings file into the persistent config dir on first
# use (e.g. Muse settings.json). Parent dir must exist (callers ensure it
# first). Existing user state is never overwritten: in-container /models
# changes persist across runs. An empty dest holds no state, so it is always
# (re)seeded — this also repairs the empty root-owned file left
# by the retired file-inside-dir bind quirk (docker created one on every run
# while the readonly file bind overlapped this dir). Refuses symlinks,
# non-regular dests, missing sources, and unwritable results.
# Usage: box_seed_writable_config <src> <dest>
box_seed_writable_config() {
  local src=${1:-} dest=${2:-}
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing seed-config paths.'
  [[ ! -L "$src" && ! -L "$dest" ]] || die "Refusing to follow symlink in seed-config paths: $dest"
  [[ -f "$src" && -r "$src" ]] || die "Cannot read seed-config source: $src"
  [[ ! -e "$dest" || -f "$dest" ]] || die "Seed-config destination must not be a directory: $dest"
  if [[ -f "$dest" && ! -s "$dest" ]]; then
    rm -f -- "$dest" || die "Cannot remove empty seed-config file: $dest"
  fi
  if [[ ! -e "$dest" ]]; then
    install -m 644 -- "$src" "$dest" || die "Cannot seed writable config: $dest"
  fi
  [[ -f "$dest" && -w "$dest" ]] || die "Seed-config destination is not writable: $dest"
}

# Re-assert the safety-critical settings keys from the seed source into the
# persisted writable copy on every launch. The persisted file stays
# user-writable by design (in-container /models changes persist), so without
# this an in-container agent could durably weaken approval_mode,
# approval_judge, telemetry.enabled, or api.base_url. Only those four keys
# are reverted to the seed values; model, reasoning_effort, and unknown keys
# are preserved (reasoning_effort drift still fails verify: pin+detect).
# Fails closed on missing jq, non-object JSON, or a seed lacking any
# enforced key. No-op (no rewrite, mtime untouched) when already compliant.
# Usage: box_enforce_safe_settings <seed_src> <persisted_dest>
box_enforce_safe_settings() {
  local src=${1:-} dest=${2:-} merged current
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing enforce-settings paths.'
  command -v jq >/dev/null || die 'jq is required (documented host prerequisite).'
  [[ ! -L "$src" && ! -L "$dest" ]] || die "Refusing to follow symlink in enforce-settings paths: $dest"
  [[ -f "$src" && -r "$src" ]] || die "Cannot read seed-config source: $src"
  [[ -f "$dest" && -w "$dest" ]] || die "Enforce-settings destination is not a writable file: $dest"
  jq -e 'has("approval_mode") and has("approval_judge") and has("telemetry") and (.telemetry|has("enabled")) and has("api") and (.api|has("base_url"))' -- "$src" >/dev/null \
    || die "Seed-config source lacks enforced safety keys: $src"
  jq -e 'type == "object"' -- "$dest" >/dev/null \
    || die "Persisted settings is not a JSON object (delete it to reseed): $dest"
  merged=$(jq -s -e '
    .[0] as $seed | .[1] as $user |
    $user * {
      approval_mode: $seed.approval_mode,
      approval_judge: $seed.approval_judge,
      telemetry: ((($user.telemetry // {}) | if type == "object" then . else {} end) * {enabled: $seed.telemetry.enabled}),
      api: ((($user.api // {}) | if type == "object" then . else {} end) * {base_url: $seed.api.base_url})
    }' -- "$src" "$dest") || die "Cannot merge enforced safety keys into: $dest"
  current=$(cat -- "$dest") || die "Cannot read persisted settings: $dest"
  [[ "$current" == "$merged" ]] || printf '%s\n' "$merged" >"$dest" \
    || die "Cannot write enforced settings: $dest"
}

# Probe container DNS under runsc for caller-supplied hosts (required: each
# launcher passes its registry probe_hosts, so shared code holds no per-tool
# default).
# Daemon/image/network problems fail closed with remediation (they are NOT a
# DNS verdict): only a healthy-daemon probe that cannot resolve counts as DNS
# failure, so callers never misroute a broken setup into the runc fallback.
# Hosts are charset-validated (no injection into the probe shell). Uses
# globals docker_cmd, host_uid, host_gid. Returns 0 when every host resolves,
# nonzero on DNS failure/timeout.
# Usage: box_probe_runsc_dns <image> <network> <host...>
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
  timeout "$BOX_DNS_PROBE_TIMEOUT" "${docker_cmd[@]}" run --rm --pull=never --runtime=runsc \
    --user "$host_uid:$host_gid" --cap-drop=ALL --security-opt=no-new-privileges \
    --read-only --network="$network" --entrypoint=/bin/bash "$image" \
    -c "$probe_cmd" \
    >/dev/null 2>&1
}

# Match a Meta device-flow URL in one tool-output line and split out the
# short code. Prints "<url>\n<code>" and returns 0 on match, 1 otherwise.
# The matcher lives here (not in box-m-login) so the path/query tolerance and
# the code charset stay in one tested place: the path/query after
# /oauth/device/ is loosened (extra params allowed) and the code charset
# covers `-_.~` (upstream may rotate formats). Only trailing
# quote/punctuation is stripped (extglob `+()` anchored at the end): a plain
# `%%[set]*` would cut at the first dot inside the URL itself. The short code
# is additionally cut at the first `&`.
# Usage: if probe_out=$(box_device_url_code "$line"); then
#          url=${probe_out%%$'\n'*}; code=${probe_out#*$'\n'}; ...
box_device_url_code() {
  local line=${1:-} url code extglob_was_off=0
  local device_url_re="https://auth\\.meta\\.com/oauth/device/\\?[^[:space:]\"']*code=[A-Za-z0-9_~.-]+"
  [[ "$line" =~ $device_url_re ]] || return 1
  url=${BASH_REMATCH[0]}
  shopt -q extglob || { extglob_was_off=1; shopt -s extglob; }
  url=${url%%+([\"\'\)\.,\;\!\?])}
  if ((extglob_was_off)); then shopt -u extglob; fi
  code=${url##*code=}
  code=${code%%\&*}
  [[ -n "$url" && -n "$code" ]] || return 1
  printf '%s\n%s\n' "$url" "$code"
}
# AUTO runtime: probe container DNS under runsc first, stay on gVisor when
# healthy, else auto-select hardened runc with a single NOTICE plus the
# standard fallback WARNING (never silent). With <allow_env>=0 a failed
# probe fails closed with remediation instead of launching a run that would
# fail opaquely inside (e.g. `device flow transport error` for the Muse
# device flow, `failed to fetch model catalog` for TUI runs). The optional
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
  if box_probe_runsc_dns "$image" "$network" "${probe_hosts[@]}"; then
    return 0
  fi
  # shellcheck disable=SC2086
  if [[ "${!allow_env:-1}" == "0" ]]; then
    die "runsc container DNS unreachable and fallback disabled via ${allow_env}=0; refusing to start $context."
  fi
  printf '%s: NOTICE: container DNS unreachable under runsc; auto-selecting hardened-runc fallback for %s.\n' "$BOX_TOOL" "$context" >&2
  runtime_args=(--runtime=runc)
  fallback_requested=1
  box_check_fallback "$allow_env"
}

# Shared AUTO-runtime gate for tool/TUI runs (both launchers). Skips the
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
