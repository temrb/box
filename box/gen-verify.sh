#!/bin/bash -p
# gen-verify.sh — generate verify-<id>.sh for every registry tool from
# verify.d/ partials. Shared §§1-2/5 live once (10-workspace.sh,
# 20-toolchain.sh, 50-containment.sh); 00/30/40/60/99 stay per-tool
# (00-header-<id>.sh, ...). Checked-in outputs stay stdin-deliverable
# (self-contained, no sourcing) for `--shell` delivery. CI asserts
# generated == checked-in (see Makefile verify-generated).
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

BOX_TOOL=gen-verify.sh
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/preflight.sh
source "$script_dir/lib/preflight.sh"
# shellcheck source=lib/tools.sh
source "$script_dir/lib/tools.sh"

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
# per-tool sections (3 + 5 * tool_count: 13 for 2 tools, 18 for 3).
partials_expected=(10-workspace.sh 20-toolchain.sh 50-containment.sh)
for _gen_id in $box_tool_ids; do
  for _gen_sec in 00-header 30-network 40-readiness 60-probe 99-footer; do
    partials_expected+=("$_gen_sec-$_gen_id.sh")
  done
done
unset _gen_id _gen_sec
for f in "${partials_expected[@]}"; do
  [[ -f "$partials/$f" ]] || die "Missing partial: $partials/$f"
done
# A new partial without a consumer rots silently: the on-disk count must equal
# the list above (add the tool row or shared consumer when adding a section),
# so the count derives from the list instead of being a second hardcoded
# number.
partials_found=$(printf '%s\n' "$partials"/*.sh | wc -l)
[[ "$partials_found" -eq "${#partials_expected[@]}" ]] \
  || die "verify.d/ holds $partials_found partials but gen-verify.sh lists ${#partials_expected[@]} (add the consumer or drop the file)"

gen_one() {
  local tool=${1:-} out=${2:-}
  [[ -n "$tool" && -n "$out" ]] || die 'Internal error: missing generator arguments.'
  local tmp prev_return_trap prev_exit_trap
  prev_return_trap=$(trap -p RETURN || true)
  prev_exit_trap=$(trap -p EXIT || true)
  tmp=$(box_mktemp_file gen-verify) || die 'Cannot create temp file.'
  # RETURN covers the normal return; EXIT covers die/exit paths inside this
  # function (RETURN alone is skipped on exit). Caller traps are saved above
  # and restored below so no stale trap (or stale local $tmp reference)
  # persists past the return and no caller EXIT trap is cleared.
  trap 'rm -f -- "$tmp"' RETURN EXIT
  cat -- \
    "$partials/00-header-$tool.sh" \
    "$partials/10-workspace.sh" \
    "$partials/20-toolchain.sh" \
    "$partials/30-network-$tool.sh" \
    "$partials/40-readiness-$tool.sh" \
    "$partials/50-containment.sh" \
    "$partials/60-probe-$tool.sh" \
    "$partials/99-footer-$tool.sh" \
    >"$tmp" || die "Cannot assemble verify-$tool.sh."
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
