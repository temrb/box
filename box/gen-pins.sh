#!/bin/bash -p
# gen-pins.sh — generate docs/architecture.md §4 pin table from the single pin source.
# Pins come from the version files via the single lib/pins.sh home (parsed,
# never sourced, never grep|cut so base64 `=` padding survives); the Debian
# base digest + date come from the Dockerfile. The checked-in table mirrors
# the resolved values for humans. CI asserts generated == checked-in
# (see Makefile verify-pins-generated); check-pins.sh remains as the
# assert-only consistency layer over the generated output.
# shellcheck disable=SC2016 # backticks below are markdown literals in the generated pin table, never expansions.
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

BOX_TOOL=gen-pins.sh
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/pins.sh
source "$script_dir/lib/pins.sh"

bundle_dir=$script_dir
dockerfile="$bundle_dir/Dockerfile"
readme="$bundle_dir/docs/architecture.md"

# --check: assert the checked-in table equals generated output without rewriting
# (for CI). Default regenerates the checked-in table.
check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
elif [[ -n "${1:-}" ]]; then
  die "Unknown argument: $1 (usage: gen-pins.sh [--check])"
fi

[[ -f "$dockerfile" ]] || die "Missing Dockerfile: $dockerfile"
[[ -f "$readme" ]] || die "Missing pin table doc: $readme"
grep -Fq '<!-- pin-table-start -->' "$readme" \
  || die 'docs/architecture.md §4 is missing the <!-- pin-table-start --> marker'
grep -Fq '<!-- pin-table-end -->' "$readme" \
  || die 'docs/architecture.md §4 is missing the <!-- pin-table-end --> marker'

# Single pin home: strict parse (LF-only, allowlist, regex). Fails closed on
# CRLF/unknown keys. NODE_VERSION + NODESOURCE_FINGERPRINT come from
# version-opencode.env (not hardcoded).
box_load_all_pins "$bundle_dir"
for _pins_id in $box_tool_ids; do
  for _pins_key in $(box_tool_field "$_pins_id" pin_keys); do
    [[ -n "${!_pins_key:-}" ]] || die "Empty $_pins_key pin after parse."
  done
done
unset _pins_id _pins_key

# Single Dockerfile base digest (all targets share one base pin).
# Single extractor home (lib/pins.sh): previously duplicated with check-pins.sh.
docker_digest=$(box_docker_base_digest "$dockerfile")

# Base date comes from the Dockerfile pin comment (`# pin-date: YYYY-MM-DD`)
# so --check stays deterministic (never `date +%F`, which would drift daily).
base_date=$(grep -Eom1 '# pin-date: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$dockerfile" \
  | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}') || die 'Cannot extract Dockerfile base date.'
[[ "$base_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || die "Cannot parse Dockerfile base date: ${base_date:-none}"

# Structural asserts share one strictness with check-pins.sh via lib/pins.sh.
box_assert_no_default_args "$dockerfile"
box_assert_tarball_pins "$dockerfile"
box_assert_shell_placement "$dockerfile"
box_assert_build_delegation "$bundle_dir"
# Harness↔config pin consistency with exact jq asserts (not substrings),
# driven by the registry config paths. `<path> | strings` under jq -e fails
# closed on missing/non-string values (no output, non-zero exit), so no
# per-tool has() pre-assert chain is needed. Tools with pin_model=0 (muse:
# user-mutable seed default) skip the model cross-check — a model grep there
# would forbid in-container /models changes. The config convention keeps
# .model at top level for every tool.
for _pins_id in $box_tool_ids; do
  _pins_cfg="$bundle_dir/$(box_tool_field "$_pins_id" config_file)"
  _pins_base_path=$(box_tool_field "$_pins_id" config_base_path)
  _pins_base=$(jq -e -r "$_pins_base_path | strings" -- "$_pins_cfg") \
    || die "$_pins_cfg lacks string $_pins_base_path."
  grep -Fq -- "$_pins_base" "$bundle_dir/verify.d/40-readiness-$_pins_id.sh" \
    || die "verify.d/40-readiness-$_pins_id.sh base pin does not match $_pins_cfg ($_pins_base)"
  if [[ "$(box_tool_field "$_pins_id" pin_model)" == 1 ]]; then
    _pins_model=$(jq -e -r '.model | strings' -- "$_pins_cfg") \
      || die "$_pins_cfg lacks string .model."
    grep -Fq -- "$_pins_model" "$bundle_dir/verify.d/40-readiness-$_pins_id.sh" \
      || die "verify.d/40-readiness-$_pins_id.sh model pin does not match $_pins_cfg ($_pins_model)"
  fi
done
unset _pins_id _pins_cfg _pins_base_path _pins_base _pins_model

# Harness version pins must track the version files: every readiness partial
# embeds its tool's binary version as a literal, and a pin bump that skips
# the harness silently breaks `verify-*.sh` (see docs/upgrades.md §12).
for _pins_id in $box_tool_ids; do
  _pins_vkey=$(box_tool_field "$_pins_id" pin_keys); _pins_vkey=${_pins_vkey%% *}
  grep -Fq -- "${!_pins_vkey}" "$bundle_dir/verify.d/40-readiness-$_pins_id.sh" \
    || die "verify.d/40-readiness-$_pins_id.sh version pin does not match $_pins_vkey (${!_pins_vkey}); update the harness and run gen-verify.sh."
done
unset _pins_id _pins_vkey

# Muse safety keys must agree between the seed and the harness: the launcher
# enforces these four values from the seed on every run while the harness
# grades them, so drift means launcher and harness permanently disagree.
# api.base_url is already cross-checked by the loop above; the other three
# are asserted here as the exact jq comparisons the partial must contain.
_pins_seed="$bundle_dir/$(box_tool_field muse config_file)"
_pins_harness="$bundle_dir/verify.d/40-readiness-muse.sh"
_pins_mode=$(jq -e -r '.approval_mode | strings' -- "$_pins_seed") \
  || die "$_pins_seed lacks string .approval_mode."
jq -e 'has("approval_judge") and (.approval_judge | type == "boolean")' -- "$_pins_seed" >/dev/null \
  || die "$_pins_seed lacks boolean .approval_judge."
_pins_judge=$(jq -r '.approval_judge | tostring' -- "$_pins_seed")
jq -e 'has("telemetry") and (.telemetry | has("enabled")) and (.telemetry.enabled | type == "boolean")' -- "$_pins_seed" >/dev/null \
  || die "$_pins_seed lacks boolean .telemetry.enabled."
_pins_telemetry=$(jq -r '.telemetry.enabled | tostring' -- "$_pins_seed")
grep -Fq -- ".approval_mode == \"$_pins_mode\"" "$_pins_harness" \
  || die "verify.d/40-readiness-muse.sh approval_mode does not match $_pins_seed ($_pins_mode)"
grep -Fq -- ".approval_judge == $_pins_judge" "$_pins_harness" \
  || die "verify.d/40-readiness-muse.sh approval_judge does not match $_pins_seed ($_pins_judge)"
grep -Fq -- ".telemetry.enabled == $_pins_telemetry" "$_pins_harness" \
  || die "verify.d/40-readiness-muse.sh telemetry.enabled does not match $_pins_seed ($_pins_telemetry)"
unset _pins_seed _pins_harness _pins_mode _pins_judge _pins_telemetry

new_block=$(box_mktemp_file gen-pins-block) || die 'Cannot create temp file.'
new_readme=$(box_mktemp_file gen-pins-readme) || die 'Cannot create temp file.'
cleanup_gen_pins() { rm -f -- "$new_block" "$new_readme"; }
trap cleanup_gen_pins EXIT

# Dockerfile target lists derive from the registry (pipe-joined for the
# --target flag shape, markdown-joined for the target list).
_pins_targets_pipe=""
_pins_targets_md=""
for _pins_id in $box_tool_ids; do
  _pins_tgt=$(box_tool_field "$_pins_id" dockerfile_target)
  _pins_targets_pipe+="${_pins_targets_pipe:+|}$_pins_tgt"
  _pins_targets_md+="${_pins_targets_md:+/}\`$_pins_tgt\`"
done
unset _pins_id _pins_tgt
{
  printf '<!-- pin-table-start -->\n'
  printf 'All images build from one `Dockerfile` (`--file Dockerfile --target %s`, targets `base`/%s) on `debian:trixie-slim` pinned to the manifest-list digest below (re-pin on every Debian point release; `check-pins.sh` asserts the single base digest matches this pin table) with Git, Bash, C/C++ toolchains, `fd`/`rg`/`jq`, an explicit `HOME=/home/box`, system-first `PATH` (writable `~/.local/bin` last), tool-scoped `XDG_DATA_HOME`/`XDG_STATE_HOME` (`/persist/data|state/<tool>`), and a UID/GID-matched `box` user. The `base` target holds only common apt + user + common `ENV` (`XDG_CONFIG_HOME`/`XDG_CACHE_HOME`/`HOME`/`PATH`/`SHELL`); each tool target owns its extra packages, dirs/symlinks/seeds, `XDG_DATA_HOME`/`XDG_STATE_HOME`, auto-update opt-out, labels, and `ENTRYPOINT`. All `ARG`s (including `HOST_UID`/`HOST_GID`) have no defaults so bare builds fail closed. The single pin source is the version files (`lib/pins.sh` threads them into `setup.sh`, `check-pins.sh`, and `lib/build.sh`, which the `Makefile` delegates to); this table is generated by `gen-pins.sh` from the version files + Dockerfile and is verified by `make pin-check` + `make verify-pins-generated`.\n' "$_pins_targets_pipe" "$_pins_targets_md"
  printf '\n'
  printf '| Pin (single source) | Value (`check-pins.sh` verifies) |\n'
  printf '|---|---|\n'
  printf '| Debian base digest | `%s` (%s) |\n' "$docker_digest" "$base_date"
  for _pins_id in $box_tool_ids; do
    _pins_vkey=$(box_tool_field "$_pins_id" pin_keys); _pins_vkey=${_pins_vkey%% *}
    printf '| %s `%s` (`%s`) | `%s` |\n' "$(box_tool_field "$_pins_id" display)" "$_pins_vkey" "$(box_tool_field "$_pins_id" version_file)" "${!_pins_vkey}"
  done
  # Node toolchain rows are opencode-owned (only npm-pinned tool needs a
  # toolchain): adding tools adds version rows via the loop above, but
  # removing opencode would require dropping these two rows.
  printf '| Node `NODE_VERSION` (`version-opencode.env`) | `%s` |\n' "$NODE_VERSION"
  printf '| NodeSource `NODESOURCE_FINGERPRINT` (`version-opencode.env`) | `%s` |\n' "$NODESOURCE_FINGERPRINT"
  printf '<!-- pin-table-end -->\n'
} >"$new_block" || die 'Cannot render pin table.'
unset _pins_targets_pipe _pins_targets_md _pins_id _pins_vkey

# Splice the fresh block between the markers (markers stay, body replaced).
seen_start=0
seen_end=0
in_block=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "<!-- pin-table-start -->" ]]; then
    cat -- "$new_block" >>"$new_readme" || die 'Cannot splice pin table.'
    seen_start=1
    in_block=1
    continue
  elif [[ "$line" == "<!-- pin-table-end -->" ]]; then
    seen_end=1
    in_block=0
    continue
  fi
  if (( ! in_block )); then
    printf '%s\n' "$line" >>"$new_readme" || die 'Cannot render updated doc.'
  fi
done <"$readme" || die 'Cannot read pin table doc.'
((seen_start && seen_end)) || die 'Pin-table markers unbalanced in docs/architecture.md.'

if ((check_only)); then
  if ! diff -u -- "$readme" "$new_readme" >/dev/null; then
    printf '%s: FAIL: docs/architecture.md §4 differs from version files/Dockerfile output; run gen-pins.sh.\n' \
      "$BOX_TOOL" >&2
    diff -u -- "$readme" "$new_readme" >&2 || true
    exit 1
  fi
else
  chmod 644 -- "$new_readme" || die 'Cannot set generated doc mode.'
  mv -f -- "$new_readme" "$readme" || die "Cannot write $readme."
fi
# $new_readme is gone after mv (rm is a no-op for it); $new_block always needs
# removal. Clear the EXIT trap after the explicit cleanup.
rm -f -- "$new_block" "$new_readme" || true
trap - EXIT
if ((check_only)); then
  printf 'gen-pins.sh: PASS (docs/architecture.md §4 matches version files/Dockerfile)\n'
else
  printf 'gen-pins.sh: PASS (docs/architecture.md §4 regenerated)\n'
fi
