# shellcheck shell=bash
# Format-based configuration parsing. Source after preflight.sh (die).
# JSON uses jq; TOML uses Python 3.11+ tomllib. Values and paths are passed
# as arguments, never evaluated as shell code or jq expressions.
[[ -n "${_BOX_CONFIG_FILE_LOADED:-}" ]] && return 0
_BOX_CONFIG_FILE_LOADED=1

box_config_require_parser() {
  case "${1:-}" in
    *.json) command -v jq >/dev/null || die 'jq is required for JSON configuration.' ;;
    *.toml)
      if ! command -v python3 >/dev/null || ! python3 -c 'import tomllib' >/dev/null 2>&1; then
        die 'Python 3.11+ with tomllib is required for TOML configuration.'
      fi ;;
    *) die 'Unsupported configuration extension (expected .json or .toml).' ;;
  esac
}

# Validate one complete object/table document, without printing its contents.
box_config_validate() {
  local file=${1:-}
  box_config_require_parser "$file"
  [[ -f "$file" && -r "$file" ]] || die 'Missing readable configuration file.'
  case "$file" in
    *.json)
      jq -e -s 'length == 1 and (.[0] | type == "object")' -- "$file" >/dev/null 2>&1 \
        || die 'Invalid JSON configuration (expected one object).' ;;
    *.toml)
      python3 - "$file" <<'PY' || die 'Invalid TOML configuration.'
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

# Extract a typed value from a simple dotted path (.api.base_url).
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
      python3 - "$file" "$path" "$kind" <<'PY' || die "Configuration lacks $kind $path."
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
