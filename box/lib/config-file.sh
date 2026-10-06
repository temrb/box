# shellcheck shell=bash
# Format-based configuration parsing. Source after preflight.sh (die).
# JSON uses jq; TOML uses Python 3.11+ tomllib. Values and paths are passed
# as arguments, never evaluated as shell code or jq expressions.
[[ -n "${_BOX_CONFIG_FILE_LOADED:-}" ]] && return 0
_BOX_CONFIG_FILE_LOADED=1

box_config_require_parser() {
  case "${1:-}" in
    json|*.json) command -v jq >/dev/null || die 'jq is required for JSON configuration.' ;;
    toml|*.toml)
      if ! command -v python3 >/dev/null || ! python3 -I -c 'import tomllib' >/dev/null 2>&1; then
        die 'Python 3.11+ with tomllib is required for TOML configuration.'
      fi ;;
    *) die 'Unsupported configuration extension (expected .json or .toml).' ;;
  esac
}

# Validate one complete object/table document, without printing its contents.
# Usage: box_config_validate <file> [format]  (format: json|toml; default: file extension)
# An explicit format parses by format even when the path lacks the matching
# extension (e.g. a BOX_*_CONFIG override pointing at extensionless TOML);
# without it the extension decides, as before.
box_config_validate() {
  local file=${1:-} format=${2:-}
  if [[ -z "$format" ]]; then
    case "$file" in
      *.json) format=json ;;
      *.toml) format=toml ;;
      *) die 'Unsupported configuration extension (expected .json or .toml).' ;;
    esac
  fi
  case "$format" in
    json|toml) ;;
    *) die "Unsupported configuration format (expected json or toml): $format" ;;
  esac
  box_config_require_parser "$format"
  [[ -f "$file" && -r "$file" ]] || die "Missing readable configuration file: $file"
  case "$format" in
    json)
      jq -e -s 'length == 1 and (.[0] | type == "object")' -- "$file" >/dev/null 2>&1 \
        || die "Invalid JSON configuration (expected one object): $file" ;;
    toml)
      python3 -I - "$file" <<'PY' || die "Invalid TOML configuration: $file"
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as source:
        tomllib.load(source)
except (OSError, ValueError):
    sys.exit(1)
PY
      ;;
  esac
}

# Extract a typed value from a simple dotted path (.endpoint_transport.base_url).
# Strings print raw; booleans/numbers/arrays/objects print JSON. False and
# empty strings are valid values; missing values and null are rejected.
box_config_get() {
  local file=${1:-} path=${2:-} kind=${3:-string}
  [[ "$path" =~ ^(\.[A-Za-z_][A-Za-z0-9_-]*)+$ ]] \
    || die 'Unsupported configuration path (expected simple dotted keys).'
  case "$kind" in
    string|boolean|number|array|object) : ;;
    *) die 'Unsupported configuration value type.' ;;
  esac
  box_config_validate "$file"
  case "$file" in
    *.json)
      jq -r --arg path "$path" --arg kind "$kind" '
        getpath($path | split(".")[1:]) |
        if type == $kind then
          if $kind == "string" then . else tojson end
        else error("invalid type") end
      ' -- "$file" 2>/dev/null \
        || die "Configuration lacks $kind $path." ;;
    *.toml)
      python3 -I - "$file" "$path" "$kind" <<'PY' || die "Configuration lacks $kind $path."
import json, sys, tomllib
try:
    with open(sys.argv[1], "rb") as source:
        value = tomllib.load(source)
    for key in sys.argv[2].split(".")[1:]:
        value = value[key]
    kinds = {"string": (str,), "boolean": (bool,), "number": (int, float),
             "array": (list,), "object": (dict,)}
    if type(value) not in kinds[sys.argv[3]]:
        raise ValueError()
    print(value if sys.argv[3] == "string" else json.dumps(value, allow_nan=False))
except (OSError, ValueError, KeyError, TypeError):
    sys.exit(1)
PY
      ;;
  esac
}

# Merge strict JSON preference layers. Empty objects contribute no overrides.
box_config_merge_json() {
  local file
  for file in "$@"; do box_config_validate "$file"; done
  jq -s '
    def merge($base; $override):
      if ($override | type) == "object" then
        if ($override | length) == 0 then $base
        else reduce ($override | keys_unsorted[]) as $key
          (if ($base | type) == "object" then $base else {} end;
           .[$key] = merge(.[$key]; $override[$key])) end
      else $override end;
    reduce .[] as $layer ({}; merge(.; $layer))' -- "$@"
}

# Print one document as canonical compact JSON (dispatch on extension, like
# box_config_validate; optional explicit format second arg). Pure reader:
# callers validate separately and die with context (same contract as the
# updater's fetch_url). Returns 1 on unreadable documents.
# Usage: json=$(box_config_canonical_json <file> [format]) || die ...
box_config_canonical_json() {
  local file=${1:-} format=${2:-}
  [[ -n "$file" ]] || die 'Internal error: missing canonicalize path.'
  if [[ -z "$format" ]]; then
    case "$file" in
      *.json) format=json ;;
      *.toml) format=toml ;;
      *) die 'Unsupported configuration extension (expected .json or .toml).' ;;
    esac
  fi
  case "$format" in
    json) jq -c . -- "$file" || return 1 ;;
    toml) python3 -I -c 'import sys,tomllib,json; print(json.dumps(tomllib.load(open(sys.argv[1], "rb")),separators=(",",":")))' "$file" || return 1 ;;
    *) die "Unsupported configuration format (expected json or toml): $format" ;;
  esac
}

# Print TOML sections for records under <table> carrying <key> (native
# trust/preference preservation pattern). Prints nothing when absent.
# Callers pass their own schema paths; shared code holds no per-tool keys.
# Returns 1 on unreadable documents (callers die with context).
# Usage: trust=$(box_config_toml_subtree <file> <table> <key>) || die ...
box_config_toml_subtree() {
  local file=${1:-} table=${2:-} key=${3:-}
  [[ -n "$file" && -n "$table" && -n "$key" ]] || die 'Internal error: missing subtree arguments.'
  [[ "$table" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ && "$key" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] \
    || die 'Unsupported TOML subtree path.'
  python3 -I - "$file" "$table" "$key" <<'PY' || return 1
import json, sys, tomllib
with open(sys.argv[1], 'rb') as f:
    data = tomllib.load(f)
for path, record in data.get(sys.argv[2], {}).items():
    if isinstance(record, dict) and sys.argv[3] in record:
        print('[' + sys.argv[2] + '.' + json.dumps(path, ensure_ascii=False) + ']')
        print(sys.argv[3] + ' = ' + json.dumps(record[sys.argv[3]], ensure_ascii=False))
PY
}
