# shellcheck shell=bash
# box/lib/pins.sh — single pin-threading home.
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

# Canonical self-dir bootstrap (no helpers yet; realpath preferred, readlink
# fallback). Same form in lib/tools.sh, lib/pins.sh, lib/build.sh; launchers
# and entry scripts use the 1-line variant (see box-m). preflight.sh, which
# defines box_realpath, is sourced below.
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

# Parse an explicit candidate/source file and invalidate any bundle cache.
# Pin assignment stays here for both registered and isolated evaluation builds.
box_load_pins_file() {
  local file=$1 format=$2 pin_key
  shift 2
  box_load_version_file "$file" "$format" "$@"
  unset _BOX_PINS_LOADED_FOR
  for pin_key in "$@"; do
    [[ -n "${box_file_pin[$pin_key]:-}" ]] || die "Empty pin after parse: $pin_key"
    printf -v "$pin_key" '%s' "${box_file_pin[$pin_key]}"
  done
}

# Load every pin from the bundle (or any dir holding the registry version
# files). Results are cached per bundle dir (_BOX_PINS_LOADED_FOR) so repeated
# loads per build cost one parse. Pass a different bundle dir to reload.
# Iterates the registry: each tool id contributes its version file, parsed
# with its version_format + pin_keys. Pin values land in same-named globals
# (e.g. MUSE_VERSION, OPENCODE_SHA256_AMD64).
# Usage: box_load_all_pins <bundle_dir>
box_load_all_pins() {
  local bundle=${1:-}
  [[ -n "$bundle" ]] || die 'Internal error: missing bundle dir for pins.'
  if [[ "${_BOX_PINS_LOADED_FOR:-}" == "$bundle" ]]; then return 0; fi
  local id vf
  for id in $box_tool_ids; do
    vf="$bundle/$(box_tool_field "$id" version_source)"
    [[ -f "$vf" ]] || die "Missing pin file: $vf"
    # shellcheck disable=SC2046 # word-splitting registry pin_keys into allowlist args is intentional.
    box_load_pins_file "$vf" "$(box_tool_field "$id" version_format)" $(box_tool_field "$id" pin_keys)
  done
  _BOX_PINS_LOADED_FOR=$bundle
}

# Forget the cached bundle dir and re-parse every pin from <bundle_dir>.
# update-pins.sh rewrites version files in-process, so the build after the
# rewrite must see the new pins instead of the cached old ones.
# Usage: box_reload_all_pins <bundle_dir>
box_reload_all_pins() {
  local bundle=${1:-}
  [[ -n "$bundle" ]] || die 'Internal error: missing bundle dir for pins.'
  unset _BOX_PINS_LOADED_FOR
  box_load_all_pins "$bundle"
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

# A pin must be declared AND consumed outside labels/comments in its own
# stage. An ARG or checksum check in a different target cannot satisfy it.
box_assert_stage_pins() {
  local dockerfile=$1 id target stage pin executable
  for id in $box_tool_ids; do
    target=$(box_tool_field "$id" dockerfile_target)
    stage=$(awk -v target="$target" '/^FROM / { active = ($NF == target) } active { print }' "$dockerfile")
    [[ -n "$stage" ]] || die "Missing stage: $target"
    executable=$(printf '%s\n' "$stage" | awk '/^#/ {next} /^LABEL / {label=1} label {if ($0 !~ /\\$/) label=0; next} {print}')
    for pin in $(box_tool_field "$id" pin_keys); do
      grep -Eq "^ARG $pin$" <<<"$stage" || die "Stage $target must declare ARG $pin"
      if ! grep -Fq "\$$pin" <<<"$executable" && ! grep -Fq "\${$pin" <<<"$executable"; then
        die "Stage $target must consume $pin outside labels"
      fi
    done
  done
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
  # Reject any non-canonical SHELL outright: otherwise a non-canonical SHELL
  # in one stage compensated by two canonical in another passes the count
  # check below (canonical count == FROM count) plus per-stage >=1-SHELL.
  local non_canonical
  non_canonical=$(grep -E '^SHELL ' "$dockerfile" | grep -Ev '^SHELL \["/bin/bash", "-o", "pipefail", "-c"\]([[:space:]]|$)' || true)
  [[ -z "$non_canonical" ]] \
    || die 'Dockerfile must use only the canonical SHELL ["/bin/bash", "-o", "pipefail", "-c"] in every stage.'
  local shell_count from_count
  shell_count=$(grep -Ec '^SHELL \["/bin/bash", "-o", "pipefail", "-c"\]([[:space:]]|$)' "$dockerfile") \
    || die 'Dockerfile must set SHELL to bash with pipefail in every stage.'
  from_count=$(grep -Ec '^FROM ' "$dockerfile") \
    || die 'Cannot count FROM stages in Dockerfile.'
  [[ "$shell_count" -eq "$from_count" ]] \
    || die "Dockerfile must repeat SHELL in every stage (found $shell_count canonical SHELL for $from_count FROM)."
  # Every SHELL is canonical at this point (rejected above), so per-stage
  # >=1 plus the count equality above implies exactly one canonical SHELL
  # per FROM stage.
  awk '/^FROM / { if (seen_from && shell_in_stage == 0) exit 1; seen_from = 1; shell_in_stage = 0; next } /^SHELL / { if (seen_from) shell_in_stage++ } END { exit !(seen_from && shell_in_stage > 0) }' "$dockerfile" \
    || die 'Dockerfile must contain a canonical SHELL in every FROM stage.'
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

# Read-only setup guard: reject obsolete contracts before any installed write.
box_plan_installed_pins() {
  local id=$1 file=$2
  [[ -e "$file" ]] || return 0
  # Parsing in a subshell preserves the bundled build pins.
  # shellcheck disable=SC2046 # ordered registry keys intentionally split
  if ! (box_load_version_file "$file" "$(box_tool_field "$id" version_format)" $(box_tool_field "$id" pin_keys)); then
    die "Incompatible installed $id pins: $file. Build the bundled image with make -C box build-$(box_tool_field "$id" launcher | sed 's/box-//'), run make -C box sync-pins-$(box_tool_field "$id" launcher | sed 's/box-//'), then rerun setup."
  fi
}

# Explicit installed-pin recovery. Subshell owns cleanup and parsed pin state.
# Callers source build.sh for the existing image/Docker helpers.
box_sync_installed_pins() (
  local id=${1:-} bundle=${2:-} skip_missing=${3:-0} cfg dest vf stage='' image rc
  local host_uid host_gid
  box_require_tool "$id"
  [[ -n "$bundle" ]] || die 'Internal error: missing synchronization bundle.'
  host_uid=$(id -u) || die 'Cannot determine UID.'
  host_gid=$(id -g) || die 'Cannot determine GID.'
  ((host_uid > 0 && host_gid > 0)) || die 'Run as your normal non-root host user.'
  cfg="$HOME/.config/$(box_tool_field "$id" config_dir)"
  cfg=$(box_plan_directory "$cfg") || exit 1
  # Mode 2 preserves the updater inventory from before builds create CLI dirs.
  if [[ ! -d "$cfg" || "$skip_missing" == 2 ]]; then
    if [[ "$skip_missing" == 1 || "$skip_missing" == 2 ]]; then
      printf '%s: WARNING: %s is not installed; skipping installed-pin sync (run setup.sh).\n' "$BOX_TOOL" "$cfg" >&2
      exit 0
    fi
    die "Missing installed config directory: $cfg (run setup first)."
  fi
  vf=$(box_tool_field "$id" version_file)
  dest="$cfg/$vf"
  [[ ! -L "$dest" ]] || die "Refusing to follow symlink: $dest"
  [[ ! -e "$dest" || -f "$dest" ]] || die 'Installed pins must be a regular file.'
  if [[ -e "$dest" ]]; then box_assert_owner_mode "$dest" 'Installed pins' nowrite; fi
  stage=$(mktemp "$cfg/.${vf}.tmp.XXXXXX") || die "Cannot stage installed pin sync: $dest"
  trap 'rm -f -- "$stage"' EXIT
  cp -- "$bundle/$(box_tool_field "$id" version_source)" "$stage" || die "Cannot copy staged pins: $dest"
  chmod 644 -- "$stage" || die "Cannot secure staged pins: $dest"
  # shellcheck disable=SC2046 # registry key allowlist intentionally split
  box_load_version_file "$stage" "$(box_tool_field "$id" version_format)" $(box_tool_field "$id" pin_keys)
  box_docker_cli "$cfg/docker-cli"
  image=$(box_image_tag_for_version "$id" "$box_file_version" "$host_uid" "$host_gid") || exit 1
  box_assert_image "$image" "$box_file_version" "$stage" "$id" 0
  if [[ -e "$dest" ]]; then
    if cmp -s -- "$stage" "$dest"; then
      printf '%s: installed pins already match: %s\n' "$BOX_TOOL" "$dest"
      exit 0
    else
      rc=$?
      [[ "$rc" == 1 ]] || die "Cannot compare installed pins: $dest"
    fi
  fi
  mv -fT -- "$stage" "$dest" || die "Cannot sync installed pins: $dest"
  printf '%s: synced %s\n' "$BOX_TOOL" "$dest"
)
