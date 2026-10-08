# shellcheck shell=bash
# harnesses/muse/auth.sh — Muse file-adapter for managed auth projections.
# Canonical envelope <-> native auth.json projection. Trust, settings,
# sessions and MCP stores are never exported. Backend qualification:
# file backend only; keychain-only behaviour fails explicitly.
# Adapter contract (generic names; sourced alone, never with siblings):
#   box_adapter_validate <native-auth-path>
#   box_adapter_export <native-auth-path> <envelope-out>
#   box_adapter_install <envelope> <native-auth-path>
#   box_adapter_collect <native-auth-path> <envelope-out>
#   box_adapter_scrub <native-auth-path>
#   box_adapter_retire <legacy-native-path> <rollback-path>

box_adapter_validate() {
  local native=${1:-}
  [[ -n "$native" ]] || return 1
  # Pinned 1.4.0-R4161.1, TBH_CREDENTIAL_BACKEND=file: auth set writes
  # schema 1 / providers.meta.api_key; logout retains an empty providers map.
  # Unknown providers, keychain references and OAuth shapes stay authoritative
  # in their native store until separately qualified.
  if [[ ! -e "$native" && ! -L "$native" ]]; then return 0; fi
  [[ ! -L "$native" && -f "$native" ]] || return 1
  box_adapter_path_safe "$native" || return 1
  command -v jq >/dev/null 2>&1 || return 1
  _box_adapter_payload_valid < "$native" || {
    printf 'Unsupported Muse credential schema/backend; only qualified file Meta API-key credentials are supported. Native state is retained.\n' >&2
    return 1
  }
}

# Validate semantic payloads directly from stdin, without native projections.
_box_adapter_payload_valid() {
  jq -e 'type == "object" and (length == 0 or (
    (keys == ["providers","schema_version"]) and .schema_version == 1 and
    (.providers | type == "object" and ((keys - ["meta"]) | length == 0)) and
    ((.providers | has("meta") | not) or (.providers.meta | type == "object" and
      keys == ["api_key"] and (.api_key | type == "string" and length > 0)))
  ))' >/dev/null 2>&1
}

box_adapter_verify_envelope() (
  set -o pipefail
  local envelope=${1:-}
  [[ -n "$envelope" ]] || return 1
  jq -e 'type == "object" and .schema_version == 1 and .harness == "muse" and
    .adapter_schema == 1 and (.revision | type == "number" and . >= 0 and floor == .) and
    (.tombstone | type == "boolean") and
    (if .tombstone then .payload == null else (.payload | type == "object") end)' \
    -- "$envelope" >/dev/null 2>&1 || return 1
  if jq -e '.tombstone == true' -- "$envelope" >/dev/null 2>&1; then return 0; fi
  jq -c '.payload' -- "$envelope" | _box_adapter_payload_valid
)

box_adapter_export_staged() {
  local native=${1:-} out=${2:-}
  [[ -n "$native" && -n "$out" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  if [[ ! -e "$native" && ! -L "$native" ]]; then
    jq -n --arg harness muse --argjson schema 1 \
      '{schema_version:$schema,harness:$harness,adapter_schema:1,revision:1,tombstone:true,payload:null}' >"$out" || return 1
    chmod 600 -- "$out" || return 1
    return 0
  fi
  box_adapter_validate "$native" || return 1
  jq -n --arg harness muse --argjson schema 1 --slurpfile p "$native" \
    '($p[0].providers.meta.api_key != null) as $present |
     {schema_version:$schema,harness:$harness,adapter_schema:1,revision:1,
      tombstone:($present | not),payload:(if $present then $p[0] else null end)}' >"$out" || return 1
  chmod 600 -- "$out" || return 1
}

# Check exact file destinations before staging, tombstone deletion or scrub.
box_adapter_path_safe() {
  python3 -I - "$1" <<'CHECK'
import os, stat, sys
from pathlib import Path
try:
    target = Path(sys.argv[1])
    for parent in (target.parent, *target.parent.parents):
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError("unsafe parent")
    if target.exists() or target.is_symlink():
        info = target.lstat()
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                or info.st_uid != os.getuid()):
            raise ValueError("unsafe file")
except (OSError, ValueError):
    sys.exit(1)
CHECK
}

# Publish only a private staged file, with durable replacement. Refuse links,
# shared inodes and foreign destinations before changing any existing bytes.
box_adapter_publish() {
  python3 -I - "$1" "$2" <<'PUBLISH'
import os, stat, sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
try:
    for parent in (target.parent, *target.parent.parents):
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError("unsafe parent")
    if target.exists() or target.is_symlink():
        info = target.lstat()
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                or info.st_uid != os.getuid()):
            raise ValueError("unsafe destination")
    with source.open("rb") as stream:
        os.fsync(stream.fileno())
    os.replace(source, target)
    fd = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
except (OSError, ValueError):
    sys.exit(1)
PUBLISH
}

box_adapter_export() (
  local native=${1:-} out=${2:-} staged
  [[ -n "$native" && -n "$out" ]] || return 1
  box_adapter_path_safe "$out" || return 1
  staged=$(mktemp "$(dirname -- "$out")/.box-auth-export.XXXXXX") || return 1
  trap 'rm -f -- "$staged"' EXIT
  box_adapter_export_staged "$native" "$staged" || return 1
  box_adapter_publish "$staged" "$out"
)

box_adapter_install() (
  local envelope=${1:-} native=${2:-} staged
  [[ -n "$envelope" && -n "$native" ]] || return 1
  box_adapter_path_safe "$native" || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e 'type == "object" and .schema_version == 1 and .harness == "muse" and .adapter_schema == 1 and
    (.revision | type == "number" and . >= 0 and floor == .) and
    (.tombstone | type == "boolean") and
    (if .tombstone then .payload == null else (.payload | type == "object") end)' -- "$envelope" >/dev/null 2>&1 || return 1
  if jq -e '.tombstone == true' -- "$envelope" >/dev/null 2>&1; then
    box_adapter_scrub "$native" || return 1
    return 0
  fi
  jq -e '.tombstone == false and (.payload | type == "object")' -- "$envelope" >/dev/null 2>&1 || return 1
  staged=$(mktemp "$(dirname -- "$native")/.box-auth-install.XXXXXX") || return 1
  trap 'rm -f -- "$staged"' EXIT
  jq -c '.payload' -- "$envelope" >"$staged" || return 1
  box_adapter_validate "$staged" || return 1
  box_adapter_publish "$staged" "$native"
)

box_adapter_collect() {
  box_adapter_export "$@"
}

box_adapter_scrub() {
  local native=${1:-}
  [[ -n "$native" ]] || return 1
  box_adapter_path_safe "$native" || return 1
  python3 -I - "$native" <<'SCRUB'
import os, sys
from pathlib import Path
try:
    target = Path(sys.argv[1])
    target.unlink(missing_ok=True)
    fd = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
except OSError:
    sys.exit(1)
SCRUB
}

# Retire legacy auth from its active importer path after the canonical
# destination verified. Absent sources succeed silently; symlinks fail.
# Usage: box_adapter_retire <legacy-native-path> <rollback-path>
box_adapter_retire() {
  local legacy=${1:-} rollback=${2:-}
  [[ -n "$legacy" && -n "$rollback" ]] || return 1
  if [[ ! -e "$legacy" && ! -L "$legacy" ]]; then return 0; fi
  [[ ! -L "$legacy" && -f "$legacy" ]] || return 1
  mv -f -- "$legacy" "$rollback" || return 1
  chmod 600 -- "$rollback" || return 1
}

# Legacy source for migration gate/planning: exact resolved native auth path
# for (project-path, project-hash). Prints the path (which may not exist →
# fresh). Dies on unsafe paths. Storage mechanics live here so shared code
# never branches on harness names.
# Usage: box_adapter_legacy_source <project-path> <project-hash>
box_adapter_legacy_source() {
  local proj=${1:-} hash=${2:-}
  [[ -n "$proj" && -n "$hash" ]] || return 1
  [[ "$hash" =~ ^[0-9a-f]{20}$ ]] || return 1
  local home=${BOX_M_PERSIST_DIR:-$HOME/.config/box-m/muse-config}
  [[ "$home" == /* ]] || return 1
  # Validate without creation (plan-only); containment is checked by callers.
  case "$home" in *','*|*$'\n'*) return 1;; esac
  printf '%s/auth.json' "$home"
}
