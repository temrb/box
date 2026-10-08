#!/bin/bash -p
# check-pins.sh — assert-only pin consistency checker (never rewrites pins).
# Loads every pin from the single lib/pins.sh home (strict LF-only allowlist
# regex parsing), then asserts the single multi-target Dockerfile ARG names
# exist, the Debian digest matches FROM ...@sha256:..., and the §4 pin table
# in docs/architecture.md (between pin-table markers).
# lib/build.sh threads --build-arg from lib/pins.sh (plus
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
  _pins_vf="$bundle_dir/$(box_tool_field "$_pins_id" version_source)"
  [[ -f "$_pins_vf" ]] || die "Missing pin file: $_pins_vf"
done
unset _pins_id _pins_vf

host_uid=$(id -u)
host_gid=$(id -g)
((host_uid > 0 && host_gid > 0)) || die 'Run as your normal non-root host user.'

# Single pin home: strict parse (LF-only, allowlist, regex). Fails closed on
# CRLF/unknown keys. Semantic harness validation (box_harness_validate) lives
# in gen-pins.sh --check / verify-config scope, not here; this checker covers
# registry + structural Dockerfile/doc consistency only.
box_validate_registry "$bundle_dir"
box_load_all_pins "$bundle_dir"
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
box_assert_stage_pins "$dockerfile"
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

# --- Standalone archive verification lives in each Dockerfile stage (sha256sum --check + exact version) ---

# --- .dockerignore allowlists the single Dockerfile ---
if [[ -f "$dockerignore" ]]; then
  grep -Eq '^!Dockerfile([[:space:]]|$)' "$dockerignore" \
    || die '.dockerignore must allowlist !Dockerfile'
  ! grep -Eq '^!Dockerfile\.(muse|opencode)([[:space:]]|$)' "$dockerignore" \
    || die '.dockerignore must not reference deleted Dockerfile.muse/Dockerfile.opencode'
  # The bounded shared exceptions are the auth supervisor and process shutdown
  # helper. Host resolvers, lifecycle operations and credentials stay excluded.
  _pins_lib_rules=$(grep -E '^!lib/' "$dockerignore" || true)
  if [[ -n "$_pins_lib_rules" ]]; then
    [[ "$_pins_lib_rules" == '!lib/
!lib/supervisor.sh
!lib/supervisor-process.py' ]] \
      || die '.dockerignore lib/ exception must contain only supervisor.sh and supervisor-process.py plus traversal'
  fi
  unset _pins_lib_rules
  ! grep -Eq 'nodesource' "$dockerignore" \
    || die '.dockerignore must not reference deleted NodeSource key'
  ! grep -Eq '^!harnesses/opencode/policy/' "$dockerignore" \
    || die '.dockerignore must not reference deleted opencode policy'
  while IFS= read -r _pins_copy; do
    [[ -n "$_pins_copy" ]] || continue
    grep -Eq "^!${_pins_copy}([[:space:]]|$)" "$dockerignore" \
      || die ".dockerignore must explicitly allowlist COPY input: $_pins_copy"
  done < <(grep -E '^[[:space:]]*COPY ' "$dockerfile" | grep -Eo 'harnesses/[^ ]+')
  unset _pins_copy
fi

# --- build delegation is covered by box_assert_build_delegation above ---

_pins_versions=""
for _pins_id in $box_tool_ids; do
  _pins_vkey=$(box_version_key "$_pins_id")
  _pins_versions+="${_pins_versions:+, }$_pins_id ${!_pins_vkey}"
done
unset _pins_id _pins_vkey
printf 'check-pins.sh: PASS (%s, base %s)\n' \
  "$_pins_versions" "$docker_digest"
unset _pins_versions
