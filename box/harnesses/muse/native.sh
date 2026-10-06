# shellcheck shell=bash
# Re-assert safety-critical keys from the selected defaults after merging
# directory preferences into a private launch snapshot. Only
# telemetry.enabled and endpoint_transport.base_url are enforced; other
# merged preferences are preserved. The finished snapshot is mounted read-only.
# Retired top-level keys ($schema, api, approval_mode, approval_judge) are
# stripped from the snapshot here, so a future binary honoring them cannot
# silently weaken approvals; approval is CLI-only in the pinned release
# (binary defaults on-request/on) with no settings equivalent, and the API
# pin lives under endpoint_transport. The bundle validator rejects them at
# the source, and readiness asserts the enforced set.
# Fails closed on missing jq, non-object JSON, or a seed lacking any
# enforced key. No-op (no rewrite, mtime untouched) when already compliant
# (via box_write_if_changed, atomic mktemp+rename).
# Canonical enforced-keys presence filter: the seed (and the live snapshot)
# must carry every enforced key. Single home for the launch seed check, the
# enforce seed check, and the verify partial (baked in via @@ENFORCED_JQ@@).
# Plain assignment (not readonly): this file has no load guard and may be
# re-sourced in one shell. The bundle validator keeps its own value-policy
# check (it pins values and rejects retired keys, not just presence).
# Usage: jq -e "$box_muse_enforced_jq" -- <file>
box_muse_enforced_jq='has("telemetry") and (.telemetry|has("enabled")) and has("endpoint_transport") and (.endpoint_transport|has("base_url")) and has("schema_version") and ((.model|type == "string") and (.model|length > 0)) and has("reasoning_effort")'
# Usage: box_enforce_safe_settings <seed_src> <persisted_dest>
box_enforce_safe_settings() {
  local src=${1:-} dest=${2:-} merged
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing enforce-settings paths.'
  command -v jq >/dev/null || die 'jq is required (documented host prerequisite).'
  [[ ! -L "$src" && ! -L "$dest" ]] || die "Refusing to follow symlink in enforce-settings paths: $dest"
  [[ -f "$src" && -r "$src" ]] || die "Cannot read seed-config source: $src"
  [[ -f "$dest" && -w "$dest" ]] || die "Enforce-settings destination is not a writable file: $dest"
  jq -e "$box_muse_enforced_jq" -- "$src" >/dev/null \
    || die "Seed-config source lacks enforced safety keys: $src"
  jq -e 'type == "object"' -- "$dest" >/dev/null \
    || die "Persisted settings is not a JSON object (delete it to reseed): $dest"
  merged=$(jq -s -e '
    .[0] as $seed | .[1] as $user |
    ($user * {
      telemetry: ((($user.telemetry // {}) | if type == "object" then . else {} end) * {enabled: $seed.telemetry.enabled}),
      endpoint_transport: ((($user.endpoint_transport // {}) | if type == "object" then . else {} end) * {base_url: $seed.endpoint_transport.base_url})
    } | del(."$schema", .api, .approval_mode, .approval_judge))' -- "$src" "$dest") || die "Cannot merge enforced safety keys into: $dest"
  box_write_if_changed "$dest" "$merged" "enforced settings"
}

# Match a Meta device-flow URL in one tool-output line and split out the
# short code. Prints "<url>\n<code>" and returns 0 on match, 1 otherwise.
# The matcher lives here (not in box-m-login) so the path/query tolerance and
# the code charset stay in one tested place: the path/query after
# /oauth/device/ is loosened (extra params allowed) and the code charset
# covers `-_.~` (upstream may rotate formats). Only trailing
# quote/punctuation is stripped (extglob `+()` anchored at the end): a plain
# `%%[set]*` would cut at the first dot inside the URL itself. The short code
# is additionally cut at the first `&`.
# Usage: if probe_out=$(box_device_url_code "$line"); then
#          url=${probe_out%%$'\n'*}; code=${probe_out#*$'\n'}; ...
box_device_url_code() {
  local line=${1:-} url code extglob_was_off=0
  local device_url_re="https://auth\\.meta\\.com/oauth/device/\\?[^[:space:]\"']*code=[A-Za-z0-9_~.-]+"
  [[ "$line" =~ $device_url_re ]] || return 1
  url=${BASH_REMATCH[0]}
  shopt -q extglob || { extglob_was_off=1; shopt -s extglob; }
  url=${url%%+([\"\'\)\.,\;\!\?])}
  if ((extglob_was_off)); then shopt -u extglob; fi
  code=${url##*code=}
  code=${code%%\&*}
  [[ -n "$url" && -n "$code" ]] || return 1
  printf '%s\n%s\n' "$url" "$code"
}
# Compute the Muse inner-sandbox bypass flag for "$@" (full-$@ opt-out scan
# + $1-only denylist). Prints the flag (possibly empty) to stdout.
# Opt-out: any --disable-sandbox/=value, custom-flag/=value, or --yolo
# anywhere disables auto-inject. Denylist ($1-only): --version/--help/-h and
# diagnostic/auth subcommands never get the bypass — keep login
# invocations bare (`box-m login`; `muse --verbose login` still gets
# the bypass by design since only $1 is inspected).
# Honors BOX_M_INNER_FLAG (empty disables). Fails closed on bad shape.
# Usage: box_muse_bypass "$@"  (call after arg parsing, before exec)
box_muse_bypass() {
  local flag=${BOX_M_INNER_FLAG---disable-sandbox} arg has_opt=0
  [[ -z "$flag" || "$flag" == --[!-]* ]] \
    || die 'BOX_M_INNER_FLAG must be empty or a --flag (e.g. --disable-sandbox).'
  [[ "$flag" != *[[:space:]]* ]] \
    || die 'BOX_M_INNER_FLAG must not contain whitespace.'
  for arg in "$@"; do
    case "$arg" in
      --disable-sandbox|--disable-sandbox=*|--yolo) has_opt=1 ;;
    esac
    if [[ -n "$flag" ]]; then
      case "$arg" in
        "$flag"|"$flag"=*) has_opt=1 ;;
      esac
    fi
  done
  (( ! has_opt )) && [[ -n "$flag" ]] || return 0
  case "${1:-}" in
    --version|-V|--help|-h|login|logout|auth|config|export|trace|skills|sandbox|schema|session-message|mcp|init) return 0 ;;
  esac
  printf '%s' "$flag"
}
