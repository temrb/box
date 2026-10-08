# shellcheck shell=bash
# harnesses/opencode/auth.sh — OpenCode SQLite adapter (bash front-end).
# Delegates row operations to auth-state.py with explicit column lists and
# parameterized statements. Sessions, messages, events, approvals,
# workspace/project rows, configuration, caches and logs are never exported.
# Active selections live in the project-state sidecar, keyed by auth identity.

_box_opencode_helper() {
  if [[ -n "${BOX_AUTH_HELPER:-}" ]]; then printf '%s' "$BOX_AUTH_HELPER"; return 0; fi
  local bundle=${BOX_BUNDLE_DIR:-}
  if [[ -z "$bundle" && -n "${BASH_SOURCE[0]:-}" ]]; then
    bundle=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
    bundle=$(dirname -- "$bundle")
    bundle=$(dirname -- "$bundle")
  fi
  printf '%s/harnesses/opencode/auth-state.py' "${bundle:-.}"
}

# Pure validation: requires no initialized database or native mutation.
box_adapter_verify_envelope() {
  local envelope=${1:-}
  [[ -n "$envelope" ]] || return 1
  python3 -I "$(_box_opencode_helper)" verify-envelope --envelope "$envelope"
}

box_adapter_validate() {
  local db=${1:-}
  [[ -n "$db" ]] || return 1
  if [[ ! -e "$db" && ! -L "$db" ]]; then return 0; fi
  [[ ! -L "$db" && -f "$db" ]] || return 1
  python3 -I "$(_box_opencode_helper)" validate --db "$db" || return 1
}

box_adapter_export() {
  local db=${1:-} out=${2:-}
  [[ -n "$db" && -n "$out" ]] || return 1
  python3 -I "$(_box_opencode_helper)" export --db "$db" --out "$out" || return 1
  chmod 600 -- "$out" || return 1
}

box_adapter_install() {
  local envelope=${1:-} db=${2:-}
  [[ -n "$envelope" && -n "$db" ]] || return 1
  python3 -I "$(_box_opencode_helper)" install --db "$db" --envelope "$envelope" || return 1
}

box_adapter_collect() {
  box_adapter_export "$@"
}

box_adapter_scrub() {
  local db=${1:-}
  [[ -n "$db" ]] || return 1
  python3 -I "$(_box_opencode_helper)" scrub --db "$db" || return 1
}

# Preserve only managed auth in rollback storage. The mixed source database
# remains at its project location with credentials scrubbed in a transaction.
box_adapter_retire() {
  local legacy=${1:-} rollback=${2:-}
  [[ -n "$legacy" && -n "$rollback" ]] || return 1
  [[ -e "$legacy" ]] || return 0
  box_adapter_export "$legacy" "$rollback" || return 1
  box_adapter_scrub "$legacy" || return 1
}

# Legacy source for migration: OpenCode's mixed database lives on a project
# volume. Public migration/recovery uses the contained volume adapter and
# refuses raw host snapshot paths pending qualified contained import support.
# This adapter coordinate function also serves synthetic storage fixtures.
# Prints the path. Storage mechanics
# live here so shared code never branches on harness names.
# Usage: box_adapter_legacy_source <project-path> <project-hash> [db-path]
box_adapter_legacy_source() {
  local proj=${1:-} hash=${2:-} db=${3:-}
  [[ -n "$proj" ]] || return 1
  [[ "$hash" =~ ^[0-9a-f]{20}$ ]] || return 1
  if [[ -z "$db" ]]; then
    local domain=production descriptor
    box_test_in_test_mode && domain="test"
    box_state_context opencode "$(id -u)" "$(id -g)" "$proj" "$domain"
    descriptor=$(box_state_resolve volume) || return 1
    printf '%s' "$(sed -n 's/^path=//p' <<<"$descriptor")"
    return 0
  fi
  [[ "$db" == /* ]] || return 1
  case "$db" in *','*|*$'\n'*) return 1;; esac
  printf '%s' "$db"
}
