#!/bin/bash -p
# gen-verify.sh — generate verify-<id>.sh for every registry tool from
# verify.d/ partials. Shared §§1-2/5 live once (10-workspace.sh,
# 20-toolchain.sh, 50-containment.sh); 00/30/40/60/99 stay per-tool
# (00-header-<id>.sh, ...). The 40-readiness partials carry their binary
# version as an @@<PIN_KEY>@@ token (registry pin_keys position 0), resolved
# here from the version files via lib/pins.sh — so a pin bump never touches
# verify.d/. Checked-in outputs stay stdin-deliverable (self-contained, no
# sourcing) for `--shell` delivery. CI asserts generated == checked-in (see
# Makefile verify-generated).
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

BOX_TOOL=gen-verify.sh
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/preflight.sh
source "$script_dir/lib/preflight.sh"
# shellcheck source=lib/tools.sh
source "$script_dir/lib/tools.sh"
# shellcheck source=lib/pins.sh
source "$script_dir/lib/pins.sh"
# shellcheck source=lib/config-file.sh
source "$script_dir/lib/config-file.sh"

bundle_dir=$script_dir
partials="$bundle_dir/verify.d"

# --check: assert checked-in outputs equal generated output without rewriting
# (for CI). Default regenerates the checked-in files.
check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
elif [[ -n "${1:-}" ]]; then
  die "Unknown argument: $1 (usage: gen-verify.sh [--check])"
fi

# Expected partials derive from the registry: 3 shared sections plus 5
# per-tool sections (3 + 5 * tool_count: 13 for 2 tools, 18 for 3; legacy arithmetic).
partials_expected=(verify.d/10-workspace.sh verify.d/20-toolchain.sh verify.d/50-containment.sh)
for _gen_id in $box_tool_ids; do
  for _gen_sec in 00-header 30-network 40-readiness 60-probe 99-footer; do
    partials_expected+=("harnesses/$_gen_id/verify.d/$_gen_sec-$_gen_id.sh")
  done
done
unset _gen_id _gen_sec
for f in "${partials_expected[@]}"; do
  [[ -f "$bundle_dir/$f" ]] || die "Missing partial: $partials/$f"
done
# A new partial without a consumer rots silently: the on-disk count must equal
# the list above (add the tool row or shared consumer when adding a section),
# so the count derives from the list instead of being a second hardcoded
# number.
partials_found=$(find "$bundle_dir/verify.d" "$bundle_dir/harnesses" -type f -path '*/verify.d/*.sh' | wc -l)
[[ "$partials_found" -eq "${#partials_expected[@]}" ]] \
  || die "verify.d/ holds $partials_found partials but gen-verify.sh lists ${#partials_expected[@]} (add the consumer or drop the file)"

gen_one() {
  local tool=${1:-} out=${2:-}
  [[ -n "$tool" && -n "$out" ]] || die 'Internal error: missing generator arguments.'
  box_require_tool "$tool"
  local tmp prev_return_trap prev_exit_trap
  local _tok_vkey _tok_tok _tok_val _tok_pat _tok_esc _tok_launcher _tok_display
  prev_return_trap=$(trap -p RETURN || true)
  prev_exit_trap=$(trap -p EXIT || true)
  tmp=$(box_mktemp_file gen-verify) || die 'Cannot create temp file.'
  # RETURN covers the normal return; EXIT covers die/exit paths inside this
  # function (RETURN alone is skipped on exit). Caller traps are saved above
  # and restored below so no stale trap (or stale local $tmp reference)
  # persists past the return and no caller EXIT trap is cleared.
  # Bespoke save/restore stays local: trap semantics plus bats subshell
  # caveats make a generic helper riskier than this accepted pattern.
  trap 'rm -f -- "$tmp"' RETURN EXIT
  cat -- \
    "$bundle_dir/harnesses/$tool/verify.d/00-header-$tool.sh" \
    "$partials/10-workspace.sh" \
    "$partials/20-toolchain.sh" \
    "$bundle_dir/harnesses/$tool/verify.d/30-network-$tool.sh" \
    "$bundle_dir/harnesses/$tool/verify.d/40-readiness-$tool.sh" \
    "$partials/50-containment.sh" \
    "$bundle_dir/harnesses/$tool/verify.d/60-probe-$tool.sh" \
    "$bundle_dir/harnesses/$tool/verify.d/99-footer-$tool.sh" \
    >"$tmp" || die "Cannot assemble verify-$tool.sh."
  # Resolve the readiness @@<PIN_KEY>@@ token from the single pin home (the
  # tool's registry row, pin_keys position 0 — never a per-tool branch). The
  # token must be present (a partial that drops its version check fails
  # closed here) and no @@ token may survive substitution (a typo'd key fails
  # closed too). Runs before --check/compare in both modes, so --check still
  # fails on stale or hand-edited outputs.
  _tok_vkey=$(box_version_key "$tool")
  _tok_tok="@@${_tok_vkey}@@"
  grep -Fq -- "$_tok_tok" "$tmp" \
    || die "verify.d/40-readiness-$tool.sh lacks its ${_tok_tok} token."
  _tok_val=${!_tok_vkey:-}
  [[ -n "$_tok_val" ]] || die "Empty $_tok_vkey pin after parse."
  _tok_pat=$(printf '%s' "$_tok_tok" | sed -e 's/[][\\.^$*|]/\\&/g')
  _tok_esc=$(printf '%s' "$_tok_val" | sed -e 's/[\\&|]/\\&/g')
  sed -i "s|$_tok_pat|$_tok_esc|g" -- "$tmp" || die "Cannot substitute ${_tok_tok} in verify-$tool.sh."
  # Header/footer tokens (same mechanism): every tool-specific string in the
  # 00/99 partials derives from registry data, so copy-paste across the three
  # headers cannot rot the usage/probe/label strings again.
  _tok_launcher=$(box_tool_field "$tool" launcher)
  _tok_display=$(box_tool_field "$tool" verify_label)
  [[ "$_tok_display" =~ ^[A-Z][A-Z\ ]*$ ]] || die "Invalid verify label: $tool"
  sed -i -e "s|@@TOOL@@|$tool|g" -e "s|@@LAUNCHER@@|$_tok_launcher|g" \
    -e "s|@@PROBE_VAR@@|_${tool}_probe|g" -e "s|@@DISPLAY@@|$_tok_display|g" -- "$tmp" \
    || die "Cannot substitute header tokens in verify-$tool.sh."
  local artifact artifact_src artifact_format artifact_json artifact_token
  for artifact in $(box_tool_field "$tool" artifacts); do
    artifact_src="$bundle_dir/$(box_artifact_field "$tool" "$artifact" source)"
    artifact_format=$(box_artifact_field "$tool" "$artifact" format)
    artifact_token="@@ARTIFACT_${artifact^^}@@"
    grep -Fq "$artifact_token" "$tmp" || die "Missing verification consumer for $tool/$artifact."
    artifact_json=$(box_config_canonical_json "$artifact_src" "$artifact_format") \
      || die "Cannot read artifact ${artifact_format^^}."
    artifact_json=$(printf '%q' "$artifact_json")
    _tok_esc=$(printf '%s' "$artifact_json" | sed -e 's/[\\&|]/\\&/g')
    sed -i "s|$artifact_token|$_tok_esc|g" -- "$tmp"
  done
  if grep -Fq '@@NATIVE_PROBE@@' "$tmp"; then
    [[ -f "$bundle_dir/harnesses/$tool/native-probe.py" ]] || die 'Missing native probe consumer.'
    python3 -I - "$tmp" "$bundle_dir/harnesses/$tool/native-probe.py" <<'PYPROBE'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("@@NATIVE_PROBE@@", pathlib.Path(sys.argv[2]).read_text()))
PYPROBE
  fi
  if grep -Fq '@@ENFORCED_JQ@@' "$tmp"; then
    [[ -f "$bundle_dir/harnesses/$tool/native.sh" ]] || die 'Missing enforced-keys consumer.'
    # source runs in this shell, so it would trip the RETURN cleanup trap
    # and delete $tmp: drop the trap across the source and re-arm it.
    trap - RETURN EXIT
    # shellcheck disable=SC1090 # fixed validated native helper path
    source "$bundle_dir/harnesses/$tool/native.sh"
    trap 'rm -f -- "$tmp"' RETURN EXIT
    [[ -n "${box_muse_enforced_jq:-}" ]] || die 'Missing enforced-keys filter.'
    _tok_esc=$(printf '%s' "$box_muse_enforced_jq" | sed -e 's/[\\&|]/\\&/g')
    sed -i "s|@@ENFORCED_JQ@@|$_tok_esc|g" -- "$tmp" || die 'Cannot substitute @@ENFORCED_JQ@@.'
  fi
  if grep -Eq '@@[A-Z_]+@@' -- "$tmp"; then
    die "Unresolved placeholder token remains in verify-$tool.sh output."
  fi
  if ((check_only)); then
    if ! diff -u -- "$out" "$tmp" >/dev/null; then
      printf '%s: FAIL: verify-%s.sh differs from verify.d/ output; run gen-verify.sh.\n' \
        "$BOX_TOOL" "$tool" >&2
      diff -u -- "$out" "$tmp" >&2 || true
      exit 1
    fi
  else
    chmod 644 -- "$tmp" || die 'Cannot set generated file mode.'
    mv -f -- "$tmp" "$out" || die "Cannot write $out."
  fi
  # Explicit cleanup for the check_only path (tmp still exists; after mv this
  # is a no-op). The RETURN/EXIT trap above covers die/exit-1 paths.
  rm -f -- "$tmp" || true
  trap - RETURN EXIT
  if [[ -n "$prev_return_trap" ]]; then eval "$prev_return_trap"; fi
  if [[ -n "$prev_exit_trap" ]]; then eval "$prev_exit_trap"; fi
}

# Single pin home: strict parse (LF-only, allowlist, regex); pins land in
# same-named globals for the @@ token substitution in gen_one.
box_validate_registry "$bundle_dir"
box_load_all_pins "$bundle_dir"

_gen_outs=""
for _gen_id in $box_tool_ids; do
  gen_one "$_gen_id" "$bundle_dir/verify-$_gen_id.sh"
  _gen_outs+="${_gen_outs:+ + }verify-$_gen_id.sh"
done
unset _gen_id
if ((check_only)); then
  printf 'gen-verify.sh: PASS (verify-*.sh match verify.d/ output)\n'
else
  printf 'gen-verify.sh: PASS (%s regenerated)\n' "$_gen_outs"
fi
unset _gen_outs
