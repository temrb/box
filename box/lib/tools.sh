# shellcheck shell=bash
# Central declarative harness, artifact, state and adapter contracts.
[[ -n "${_BOX_TOOLS_LOADED:-}" ]] && return 0
_BOX_TOOLS_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Canonical self-dir bootstrap (bootstrap paradox: no helpers exist yet, so
# every site copies this snippet instead of sharing it; realpath preferred,
# readlink fallback). Same form in lib/preflight.sh, lib/pins.sh,
# lib/build.sh; launchers and entry scripts use the 1-line variant (see
# box-m). Drift fails loudly via the shape test in tests/bats/preflight.bats.
# preflight.sh, which defines die, is sourced below. Same self-source pattern
# as lib/pins.sh so standalone consumers (`bash lib/build.sh`,
# `bash -c 'source lib/pins.sh ...'`) work.
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
readonly box_tool_ids='muse opencode codex'

# Declared fields (every id defines every field; forwarding/install adapters
# may be empty when native authentication or preparation needs none).
# Probe endpoints are canonical HTTPS URLs whose host must appear in
# probe_hosts and in the harness 30-network partial (muse exact URL equals
# settings.json endpoint_transport.base_url; codex/opencode hosts match
# their network probes).
# launchers probe DNS via probe_hosts (lib/launcher.sh); verify harnesses prove
# egress against probe_url/probe_hosts. No per-tool literals elsewhere.
# shellcheck disable=SC2034 # consumed by tests/bats/tools.bats completeness.
readonly box_tool_fields='launcher image_prefix network state_prefix config_dir config_file version_file dockerfile_target version_format probe_hosts forward_keys pin_keys label_pins display git_prefix package version_source launch_adapter install_adapter update_adapter validate_adapter native_helper verify_label artifacts states probe_url directory_configs directory_parser'

# The table: composite "<id>,<field>" keys. -g: helpers.bash sources lib
# files inside setup(), where a plain declare would scope this local.
# shellcheck disable=SC2034 # read via box_tool_field.
declare -gA _BOX_TOOL_REGISTRY=(
  [muse,directory_parser]='json'
  [muse,directory_configs]='.muse/settings.json'
  [muse,launcher]='box-m'
  [muse,image_prefix]='box-m'
  [muse,network]='box-m'
  [muse,state_prefix]='box-m'
  [muse,config_dir]='box-m'
  [muse,config_file]='settings.json'
  [muse,version_file]='version-muse.env'
  [muse,dockerfile_target]='muse'
  [muse,version_format]='sha-pinned'
  [muse,probe_hosts]='auth.meta.com api.meta.ai'
  [muse,forward_keys]='MUSE_CODE_API_KEY'
  [muse,pin_keys]='MUSE_VERSION MUSE_SHA256_AMD64 MUSE_SHA256_ARM64'
  [muse,label_pins]='MUSE_VERSION:org.meta.muse.box.version MUSE_SHA256_AMD64:org.meta.muse.box.sha256-amd64 MUSE_SHA256_ARM64:org.meta.muse.box.sha256-arm64'
  [muse,display]='Muse'
  [muse,git_prefix]='BOX_M'
  [opencode,directory_parser]='native'
  [opencode,directory_configs]='opencode.json:opencode.jsonc .opencode/opencode.json:.opencode/opencode.jsonc'
  [opencode,launcher]='box-o'
  [opencode,image_prefix]='box-o'
  [opencode,network]='box-o'
  [opencode,state_prefix]='box-o-v2'
  [opencode,config_dir]='box-o'
  [opencode,config_file]='opencode.json'
  [opencode,version_file]='version-opencode.env'
  [opencode,dockerfile_target]='opencode'
  [opencode,version_format]='sha-pinned'
  [opencode,probe_hosts]='opencode.ai'
  [opencode,forward_keys]='' # pure /connect: zero manual keys forwarded
  [opencode,pin_keys]='OPENCODE_VERSION OPENCODE_SHA256_AMD64 OPENCODE_SHA256_ARM64'
  [opencode,label_pins]='OPENCODE_VERSION:org.opencode.box.version OPENCODE_SHA256_AMD64:org.opencode.box.sha256-amd64 OPENCODE_SHA256_ARM64:org.opencode.box.sha256-arm64'
  [opencode,display]='OpenCode'
  [opencode,git_prefix]='BOX_O'
  [muse,package]='harnesses/muse'
  [muse,version_source]='harnesses/muse/version-muse.env'
  [muse,launch_adapter]='harnesses/muse/launch.sh'
  [muse,install_adapter]='harnesses/muse/install.sh'
  [muse,update_adapter]='harnesses/muse/update.sh'
  [muse,validate_adapter]='harnesses/muse/validate.sh'
  [muse,native_helper]='harnesses/muse/native.sh'
  [muse,verify_label]='MUSE CODE'
  [muse,artifacts]='settings'
  [muse,states]='home volume'
  [muse,probe_url]='https://api.meta.ai/v1'
  [opencode,package]='harnesses/opencode'
  [opencode,version_source]='harnesses/opencode/version-opencode.env'
  [opencode,launch_adapter]='harnesses/opencode/launch.sh'
  [opencode,install_adapter]=''
  [opencode,update_adapter]='harnesses/opencode/update.sh'
  [opencode,validate_adapter]='harnesses/opencode/validate.sh'
  [opencode,native_helper]=''
  [opencode,verify_label]='OPENCODE'
  [opencode,artifacts]='config'
  [opencode,states]='volume config-parent'
  [opencode,probe_url]='https://opencode.ai'
  [codex,package]='harnesses/codex'
  [codex,version_source]='harnesses/codex/version-codex.env'
  [codex,launch_adapter]='harnesses/codex/launch.sh'
  [codex,install_adapter]=''
  [codex,update_adapter]='harnesses/codex/update.sh'
  [codex,validate_adapter]='harnesses/codex/validate.sh'
  [codex,native_helper]=''
  [codex,verify_label]='CODEX'
  [codex,artifacts]='config policy'
  [codex,states]='home volume'
  [codex,probe_url]='https://auth.openai.com'
  [codex,directory_parser]='toml'
  [codex,directory_configs]='.codex/config.toml'
  [codex,launcher]='box-c'
  [codex,image_prefix]='box-c'
  [codex,network]='box-c'
  [codex,state_prefix]='box-c'
  [codex,config_dir]='box-c'
  [codex,config_file]='config.toml'
  [codex,version_file]='version-codex.env'
  [codex,dockerfile_target]='codex'
  [codex,version_format]='sha-pinned'
  [codex,probe_hosts]='auth.openai.com api.openai.com chatgpt.com'
  [codex,forward_keys]='OPENAI_API_KEY'
  [codex,pin_keys]='CODEX_VERSION CODEX_SHA256_AMD64 CODEX_SHA256_ARM64'
  [codex,label_pins]='CODEX_VERSION:org.openai.codex.box.version CODEX_SHA256_AMD64:org.openai.codex.box.sha256-amd64 CODEX_SHA256_ARM64:org.openai.codex.box.sha256-arm64'
  [codex,display]='Codex'
  [codex,git_prefix]='BOX_C'

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
# (never an empty expansion under `set -u` callers); declared empty values
# print empty.
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

# Records use fixed positional fields and literal values, never executable data.
# Artifact: source, format, role, installed leaf, runtime path, lifecycle,
#           mode, owner, consumers. Native schema belongs to validate_adapter.
readonly box_artifact_fields='source format role installed runtime lifecycle mode owner consumers'
declare -gA _BOX_ARTIFACTS=()
_box_artifact_record() {
  local tool=$1 artifact=$2 field; shift 2
  for field in $box_artifact_fields; do
    _BOX_ARTIFACTS[$tool,$artifact,$field]=$1; shift
  done
  (($# == 0)) || die 'Invalid artifact record.'
}
_box_artifact_record muse settings harnesses/muse/config/settings.json json live-config settings.json /home/box/.config/muse/settings.json refresh-live 644 user 'setup launch validate verify'
_box_artifact_record opencode config harnesses/opencode/config/opencode.json json live-config opencode.json /persist/config/opencode/opencode.json refresh-live 644 user 'setup launch validate verify'
_box_artifact_record codex config harnesses/codex/config/config.toml toml live-config config.toml /etc/codex/config.toml refresh-live 600 user 'setup launch validate verify'
_box_artifact_record codex policy harnesses/codex/policy/requirements.toml toml managed-image '' /etc/codex/requirements.toml managed-image 644 root 'build validate verify'
unset -f _box_artifact_record

# State: scope, kind, relative host root, override, container path, mode,
#        reset consequence. Volume naming remains project/UID/GID scoped.
readonly box_state_fields='scope kind root override runtime mode reset'
declare -gA _BOX_STATES=()
_box_state_record() {
  local tool=$1 state=$2 field; shift 2
  for field in $box_state_fields; do _BOX_STATES[$tool,$state,$field]=$1; shift; done
  (($# == 0)) || die 'Invalid state record.'
}
_box_state_record muse home global bind .config/box-m/muse-config BOX_M_PERSIST_DIR /home/box/.config/muse 700 'global-settings-auth-trust'
_box_state_record muse volume physical-project volume '' '' /persist 700 'project-data-state'
_box_state_record opencode volume physical-project volume '' '' /persist 700 'project-auth-data-state'
_box_state_record opencode config-parent physical-project volume '' '' /persist/config/opencode 700 'client-preferences'
_box_state_record codex home physical-project bind .config/box-c/projects 'BOX_C_STATE_ROOT BOX_C_STATE_DIR' /home/box/.codex 700 'project-auth-preferences-transcripts'
_box_state_record codex volume physical-project volume '' '' /persist 700 'project-sqlite-state'
unset -f _box_state_record

box_artifact_field() {
  local key=${1:-},${2:-},${3:-}
  [[ -n "${_BOX_ARTIFACTS[$key]+set}" ]] || die "Unknown artifact field: $key"
  printf '%s' "${_BOX_ARTIFACTS[$key]}"
}
box_state_field() {
  local key=${1:-},${2:-},${3:-}
  [[ -n "${_BOX_STATES[$key]+set}" ]] || die "Unknown state field: $key"
  printf '%s' "${_BOX_STATES[$key]}"
}
box_config_sources() {
  local id a
  for id in $box_tool_ids; do
    for a in $(box_tool_field "$id" artifacts); do box_artifact_field "$id" "$a" source; printf '\n'; done
  done
}
box_assert_relative_source() {
  local bundle=$1 path=$2 physical
  [[ "$path" =~ ^[a-zA-Z0-9_./-]+$ && "$path" != /* && "$path" != *'//'* && "/$path/" != *'/../'* && "/$path/" != *'/./'* ]] || die "Escaping or invalid source path: $path"
  [[ -f "$bundle/$path" && ! -L "$bundle/$path" ]] || die "Missing regular source: $path"
  physical=$(box_realpath -e -- "$bundle/$path") || die "Cannot resolve source: $path"
  case "$physical" in "$bundle/"*) ;; *) die "Escaping source path: $path";; esac
}
# Identity slice of box_validate_registry: id shape/uniqueness, field
# completeness, and directory parser/config paths.
box_validate_registry_identity() {
  local id=$1
  local -n _seen=$2
  local f directory_path directory_group
  [[ "$id" =~ ^[a-z][a-z0-9-]*$ && -z "${_seen[id,$id]+set}" ]] || die "Invalid/duplicate harness id: $id"
  _seen[id,$id]=1
  for f in $box_tool_fields; do box_tool_field "$id" "$f" >/dev/null; done
  case "$(box_tool_field "$id" directory_parser)" in json|toml|native) ;; *) die "Invalid directory parser: $id";; esac
  [[ -n "$(box_tool_field "$id" directory_configs)" ]] || die "Missing directory config paths: $id"
  for directory_group in $(box_tool_field "$id" directory_configs); do
    local -a directory_group_paths=()
    IFS=: read -r -a directory_group_paths <<< "$directory_group"
    for directory_path in "${directory_group_paths[@]}"; do
      [[ "$directory_path" != /* && "$directory_path" != *..* && "$directory_path" =~ ^[A-Za-z0-9_./-]+$ ]] || die "Invalid directory config path: $id"
    done
  done
}

# Destinations slice: launcher/config/version destinations, package, naming
# fields, launcher source, and pin-key uniqueness.
box_validate_registry_destinations() {
  local id=$1 bundle=$2
  local -n _seen=$3
  local f value pin
  for f in launcher config_dir version_file; do
    value=$(box_tool_field "$id" "$f")
    [[ "$value" =~ ^[A-Za-z0-9_.-]+$ && "$value" != . && "$value" != .. && -z "${_seen[$f,$value]+set}" ]] || die "Invalid/duplicate $f destination: $value"
    _seen[$f,$value]=1
  done
  [[ "$(box_tool_field "$id" package)" == "harnesses/$id" ]] || die "Invalid package: $id"
  for f in image_prefix network dockerfile_target git_prefix config_file; do
    value=$(box_tool_field "$id" "$f")
    [[ "$value" =~ ^[A-Za-z0-9_.-]+$ && "$value" != . && "$value" != .. && ( "$f" == config_file || -z "${_seen[$f,$value]+set}" ) ]] || die "Invalid/duplicate $f: $id"
    _seen[$f,$value]=1
  done
  box_assert_relative_source "$bundle" "$(box_tool_field "$id" launcher)"
  for pin in $(box_tool_field "$id" pin_keys); do
    [[ "$pin" =~ ^[A-Z][A-Z0-9_]*$ && -z "${_seen[pin,$pin]+set}" ]] || die "Invalid/duplicate pin key: $pin"
    _seen[pin,$pin]=1
  done
}

# Adapters slice: launch/update/validate/install adapters, native helper,
# version source, and pin labels.
box_validate_registry_adapters() {
  local id=$1 bundle=$2
  local -n _seen=$3
  local f value source pair pin label
  for f in launch update validate install; do
    value=$(box_tool_field "$id" "${f}_adapter")
    [[ -n "$value" || "$f" == install ]] || die "Missing $f adapter: $id"
    [[ -n "$value" ]] || continue
    [[ "$value" == "harnesses/$id/$f.sh" ]] || die "Invalid adapter: $value"
    box_assert_relative_source "$bundle" "$value"
  done
  value=$(box_tool_field "$id" native_helper)
  if [[ -n "$value" ]]; then
    [[ "$value" == "harnesses/$id/native.sh" ]] || die "Invalid native helper: $value"
    box_assert_relative_source "$bundle" "$value"
  fi
  source=$(box_tool_field "$id" version_source)
  [[ "$source" == "harnesses/$id/$(box_tool_field "$id" version_file)" ]] || die "Pin source/install mismatch: $id"
  box_assert_relative_source "$bundle" "$source"
  for pair in $(box_tool_field "$id" label_pins); do
    pin=${pair%%:*}; label=${pair#*:}
    [[ " $(box_tool_field "$id" pin_keys) " == *" $pin "* && "$label" =~ ^[a-zA-Z0-9_.-]+$ && -z "${_seen[label,$label]+set}" && -z "${_seen[label-pin,$id/$pin]+set}" ]] || die "Invalid/duplicate pin label: $pair"
    _seen[label,$label]=1
    _seen[label-pin,$id/$pin]=1
  done
  for pin in $(box_tool_field "$id" pin_keys); do
    [[ -n "${_seen[label-pin,$id/$pin]+set}" ]] || die "Missing pin label: $id/$pin"
  done
}

# Artifacts slice: per-artifact records, sources, lifecycle/format/mode/owner,
# runtime destinations, and consumers, plus the primary-config check.
box_validate_registry_artifacts() {
  local id=$1 bundle=$2
  local -n _seen=$3 _sources=$4 _records=$5
  local a f source installed role consumer value primary
  primary=0
  for a in $(box_tool_field "$id" artifacts); do
    [[ "$a" =~ ^[a-z][a-z0-9-]*$ && -z "${_records[$id,$a]+set}" ]] || die "Invalid/duplicate artifact: $id/$a"
    _records[$id,$a]=1
    for f in $box_artifact_fields; do box_artifact_field "$id" "$a" "$f" >/dev/null; done
    source=$(box_artifact_field "$id" "$a" source)
    [[ "$source" == "harnesses/$id/"* && -z "${_sources[$source]+set}" ]] || die "Invalid/duplicate artifact source: $source"
    box_assert_relative_source "$bundle" "$source"; _sources[$source]=1
    installed=$(box_artifact_field "$id" "$a" installed)
    [[ "$installed" != "$(box_tool_field "$id" version_file)" ]] || die 'Artifact collides with installed pins.'
    if [[ "$installed" == "$(box_tool_field "$id" config_file)" ]]; then primary=$((primary + 1)); fi
    role=$(box_artifact_field "$id" "$a" role)
    case "$role:$(box_artifact_field "$id" "$a" lifecycle)" in
      template:refresh-seed-if-absent|template:refresh-seed-legacy-empty|live-config:refresh-live)
        [[ "$installed" =~ ^[a-zA-Z0-9_.-]+$ && "$installed" != . && "$installed" != .. && -z "${_seen[dest,$id/$installed]+set}" ]] || die "Invalid/duplicate install destination: $installed"
        _seen[dest,$id/$installed]=1 ;;
      managed-image:managed-image) [[ -z "$installed" && "$(box_artifact_field "$id" "$a" owner)" == root ]] || die 'Managed policy must be image owned.' ;;
      *) die "Invalid artifact lifecycle: $id/$a";;
    esac
    case "$(box_artifact_field "$id" "$a" format)" in json|toml) ;; *) die 'Invalid artifact format.';; esac
    case "$(box_artifact_field "$id" "$a" mode)" in 600|644) ;; *) die 'Invalid artifact mode.';; esac
    case "$role:$(box_artifact_field "$id" "$a" owner)" in template:user|live-config:user|managed-image:root) ;; *) die 'Invalid artifact owner.';; esac
    value=$(box_artifact_field "$id" "$a" runtime)
    [[ "$value" =~ ^/[A-Za-z0-9_./-]+$ && "/$value/" != *'/../'* && "/$value/" != *'/./'* && -z "${_seen[runtime,$id/$value]+set}" ]] || die 'Invalid/duplicate runtime destination.'
    _seen[runtime,$id/$value]=1
    value=$(box_artifact_field "$id" "$a" consumers)
    [[ -n "$value" ]] || die "Missing artifact consumers: $id/$a"
    for consumer in $value; do
      case "$consumer" in setup|launch|build|validate|verify) ;; *) die "Unknown artifact consumer: $consumer";; esac
    done
    [[ " $value " == *' validate '* && " $value " == *' verify '* ]] || die "Missing validation consumers: $id/$a"
    if [[ "$role" == managed-image ]]; then
      if [[ " $value " != *' build '* ]] || ! grep -Fq "COPY $source " "$bundle/Dockerfile"; then die "Missing build consumer: $source"; fi
    else [[ " $value " == *' setup '* && " $value " == *' launch '* ]] || die "Missing host consumers: $source"; fi
  done
  [[ "$primary" == 1 ]] || die "Missing primary configuration consumer: $id"
}

# States slice: per-state contracts, then the config/policy asset sweep
# (stays last to preserve check order).
box_validate_registry_states() {
  local id=$1 bundle=$2
  local -n _seen=$3 _sources=$4
  local state f kind value override file
  for state in $(box_tool_field "$id" states); do
    [[ "$state" =~ ^[a-z][a-z0-9-]*$ && -z "${_seen[state,$id/$state]+set}" ]] || die "Invalid/duplicate state: $id/$state"
    _seen[state,$id/$state]=1
    for f in $box_state_fields; do box_state_field "$id" "$state" "$f" >/dev/null; done
    case "$(box_state_field "$id" "$state" scope):$(box_state_field "$id" "$state" kind)" in global:bind|physical-project:bind|physical-project:volume|ephemeral:tmpfs) ;; *) die "Invalid state contract: $id/$state";; esac
    [[ "$(box_state_field "$id" "$state" mode)" == 700 && -n "$(box_state_field "$id" "$state" reset)" ]] || die "Invalid state permissions/lifecycle: $id/$state"
    kind=$(box_state_field "$id" "$state" kind)
    value=$(box_state_field "$id" "$state" root)
    if [[ "$kind" == bind ]]; then
      [[ "$value" =~ ^[A-Za-z0-9_./-]+$ && "$value" != /* && "/$value/" != *'/../'* && "/$value/" != *'/./'* ]] || die 'Escaping state root.'
      for override in $(box_state_field "$id" "$state" override); do
        [[ "$override" =~ ^[A-Z][A-Z0-9_]*$ ]] || die 'Invalid state override.'
      done
    else
      [[ -z "$value" && -z "$(box_state_field "$id" "$state" override)" ]] || die 'Non-bind state must not declare a host root.'
    fi
    value=$(box_state_field "$id" "$state" runtime)
    [[ "$value" =~ ^/[A-Za-z0-9_./-]+$ && "/$value/" != *'/../'* && "/$value/" != *'/./'* ]] || die 'Escaping state runtime path.'
  done
  while IFS= read -r file; do [[ -n "${_sources[${file#"$bundle/"}]+set}" ]] || die "Artifact lacks consumer: $file"; done < <(find "$bundle/harnesses/$id/config" "$bundle/harnesses/$id/policy" -type f 2>/dev/null)
}

# Orphans slice: no artifact/state records outside the declared per-id sets.
box_validate_registry_orphans() {
  local -n _seen=$1 _records=$2
  local key id a state f
  for key in "${!_BOX_ARTIFACTS[@]}"; do
    IFS=, read -r id a f <<<"$key"
    [[ " $box_tool_ids " == *" $id "* && -n "${_records[$id,$a]+set}" && " $box_artifact_fields " == *" $f "* ]] || die "Orphan artifact record: $id/$a"
  done
  for key in "${!_BOX_STATES[@]}"; do
    IFS=, read -r id state f <<<"$key"
    [[ -n "${_seen[state,$id/$state]+set}" && " $box_state_fields " == *" $f "* ]] || die "Orphan state record: $id/$state"
  done
}

# Validate before setup/build/generation. All destinations and labels are unique;
# adapter filenames are fixed, and artifact directories have no orphan assets.
box_validate_registry() {
  local bundle=$1 id
  bundle=$(box_realpath -e -- "$bundle") || die 'Cannot resolve bundle.'
  local -A seen=() sources=() records=()
  for id in $box_tool_ids; do
    box_validate_registry_identity "$id" seen
    box_validate_registry_destinations "$id" "$bundle" seen
    box_validate_registry_adapters "$id" "$bundle" seen
    box_validate_registry_artifacts "$id" "$bundle" seen sources records
    box_validate_registry_states "$id" "$bundle" seen sources
  done
  box_validate_registry_orphans seen records
}
