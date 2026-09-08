# shellcheck shell=bash
# box/lib/pins.sh — single pin-threading home.
# NODE_VERSION + NODESOURCE_FINGERPRINT live in version-opencode.env (parsed by
# box_load_version_file in lib/preflight.sh), not hardcoded.
# Never sources version files directly: sourcing executes arbitrary shell
# code from an untrusted clone — parse literal pins only.
# Requires lib/preflight.sh (die, BOX_TOOL, box_realpath);
# never executed directly.
# shellcheck disable=SC2034,SC2154 # pin globals are set here and consumed by
# setup.sh / check-pins.sh / Makefile-via-bash-c; standalone analysis cannot
# see that.

[[ -n "${_BOX_PINS_LOADED:-}" ]] && return 0
_BOX_PINS_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Resolve our own dir without helpers (preflight.sh, which defines
# box_realpath, is sourced below).
_pins_src=${BASH_SOURCE[0]}
if command -v realpath >/dev/null 2>&1; then
  _pins_src=$(realpath -- "$_pins_src" 2>/dev/null || printf '%s' "$_pins_src")
elif command -v readlink >/dev/null 2>&1; then
  _pins_src=$(readlink -f -- "$_pins_src" 2>/dev/null || printf '%s' "$_pins_src")
fi
_pins_dir=$(dirname -- "$_pins_src")
unset _pins_src
# shellcheck source=lib/preflight.sh
source "$_pins_dir/preflight.sh"
# shellcheck source=lib/tools.sh
source "$_pins_dir/tools.sh"
unset _pins_dir

# Load every pin from the bundle (or any dir holding the registry version
# files). Results are cached per bundle dir (_BOX_PINS_LOADED_FOR) so repeated
# loads per build cost one parse. Pass a different bundle dir to reload.
# Iterates the registry: each tool id contributes its version file, parsed
# with its version_format + pin_keys. Pin values land in same-named globals
# (e.g. MUSE_VERSION, OPENCODE_NPM_INTEGRITY, NODE_VERSION).
# Usage: box_load_all_pins <bundle_dir>
box_load_all_pins() {
  local bundle=${1:-}
  [[ -n "$bundle" ]] || die 'Internal error: missing bundle dir for pins.'
  if [[ "${_BOX_PINS_LOADED_FOR:-}" == "$bundle" ]]; then return 0; fi
  local id vf key
  for id in $box_tool_ids; do
    vf="$bundle/$(box_tool_field "$id" version_file)"
    [[ -f "$vf" ]] || die "Missing pin file: $vf"
    # shellcheck disable=SC2046 # word-splitting registry pin_keys into allowlist args is intentional.
    box_load_version_file "$vf" "$(box_tool_field "$id" version_format)" $(box_tool_field "$id" pin_keys)
    for key in $(box_tool_field "$id" pin_keys); do
      [[ -n "${box_file_pin[$key]:-}" ]] || die "Empty pin after parse: $key"
      printf -v "$key" '%s' "${box_file_pin[$key]}"
    done
  done
  _BOX_PINS_LOADED_FOR=$bundle
}

# Print one pin value to stdout (for the Makefile, which cannot source shell
# code directly and must call via `bash -c`). Loads from <bundle_dir> each
# call so `make` stays correct with no exported state. The name must be a
# registry-declared pin key for some tool.
# Usage: box_print_pin <bundle_dir> <PIN_NAME>
box_print_pin() {
  local bundle=${1:-} name=${2:-}
  [[ -n "$bundle" && -n "$name" ]] || die 'Internal error: missing print-pin arguments.'
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Internal error: unknown pin name: $name"
  box_load_all_pins "$bundle"
  local id keys
  for id in $box_tool_ids; do
    keys=" $(box_tool_field "$id" pin_keys) "
    if [[ "$keys" == *" $name "* ]]; then
      printf '%s' "${!name}"
      return 0
    fi
  done
  die "Internal error: unknown pin name: $name"
}

# Single Dockerfile base-digest extractor (one parser for check-pins.sh +
# gen-pins.sh --check).
# Prints the single `sha256:<hex>` digest and fails closed on zero or >1.
# Usage: box_docker_base_digest <Dockerfile>
box_docker_base_digest() {
  local dockerfile=${1:-} digests count
  [[ -n "$dockerfile" ]] || die 'Internal error: missing Dockerfile path for digest.'
  [[ -f "$dockerfile" ]] || die "Missing Dockerfile: $dockerfile"
  digests=$(grep -Eo 'FROM debian:trixie-slim@sha256:[0-9a-f]{64}' "$dockerfile" \
    | grep -Eo 'sha256:[0-9a-f]{64}' | sort -u) || die 'Cannot extract Dockerfile base digest.'
  [[ -n "$digests" ]] || die 'No Debian digest found in Dockerfile.'
  count=$(printf '%s\n' "$digests" | wc -l)
  [[ "$count" -eq 1 ]] || die "Dockerfile must pin a single Debian digest, found: $digests"
  printf '%s' "$digests"
}

# Shared structural asserts: one strictness for check-pins.sh and
# gen-pins.sh --check (previously diverged: 10 flags + ban vs 6 flags).
# The ARG list derives from the registry (HOST_UID/HOST_GID plus every
# tool's pin_keys), so new tools are covered without an assert edit.
# Usage: box_assert_no_default_args <Dockerfile>
box_assert_no_default_args() {
  local dockerfile=${1:-} arg id
  [[ -n "$dockerfile" ]] || die 'Internal error: missing Dockerfile for ARG check.'
  local -a args=(HOST_UID HOST_GID)
  for id in $box_tool_ids; do
    for arg in $(box_tool_field "$id" pin_keys); do args+=("$arg"); done
  done
  for arg in "${args[@]}"; do
    grep -Eq "^ARG ${arg}[[:space:]]*$" "$dockerfile" \
      || die "Dockerfile must contain no-default ARG: ARG $arg (bare builds fail closed)"
    ! grep -Eq "^ARG ${arg}=" "$dockerfile" \
      || die "Dockerfile must not give ARG $arg a default (bare builds fail closed)"
  done
  grep -Eq '^ARG TARGETARCH([[:space:]]|$)' "$dockerfile" \
    || die 'Dockerfile must contain ARG TARGETARCH'
}

# Shared tarball-pin assert: the Dockerfile must verify packed bytes, not
# just registry metadata — scoped to npm-pinned tools (sha-pinned tools
# verify raw binaries via sha256sum instead, see the Dockerfile). When no
# registry tool declares npm-pinned, there is nothing to assert.
# Usage: box_assert_tarball_pins <Dockerfile>
box_assert_tarball_pins() {
  local dockerfile=${1:-}
  [[ -n "$dockerfile" ]] || die 'Internal error: missing Dockerfile for tarball check.'
  local id formats=' '
  for id in $box_tool_ids; do formats+="$(box_tool_field "$id" version_format) "; done
  [[ "$formats" == *' npm-pinned '* ]] || return 0
  grep -Fq 'npm pack' "$dockerfile" \
    || die 'Dockerfile must verify npm-pinned tarballs via npm pack (tarball-to-pin, not metadata-only)'
  grep -Fq 'createHash("sha512")' "$dockerfile" \
    || die 'Dockerfile must compute tarball sha512 hashes for the pin comparison'
}

# Shared SHELL-placement assert: SHELL cannot appear before the first FROM
# (BuildKit fails with "no build stage in current context") and resets on
# every FROM, so each target must repeat the canonical bash+pipefail SHELL.
# Usage: box_assert_shell_placement <Dockerfile>
box_assert_shell_placement() {
  local dockerfile=${1:-}
  [[ -n "$dockerfile" ]] || die 'Internal error: missing Dockerfile for SHELL check.'
  [[ -f "$dockerfile" ]] || die "Missing Dockerfile: $dockerfile"
  local first_from
  first_from=$(grep -n -m1 '^FROM ' "$dockerfile" | cut -d: -f1) \
    || die 'Cannot locate first FROM in Dockerfile.'
  [[ -n "$first_from" ]] || die 'Dockerfile must contain a FROM stage.'
  local n
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    (( n < first_from )) \
      && die 'Dockerfile must not place SHELL before the first FROM (no build stage in current context; SHELL is per-stage).'
  done < <(grep -n '^SHELL ' "$dockerfile" | cut -d: -f1 || true)
  local shell_count from_count
  shell_count=$(grep -Ec '^SHELL \["/bin/bash", "-o", "pipefail", "-c"\]([[:space:]]|$)' "$dockerfile") \
    || die 'Dockerfile must set SHELL to bash with pipefail in every stage.'
  from_count=$(grep -Ec '^FROM ' "$dockerfile") \
    || die 'Cannot count FROM stages in Dockerfile.'
  [[ "$shell_count" -eq "$from_count" ]] \
    || die "Dockerfile must repeat SHELL in every stage (found $shell_count canonical SHELL for $from_count FROM)."
  awk '/^FROM / { if (seen_from && shell_in_stage == 0) exit 1; seen_from = 1; shell_in_stage = 0; next } /^SHELL / { if (seen_from) shell_in_stage++ } END { exit !(seen_from && shell_in_stage > 0) }' "$dockerfile" \
    || die 'Dockerfile must contain a SHELL in every FROM stage.'
}

# Shared build-delegation assert: lib/build.sh owns flags; setup.sh and the
# Makefile delegate. Usage: box_assert_build_delegation <bundle_dir>
box_assert_build_delegation() {
  local bundle=${1:-} build_sh setup_sh makefile flag
  [[ -n "$bundle" ]] || die 'Internal error: missing bundle dir for delegation check.'
  build_sh="$bundle/lib/build.sh"
  setup_sh="$bundle/setup.sh"
  makefile="$bundle/Makefile"
  [[ -f "$build_sh" ]] || die "Missing build home: $build_sh"
  # shellcheck disable=SC2016 # '$tool'/'$pin'/'$target' literals below match lib/build.sh source text.
  for flag in 'box_require_tool "$tool"' 'box_tool_field "$tool" pin_keys' \
      'box_tool_field "$tool" label_pins' 'box_tool_field "$tool" dockerfile_target' \
      'box_tool_field "$tool" config_dir' '--build-arg "$pin=' '--target "$target"' \
      'box_docker_cli' 'box_load_all_pins'; do
    grep -Fq -- "$flag" "$build_sh" \
      || die "lib/build.sh must own the canonical build flags ($flag missing)"
  done
  if [[ -f "$setup_sh" ]]; then
    for flag in 'box_build_image' 'lib/build.sh'; do
      grep -Fq -- "$flag" "$setup_sh" \
        || die "setup.sh must delegate builds to lib/build.sh ($flag missing)"
    done
    ! grep -Fq -- 'build --pull' "$setup_sh" \
      || die 'setup.sh must not duplicate docker build blocks (use lib/build.sh)'
  fi
  if [[ -f "$makefile" ]]; then
    # shellcheck disable=SC2016 # '$(...)' literals below match Makefile source text.
    for flag in 'build-%: FORCE' 'box_tool_id_for_launcher "box-$*"' 'lib/build.sh" "$$_id"' \
        'build: $(addprefix build-,$(BUILD_STEMS))' 'lib/build.sh" --clean'; do
      grep -Fq -- "$flag" "$makefile" \
        || die "Makefile must delegate builds to lib/build.sh ($flag missing)"
    done
    ! grep -Fq 'cut -d=' "$makefile" \
      || die "Makefile must not parse version files with cut (pins live in lib/build.sh via lib/pins.sh)"
    ! grep -Eq '^[[:space:]]*[^#]*box_print_pin' "$makefile" \
      || die "Makefile must not parse pins per-var (single load inside lib/build.sh)"
  fi
}

# Extract the <!-- pin-table-start/end --> block from a doc file.
# Usage: box_pin_block <doc>  (prints block to stdout)
box_pin_block() {
  local doc=${1:-}
  [[ -n "$doc" ]] || die 'Internal error: missing doc for pin block.'
  sed -n '/<!-- pin-table-start -->/,/<!-- pin-table-end -->/p' "$doc"
}
