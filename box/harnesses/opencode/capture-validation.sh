#!/bin/bash -p
# Capture redacted v2 source inspection; enforcement is tested separately.
# Compare ordered permissions, default_agent and update before replacing artifacts.
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

BOX_TOOL=regen-validation.sh
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/preflight.sh
source "$script_dir/../../lib/preflight.sh"
# shellcheck source=lib/pins.sh
source "$script_dir/../../lib/pins.sh"
# shellcheck source=lib/docker.sh
source "$script_dir/../../lib/docker.sh"
# shellcheck source=lib/test-state.sh
source "$script_dir/../../lib/test-state.sh"

bundle_dir=$(realpath "$script_dir/../..")
shipped="$bundle_dir/harnesses/opencode/config/opencode.json"
resolved="$bundle_dir/harnesses/opencode/validation/resolved-config.json"
resolved_stderr="$bundle_dir/harnesses/opencode/validation/config-stderr.txt"
launcher="$HOME/.local/bin/box-o"

check_only=0
runtime_flag=--runsc
while (($#)); do
  case "$1" in
    --check) check_only=1 ;;
    --runsc|--docker-fallback) runtime_flag=$1 ;;
    --output-dir)
      [[ $# -ge 2 && -n $2 ]] || die '--output-dir requires a directory.'
      mkdir -p -- "$2" || die 'Cannot create output directory.'
      resolved="$(realpath -- "$2")/resolved-config.json"
      resolved_stderr="$(realpath -- "$2")/config-stderr.txt"
      shift ;;
    *) die "Unknown argument: $1 (usage: regen-validation.sh [--check] [--output-dir DIR] [--runsc|--docker-fallback])" ;;
  esac
  shift
done

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
# a throwaway scratch project. Capture ALWAYS runs in a fresh disposable
# namespace — including when invoked from a normal production shell — so it
# never consumes global auth merely to inspect configuration, and it never
# touches a production volume.
# In test-namespace runs the scratch project lives under the disposable
# BOX_TEST_TASK_ROOT, and the capture owns an independent
# `<ns>-cap-<8hex>` sub-namespace (specs/plan.md §0 B0): the parent-NS volume
# is never touched by the capture run. Outside test mode a fresh disposable
# task root + namespace is minted for the same isolation.
# Single EXIT trap declared upfront; subshell (cd) avoids pushd/popd asymmetry.
scratch_parent=$HOME
capture_ns=
capture_task_root=
capture_own_root=0
if box_test_in_test_mode; then
  box_test_require_vars
  capture_ns=$(box_test_capture_ns) || die 'Cannot derive capture sub-namespace.'
  scratch_parent=$BOX_TEST_TASK_ROOT
else
  capture_task_root=$(mktemp -d "$HOME/.box-capture.XXXXXX") || die 'Cannot create disposable capture task root.'
  chmod 700 -- "$capture_task_root" || die 'Cannot secure disposable capture task root.'
  capture_own_root=1
  capture_ns=$(box_test_new_ns) || die 'Cannot mint disposable capture namespace.'
  scratch_parent=$capture_task_root
fi
# Capture owns a new namespace and a new physical scratch project. A caller's
# project-qualified fixture hash cannot describe that scratch workspace.
unset BOX_TEST_PROJECT_HASH
scratch=$(mktemp -d "$scratch_parent/.box-regen.XXXXXX") || die 'Cannot create scratch project.'
cache_tmp=$scratch
effective_err=$(mktemp "$cache_tmp/regen-validation-err.XXXXXX") || die 'Cannot create temp file.'
redacted=$(mktemp "$cache_tmp/regen-validation-redacted.XXXXXX") || die 'Cannot create temp file.'
chmod 600 -- "$effective_err" "$redacted" || die 'Cannot secure temp files.'
# The capture owns this unique physical project's v2 volume only, resolved
# through the disposable test resolver in every domain.
host_uid=$(id -u)
host_gid=$(id -g)
capture_volume=$(box_test_volume opencode "$capture_ns" "$host_uid" "$host_gid") || die 'Cannot derive capture volume.'
# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap (SC2317 for shellcheck 0.9, SC2329 for 0.11+)
cleanup_regen() {
  local status=$? cid inventory containers cleanup_failed=0
  if [[ -d "$HOME/.config/box-o/docker-cli" ]]; then
    box_docker_cli "$HOME/.config/box-o/docker-cli"
    # Capture cleanup is strictly authorized: only the capture's own
    # sub-namespace volume may be removed, never the parent NS and
    # never a production volume. The guard dies without touching Docker.
    box_test_guard_cleanup "$capture_volume" opencode "$capture_ns" "$host_uid" "$host_gid" >/dev/null || return 1
    if containers=$("${docker_cmd[@]}" ps -aq --filter "volume=$capture_volume"); then
      while IFS= read -r cid; do
        if [[ -n "$cid" ]]; then
          "${docker_cmd[@]}" rm -f "$cid" >/dev/null || cleanup_failed=1
        fi
      done <<<"$containers"
    else cleanup_failed=1; fi
    if inventory=$("${docker_cmd[@]}" volume ls -q); then
      if [[ $'\n'"$inventory"$'\n' == *$'\n'"$capture_volume"$'\n'* ]]; then
        "${docker_cmd[@]}" volume rm "$capture_volume" >/dev/null || cleanup_failed=1
      fi
    else cleanup_failed=1; fi
  fi
  rm -rf -- "$scratch" "$effective_err" "$redacted" || cleanup_failed=1
  if ((capture_own_root)) && [[ -n "$capture_task_root" ]]; then
    rm -rf -- "$capture_task_root" || cleanup_failed=1
  fi
  if ((cleanup_failed)); then
    printf 'FAIL: capture cleanup failed for owned volume %s\n' "$capture_volume" >&2
    status=1
  fi
  return "$status"
}
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
if ! (cd -- "$scratch" && BOX_TEST_REAL_HOME="${BOX_TEST_REAL_HOME:-$HOME}" BOX_TEST_TASK_ROOT="${capture_task_root:-${BOX_TEST_TASK_ROOT:-}}" BOX_TEST_STATE_NS="$capture_ns" timeout 45 "$launcher" "$runtime_flag" --shell -c 'opencode debug config' 2>"$effective_err" \
    | jq -e 'walk(if type == "object" then with_entries(if (.key | ascii_downcase | test("apikey|api_key|token|secret|passwd|password|authorization|credential|private_key")) then .value = "validation-placeholder" else . end) else . end)' \
    >"$redacted"); then
  # Native diagnostics may echo user configuration. Keep raw stderr private.
  printf '%s: native config diagnostics withheld (%s bytes).\n' "$BOX_TOOL" "$(wc -c <"$effective_err")" >&2
  die 'opencode debug config failed (build the image and start the Engine first).'
fi

# Debug output is an array of source records, not an effective config object.
source_record=$(jq -e -c '[.[] | select(.path == "/persist/config/opencode/opencode.json") | .info] | if length == 1 then .[0] else error("missing or ambiguous shipped source") end' "$redacted") || die 'Missing native shipped source inspection.'
printf '%s\n' "$source_record" >"$redacted"
for field in permissions default_agent update; do
  check_field "$field" ".$field" "$shipped" "$redacted"
done
((fail == 0)) || die 'Shipped v2 source differs; artifacts were not replaced.'
if ((check_only)); then
  printf '%s: PASS (v2 shipped source inspection matches)\n' "$BOX_TOOL"
  exit 0
fi
install -m 644 -- "$redacted" "$resolved" || die 'Cannot write resolved-config.json.'
# A 0-byte stderr is ambiguous with "never ran": record a one-line sentinel
# for the clean case so the artifact always witnesses its own run.
if [[ -s "$effective_err" ]]; then
  printf 'Native config diagnostics withheld (%s bytes); no raw user configuration retained.\n' \
    "$(wc -c <"$effective_err")" >"$resolved_stderr" || die 'Cannot write config-stderr.txt.'
  chmod 644 "$resolved_stderr"
else
  printf '(clean config load: no warnings on stderr)\n' >"$resolved_stderr" \
    || die 'Cannot write config-stderr.txt.'
  chmod 644 -- "$resolved_stderr" || die 'Cannot write config-stderr.txt.'
fi

printf '%s: PASS (redacted v2 source inspection regenerated)\n' "$BOX_TOOL"
