# shellcheck shell=bash
# box/lib/tools.sh — single declarative tool registry.
# Every tool (muse, opencode, and future additions) is one row of identity
# DATA here; shared code iterates the registry instead of branching
# `case "$tool" in muse|opencode)`. Adding a tool is one row plus the bounded
# surfaces in docs/adding-a-tool.md — never a shared-lib edit.
# Sourced after lib/preflight.sh (uses die). Never executed directly.
# Field reference (non-empty except opencode model/forward_keys — pure
# /connect ships no model and forwards no keys, so both are empty strings):
#   launcher          thin launcher file name (box-m)
#   image_prefix      docker image/tag prefix + container/volume prefix (box-m)
#   network           dedicated bridge network (box-m)
#   config_dir        host config dir name under ~/.config (box-m)
#   config_file       default config template file name (settings.json)
#   version_file      pin file name (version-muse.env)
#   dockerfile_target Dockerfile build target (muse)
#   version_format    pin-file shape (sha-pinned | npm-pinned); the version
#                     parser branches on format, never on tool name
#   model             seed-default model, mirrored in <config_file>; empty
#                     when the tool ships no model (opencode: pure /connect)
#   api_base_url      tool API base URL, mirrored in <config_file>; opencode
#                     carries the generic egress probe URL instead (no
#                     provider endpoint lives in its config)
#   probe_hosts       space-separated container-DNS probe hosts (ordered)
#   forward_keys      space-separated credential keys forwarded by --env
#                     NAME; empty when the tool forwards nothing (opencode:
#                     pure /connect — box_forward_keys no-ops on empty)
#   pin_keys          space-separated version-file key names in version_format
#                     positional order (also the Dockerfile build-arg names)
#   label_pins        space-separated PIN:LABEL_KEY pairs verified on the
#                     built image (a subset of pin_keys: toolchain-only pins
#                     such as NODE_VERSION carry no image label)
#   display           human tool name for generated docs (Muse)
#   config_base_path  jq path to the pinned config value inside <config_file>
#                     (.api.base_url); the readiness partial must mirror it
#                     (opencode pins .permission.external_directory — a
#                     permission value, not a URL)
#   pin_model         1 when the readiness partial pins the model value, 0
#                     when the model is a user-mutable seed default or absent
#                     (the config convention keeps .model top-level when set)
#   git_prefix        env prefix for git identity (BOX_M: BOX_M_GIT_NAME/_EMAIL)
# Single-source rule: per-tool identity lives ONLY here. lib/config.sh keeps
# just the genuinely shared values (credential allowlist, timeouts,
# resources) and must not gain per-tool constants.

[[ -n "${_BOX_TOOLS_LOADED:-}" ]] && return 0
_BOX_TOOLS_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Resolve our own dir without helpers (preflight.sh, which defines die, is
# sourced below). Same self-source pattern as lib/pins.sh so standalone
# consumers (`bash lib/build.sh`, `bash -c 'source lib/pins.sh ...'`) work.
_tools_src=${BASH_SOURCE[0]}
if command -v realpath >/dev/null 2>&1; then
  _tools_src=$(realpath -- "$_tools_src" 2>/dev/null || printf '%s' "$_tools_src")
elif command -v readlink >/dev/null 2>&1; then
  _tools_src=$(readlink -f -- "$_tools_src" 2>/dev/null || printf '%s' "$_tools_src")
fi
_tools_dir=$(dirname -- "$_tools_src")
unset _tools_src
# shellcheck source=lib/preflight.sh
source "$_tools_dir/preflight.sh"
unset _tools_dir

# Ordered tool ids (declaration order = install/build/generate order).
# shellcheck disable=SC2034 # consumed cross-file (setup.sh, generators, tests).
readonly box_tool_ids='muse opencode'

# Declared fields (every id defines every field; opencode model and
# forward_keys are empty by design — pure /connect).
# shellcheck disable=SC2034 # consumed by tests/bats/tools.bats completeness.
readonly box_tool_fields='launcher image_prefix network config_dir config_file version_file dockerfile_target version_format model api_base_url probe_hosts forward_keys pin_keys label_pins display config_base_path pin_model git_prefix'

# The table: composite "<id>,<field>" keys. -g: helpers.bash sources lib
# files inside setup(), where a plain declare would scope this local.
# shellcheck disable=SC2034 # read via box_tool_field.
declare -gA _BOX_TOOL_REGISTRY=(
  [muse,launcher]='box-m'
  [muse,image_prefix]='box-m'
  [muse,network]='box-m'
  [muse,config_dir]='box-m'
  [muse,config_file]='settings.json'
  [muse,version_file]='version-muse.env'
  [muse,dockerfile_target]='muse'
  [muse,version_format]='sha-pinned'
  [muse,model]='muse-spark-1.3'
  [muse,api_base_url]='https://api.meta.ai/v1'
  [muse,probe_hosts]='auth.meta.com api.meta.ai'
  [muse,forward_keys]='MUSE_CODE_API_KEY'
  [muse,pin_keys]='MUSE_VERSION MUSE_SHA256_AMD64 MUSE_SHA256_ARM64'
  [muse,label_pins]='MUSE_VERSION:org.meta.muse.box.version MUSE_SHA256_AMD64:org.meta.muse.box.sha256-amd64 MUSE_SHA256_ARM64:org.meta.muse.box.sha256-arm64'
  [muse,display]='Muse'
  [muse,config_base_path]='.api.base_url'
  [muse,pin_model]='0'
  [muse,git_prefix]='BOX_M'
  [opencode,launcher]='box-o'
  [opencode,image_prefix]='box-o'
  [opencode,network]='box-o'
  [opencode,config_dir]='box-o'
  [opencode,config_file]='opencode.json'
  [opencode,version_file]='version-opencode.env'
  [opencode,dockerfile_target]='opencode'
  [opencode,version_format]='npm-pinned'
  [opencode,model]=''
  [opencode,api_base_url]='https://registry.npmjs.org/opencode-ai'
  [opencode,probe_hosts]='registry.npmjs.org'
  [opencode,forward_keys]='' # pure /connect: zero manual keys forwarded
  [opencode,pin_keys]='OPENCODE_VERSION OPENCODE_NPM_INTEGRITY OPENCODE_NPM_INTEGRITY_LINUX_X64 OPENCODE_NPM_INTEGRITY_LINUX_ARM64 NODE_VERSION NODESOURCE_FINGERPRINT'
  [opencode,label_pins]='OPENCODE_VERSION:org.opencode.box.version OPENCODE_NPM_INTEGRITY:org.opencode.box.npm-integrity OPENCODE_NPM_INTEGRITY_LINUX_X64:org.opencode.box.npm-integrity-linux-x64 OPENCODE_NPM_INTEGRITY_LINUX_ARM64:org.opencode.box.npm-integrity-linux-arm64'
  [opencode,display]='OpenCode'
  [opencode,config_base_path]='.permission.external_directory'
  [opencode,pin_model]='0'
  [opencode,git_prefix]='BOX_O'
)

# Validate a tool id (fail-closed). Call this in the function BODY before
# capturing box_tool_field in $(...): die inside a command substitution
# exits only the subshell, so an unguarded capture would continue with an
# empty value in callers running without `set -e` (notably bats tests).
# Usage: box_require_tool <id>
box_require_tool() {
  local id=${1:-}
  case " $box_tool_ids " in
    *" $id "*) : ;;
    *) die "Internal error: unknown tool id: ${id:-<empty>}" ;;
  esac
}

# Map a launcher name back to its tool id. Used by the Makefile build-%
# pattern rule so `make build-<suffix>` tracks registry launchers
# (box-<suffix>) with zero per-tool lines. Fail-closed on unknown names.
# Usage: box_tool_id_for_launcher <launcher>  (e.g. box_tool_id_for_launcher box-m)
box_tool_id_for_launcher() {
  local name=${1:-} id
  [[ -n "$name" ]] || die 'Internal error: missing launcher name.'
  for id in $box_tool_ids; do
    if [[ "$(box_tool_field "$id" launcher)" == "$name" ]]; then printf '%s' "$id"; return 0; fi
  done
  die "Internal error: unknown launcher: $name"
}

# Print one registry value to stdout. Fail-closed: unknown id or field dies
# (never an empty expansion under `set -u` callers); a declared-but-empty
# value (opencode model/forward_keys under pure /connect) prints empty.
# Direct calls (not captured in $(...)) rely on this alone; captured calls
# must box_require_tool first (see above).
# Usage: box_tool_field <id> <field>  (e.g. box_tool_field muse network)
box_tool_field() {
  local id=${1:-} field=${2:-} value
  [[ -n "$id" && -n "$field" ]] || die 'Internal error: missing tool field arguments.'
  case " $box_tool_ids " in
    *" $id "*) : ;;
    *) die "Internal error: unknown tool id: $id" ;;
  esac
  # Existence (`+set`, safe under `set -u`), not non-emptiness, decides
  # unknown fields: empty values are legitimate registry data now.
  [[ -n "${_BOX_TOOL_REGISTRY[$id,$field]+set}" ]] \
    || die "Internal error: unknown tool field: $field"
  value=${_BOX_TOOL_REGISTRY[$id,$field]}
  printf '%s' "$value"
}
