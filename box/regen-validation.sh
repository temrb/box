#!/bin/bash -p
# regen-validation.sh — regenerate validation/resolved-config.json from the
# container and diff the pinned sections against the shipped opencode.json.
# Secret-shaped values are redacted via a pipe (never land unredacted in a
# temp file), and the permission pin is diffed field-wise (the effective merged
# config adds defaults the shipped file never carries, so a full-file diff
# would always fail; there is no model or provider pin — pure /connect).
# Only `.permission` is pinned by design: other top-level keys (e.g.
# `default_agent`, `agent`, `provider`, `compaction`) are intentionally
# excluded because the effective merged config adds upstream defaults and
# user-chosen values the shipped file never carries. Shipped-vs-effective
# drift outside `.permission` (e.g. `default_agent: plan` vs `build`) passes
# silently and is expected.
# Requires a built image + running Engine.
# Usage: regen-validation.sh [--check]  (--check diffs field-wise without rewriting)
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

BOX_TOOL=regen-validation.sh
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/preflight.sh
source "$script_dir/lib/preflight.sh"
# shellcheck source=lib/pins.sh
source "$script_dir/lib/pins.sh"

bundle_dir=$script_dir
shipped="$bundle_dir/opencode.json"
resolved="$bundle_dir/validation/resolved-config.json"
resolved_stderr="$bundle_dir/validation/config-stderr.txt"
launcher="$bundle_dir/box-o"

check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
elif [[ -n "${1:-}" ]]; then
  die "Unknown argument: $1 (usage: regen-validation.sh [--check])"
fi

[[ -f "$shipped" ]] || die "Missing shipped config: $shipped"
[[ -x "$launcher" ]] || die "Missing launcher: $launcher"
command -v jq >/dev/null || die 'jq is required.'

fail=0
check_field() {
  local desc=${1:-} filter=${2:-} a=${3:-} b=${4:-}
  local want got
  want=$(jq -e -c "$filter" -- "$a") || { printf '%s: FAIL: cannot read shipped %s\n' "$BOX_TOOL" "$desc" >&2; fail=1; return; }
  got=$(jq -e -c "$filter" -- "$b") || { printf '%s: FAIL: cannot read effective %s\n' "$BOX_TOOL" "$desc" >&2; fail=1; return; }
  if [[ "$want" == "$got" ]]; then
    printf '%s: ok %s = %s\n' "$BOX_TOOL" "$desc" "$want" >&2
  else
    printf '%s: FAIL: %s differs (shipped=%s effective=%s)\n' "$BOX_TOOL" "$desc" "$want" "$got" >&2
    fail=1
  fi
}

# `opencode debug config` needs a project CWD for the launcher preflight; use
# a throwaway scratch project under HOME (never /tmp: /tmp/* is denylisted).
# Single EXIT trap declared upfront; subshell (cd) avoids pushd/popd asymmetry.
scratch=$(mktemp -d "$HOME/.box-regen.XXXXXX") || die 'Cannot create scratch project.'
cache_tmp=${TMPDIR:-$HOME/.cache}
effective_err=$(mktemp "$cache_tmp/regen-validation-err.XXXXXX") || die 'Cannot create temp file.'
redacted=$(mktemp "$cache_tmp/regen-validation-redacted.XXXXXX") || die 'Cannot create temp file.'
chmod 600 -- "$effective_err" "$redacted" || die 'Cannot secure temp files.'
cleanup_regen() { rm -rf -- "$scratch" "$effective_err" "$redacted"; }
trap cleanup_regen EXIT

# Generic secret redaction (no provider required): native /connect auth may
# surface keys for user-chosen providers, and none may exist at all. Any
# object key whose name looks secret-shaped (case-insensitive) is replaced,
# not just `apiKey`, so new credential-shaped merged fields cannot land in
# the checked-in artifact.
# Shell invocation shape (pinned by tests/bats/makefile.bats): `--shell -c
# 'opencode debug config'` so the launcher's `--entrypoint=/bin/bash` receives
# `-c` plus the command. `--shell -- opencode debug config` is wrong: bash
# would treat `opencode` as a script file (exit 127); merely dropping `--`
# does not fix it.
if ! (cd -- "$scratch" && "$launcher" --shell -c 'opencode debug config' 2>"$effective_err" \
    | jq -e 'walk(if type == "object" then with_entries(if (.key | ascii_downcase | test("apikey|api_key|token|secret|passwd|password|authorization|credential|private_key")) then .value = "validation-placeholder" else . end) else . end)' \
    >"$redacted"); then
  cat -- "$effective_err" >&2 || true
  die 'opencode debug config failed (build the image and start the Engine first).'
fi

if ((check_only)); then
  # Field-wise --check (same oracle as the regen path): full-file diff is
  # brittle to upstream defaults (agents/openai/compaction). Only
  # `.permission` is pinned; drift elsewhere is intentionally ignored (see
  # the header comment).
  check_field 'permission' '.permission' "$shipped" "$redacted"
  ((fail == 0)) || die 'Pinned sections differ; run make regen-validation.'
  printf '%s: PASS (permission section matches container effective config)\n' "$BOX_TOOL"
  exit 0
fi
install -m 644 -- "$redacted" "$resolved" || die 'Cannot write resolved-config.json.'
# A 0-byte stderr is ambiguous with "never ran": record a one-line sentinel
# for the clean case so the artifact always witnesses its own run.
if [[ -s "$effective_err" ]]; then
  install -m 644 -- "$effective_err" "$resolved_stderr" || die 'Cannot write config-stderr.txt.'
else
  printf '(clean config load: no warnings on stderr)\n' >"$resolved_stderr" \
    || die 'Cannot write config-stderr.txt.'
  chmod 644 -- "$resolved_stderr" || die 'Cannot write config-stderr.txt.'
fi

check_field 'permission' '.permission' "$shipped" "$resolved"
((fail == 0)) || die 'Pinned sections differ; sync opencode.json or the image and re-run.'
printf '%s: PASS (resolved-config.json regenerated, permission section matches)\n' "$BOX_TOOL"
