#!/bin/bash -p
# box/lib/build.sh — single image-build home.
# setup.sh -> box_build_image (sourced); Makefile -> `bash lib/build.sh`.
# Probes the isolated Docker CLI via box_docker_cli so no caller bypasses
# it with hardcoded `docker --config/--host`. When sourced, defines functions
# only (no set/export side effects on the caller). When executed, sets strict
# mode locally and builds/prints/removes the requested image.
# shellcheck disable=SC2034,SC2154 # pin globals cross files.

[[ -n "${_BOX_BUILD_LOADED:-}" ]] && return 0
_BOX_BUILD_LOADED=1

# Direct execution (`bash lib/build.sh ...`) sets no BOX_TOOL yet; default
# it here so the guards below pass. Sourced callers must set it first.
if [[ "${BASH_SOURCE[0]}" == "$0" && -z "${BOX_TOOL:-}" ]]; then
  BOX_TOOL=build.sh
fi

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Canonical self-dir bootstrap (no helpers yet; realpath preferred, readlink
# fallback). Same form in lib/tools.sh, lib/pins.sh, lib/build.sh; launchers
# and entry scripts use the 1-line variant (see box-m). Factored as a function
# here because box_bundle_dir() reuses it later.
_box_build_lib_dir() {
  local src=${BASH_SOURCE[0]}
  if command -v realpath >/dev/null 2>&1; then
    src=$(realpath -- "$src" 2>/dev/null || printf '%s' "$src")
  elif command -v readlink >/dev/null 2>&1; then
    src=$(readlink -f -- "$src" 2>/dev/null || printf '%s' "$src")
  fi
  dirname -- "$src" || return 1
}

# Source dependencies (each has its own load guard; double-source is free).
{
  _box_lib_dir=$(_box_build_lib_dir) || exit 1
  # shellcheck source=lib/preflight.sh
  source "$_box_lib_dir/preflight.sh"
  # shellcheck source=lib/tools.sh
  source "$_box_lib_dir/tools.sh"
  # shellcheck source=lib/config.sh
  source "$_box_lib_dir/config.sh"
  # shellcheck source=lib/docker.sh
  source "$_box_lib_dir/docker.sh"
  # shellcheck source=lib/pins.sh
  source "$_box_lib_dir/pins.sh"
  unset _box_lib_dir
}

# Canonical bundle dir (parent of lib/).
box_bundle_dir() {
  local lib_dir
  lib_dir=$(_box_build_lib_dir) || die 'Cannot resolve lib dir.'
  printf '%s' "$(dirname -- "$lib_dir")"
}

# Print the per-UID/GID image tag for <tool> at an already-validated
# <version> (no daemon contact, no pin loading). Single tag-format home:
# launchers call this with the config-file $file_version they already
# parsed, since the installed layout (~/.local/bin) carries launchers +
# lib only and has no bundle version files to load from. The tool id is
# validated by the registry lookup (fail-closed on unknown ids).
# Usage: box_image_tag_for_version <tool-id> <version> <uid> <gid>
box_image_tag_for_version() {
  local tool=${1:-} ver=${2:-} uid=${3:-} gid=${4:-} prefix
  box_require_tool "$tool"
  prefix=$(box_tool_field "$tool" image_prefix)
  [[ -n "$ver" && -n "$uid" && -n "$gid" ]] || die 'Internal error: missing tag arguments.'
  printf '%s:%s-u%s-g%s' "$prefix" "$ver" "$uid" "$gid"
}

# Print the per-UID/GID image tag for <tool> from a bundle dir (no daemon
# contact). Build-path only: loads pins, then delegates to the single
# format home above. Launchers must NOT use this (see above). The version
# is the first registry pin key (position 0 of every version_format).
# Usage: box_image_tag <tool-id> <bundle_dir> <uid> <gid>
box_image_tag() {
  local tool=${1:-} bundle=${2:-} uid=${3:-} gid=${4:-} ver vkey
  box_require_tool "$tool"
  [[ -n "$bundle" && -n "$uid" && -n "$gid" ]] || die 'Internal error: missing tag arguments.'
  box_load_all_pins "$bundle" >/dev/null
  vkey=$(box_tool_field "$tool" pin_keys); vkey=${vkey%% *}
  ver=${!vkey:-}
  [[ -n "$ver" ]] || die 'Empty version pin for tag.'
  box_image_tag_for_version "$tool" "$ver" "$uid" "$gid"
}

# Build + label-verify one tool image (single canonical path). Build args,
# Dockerfile target, CLI dir, and label keys all come from the registry, so
# one code path builds every tool.
# Usage: box_build_image <tool-id> [bundle_dir]
box_build_image() {
  local tool=${1:-} bundle=${2:-}
  box_require_tool "$tool"
  [[ -n "${HOME:-}" ]] || die 'HOME is unset.'
  if [[ -z "$bundle" ]]; then bundle=$(box_bundle_dir); fi
  local host_uid host_gid tag cli_dir target inspect_out pin pair lkey fmt expected
  local -a build_args=()
  host_uid=$(id -u) || die 'Cannot determine UID.'
  host_gid=$(id -g) || die 'Cannot determine GID.'
  ((host_uid > 0 && host_gid > 0)) || die 'Run as your normal non-root host user.'
  box_load_all_pins "$bundle"
  tag=$(box_image_tag "$tool" "$bundle" "$host_uid" "$host_gid")
  cli_dir="$HOME/.config/$(box_tool_field "$tool" config_dir)/docker-cli"
  target=$(box_tool_field "$tool" dockerfile_target)
  box_docker_cli "$cli_dir"
  build_args=(build --pull \
    --build-arg HOST_UID="$host_uid" \
    --build-arg HOST_GID="$host_gid")
  for pin in $(box_tool_field "$tool" pin_keys); do
    build_args+=(--build-arg "$pin=${!pin}")
  done
  "${docker_cmd[@]}" "${build_args[@]}" \
    --tag "$tag" \
    --file "$bundle/Dockerfile" --target "$target" \
    -- "$bundle" || die "Cannot build image $tag."
  fmt='{{.Config.User}}'
  expected="$host_uid:$host_gid"
  for pair in $(box_tool_field "$tool" label_pins); do
    pin=${pair%%:*}; lkey=${pair#*:}
    fmt+="|{{index .Config.Labels \"$lkey\"}}"
    expected+="|${!pin}"
  done
  inspect_out=$("${docker_cmd[@]}" image inspect \
    --format "$fmt" \
    -- "$tag") || die "Cannot inspect image $tag."
  [[ "$inspect_out" == "$expected" ]] \
    || die "Image labels mismatch after build $tag (got: $inspect_out)."
  printf '%s: built + labels verified: %s\n' "$BOX_TOOL" "$tag" >&2
}

# Remove one tool image via the isolated CLI (never fails the caller).
# Usage: box_clean_image <tool-id> [bundle_dir]
box_clean_image() {
  local tool=${1:-} bundle=${2:-}
  box_require_tool "$tool"
  [[ -n "${HOME:-}" ]] || die 'HOME is unset.'
  if [[ -z "$bundle" ]]; then bundle=$(box_bundle_dir); fi
  local host_uid host_gid tag cli_dir
  host_uid=$(id -u) || die 'Cannot determine UID.'
  host_gid=$(id -g) || die 'Cannot determine GID.'
  tag=$(box_image_tag "$tool" "$bundle" "$host_uid" "$host_gid")
  cli_dir="$HOME/.config/$(box_tool_field "$tool" config_dir)/docker-cli"
  box_docker_cli "$cli_dir"
  "${docker_cmd[@]}" image rm -- "$tag" || true
}

# Direct-execution CLI (sourcing returns above via the guard below).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export PATH
  BOX_TOOL=build.sh
  _box_want=${box_tool_ids// /|}
  case "${1:-}" in
    --tag)
      [[ -n "${2:-}" ]] || { echo "build.sh: usage: build.sh [--tag|--clean] <$_box_want>" >&2; exit 2; }
      (
        _b_dir=$(box_bundle_dir)
        box_image_tag "$2" "$_b_dir" "$(id -u)" "$(id -g)"
        printf '\n'
      )
      ;;
    --clean)
      [[ -n "${2:-}" ]] || { echo "build.sh: usage: build.sh [--tag|--clean] <$_box_want>" >&2; exit 2; }
      box_clean_image "$2"
      ;;
    ''|--help|-h) echo "Usage: build.sh [--tag|--clean] <$_box_want>" ;;
    *)
      case " $box_tool_ids " in
        *" $1 "*) box_build_image "$1" ;;
        *) echo "build.sh: unknown tool: $1 (want $_box_want)" >&2; exit 2 ;;
      esac
      ;;
  esac
fi
