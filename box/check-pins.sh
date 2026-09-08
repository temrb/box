#!/bin/bash -p
# shellcheck disable=SC2153 # pin globals are assigned dynamically by box_load_all_pins via printf -v, so static analysis cannot see them; the lowercase node locals are intentional copies, not misspellings.
# check-pins.sh — assert-only pin consistency checker (never rewrites pins).
# Loads every pin from the single lib/pins.sh home (strict LF-only allowlist
# regex parsing), then asserts the single multi-target Dockerfile ARG names
# exist, the Debian digest matches FROM ...@sha256:..., and the Node.js +
# fingerprint pins from version-opencode.env match the Dockerfile logic and
# the §4 pin table in docs/architecture.md (between pin-table markers).
# setup.sh and the Makefile thread --build-arg from lib/pins.sh (plus
# HOST_UID/HOST_GID from `id`), and all ARGs have no defaults so bare builds
# fail closed.
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

BOX_TOOL=check-pins.sh
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/pins.sh
source "$script_dir/lib/pins.sh"

bundle_dir=$script_dir
dockerfile="$bundle_dir/Dockerfile"
readme="$bundle_dir/docs/architecture.md"
dockerignore="$bundle_dir/.dockerignore"
makefile="$bundle_dir/Makefile"
setup_sh="$bundle_dir/setup.sh"

[[ -f "$dockerfile" ]] || die "Missing Dockerfile: $dockerfile"
[[ -f "$readme" ]] || die "Missing pin table doc: $readme"
for _pins_id in $box_tool_ids; do
  _pins_vf="$bundle_dir/$(box_tool_field "$_pins_id" version_file)"
  [[ -f "$_pins_vf" ]] || die "Missing pin file: $_pins_vf"
done
unset _pins_id _pins_vf

host_uid=$(id -u)
host_gid=$(id -g)
((host_uid > 0 && host_gid > 0)) || die 'Run as your normal non-root host user.'

# Single pin home: strict parse (LF-only, allowlist, regex). Fails closed on
# CRLF/unknown keys. NODE_VERSION + NODESOURCE_FINGERPRINT come from
# version-opencode.env (not hardcoded). The Node toolchain is opencode-owned
# (only npm-pinned tool needs it): adding tools is unaffected, but removing
# opencode would require updating this block and the Dockerfile asserts below.
box_load_all_pins "$bundle_dir"
node_version=$NODE_VERSION
fingerprint=$NODESOURCE_FINGERPRINT
for _pins_id in $box_tool_ids; do
  for _pins_key in $(box_tool_field "$_pins_id" pin_keys); do
    [[ -n "${!_pins_key:-}" ]] || die "Empty $_pins_key pin after parse."
  done
done
unset _pins_id _pins_key

# --- base + one FROM target per registry tool exist ---
grep -Eq '^FROM debian:trixie-slim@sha256:[0-9a-f]{64} AS base([[:space:]]|$)' "$dockerfile" \
  || die 'Dockerfile must contain: FROM debian:trixie-slim@sha256:<digest> AS base'
for _pins_id in $box_tool_ids; do
  _pins_tgt=$(box_tool_field "$_pins_id" dockerfile_target)
  grep -Eq "^FROM base AS ${_pins_tgt}([[:space:]]|$)" "$dockerfile" \
    || die "Dockerfile must contain: FROM base AS $_pins_tgt"
done
unset _pins_id _pins_tgt

# --- Shared structural asserts (single strictness with gen-pins.sh --check) ---
box_assert_no_default_args "$dockerfile"
box_assert_tarball_pins "$dockerfile"
box_assert_shell_placement "$dockerfile"
box_assert_build_delegation "$bundle_dir"

# --- Debian digest: single FROM digest matches docs/architecture.md §4 pin block ---
# Scoped to the <!-- pin-table-start/end --> markers: doc prose elsewhere may
# quote other example hashes without breaking this check.
# Single extractor home (lib/pins.sh): previously duplicated with gen-pins.sh.
docker_digest=$(box_docker_base_digest "$dockerfile")
grep -Fq '<!-- pin-table-start -->' "$readme" \
  || die 'docs/architecture.md §4 is missing the <!-- pin-table-start --> marker'
grep -Fq '<!-- pin-table-end -->' "$readme" \
  || die 'docs/architecture.md §4 is missing the <!-- pin-table-end --> marker'
readme_pins=$(box_pin_block "$readme") \
  || die 'Cannot extract docs/architecture.md §4 pin block.'
readme_digests=$(printf '%s\n' "$readme_pins" | grep -Eo 'sha256:[0-9a-f]{64}' | sort -u) \
  || die 'Cannot extract docs/architecture.md §4 digests.'
[[ -n "$readme_digests" ]] || die 'No sha256 digest found in docs/architecture.md §4 pin block.'
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  [[ "$d" == "$docker_digest" ]] \
    || die "Pin-table digest $d does not match Dockerfile $docker_digest (re-pin both together)"
done <<<"$readme_digests"

# --- Node.js exact pin + fingerprint match Dockerfile logic + docs/architecture.md §4 table ---
# Both pins live once in version-opencode.env (via lib/pins.sh). The
# Dockerfile consumes them parameterized (no hardcoded copy); the docs/architecture.md §4
# pin table records the resolved values for humans.
# shellcheck disable=SC2016 # '${...}' literals below match Dockerfile source text.
grep -Fq '"nodejs=${NODE_VERSION}"' "$dockerfile" \
  || die 'Dockerfile must install parameterized "nodejs=${NODE_VERSION}"'
# shellcheck disable=SC2016 # '${...}' literal matches Dockerfile source text.
grep -Fq '"${NODESOURCE_FINGERPRINT}"' "$dockerfile" \
  || die 'Dockerfile must assert parameterized "${NODESOURCE_FINGERPRINT}"'
# The vendored NodeSource key holds a primary + subkey (2 `fpr:` lines);
# the Dockerfile asserts that count plus a primary-fingerprint match.
# shellcheck disable=SC2016 # '$fpr_count' below is an intentional literal.
grep -Fq 'test "$fpr_count" = 2' "$dockerfile" \
  || die 'Dockerfile must assert two NodeSource fingerprints (primary + subkey)'
# shellcheck disable=SC2016 # '$NODE_VERSION' below is an intentional literal.
! grep -Fq 'nodejs=22.' "$dockerfile" \
  || die 'Dockerfile must not hardcode a Node version (use $NODE_VERSION from version-opencode.env)'
grep -Fq "$node_version" <<<"$readme_pins" \
  || die "docs/architecture.md §4 pin table must contain exact Node version: $node_version"
grep -Fq "$fingerprint" <<<"$readme_pins" \
  || die "docs/architecture.md §4 pin table must contain NodeSource fingerprint: $fingerprint"

# --- OpenCode tarball-to-pin strength is covered by box_assert_tarball_pins above ---

# --- .dockerignore allowlists the single Dockerfile (+ vendored key) ---
if [[ -f "$dockerignore" ]]; then
  grep -Eq '^!Dockerfile([[:space:]]|$)' "$dockerignore" \
    || die '.dockerignore must allowlist !Dockerfile'
  ! grep -Eq '^!Dockerfile\.(muse|opencode)([[:space:]]|$)' "$dockerignore" \
    || die '.dockerignore must not reference deleted Dockerfile.muse/Dockerfile.opencode'
  ! grep -Eq '^!lib/' "$dockerignore" \
    || die '.dockerignore must not allowlist lib/ (dead: only keys/nodesource.asc is COPYd)'
  grep -Eq '^!keys/nodesource\.asc([[:space:]]|$)' "$dockerignore" \
    || die '.dockerignore must allowlist !keys/nodesource.asc (vendored APT key COPYd by the Dockerfile)'
fi

# --- build delegation is covered by box_assert_build_delegation above ---

_pins_versions=""
for _pins_id in $box_tool_ids; do
  _pins_vkey=$(box_tool_field "$_pins_id" pin_keys); _pins_vkey=${_pins_vkey%% *}
  _pins_versions+="${_pins_versions:+, }$_pins_id ${!_pins_vkey}"
done
unset _pins_id _pins_vkey
printf 'check-pins.sh: PASS (%s, base %s, node nodejs=%s)\n' \
  "$_pins_versions" "$docker_digest" "$node_version"
unset _pins_versions
