# shellcheck shell=bash
# Re-assert safety-critical keys from the selected defaults after merging
# directory preferences into a private launch snapshot. Only approval_mode,
# approval_judge, telemetry.enabled and api.base_url are enforced; other
# merged preferences are preserved. The finished snapshot is mounted read-only.
# Fails closed on missing jq, non-object JSON, or a seed lacking any
# enforced key. No-op (no rewrite, mtime untouched) when already compliant
# (via box_write_if_changed, atomic mktemp+rename).
# Usage: box_enforce_safe_settings <seed_src> <persisted_dest>
box_enforce_safe_settings() {
  local src=${1:-} dest=${2:-} merged
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing enforce-settings paths.'
  command -v jq >/dev/null || die 'jq is required (documented host prerequisite).'
  [[ ! -L "$src" && ! -L "$dest" ]] || die "Refusing to follow symlink in enforce-settings paths: $dest"
  [[ -f "$src" && -r "$src" ]] || die "Cannot read seed-config source: $src"
  [[ -f "$dest" && -w "$dest" ]] || die "Enforce-settings destination is not a writable file: $dest"
  jq -e 'has("approval_mode") and has("approval_judge") and has("telemetry") and (.telemetry|has("enabled")) and has("api") and (.api|has("base_url"))' -- "$src" >/dev/null \
    || die "Seed-config source lacks enforced safety keys: $src"
  jq -e 'type == "object"' -- "$dest" >/dev/null \
    || die "Persisted settings is not a JSON object (delete it to reseed): $dest"
  merged=$(jq -s -e '
    .[0] as $seed | .[1] as $user |
    $user * {
      approval_mode: $seed.approval_mode,
      approval_judge: $seed.approval_judge,
      telemetry: ((($user.telemetry // {}) | if type == "object" then . else {} end) * {enabled: $seed.telemetry.enabled}),
      api: ((($user.api // {}) | if type == "object" then . else {} end) * {base_url: $seed.api.base_url})
    }' -- "$src" "$dest") || die "Cannot merge enforced safety keys into: $dest"
  box_write_if_changed "$dest" "$merged" "enforced settings"
}

# One-way host→persist TUI theme sync (muse): fill the theme keys missing
# from the persisted writable copy from the host-native Muse settings. Only
# the three theme keys (tui.theme, tui.color_depth, tui.terminal_background)
# are copied, and only when the persisted file lacks them (missing or null)
# while the host file carries a non-null value — existing sandbox values
# always win, so in-sandbox /theme choices persist globally and are never
# clobbered, and later host changes do not propagate (use in-sandbox /theme
# to change the sandbox theme after the first sync). Non-object .tui blocks
# on either side are treated as empty (a non-object persisted block is
# repaired when a fill lands, mirroring box_enforce_safe_settings).
# The host file is read by the launcher on the host; only theme strings are
# copied — no host path is mounted, so the Layer B host-$HOME exclusion
# still holds for the container. Symlink policy (deliberately unlike
# seed/enforce, which refuse symlinks on both sides): the host source is a
# read-only cosmetic input, so symlinks are followed (cf.
# box_load_credentials) and dotfile-managed native configs sync; the
# persisted destination is a write target and still refuses symlinks.
# Best-effort on the host side: a missing host file (native muse never ran)
# is a silent no-op, and an unreadable/non-object host file warns and
# continues — cosmetic input never blocks launch. Destination problems fail
# closed like enforce (in launcher flow enforce already ran first, so these
# are unreachable there). No-op (no rewrite, mtime untouched) when nothing
# fills (via box_write_if_changed, atomic mktemp+rename).
# Usage: box_sync_host_tui_theme <host_src> <persisted_dest>
box_sync_host_tui_theme() {
  local src=${1:-} dest=${2:-} merged
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing theme-sync paths.'
  [[ -e "$src" || -L "$src" ]] || return 0
  command -v jq >/dev/null || die 'jq is required (documented host prerequisite).'
  [[ ! -L "$dest" ]] || die "Refusing to follow symlink in theme-sync destination: $dest"
  [[ -f "$dest" && -w "$dest" ]] || die "Theme-sync destination is not a writable file: $dest"
  if [[ ! -f "$src" || ! -r "$src" ]]; then
    printf '%s: WARNING: cannot read host theme settings; skipping theme sync: %s\n' "$BOX_TOOL" "$src" >&2
    return 0
  fi
  jq -e 'type == "object"' -- "$src" >/dev/null 2>&1 || {
    printf '%s: WARNING: host theme settings is not a JSON object; skipping theme sync: %s\n' "$BOX_TOOL" "$src" >&2
    return 0
  }
  jq -e 'type == "object"' -- "$dest" >/dev/null \
    || die "Persisted settings is not a JSON object (delete it to reseed): $dest"
  merged=$(jq -s -e '
    .[0] as $host | .[1] as $user |
    (($host.tui // {}) | if type == "object" then . else {} end) as $h |
    (($user.tui // {}) | if type == "object" then . else {} end) as $u |
    (["theme", "color_depth", "terminal_background"]
      | map(select(($u[.] == null) and ($h[.] != null)) | {(.): $h[.]})
      | add // {}) as $fill |
    if ($fill | length == 0) then $user else $user + {tui: ($u + $fill)} end' -- "$src" "$dest") \
    || die "Cannot merge host theme keys into: $dest"
  box_write_if_changed "$dest" "$merged" "theme-synced settings"
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


# Muse compatibility for the retired empty JSON bind artifact only.
box_muse_seed_config() {
  [[ ! -L "$2" ]] || die 'Refusing symlink in Muse settings.'
  if [[ -f "$2" && ! -s "$2" ]]; then
    box_assert_owner_mode "$2" 'Muse settings' nowrite
    rm -f -- "$2" || die 'Cannot remove empty legacy Muse settings.'
  fi
  box_seed_writable_config "$@"
}
