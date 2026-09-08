# shellcheck shell=bash
# box/lib/preflight.sh — project/credential/version/config validators.
# Sourced first by every entry point (defines die() plus portable helpers).
# Never executed directly and never echoes secret values. Callers must set
# BOX_TOOL before sourcing and set project/host_uid/host_gid before
# calling the preflight functions.
# All functions die (non-zero exit) on violation: fail-closed by design.
# Linux-only (stat -c, realpath/readlink -f, date +%s): macOS unsupported.

[[ -n "${_BOX_PREFLIGHT_LOADED:-}" ]] && return 0
_BOX_PREFLIGHT_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

die() { printf '%s: %s\n' "$BOX_TOOL" "$*" >&2; exit 1; }

# Generic parsed-pin map (KEY -> value), reset by every box_load_version_file
# call. -g: helpers.bash sources lib files inside setup(), where a plain
# declare would scope this local.
declare -gA box_file_pin=()

# Portable canonicalizer: realpath preferred, readlink -f fallback, python3
# last resort. Fails closed when nothing is available.
# Usage: box_realpath [-e|-m] -- <path>  (flags mirror realpath)
box_realpath() {
  local mode="--" path
  case "${1:-}" in -e|-m) mode="$1"; shift ;; esac
  [[ "${1:-}" == "--" ]] && shift
  path=${1:-}
  [[ -n "$path" ]] || die 'Internal error: missing realpath path.'
  if command -v realpath >/dev/null 2>&1; then
    realpath "$mode" -- "$path"
    return
  fi
  if command -v readlink >/dev/null 2>&1; then
    case "$mode" in
      -e) readlink -e -- "$path" ;;
      -m) readlink -m -- "$path" 2>/dev/null || readlink -f -- "$path" ;;
      *) readlink -f -- "$path" ;;
    esac
    return
  fi
  command -v python3 >/dev/null 2>&1 \
    || die 'Cannot canonicalize path: realpath, readlink, and python3 are all missing.'
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path"
}

# mktemp honoring TMPDIR (never hardcoded /tmp for non-secrets; secrets use
# ${TMPDIR:-$HOME/.cache} via the caller).
# Usage: box_mktemp_file <template-prefix> / box_mktemp_dir <template-prefix>
box_mktemp_file() {
  local prefix=${1:-box-tmp}
  mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}
box_mktemp_dir() {
  local prefix=${1:-box-tmp}
  mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# Shared closed denylist (exact + subpaths), used for both the project itself
# and project-symlink targets so the two can never drift apart.
# /home is exact-only: subdirectories of $HOME are legitimate project
# locations (guarded by the $HOME + credential checks); rejecting /home/*
# would make ~/projects unusable. /srv, /data, and /workspace are
# exact+subpaths: they are conventional service/data roots, never a single
# dev project. /snap covers Ubuntu snap mounts.
# Usage: box_denylisted_system_path <path>  (returns 0 when denylisted)
box_denylisted_system_path() {
  case "${1:-}" in
    /|/home|/root|/root/*|/etc|/etc/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*|/var/run|/var/run/*|/usr|/usr/*|/boot|/boot/*|/var|/var/*|/tmp|/tmp/*|/opt|/opt/*|/mnt|/mnt/*|/media|/media/*|/snap|/snap/*|/srv|/srv/*|/data|/data/*|/workspace|/workspace/*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# Project denylist step. Reads global: project. No arguments.
box_preflight_denylist() {
  if box_denylisted_system_path "$project"; then
    die 'Choose one project directory, not a host system directory.'
  fi
}

# $HOME step: rejects the home itself and projects containing it.
# Compare physical paths: a symlinked $HOME would otherwise evade the guard.
# Sets global: box_physical_home (for the symlink step). No arguments.
# Reads globals: project, HOME.
box_preflight_home() {
  [[ -n "${HOME:-}" ]] || die 'HOME is unset.'
  box_physical_home=$(box_realpath -e -- "$HOME") || die 'Cannot resolve host home directory.'
  case "$project" in "$box_physical_home")
    die 'Choose one project directory, not your entire home directory.' ;;
  esac
  case "$box_physical_home/" in "$project/"*) die 'The project must not contain your home directory.';; esac
}

# Credential-dir step: the 7 credential paths are protected together with
# their physical symlink targets, in both directions (project is
# target/under-target, or target is under project). Subdirectories of the
# home stay legitimate project locations.
# Sets global: box_credential_targets (array, for the symlink step).
# Reads globals: project, HOME. No arguments.
box_preflight_credentials() {
  local credential_dir resolved
  box_credential_targets=()
  for credential_dir in .ssh .gnupg .aws .docker .git-credentials .netrc .config/gcloud; do
    if [[ -e "$HOME/$credential_dir" || -L "$HOME/$credential_dir" ]]; then
      resolved=$(box_realpath -e -- "$HOME/$credential_dir") \
        || die "Cannot resolve the $credential_dir path."
      box_credential_targets+=("$resolved")
      case "$project" in "$resolved"|"$resolved/"*)
        die 'Choose one project directory, not a credential directory.' ;;
      esac
      case "$resolved/" in "$project/"*)
        die 'The project would contain a credential path.' ;;
      esac
    fi
  done
}

# Explicit tool-directory guard (fail-closed even without the credentials
# file): the project must not be the shared secret dir, either tool config
# dir, or the launcher install dir — and must not contain them.
# Compares against the physical $HOME like the sibling steps so a symlinked
# $HOME cannot evade the guard in either direction.
# Reads globals: project, HOME, box_physical_home (when set). No arguments.
box_preflight_tool_dirs() {
  local tool_dir physical_home=${box_physical_home:-}
  [[ -n "${HOME:-}" ]] || die 'HOME is unset.'
  if [[ -z "$physical_home" ]]; then
    physical_home=$(box_realpath -e -- "$HOME") || die 'Cannot resolve host home directory.'
  fi
  for tool_dir in "$physical_home/.config/box" "$physical_home/.config/box-m" "$physical_home/.config/box-o" "$physical_home/.local/bin"; do
    case "$project" in "$tool_dir"|"$tool_dir/"*)
      die 'Choose one project directory, not a sandbox tool directory.' ;;
    esac
    case "$tool_dir/" in "$project/"*)
      die 'The project would contain a sandbox tool directory.' ;;
    esac
  done
}

# IPC step: prevent inclusion of existing host service sockets, devices, or
# FIFOs through the bind mount. Best-effort and check-then-mount by nature: a
# socket created after this preflight still lands in the bind mount, so
# keep IPC endpoints out of project trees as a workflow rule.
# `-print -quit` short-circuits on the first hit; the healthy path still
# walks the whole tree once per launch — the accepted price of the absence
# proof (pruning heavy dirs would fail open on sockets hidden inside them).
# Reads global: project. No arguments.
box_preflight_ipc() {
  local special
  special=$(find "$project" -xdev \( -type s -o -type b -o -type c -o -type p \) -print -quit) \
    || die 'Cannot inspect project for host sockets/devices.'
  [[ -z "$special" ]] || die 'Project contains a socket/device/FIFO; keep host IPC endpoints outside it.'
}

# Bounded defense-in-depth symlink scan. Project symlinks resolve inside
# container namespaces (not to host paths), so this is best-effort hygiene
# against confusing host-side tooling — not a container-escape boundary.
# The scan is capped so link-heavy trees (e.g. node_modules/.bin) stay
# fast; truncation warns instead of failing. Exit 141 (SIGPIPE from
# find|head on large trees under pipefail) is treated as truncation, not
# as an inspection failure; other non-zero statuses still fail closed.
# Reads globals: project, box_physical_home, box_credential_targets.
# No arguments.
box_preflight_symlinks() {
  local link target sens symlink_list symlink_checked symlink_rc
  # find|head must run under pipefail so a find permission-denied cannot
  # fail open as an empty list (head's status would mask it otherwise).
  # pipefail is forced subshell-scoped: no global option to save/restore.
  symlink_list=$(set -o pipefail; find "$project" -xdev -type l -print | head -n 501) || symlink_rc=$?
  symlink_rc=${symlink_rc:-0}
  ((symlink_rc == 0 || symlink_rc == 141)) || die 'Cannot inspect project for symlinks.'
  symlink_checked=0
  while IFS= read -r link; do
    [[ -n "$link" ]] || continue
    symlink_checked=$((symlink_checked + 1))
    if ((symlink_checked > 500)); then
      printf '%s: WARNING: project contains more than 500 symlinks; symlink scan truncated (best-effort).\n' "$BOX_TOOL" >&2
      break
    fi
    target=$(box_realpath -m -- "$link") \
      || die "Cannot resolve project symlink: $link"
    if box_denylisted_system_path "$target"; then
      die "Project symlink points at a host system path: $link"
    fi
    [[ "$target" != "$box_physical_home" ]] \
      || die "Project symlink points at your home directory: $link"
    for sens in "${box_credential_targets[@]}"; do
      [[ "$target" != "$sens" && "$target" != "$sens/"* ]] \
        || die "Project symlink points at a credential path: $link"
    done
  done <<<"$symlink_list"
}

# Git step: prevent external Git metadata escapes from linked worktrees.
# Canonicalize both dirs with realpath -m so ../ and symlink escapes cannot
# evade the under-$project check (rev-parse may return relative paths).
# NOTE: this inspects .git in the current directory; the launchers always
# run with CWD == $project, so that is the mounted directory. A
# subdirectory run mounts only that subdirectory (see docs/operations.md §9).
# Unset GIT_* overrides first: an exported GIT_DIR/WORK_TREE/COMMON_DIR/
# CEILING/INDEX_FILE would otherwise redirect rev-parse outside the project
# and poison the worktree check.
# Reads global: project. No arguments.
box_preflight_git() {
  local gitdir common_raw common
  if [[ -e .git || -L .git ]]; then
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES GIT_INDEX_FILE
    gitdir=$(git -c safe.directory='*' rev-parse --absolute-git-dir) || die 'Cannot resolve .git.'
    gitdir=$(box_realpath -m -- "$gitdir") || die 'Cannot canonicalize Git dir.'
    common_raw=$(git -c safe.directory='*' rev-parse --git-common-dir) || die 'Cannot resolve Git common dir.'
    case "$common_raw" in /*) common=$(box_realpath -m -- "$common_raw") ;; *) common=$(box_realpath -m -- "$project/$common_raw") ;; esac \
      || die 'Cannot canonicalize Git common dir.'
    case "$gitdir/" in "$project/"*) ;; *) die 'Use a standalone clone: this worktree has external Git metadata.';; esac
    case "$common/" in "$project/"*) ;; *) die 'Use a standalone clone: this worktree shares external Git metadata.';; esac
  fi
}

# Closed denylist + $HOME/credential-dir + IPC + symlink + git-worktree preflight.
# Thin ordering wrapper over the per-concern steps above (each step is also
# unit-testable on its own). Reads globals: project, HOME, host_uid, host_gid.
# No arguments.
box_preflight_project() {
  # shellcheck disable=SC2016 # '$project' is an intentional literal in this message.
  [[ -n "${project:-}" ]] || die 'Internal error: $project is unset.'
  # host_uid/host_gid are caller-provided globals (set by the launcher).
  # shellcheck disable=SC2154
  ((host_uid > 0 && host_gid > 0)) || die 'Run as your normal non-root host user.'
  box_preflight_denylist
  box_preflight_home
  box_preflight_credentials
  case "$project" in *','*|*$'\n'*) die 'Docker mount paths must not contain commas or newlines.';; esac
  box_preflight_tool_dirs
  box_preflight_ipc
  box_preflight_symlinks
  box_preflight_git
}

# Outside-project guard: when $project is set (launchers always set it via
# box_project_identity before any config/version/credential load), the
# path must lie outside it — an in-project file would stay agent-rewritable
# via /workspace. When $project is unset (setup.sh, check-pins.sh, unit
# tests), there is no project to be inside of, so the check is vacuous.
# Usage: box_assert_outside_project <resolved-path> <label>
box_assert_outside_project() {
  local path=${1:-} label=${2:-File}
  [[ -n "$path" && -n "$label" ]] || die 'Internal error: missing outside-project arguments.'
  if [[ -n "${project:-}" ]]; then
    case "$path" in "$project"|"$project/"*) die "$label must be outside the project.";; esac
  fi
}

# Owner + mode guard shared by the config/version/credential/persist-dir
# checks (4x duplicated stat blocks unified here).
# Usage: box_assert_owner_mode <path> <What> <policy>
#   What:   'Configuration file' | 'Pinned-version file' | 'Credentials file'
#           | 'Persistent config dir' (drives the message nouns)
#   policy: nowrite (no group/other write bits) | creds (exactly 600, 400 also
#           accepted) | dir700 (exactly 700)
# Reads global: host_uid.
box_assert_owner_mode() {
  local path=${1:-} what=${2:-File} policy=${3:-nowrite} fuid fmode
  [[ -n "$path" && -n "$what" ]] || die 'Internal error: missing owner/mode arguments.'
  case "$policy" in
    nowrite|creds|dir700) : ;;
    *) die 'Internal error: unknown owner/mode policy.' ;;
  esac
  fuid=$(stat -c %u -- "$path") || die "Cannot stat ${what,,}."
  [[ "$fuid" =~ ^[0-9]+$ ]] || die "Cannot stat ${what,,}."
  ((fuid == host_uid)) || die "$what must be owned by you."
  fmode=$(stat -c %a -- "$path") || die "Cannot stat ${what,,}."
  case "$policy" in
    nowrite) (( (8#$fmode & 022) == 0 )) || die "$what must not be group/other-writable." ;;
    creds) [[ "$fmode" == 600 || "$fmode" == 400 ]] || die "Set ${what,,} mode to 600 (400 also accepted)." ;;
    dir700) [[ "$fmode" == 700 ]] || die "$what must be mode 700." ;;
  esac
}

# Resolve a tool config path: must exist/readable, canonicalized with
# realpath -e, no commas/newlines, owned by the invoking user, not
# group/other-writable, and outside the project (a config inside $project
# would stay writable via the /workspace bind even though its
# /home/box/... mount is readonly, letting the agent rewrite its own
# config). Prints the resolved path to stdout.
# Usage: resolved=$(box_resolve_config "$raw")
# Reads globals: project (when set), host_uid.
box_resolve_config() {
  local raw=${1:-} resolved
  [[ -n "$raw" ]] || die 'Empty configuration path.'
  [[ -f "$raw" && -r "$raw" ]] || die "Missing readable configuration: $raw"
  resolved=$(box_realpath -e -- "$raw") || die 'Cannot resolve configuration path.'
  case "$resolved" in *','*|*$'\n'*) die 'Invalid configuration mount path.';; esac
  box_assert_outside_project "$resolved" 'Tool configuration'
  if [[ -n "${host_uid:-}" ]]; then
    box_assert_owner_mode "$resolved" 'Configuration file' nowrite
  fi
  printf '%s' "$resolved"
}

# Parse a pinned-version file (LF-only, `#` comments, literal KEY=value).
# The file is canonicalized, must sit outside the project when $project is
# known (an in-project pin file would be agent-rewritable via /workspace),
# and must be owned by the invoking user without group/other write bits.
# The parser branches on pin-file FORMAT, never on tool name: callers pass
# the registry version_format + pin_keys for their tool id, so a new tool
# reusing a format needs no parser change. Duplicate keys are last-wins.
# Formats (positional key semantics):
#   sha-pinned: <VERSION> <SHA256_AMD64> <SHA256_ARM64>
#   npm-pinned: <VERSION> <NPM_INTEGRITY> <NPM_INTEGRITY_LINUX_X64>
#               <NPM_INTEGRITY_LINUX_ARM64> <NODE_VERSION> <NODESOURCE_FINGERPRINT>
# Usage: box_load_version_file <file> <sha-pinned|npm-pinned> <KEY...>
# Sets: box_file_version plus positional globals (box_file_sha_amd64,
#   box_file_sha_arm64 | box_file_npm_integrity, box_file_npm_integrity_x64,
#   box_file_npm_integrity_arm64, box_file_node_version,
#   box_file_nodesource_fpr) and the generic box_file_pin[KEY]=value map.
# Reads globals: project (when set), host_uid (when set).
box_load_version_file() {
  local version_file=${1:-} format=${2:-}
  shift 2 || die 'Internal error: missing version allowlist.'
  (($# > 0)) || die 'Internal error: empty version allowlist.'
  local line key value allow_key
  [[ -n "$version_file" ]] || die 'Empty version-file path.'
  case "$format" in
    sha-pinned) (($# == 3)) || die 'Internal error: sha-pinned needs exactly 3 version keys.' ;;
    npm-pinned) (($# == 6)) || die 'Internal error: npm-pinned needs exactly 6 version keys.' ;;
    *) die 'Internal error: unknown version format.' ;;
  esac
  local -A allowlist=()
  local -a ordered_keys=()
  for allow_key in "$@"; do
    [[ "$allow_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 'Internal error: invalid version allowlist entry.'
    [[ -z "${allowlist[$allow_key]:-}" ]] || die 'Internal error: duplicate version allowlist entry.'
    allowlist[$allow_key]=1
    ordered_keys+=("$allow_key")
  done
  [[ -r "$version_file" ]] || die "Missing readable pinned-version file: $version_file"
  version_file=$(box_realpath -e -- "$version_file") || die 'Cannot resolve pinned-version file.'
  box_assert_outside_project "$version_file" 'Pinned-version file'
  if [[ -n "${host_uid:-}" ]]; then
    box_assert_owner_mode "$version_file" 'Pinned-version file' nowrite
  fi
  box_file_version='' box_file_sha_amd64='' box_file_sha_arm64=''
  box_file_npm_integrity='' box_file_npm_integrity_x64='' box_file_npm_integrity_arm64=''
  box_file_node_version='' box_file_nodesource_fpr=''
  box_file_pin=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" != *$'\r'* ]] || die "CRLF line endings are not allowed in $version_file (use LF only)."
    [[ "$line" == *=* ]] || die "Invalid line in $version_file."
    key=${line%%=*}
    value=${line#*=}
    [[ -n "${allowlist[$key]:-}" ]] || die "Unsupported entry in $version_file: $key"
    box_file_pin[$key]=$value
  done < "$version_file"
  if [[ "$format" == sha-pinned ]]; then
    box_file_version=${box_file_pin[${ordered_keys[0]}]:-}
    box_file_sha_amd64=${box_file_pin[${ordered_keys[1]}]:-}
    box_file_sha_arm64=${box_file_pin[${ordered_keys[2]}]:-}
    [[ "$box_file_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] \
      || die "Invalid ${ordered_keys[0]} in $version_file."
    [[ "$box_file_sha_amd64" =~ ^[0-9a-f]{64}$ ]] \
      || die "Invalid ${ordered_keys[1]} in $version_file."
    [[ "$box_file_sha_arm64" =~ ^[0-9a-f]{64}$ ]] \
      || die "Invalid ${ordered_keys[2]} in $version_file."
  else
    box_file_version=${box_file_pin[${ordered_keys[0]}]:-}
    box_file_npm_integrity=${box_file_pin[${ordered_keys[1]}]:-}
    box_file_npm_integrity_x64=${box_file_pin[${ordered_keys[2]}]:-}
    box_file_npm_integrity_arm64=${box_file_pin[${ordered_keys[3]}]:-}
    box_file_node_version=${box_file_pin[${ordered_keys[4]}]:-}
    box_file_nodesource_fpr=${box_file_pin[${ordered_keys[5]}]:-}
    [[ "$box_file_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || die "Invalid ${ordered_keys[0]} in $version_file."
    [[ "$box_file_npm_integrity" =~ ^sha512-[A-Za-z0-9+/=]+$ ]] \
      || die "Invalid ${ordered_keys[1]} in $version_file."
    [[ "$box_file_npm_integrity_x64" =~ ^sha512-[A-Za-z0-9+/=]+$ ]] \
      || die "Invalid ${ordered_keys[2]} in $version_file."
    [[ "$box_file_npm_integrity_arm64" =~ ^sha512-[A-Za-z0-9+/=]+$ ]] \
      || die "Invalid ${ordered_keys[3]} in $version_file."
    [[ "$box_file_node_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+nodesource1$ ]] \
      || die "Invalid ${ordered_keys[4]} in $version_file."
    # The -[0-9]+ revision intentionally accepts upstream NodeSource rebuilds
    # (e.g. -2nodesource1); only the trailing `nodesource1` distributor tag is
    # pinned, so a rebuild revision bumps the pin without a regex change.
    [[ "$box_file_nodesource_fpr" =~ ^[0-9A-F]{40}$ ]] \
      || die "Invalid ${ordered_keys[5]} in $version_file."
  fi
}

# Reports whether <path> holds at least one active allowlisted KEY=value line
# under the same shape rules the loader accepts (literal KEY=value, valid key
# charset, non-empty value, no CR). Comments/blanks are skipped; malformed
# lines are ignored here (the loader fails closed on them at launch with a
# precise error), so this stays a presence probe, never a validator.
# Usage: box_credentials_filled <path> <ALLOWED_KEY...>
# Returns 0 when filled, 1 otherwise (safe under `set -e` in `if` tests).
box_credentials_filled() {
  local file=${1:-}
  shift || die 'Internal error: missing credential allowlist.'
  (($# > 0)) || die 'Internal error: empty credential allowlist.'
  local key value line allow_key found=0
  local -A allowlist=()
  for allow_key in "$@"; do
    [[ "$allow_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 'Internal error: invalid credential allowlist entry.'
    allowlist[$allow_key]=1
  done
  [[ -f "$file" && -r "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* && "$line" != *$'\r'* ]] || continue
    key=${line%%=*}
    value=${line#*=}
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -n "$value" && -n "${allowlist[$key]:-}" ]] || continue
    found=1
    break
  done < "$file"
  ((found))
}
# Parse literal KEY=value credentials; never source the file. Fail-closed
# except under --dry-run (dry_run=1 skips all file access). Unknown keys
# hard-FAIL. Allowed keys are exported (last-wins on duplicates); callers
# pass them into the container by name only (--env NAME, never =value).
# Inherited allowlisted variables are unset first so host-injected values
# cannot bypass owner/mode/parse checks. Under --dry-run no keys are
# exported, so forward loops pass nothing.
# Symlink policy (deliberately unlike seed/enforce, which refuse symlinks):
# the credentials path is resolved with realpath -e and every guard below
# (outside-project, owner, mode 600/400) runs on the RESOLVED path, so a
# symlink can only point at a file that passes the same checks a direct
# path would (dotfile-managed providers.env keeps working).
# Usage: box_load_credentials <path> <dry_run:0|1> <ALLOWED_KEY...>
# Reads globals: project, host_uid.
box_load_credentials() {
  local credentials=${1:-} dry_run=${2:-0}
  shift 2 || die 'Internal error: missing credential allowlist.'
  (($# > 0)) || die 'Internal error: empty credential allowlist.'
  local key value line allow_key
  local -A allowlist=()
  for allow_key in "$@"; do
    [[ "$allow_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 'Internal error: invalid credential allowlist entry.'
    allowlist[$allow_key]=1
    unset "$allow_key"
  done
  ((dry_run)) && return 0
  [[ -n "$credentials" ]] || die 'Empty credentials path.'
  case "$credentials" in *$'\n'*) die 'Invalid credentials path.';; esac
  [[ -e "$credentials" ]] || die "Missing credentials file: $credentials (create mode-600 providers.env)."
  credentials=$(box_realpath -e -- "$credentials") \
    || die 'Cannot resolve credentials path.'
  box_assert_outside_project "$credentials" 'Provider credentials'
  [[ -f "$credentials" && -r "$credentials" ]] || die 'Credentials file is not readable.'
  box_assert_owner_mode "$credentials" 'Credentials file' creds
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* && "$line" != *$'\r'* ]] || die 'Use LF lines with literal KEY=value in providers.env.'
    key=${line%%=*}
    value=${line#*=}
    # Validate the key charset before allowlist matching so unknown-key
    # detection stays exact even for glob-looking keys.
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Unsupported credential variable: $key"
    # Empty values would be silently dropped by the launchers' `-n` guard and
    # fail opaquely inside the container: reject them here instead.
    [[ -n "$value" ]] || die "Empty value for credential variable: $key"
    if [[ -n "${allowlist[$key]:-}" ]]; then
      export "$key=$value"
    else
      die "Unsupported credential variable: $key"
    fi
  done < "$credentials"
}
