# shellcheck shell=bash
# Host installation file operations, separated from Docker/setup orchestration.
# Source after preflight.sh and tools.sh. These helpers never read secrets.
# box_atomic_install is the single src→dest atomic-publish home (update-pins
# install_candidate migrated here too). Content writers stay separate by
# construction: box_write_if_changed (compare + reference-mode),
# box_seed_writable_config (create-only + hardlink publish), the docker-CLI
# reset (generated content + backup), and the installed-pin sync (validation
# between staging and publish) cannot share a src→dest primitive.
# shellcheck disable=SC2154 # registry and host_uid belong to the caller.
[[ -n "${_BOX_INSTALL_LOADED:-}" ]] && return 0
_BOX_INSTALL_LOADED=1

box_install_warn() { printf '  [warn] %s\n' "$*" >&2; }

# Stage beside the destination so failed/interrupted writes leave its valid
# bytes intact. A subshell keeps cleanup traps local to this operation.
# Usage: box_atomic_install <src> <dest> <mode>
box_atomic_install() (
  local src=$1 dest=$2 mode=$3 stage
  stage=$(mktemp "${dest%/*}/.box-install.XXXXXX") || die "Cannot stage installation: $dest"
  trap 'rm -f -- "$stage"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  install -m "$mode" -- "$src" "$stage" || die "Cannot stage installation: $dest"
  mv -fT -- "$stage" "$dest" || die "Cannot install: $dest"
)

# Refresh a template, preserving one backup of a customized predecessor.
box_install_tool_config() {
  local src=${1:-} dest=${2:-}
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing tool-config paths.'
  [[ ! -L "$dest" && ! -L "$dest.bak" ]] || die "Refusing to follow symlink: $dest (or backup)"
  [[ ! -e "$dest" || -f "$dest" ]] || die 'Tool configuration must be a regular file.'
  [[ ! -e "$dest.bak" || -f "$dest.bak" ]] || die 'Configuration backup must be a regular file.'
  if [[ -e "$dest" ]] && ! cmp -s -- "$src" "$dest"; then
    cp -p -- "$dest" "$dest.bak" || die "Cannot back up customized config: $dest"
    box_install_warn "$dest customized; previous version saved to $dest.bak (overwritten)."
  fi
  box_atomic_install "$src" "$dest" "${3:-644}"
}

# Installed pins win on reruns; only explicit update/sync replaces them.
box_install_version_pin() {
  local src=${1:-} dest=${2:-}
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing version-pin paths.'
  [[ ! -L "$dest" && ! -L "$src" ]] || die "Refusing to follow symlink in version-pin paths: $dest"
  [[ ! -e "$dest" || -f "$dest" ]] || die 'Installed pins must be a regular file.'
  if [[ ! -e "$dest" ]]; then
    box_atomic_install "$src" "$dest" 644
  elif ! cmp -s -- "$src" "$dest"; then
    box_install_warn "$dest differs from the bundle; keeping installed pins (sync via make -C box sync-pins-<stem>; see docs/upgrades.md)."
  fi
}

# Preserve an existing registered default unless the caller selected an id.
# A fresh install chooses the first registry tool. Reject unmanaged links.
box_install_default() {
  local dest=${1:-} id=${2:-} current candidate known=0
  [[ -n "$dest" ]] || die 'Internal error: missing default launcher path.'
  [[ ! -e "$dest" || -L "$dest" ]] || die "Refusing to clobber non-symlink: $dest"
  if [[ -z "$id" && -L "$dest" ]]; then
    current=$(readlink -- "$dest") || die 'Cannot read default launcher.'
    for candidate in $box_tool_ids; do
      if [[ "$current" == "$(box_tool_field "$candidate" launcher)" ]]; then known=1; break; fi
    done
    ((known)) || die "Unknown default launcher symlink: $dest (select --default <id>)."
    printf '%s' "$current"
    return 0
  fi
  id=${id:-${box_tool_ids%% *}}
  box_require_tool "$id"
  current=$(box_tool_field "$id" launcher)
  ln -sfn -- "$current" "$dest" || die 'Cannot install default launcher.'
  printf '%s' "$current"
}

# Create an empty provider file exclusively, or secure its existing mode.
# Print only a creation verdict; never inspect or print credential contents.
box_install_provider_file() {
  local dest=${1:-} fuid mode
  [[ -n "$dest" ]] || die 'Internal error: missing provider-file path.'
  [[ ! -L "$dest" ]] || die "Refusing to follow symlink: $dest"
  if [[ ! -e "$dest" ]]; then
    (umask 077; set -o noclobber; : > "$dest") || die "Cannot create exclusive providers file: $dest"
    [[ ! -L "$dest" ]] || die "Refusing to follow symlink: $dest"
    printf 'created'
  else
    [[ -f "$dest" ]] || die 'Providers file must be a regular file.'
    fuid=$(stat -c %u -- "$dest") || die 'Cannot stat providers file.'
    [[ "$fuid" == "$host_uid" ]] || die 'Credentials file must be owned by you.'
    mode=$(stat -c %a -- "$dest") || die 'Cannot stat providers file.'
    case "$mode" in 400|600) : ;; *) chmod 600 -- "$dest" || die 'Cannot secure providers file.' ;; esac
    printf 'kept'
  fi
}

# Seed the versioned state-policy file with no explicit scope settings.
# Reruns preserve it byte-for-byte and never migrate login material.
# Setup installs the interface; scope stays configurable at runtime and
# durably through user configuration. Prints created|kept.
# Usage: box_install_state_policy [path]  (default $HOME/.config/box/state.toml)
box_install_state_policy() {
  local dest=${1:-$HOME/.config/box/state.toml}
  [[ ! -L "$dest" ]] || die "Refusing to follow symlink: $dest"
  if [[ ! -e "$dest" ]]; then
    [[ -d "$(dirname -- "$dest")" ]] || die "Missing state-policy parent: $(dirname -- "$dest")"
    (
      local stage
      stage=$(mktemp "${dest%/*}/.state-policy.XXXXXX") || die 'Cannot stage state policy.'
      trap 'rm -f -- "$stage"' EXIT
      printf 'schema_version = 1\n' >"$stage" || die 'Cannot stage state policy.'
      chmod 600 -- "$stage" || die 'Cannot secure state policy.'
      ln -T -- "$stage" "$dest" || die 'Cannot exclusively install state policy.'
    ) || return 1
    printf 'created'
  else
    [[ -f "$dest" ]] || die 'State policy must be a regular file.'
    [[ "$(stat -c %u -- "$dest")" == "$host_uid" ]] || die 'State policy must be owned by you.'
    case "$(stat -c %a -- "$dest")" in 600|400) : ;; *) die 'State policy must be mode 600 (400 also accepted).' ;; esac
    printf 'kept'
  fi
}
