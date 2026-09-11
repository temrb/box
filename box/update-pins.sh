#!/bin/bash -p
# update-pins.sh — one-command CLI pin updater for both sandboxes.
# Fetches the latest Muse release (channel manifest with SHA-256 checksums)
# and the latest OpenCode release (npm registry dist.integrity pins), then
# walks the docs/upgrades.md §12 bump checklist: rewrite version-muse.env /
# version-opencode.env (all values together), move the pinned consumers with
# them (verify.d literals + gen-verify.sh, §4 pin table + gen-pins.sh, bats
# tripwire literals), validate (check-pins.sh + both --check gates), rebuild
# changed images via lib/build.sh, and sync the installed copies in
# ~/.config/box-*/. CLI pins only: Node/Debian pins ride through unchanged
# (see §12 for the toolchain/base procedures). Never hand-edits generated
# files. Never writes pins without parsing them through the strict
# version-file parser first (seed, explicit, and fetched pins alike).
# Usage: update-pins.sh [--check] [--pins-only] [--muse VERSION] [--opencode VERSION]
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

BOX_TOOL=update-pins.sh
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/pins.sh
source "$script_dir/lib/pins.sh"
# shellcheck source=lib/build.sh
source "$script_dir/lib/build.sh"

bundle_dir=$script_dir

# Upstream sources (same hosts the Dockerfile builds from).
muse_channel_url='https://api.meta.ai/muse-code/channels/muse-stable'
muse_download_base='https://lookaside.facebook.com/lookaside/muse/download/'
npm_registry='https://registry.npmjs.org'

update_usage() {
  cat <<'EOF'
Usage: update-pins.sh [--check] [--pins-only] [--muse VERSION] [--opencode VERSION]
Fetch the latest CLI pins and apply the §12 bump checklist for both tools.

  --check            report current -> latest per tool; change nothing.
  --pins-only        rewrite pins + regen + validate; skip rebuild and
                     installed-pin sync (no Docker needed).
  --muse VERSION     pin Muse to VERSION instead of latest (hashes are
                     still fetched from that version's manifest).
  --opencode VERSION pin OpenCode to VERSION instead of latest (integrities
                     are still fetched from the registry).

Advanced (mainly for tests): seed a tool's pins via the environment to skip
its network fetch — BOX_UPDATE_MUSE_VERSION + BOX_UPDATE_MUSE_SHA256_AMD64 +
BOX_UPDATE_MUSE_SHA256_ARM64, or BOX_UPDATE_OPENCODE_VERSION +
BOX_UPDATE_OPENCODE_NPM_INTEGRITY + _LINUX_X64 + _LINUX_ARM64. Seeds must be
complete per tool, pass the strict parser, and must not combine with the
matching --muse/--opencode flag.

Skipped by design: Debian base digest, NODE_VERSION/NODESOURCE_FINGERPRINT
(CLI pins only), the launcher smoke test (needs your project dir — the exact
commands are printed at the end), and `make test` (run it as the final gate).
EOF
}

check_only=0
pins_only=0
muse_explicit=''
opencode_explicit=''
while (($#)); do
  update_arg=$1; shift
  case "$update_arg" in
    --check) check_only=1 ;;
    --pins-only) pins_only=1 ;;
    --muse)
      [[ -n "${1:-}" ]] || die 'update-pins.sh: --muse needs a version.'
      muse_explicit=$1; shift ;;
    --opencode)
      [[ -n "${1:-}" ]] || die 'update-pins.sh: --opencode needs a version.'
      opencode_explicit=$1; shift ;;
    --help|-h) update_usage; exit 0 ;;
    --) break ;;
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

# Resolve Muse pins. Sets want_muse_version/_amd64/_arm64. Skips the manifest
# fetch when the target equals the current pin (explicit or seed).
resolve_muse() {
  local explicit=${1:-} channel_json version manifest_url manifest_json got algo
  if [[ -n "${BOX_UPDATE_MUSE_VERSION:-}" ]]; then
    [[ -z "$explicit" ]] || die 'Conflicting Muse pins: --muse and BOX_UPDATE_MUSE_VERSION are both set.'
    want_muse_version=$BOX_UPDATE_MUSE_VERSION
    want_muse_amd64=${BOX_UPDATE_MUSE_SHA256_AMD64:-}
    want_muse_arm64=${BOX_UPDATE_MUSE_SHA256_ARM64:-}
    [[ -n "$want_muse_amd64" && -n "$want_muse_arm64" ]] \
      || die 'Partial Muse seed: set BOX_UPDATE_MUSE_VERSION, BOX_UPDATE_MUSE_SHA256_AMD64, and BOX_UPDATE_MUSE_SHA256_ARM64 together.'
    return 0
  fi
  if [[ -n "${BOX_UPDATE_MUSE_SHA256_AMD64:-}${BOX_UPDATE_MUSE_SHA256_ARM64:-}" ]]; then
    die 'Partial Muse seed: set BOX_UPDATE_MUSE_VERSION, BOX_UPDATE_MUSE_SHA256_AMD64, and BOX_UPDATE_MUSE_SHA256_ARM64 together.'
  fi
  if [[ -n "$explicit" ]]; then
    if [[ "$explicit" == "$MUSE_VERSION" ]]; then
      want_muse_version=$MUSE_VERSION
      want_muse_amd64=$MUSE_SHA256_AMD64
      want_muse_arm64=$MUSE_SHA256_ARM64
      return 0
    fi
    assert_url_safe_version "$explicit" 'muse version'
    manifest_url="${muse_download_base}?channel=muse&version=${explicit}&file=manifest.json"
    version=$explicit
  else
    channel_json=$(fetch_url "$muse_channel_url") || die 'Cannot fetch the Muse channel manifest.'
    version=$(printf '%s' "$channel_json" | jq -e -r '.version | strings') \
      || die 'Cannot parse the Muse channel version.'
    manifest_url=$(printf '%s' "$channel_json" | jq -e -r '.manifest_url | strings') \
      || die 'Cannot parse the Muse channel manifest URL.'
    case "$manifest_url" in https://*) ;; *) die 'Muse manifest URL must be https.';; esac
    if [[ "$version" == "$MUSE_VERSION" ]]; then
      want_muse_version=$MUSE_VERSION
      want_muse_amd64=$MUSE_SHA256_AMD64
      want_muse_arm64=$MUSE_SHA256_ARM64
      return 0
    fi
    assert_url_safe_version "$version" 'muse channel version'
  fi
  manifest_json=$(fetch_url "$manifest_url") || die "Cannot fetch the Muse manifest for $version."
  got=$(printf '%s' "$manifest_json" | jq -e -r '.version | strings') \
    || die "Cannot parse the Muse manifest version for $version."
  [[ "$got" == "$version" ]] || die "Muse manifest reports $got, want $version."
  algo=$(printf '%s' "$manifest_json" | jq -e -r '.checksum_algorithm | strings') \
    || die "Cannot parse the Muse manifest checksum algorithm for $version."
  [[ "$algo" == "sha256" ]] || die "Muse manifest checksum algorithm is $algo, want sha256."
  want_muse_version=$version
  want_muse_amd64=$(printf '%s' "$manifest_json" | jq -e -r '.artifacts.x86_linux.checksum | strings') \
    || die "Cannot parse the Muse x86_linux checksum for $version."
  want_muse_arm64=$(printf '%s' "$manifest_json" | jq -e -r '.artifacts.aarch64_linux.checksum | strings') \
    || die "Cannot parse the Muse aarch64_linux checksum for $version."
}

# Resolve OpenCode pins. Sets want_opencode_version/_integ/_x64/_arm64. Skips
# the integrity fetches when the target equals the current pin.
resolve_opencode() {
  local explicit=${1:-} version pkg integ
  if [[ -n "${BOX_UPDATE_OPENCODE_VERSION:-}" ]]; then
    [[ -z "$explicit" ]] || die 'Conflicting OpenCode pins: --opencode and BOX_UPDATE_OPENCODE_VERSION are both set.'
    want_opencode_version=$BOX_UPDATE_OPENCODE_VERSION
    want_opencode_integ=${BOX_UPDATE_OPENCODE_NPM_INTEGRITY:-}
    want_opencode_x64=${BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64:-}
    want_opencode_arm64=${BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64:-}
    [[ -n "$want_opencode_integ" && -n "$want_opencode_x64" && -n "$want_opencode_arm64" ]] \
      || die 'Partial OpenCode seed: set BOX_UPDATE_OPENCODE_VERSION plus all three BOX_UPDATE_OPENCODE_NPM_INTEGRITY* pins together.'
    return 0
  fi
  if [[ -n "${BOX_UPDATE_OPENCODE_NPM_INTEGRITY:-}${BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64:-}${BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64:-}" ]]; then
    die 'Partial OpenCode seed: set BOX_UPDATE_OPENCODE_VERSION plus all three BOX_UPDATE_OPENCODE_NPM_INTEGRITY* pins together.'
  fi
  if [[ -n "$explicit" ]]; then
    version=$explicit
  else
    version=$(fetch_url "$npm_registry/opencode-ai/latest" | jq -e -r '.version | strings') \
      || die 'Cannot fetch the latest OpenCode version.'
  fi
  if [[ "$version" == "$OPENCODE_VERSION" ]]; then
    want_opencode_version=$OPENCODE_VERSION
    want_opencode_integ=$OPENCODE_NPM_INTEGRITY
    want_opencode_x64=$OPENCODE_NPM_INTEGRITY_LINUX_X64
    want_opencode_arm64=$OPENCODE_NPM_INTEGRITY_LINUX_ARM64
    return 0
  fi
  assert_url_safe_version "$version" 'opencode version'
  want_opencode_version=$version
  for pkg in opencode-ai opencode-linux-x64 opencode-linux-arm64; do
    integ=$(fetch_url "$npm_registry/$pkg/$version" | jq -e -r '.dist.integrity | strings') \
      || die "Cannot fetch dist.integrity for $pkg@$version."
    case "$pkg" in
      opencode-ai) want_opencode_integ=$integ ;;
      opencode-linux-x64) want_opencode_x64=$integ ;;
      opencode-linux-arm64) want_opencode_arm64=$integ ;;
    esac
  done
}

# Replace one literal everywhere in a file. Fails closed when the old literal
# is absent (a silently skipped consumer breaks the pin invariant).
replace_literal() {
  local file=${1:-} old=${2:-} new=${3:-} old_esc new_esc
  [[ -n "$file" && -n "$old" && -n "$new" ]] || die 'Internal error: missing replacement arguments.'
  grep -Fq -- "$old" "$file" || die "Expected literal $old not found in $file."
  old_esc=$(printf '%s' "$old" | sed -e 's/[][\\.^$*]/\\&/g')
  new_esc=$(printf '%s' "$new" | sed -e 's/[\\&]/\\&/g')
  sed -i "s/$old_esc/$new_esc/g" -- "$file"
  grep -Fq -- "$new" "$file" || die "Literal replacement failed in $file."
}

# Sync one installed pin file from the bundle (atomic rename + cmp, same as
# §12). Warn-skips when the tool was never installed (bundle update stands).
sync_installed_pin() {
  local id=${1:-} cfgdir vf dest
  box_require_tool "$id"
  cfgdir="$HOME/.config/$(box_tool_field "$id" config_dir)"
  vf=$(box_tool_field "$id" version_file)
  dest="$cfgdir/$vf"
  if [[ ! -d "$cfgdir" ]]; then
    printf '%s: WARNING: %s is not installed; skipping installed-pin sync (run setup.sh).\n' \
      "$BOX_TOOL" "$cfgdir" >&2
    return 0
  fi
  [[ ! -L "$dest" ]] || die "Refusing to follow symlink: $dest"
  sync_stage=$(mktemp "$cfgdir/.${vf}.tmp.XXXXXX") || die "Cannot stage installed pin sync: $dest"
  cp -- "$bundle_dir/$vf" "$sync_stage" || die "Cannot stage installed pin sync: $dest"
  chmod 644 -- "$sync_stage" || die "Cannot stage installed pin sync: $dest"
  mv -f -- "$sync_stage" "$dest" || die "Cannot sync installed pins: $dest"
  cmp -s -- "$bundle_dir/$vf" "$dest" || die "Installed pin sync failed: $dest"
  printf '%s: synced %s\n' "$BOX_TOOL" "$dest"
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

resolve_muse "$muse_explicit"
resolve_opencode "$opencode_explicit"

# Candidate pins: resolved CLI values plus the carried toolchain pins.
declare -A new_pin=(
  [MUSE_VERSION]="$want_muse_version"
  [MUSE_SHA256_AMD64]="$want_muse_amd64"
  [MUSE_SHA256_ARM64]="$want_muse_arm64"
  [OPENCODE_VERSION]="$want_opencode_version"
  [OPENCODE_NPM_INTEGRITY]="$want_opencode_integ"
  [OPENCODE_NPM_INTEGRITY_LINUX_X64]="$want_opencode_x64"
  [OPENCODE_NPM_INTEGRITY_LINUX_ARM64]="$want_opencode_arm64"
  [NODE_VERSION]="$NODE_VERSION"
  [NODESOURCE_FINGERPRINT]="$NODESOURCE_FINGERPRINT"
)

muse_changed=0
opencode_changed=0
if [[ "$want_muse_version" != "$MUSE_VERSION" ]]; then muse_changed=1; fi
if [[ "$want_opencode_version" != "$OPENCODE_VERSION" ]]; then opencode_changed=1; fi

report_tool() {
  local display=${1:-} current=${2:-} want=${3:-}
  if [[ "$current" == "$want" ]]; then
    printf '%s: %s: %s (up to date)\n' "$BOX_TOOL" "$display" "$current"
  else
    printf '%s: %s: %s -> %s (update available)\n' "$BOX_TOOL" "$display" "$current" "$want"
  fi
}
report_tool Muse "$MUSE_VERSION" "$want_muse_version"
report_tool OpenCode "$OPENCODE_VERSION" "$want_opencode_version"

if ((check_only)); then exit 0; fi

if (( ! muse_changed && ! opencode_changed )); then
  printf '%s: already up to date.\n' "$BOX_TOOL"
  exit 0
fi

# Mutating modes refuse root before touching the bundle (check-pins.sh would
# refuse root after the rewrite otherwise).
((host_uid > 0 && host_gid > 0)) || die 'Run as your normal non-root host user.'

# Stage + strictly parse both candidates BEFORE mutating anything, so a bad
# fetch (or seed) fails with the bundle untouched.
muse_candidate=''
opencode_candidate=''
sync_stage=''
cleanup_update_pins() {
  if [[ -n "$muse_candidate" ]]; then rm -f -- "$muse_candidate"; fi
  if [[ -n "$opencode_candidate" ]]; then rm -f -- "$opencode_candidate"; fi
  if [[ -n "$sync_stage" ]]; then rm -f -- "$sync_stage"; fi
}
trap cleanup_update_pins EXIT
muse_candidate=$(box_mktemp_file update-pins-muse) || die 'Cannot create temp file.'
opencode_candidate=$(box_mktemp_file update-pins-opencode) || die 'Cannot create temp file.'
stage_candidate() {
  local id=${1:-} tmp=${2:-} src key
  box_require_tool "$id"
  [[ -n "$tmp" ]] || die 'Internal error: missing candidate temp file.'
  src="$bundle_dir/$(box_tool_field "$id" version_file)"
  grep '^#' -- "$src" >"$tmp" || true # preserve header comments
  # shellcheck disable=SC2046 # word-splitting registry pin_keys is intentional.
  for key in $(box_tool_field "$id" pin_keys); do
    [[ -n "${new_pin[$key]:-}" ]] || die "Internal error: missing candidate pin $key."
    printf '%s=%s\n' "$key" "${new_pin[$key]}" >>"$tmp" || die 'Cannot stage candidate pins.'
  done
  chmod 600 -- "$tmp" || die 'Cannot stage candidate pins.'
  # shellcheck disable=SC2046 # word-splitting registry pin_keys into allowlist args is intentional.
  box_load_version_file "$tmp" "$(box_tool_field "$id" version_format)" $(box_tool_field "$id" pin_keys)
}
stage_candidate muse "$muse_candidate"
stage_candidate opencode "$opencode_candidate"

# Full-mode Docker preflight BEFORE mutating, so a missing Engine fails with
# the bundle untouched (--pins-only never touches Docker or $HOME).
if ((!pins_only)); then
  [[ -n "${HOME:-}" ]] || die 'HOME is unset.'
  if ((muse_changed)); then
    box_docker_cli "$HOME/.config/$(box_tool_field muse config_dir)/docker-cli"
    box_assert_engine
  fi
  if ((opencode_changed)); then
    box_docker_cli "$HOME/.config/$(box_tool_field opencode config_dir)/docker-cli"
    box_assert_engine
  fi
fi

# Install validated candidates (atomic rename inside the bundle dir).
install_candidate() {
  local id=${1:-} tmp=${2:-} vf dest stage
  box_require_tool "$id"
  vf=$(box_tool_field "$id" version_file)
  dest="$bundle_dir/$vf"
  [[ ! -L "$dest" ]] || die "Refusing to follow symlink: $dest"
  stage=$(mktemp "$bundle_dir/.${vf}.tmp.XXXXXX") || die "Cannot stage pin update: $dest"
  cp -- "$tmp" "$stage" || { rm -f -- "$stage"; die "Cannot stage pin update: $dest"; }
  chmod 644 -- "$stage" || { rm -f -- "$stage"; die "Cannot stage pin update: $dest"; }
  mv -f -- "$stage" "$dest" || { rm -f -- "$stage"; die "Cannot write $dest."; }
}
if ((muse_changed)); then install_candidate muse "$muse_candidate"; fi
if ((opencode_changed)); then install_candidate opencode "$opencode_candidate"; fi

# Move the version-literal consumers (§12 checklist): readiness partials +
# bats tripwires, registry-driven (position-0 pin key is the version).
for _upd_id in $box_tool_ids; do
  _upd_vkey=$(box_tool_field "$_upd_id" pin_keys); _upd_vkey=${_upd_vkey%% *}
  _upd_old=${!_upd_vkey}
  _upd_new=${new_pin[$_upd_vkey]}
  if [[ "$_upd_old" != "$_upd_new" ]]; then
    replace_literal "$bundle_dir/verify.d/40-readiness-$_upd_id.sh" "$_upd_old" "$_upd_new"
    replace_literal "$bundle_dir/tests/bats/pins.bats" "$_upd_old" "$_upd_new"
    replace_literal "$bundle_dir/tests/bats/version.bats" "$_upd_old" "$_upd_new"
  fi
done
unset _upd_id _upd_vkey _upd_old _upd_new

bash "$bundle_dir/gen-verify.sh"
bash "$bundle_dir/gen-pins.sh"
bash "$bundle_dir/check-pins.sh"
bash "$bundle_dir/gen-pins.sh" --check
bash "$bundle_dir/gen-verify.sh" --check

if ((!pins_only)); then
  # The version files changed above but box_load_all_pins cached the old
  # pins at startup; re-parse so the in-process build tags/labels the new
  # pins (after the replace loop, which needs the old globals).
  box_reload_all_pins "$bundle_dir"
  if ((muse_changed)); then box_build_image muse "$bundle_dir"; fi
  if ((opencode_changed)); then box_build_image opencode "$bundle_dir"; fi
  if ((muse_changed)); then sync_installed_pin muse; fi
  if ((opencode_changed)); then sync_installed_pin opencode; fi
fi

rm -f -- "$muse_candidate" "$opencode_candidate" || true
trap - EXIT
if ((pins_only)); then
  printf '%s: PASS (pins updated; rebuild + sync skipped).\n' "$BOX_TOOL"
  printf 'Next: make -C %s build, then sync ~/.config/box-*/version-*.env per §12.\n' "$bundle_dir"
else
  printf '%s: PASS (pins updated, images rebuilt, installed pins synced).\n' "$BOX_TOOL"
  if ((muse_changed)); then
    printf 'Smoke test: BOX_M_IMAGE="%s" box-m --version\n' \
      "$(box_image_tag_for_version muse "$want_muse_version" "$host_uid" "$host_gid")"
  fi
  if ((opencode_changed)); then
    printf 'Smoke test: BOX_O_IMAGE="%s" box-o --version\n' \
      "$(box_image_tag_for_version opencode "$want_opencode_version" "$host_uid" "$host_gid")"
  fi
fi
printf 'Final gate: make -C %s pins && make -C %s test\n' "$bundle_dir" "$bundle_dir"
