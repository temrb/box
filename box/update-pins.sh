#!/bin/bash -p
# update-pins.sh — registry-driven CLI pin updater for all harnesses.
# Harness adapters resolve channel checksums, standalone archive digests, or
# verified complete musl archives, then walk the docs/upgrades.md §12 bump checklist:
# rewrite selected package pin files (all values together), move consumers with
# them (readiness @@tokens@@ via gen-verify.sh, §4 pin table via gen-pins.sh;
# verify.d/ partials and bats carry no pin literals, so nothing else moves),
# validate (check-pins.sh + both --check gates), rebuild
# changed images via lib/build.sh, and sync the installed copies in
# ~/.config/box-*/. CLI pins only: Debian base rides through unchanged
# (see §12 for the base procedure). Never hand-edits generated
# files. Never writes pins without parsing them through the strict
# version-file parser first (seed, explicit, and fetched pins alike).
# Usage: update-pins.sh [--check] [--pins-only] [--muse VERSION] [--opencode VERSION] [--codex VERSION] [--only <id>]
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

BOX_TOOL=update-pins.sh
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/pins.sh
source "$script_dir/lib/pins.sh"
# shellcheck source=lib/build.sh
source "$script_dir/lib/build.sh"
# shellcheck source=lib/install.sh
source "$script_dir/lib/install.sh"

bundle_dir=$script_dir

update_usage() {
  cat <<'EOF'
Usage: update-pins.sh [--check] [--pins-only] [--muse VERSION] [--opencode VERSION] [--codex VERSION] [--only <id>]
Fetch selected CLI pins and apply the §12 bump checklist.
  --only <id>        select one harness; all others retain pins with no fetch.
  --codex VERSION    select a stable complete musl package release.

  --check            report current -> latest per tool; change nothing.
  --pins-only        rewrite pins + regen + validate; skip rebuild and
                     installed-pin sync (no Docker needed).
  --muse VERSION     pin Muse to VERSION instead of latest (hashes are
                     still fetched from that version's manifest).
  --opencode VERSION pin OpenCode to VERSION (required: no latest channel;
                      digests are fetched from opencode.ai/files/bin).

Advanced (mainly for tests): seed a tool's pins via the environment to skip
its network fetch — BOX_UPDATE_MUSE_VERSION + BOX_UPDATE_MUSE_SHA256_AMD64 +
BOX_UPDATE_MUSE_SHA256_ARM64, BOX_UPDATE_OPENCODE_VERSION +
BOX_UPDATE_OPENCODE_SHA256_AMD64 + BOX_UPDATE_OPENCODE_SHA256_ARM64, or
BOX_UPDATE_CODEX_VERSION + BOX_UPDATE_CODEX_SHA256_AMD64 + _ARM64. Seeds must be
complete per tool, pass the strict parser, and must not combine with the
matching version flag.

Skipped by design: Debian base digest, the launcher smoke test (needs your
project dir — the exact commands are printed at the end), and `make test`
(run it as the final gate).
EOF
}

check_only=0
pins_only=0
declare -A explicit_versions=()
only=''
while (($#)); do
  update_arg=$1; shift
  case "$update_arg" in
    --check) check_only=1 ;;
    --pins-only) pins_only=1 ;;
    --only)
      [[ -n "${1:-}" && -z "$only" ]] || die '--only needs exactly one harness id.'
      box_require_tool "$1"; only=$1; shift ;;
    --help|-h) update_usage; exit 0 ;;
    --) break ;;
    --*)
      _upd_select=${update_arg#--}
      box_require_tool "$_upd_select"
      [[ -n "${1:-}" && -z "${explicit_versions[$_upd_select]+set}" ]] || die "$update_arg needs one version."
      explicit_versions[$_upd_select]=$1; shift ;;
    -*) die "Unknown flag: $update_arg (see --help)." ;;
    *) die "Takes no positional arguments (got '$update_arg')." ;;
  esac
done
unset update_arg
# `--` ends flag parsing; the tool takes no positionals, so anything left is
# a usage error (never silently swallowed).
(( $# == 0 )) || die "Takes no positional arguments (got '$1')."

command -v curl >/dev/null || die 'curl is required (documented host prerequisite).'
command -v jq >/dev/null || die 'jq is required (documented host prerequisite).'
command -v flock >/dev/null || die 'flock is required (util-linux).'
# Lock the physical bundle directory: no lock file, stale PID or unlink race.
# Hold through rollback, regeneration, build and installed-pin synchronization.
# Even --check needs a consistent snapshot of the multi-file pin transaction.
exec {update_lock_fd}<"$bundle_dir" || die 'Cannot open maintenance lock.'
flock -n -x "$update_lock_fd" || die 'Bundle maintenance already running; retry after it finishes.'

# Globals for owner checks (same as check-pins.sh). Only --check and the
# up-to-date early exit are root-safe; every mutating mode refuses root
# before any mutation (check-pins.sh + box_build_image both refuse root).
host_uid=$(id -u) || die 'Cannot determine UID.'
host_gid=$(id -g) || die 'Cannot determine GID.'
# `project` stays unset so the version parser skips the outside-project
# check for bundle files (same as check-pins.sh).

# Fetch a small metadata document. Fail closed (callers die with context).
fetch_url() {
  local url=${1:-}
  [[ -n "$url" ]] || die 'Internal error: empty fetch URL.'
  curl --fail --silent --show-error --proto '=https' --tlsv1.2 --location \
    --retry 3 --connect-timeout 15 --max-time 60 \
    -- "$url"
}

# Guard a version string before interpolating it into a fetch URL (path or
# query). The strict format contract stays in the version parser (every
# candidate file is parsed before use); this only kills traversal/parameter
# injection from explicit CLI versions and network responses.
assert_url_safe_version() {
  local ver=${1:-} what=${2:-version}
  [[ "$ver" =~ ^[A-Za-z0-9][A-Za-z0-9.+-]*$ ]] || die "Invalid $what: ${ver:-<empty>}"
  [[ "$ver" != *'..'* ]] || die "Invalid $what: ${ver:-<empty>}"
}

# Complete-seed fast path for sha-pinned triples. When
# BOX_UPDATE_<PREFIX>_VERSION is set, require the two SHA seeds with it,
# reject conflict with an explicit CLI pin, assign the three target vars and
# return 0. With no version seed, reject lone SHA seeds and return 1 so the
# caller continues to explicit/channel resolution. Dies (never silent)
# because it runs in the caller's shell, not a substitution.
# Usage: if box_update_seed <PREFIX> <explicit> <flag> <Display> <vvar> <avar> <rvar>; then return 0; fi
box_update_seed() {
  local prefix=${1:-} explicit=${2:-} flag=${3:-} display=${4:-}
  local -n _seed_v=${5:-} _seed_a=${6:-} _seed_r=${7:-}
  [[ -n "$prefix" && -n "$flag" && -n "$display" && -n "${5:-}" && -n "${6:-}" && -n "${7:-}" ]] \
    || die 'Internal error: missing seed arguments.'
  local vv="BOX_UPDATE_${prefix}_VERSION" va="BOX_UPDATE_${prefix}_SHA256_AMD64" vr="BOX_UPDATE_${prefix}_SHA256_ARM64"
  if [[ -n "${!vv:-}" ]]; then
    [[ -z "$explicit" ]] || die "Conflicting $display pins: $flag and $vv are both set."
    [[ -n "${!va:-}" && -n "${!vr:-}" ]] \
      || die "Partial $display seed: set $vv, $va, and $vr together."
    _seed_v=${!vv}; _seed_a=${!va}; _seed_r=${!vr}
    return 0
  fi
  [[ -z "${!va:-}${!vr:-}" ]] \
    || die "Partial $display seed: set $vv, $va, and $vr together."
  return 1
}

# Download <url> to caller-owned <file> and print its sha256 digest.
# Transport failure removes the temp and returns 1 (callers die with
# context, same contract as fetch_url); digest/archive validation stays
# per-harness because companions differ (manifest, archive.py, tar listing).
# Usage: computed=$(box_fetch_verify <url> <file>) || die "Cannot download ..."
box_fetch_verify() {
  local url=${1:-} file=${2:-} computed
  [[ -n "$url" && -n "$file" ]] || die 'Internal error: missing fetch arguments.'
  curl --fail --silent --show-error --proto '=https' --tlsv1.2 --location --connect-timeout 15 --max-time 600 -o "$file" -- "$url" \
    || { rm -f -- "$file"; return 1; }
  computed=$(sha256sum -- "$file"); computed=${computed%% *}
  printf '%s' "$computed"
}

# Single pin home: current pins land in same-named globals.
box_load_all_pins "$bundle_dir"
for _upd_id in $box_tool_ids; do
  # shellcheck disable=SC2046 # word-splitting registry pin_keys into allowlist args is intentional.
  for _upd_key in $(box_tool_field "$_upd_id" pin_keys); do
    [[ -n "${!_upd_key:-}" ]] || die "Empty $_upd_key pin after parse."
  done
done
unset _upd_id _upd_key

box_validate_registry "$bundle_dir"
# Reject every selector before calling any resolver: a later invalid flag
# must not cause an earlier harness's unnecessary network fetch.
for _upd_id in "${!explicit_versions[@]}"; do
  [[ -z "$only" || "$only" == "$_upd_id" ]] || die '--only cannot combine with another harness version flag.'
  assert_url_safe_version "${explicit_versions[$_upd_id]}" "$_upd_id version"
done
declare -A new_pin=()
for _upd_id in $box_tool_ids; do
  for _upd_key in $(box_tool_field "$_upd_id" pin_keys); do new_pin[$_upd_key]=${!_upd_key}; done
  if [[ -n "$only" && "$only" != "$_upd_id" ]]; then
    [[ -z "${explicit_versions[$_upd_id]+set}" ]] || die '--only cannot combine with another harness version flag.'
    continue
  fi
  [[ -z "${explicit_versions[$_upd_id]:-}" ]] || assert_url_safe_version "${explicit_versions[$_upd_id]}" "$_upd_id version"
  # shellcheck disable=SC1090 # registry validation fixes trusted adapter paths
  source "$bundle_dir/$(box_tool_field "$_upd_id" update_adapter)"
  box_harness_resolve "${explicit_versions[$_upd_id]:-}"
done
unset _upd_id _upd_key

# Candidate staging and lifecycle are registry-driven; only the upstream
# resolvers and new_pin data above know individual tool identities.
declare -A candidates=() changed=() installed=()
for id in $box_tool_ids; do
  installed[$id]=0
  if [[ -d "$HOME/.config/$(box_tool_field "$id" config_dir)" ]]; then installed[$id]=1; fi
done
backup_dir=''
rollback=0
cleanup_update_pins() {
  local rc=$? file
  if ((rollback)); then
    for file in "$backup_dir"/*; do
      cp -p -- "$file" "${restore_path[${file##*/}]}" \
        || printf '%s: FAIL: cannot restore %s after failed validation.\n' "$BOX_TOOL" "${file##*/}" >&2
    done
  fi
  for file in "${candidates[@]}"; do
    [[ -z "$file" ]] || rm -f -- "$file"
  done
  [[ -z "$backup_dir" ]] || rm -rf -- "$backup_dir"
  return "$rc"
}
trap cleanup_update_pins EXIT

stage_candidate() {
  local id=${1:-} tmp=${2:-} src key
  box_require_tool "$id"
  [[ -n "$tmp" ]] || die 'Internal error: missing candidate temp file.'
  src="$bundle_dir/$(box_tool_field "$id" version_source)"
  grep '^#' -- "$src" >"$tmp" || true # preserve header comments
  for key in $(box_tool_field "$id" pin_keys); do
    [[ -n "${new_pin[$key]:-}" ]] || die "Internal error: missing candidate pin $key."
    printf '%s=%s\n' "$key" "${new_pin[$key]}" >>"$tmp" || die 'Cannot stage candidate pins.'
  done
  chmod 600 -- "$tmp" || die 'Cannot stage candidate pins.'
  # shellcheck disable=SC2046 # registry keys intentionally become allowlist args.
  box_load_version_file "$tmp" "$(box_tool_field "$id" version_format)" $(box_tool_field "$id" pin_keys)
}

any_changed=0
for id in $box_tool_ids; do
  candidates[$id]=$(box_mktemp_file "update-pins-$id") || die 'Cannot create temp file.'
  # --check and unchanged candidates use the same strict parser as writes.
  stage_candidate "$id" "${candidates[$id]}"
  changed[$id]=0
  changed_keys=''
  keys=$(box_tool_field "$id" pin_keys)
  version_key=$(box_version_key "$id")
  for key in $keys; do
    if [[ "${new_pin[$key]}" != "${!key}" ]]; then
      changed[$id]=1
      any_changed=1
      changed_keys+="${changed_keys:+, }$key"
    fi
  done
  display=$(box_tool_field "$id" display)
  if ((!changed[$id])); then
    printf '%s: %s: %s (up to date)\n' "$BOX_TOOL" "$display" "${!version_key}"
  elif [[ "${new_pin[$version_key]}" == "${!version_key}" ]]; then
    printf '%s: %s: %s (pins changed: %s)\n' "$BOX_TOOL" "$display" "${!version_key}" "$changed_keys"
  else
    printf '%s: %s: %s -> %s (update available)\n' "$BOX_TOOL" "$display" "${!version_key}" "${new_pin[$version_key]}"
  fi
done
if ((check_only)); then exit 0; fi
if ((!any_changed)); then
  printf '%s: already up to date.\n' "$BOX_TOOL"
  exit 0
fi
((host_uid > 0 && host_gid > 0)) || die 'Run as your normal non-root host user.'

# Full mode checks Docker before rewriting bundle files.
if ((!pins_only)); then
  [[ -n "${HOME:-}" ]] || die 'HOME is unset.'
  for id in $box_tool_ids; do
    if ((changed[$id])); then
      box_docker_cli "$HOME/.config/$(box_tool_field "$id" config_dir)/docker-cli"
      box_assert_engine
    fi
  done
fi

# Keep the pin files, generated harnesses, and table together if generation
# or consistency validation fails. After validation, build failures leave
# accepted pins in place so the documented rebuild/sync path can retry.
declare -A restore_path=()
backup_dir=$(box_mktemp_dir update-pins-backup) || die 'Cannot create pin backup directory.'
backup_file() {
  local file=$1 name=${1##*/}
  [[ -f "$file" && ! -L "$file" ]] || die "Refusing non-regular pin consumer: $file"
  cp -p -- "$file" "$backup_dir/$name" || die 'Cannot back up pin consumers.'
  restore_path[$name]=$file
}
for id in $box_tool_ids; do
  backup_file "$bundle_dir/$(box_tool_field "$id" version_source)"
  backup_file "$bundle_dir/verify-$id.sh"
done
backup_file "$bundle_dir/docs/architecture.md"
rollback=1

# Atomic rename inside the destination directory.
install_candidate() {
  local id=${1:-} tmp=${2:-} vf dest
  box_require_tool "$id"
  vf=$(box_tool_field "$id" version_file)
  dest="$bundle_dir/$(box_tool_field "$id" version_source)"
  [[ ! -L "$dest" ]] || die "Refusing to follow symlink: $dest"
  box_atomic_install "$tmp" "$dest" 644
}
for id in $box_tool_ids; do
  if ((changed[$id])); then install_candidate "$id" "${candidates[$id]}"; fi
done
bash "$bundle_dir/gen-verify.sh"
bash "$bundle_dir/gen-pins.sh"
bash "$bundle_dir/check-pins.sh"
bash "$bundle_dir/gen-pins.sh" --check
bash "$bundle_dir/gen-verify.sh" --check
rollback=0

if ((!pins_only)); then
  box_reload_all_pins "$bundle_dir"
  for id in $box_tool_ids; do
    if ((changed[$id])); then box_build_image "$id" "$bundle_dir"; fi
  done
  for id in $box_tool_ids; do
    if ((changed[$id])); then
      if ((installed[$id])); then
        box_sync_installed_pins "$id" "$bundle_dir"
      else
        box_sync_installed_pins "$id" "$bundle_dir" 2
      fi
    fi
  done
fi
if ((pins_only)); then
  printf '%s: PASS (pins updated; rebuild + sync skipped).\n' "$BOX_TOOL"
  printf 'Next: make -C %s build, then make sync-pins-<stem> per §12.\n' "$bundle_dir"
else
  printf '%s: PASS (pins updated, images rebuilt, installed pins synced).\n' "$BOX_TOOL"
  for id in $box_tool_ids; do
    if ((changed[$id])); then
      printf 'Smoke test (installed pins, no image override): %s --version\n' "$(box_tool_field "$id" launcher)"
    fi
  done
fi
printf 'Final gate: make -C %s verify-static\n' "$bundle_dir"
