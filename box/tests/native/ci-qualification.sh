#!/usr/bin/env bash
# Account-independent qualification on a dedicated, trusted self-hosted runner.
# Retains exact disposable coordinates/evidence; never selects production auth.
set -euo pipefail
# shellcheck disable=SC2154 # registered ids are supplied by tools.sh.
check_only=0
if (($#)); then
  [[ $# == 1 && $1 == --check ]] || { printf 'Usage: ci-qualification.sh [--check]\n' >&2; exit 2; }
  check_only=1
fi
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
export BOX_TOOL=ci-qualification.sh
bundle_dir=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")/../..")
# shellcheck source=lib/preflight.sh
source "$bundle_dir/lib/preflight.sh"
# shellcheck source=lib/tools.sh
source "$bundle_dir/lib/tools.sh"
host_uid=$(id -u)
host_gid=$(id -g)
((host_uid > 0 && host_gid > 0)) || die 'Qualification requires a non-root runner user.'
[[ "${BOX_QUALIFICATION_PLATFORM:-}" == amd64 || "${BOX_QUALIFICATION_PLATFORM:-}" == arm64 ]] \
  || die 'BOX_QUALIFICATION_PLATFORM must be amd64 or arm64.'
case "$(uname -m):$BOX_QUALIFICATION_PLATFORM" in
  x86_64:amd64|aarch64:arm64) ;;
  *) die 'Runner architecture does not match the selected qualification platform.' ;;
esac
[[ -n "${BOX_QUALIFICATION_ROOT:-}" ]] || die 'Set BOX_QUALIFICATION_ROOT to a dedicated protected project parent.'
qualification_root=$(box_plan_directory "$BOX_QUALIFICATION_ROOT") || exit 1
[[ -d "$qualification_root" ]] || die 'Qualification root must already exist.'
box_assert_owner_mode "$qualification_root" 'Qualification root' dir700
box_denylisted_system_path "$qualification_root" && die 'Qualification root is on the project denylist.'
case "$qualification_root/" in "$bundle_dir/"*|"${bundle_dir%/box}/"*) die 'Qualification root must be outside the source checkout.';; esac
# Clear every registered production selector before allocating test state.
for id in $box_tool_ids; do
  prefix=$(box_tool_field "$id" git_prefix)
  for suffix in CONFIG VERSION_FILE ENV_FILE IMAGE EXTRA_GIDS AUTH AUTH_SCOPE ALLOW_FALLBACK GIT_NAME GIT_EMAIL; do
    unset "${prefix}_$suffix"
  done
  for key in $(box_tool_field "$id" forward_keys); do unset "$key"; done
  for state in $(box_tool_field "$id" states); do
    for selector in $(box_state_field "$id" "$state" override); do unset "$selector"; done
  done
done
unset BOX_AUTH_SCOPE BOX_AUTH_ROOT BOX_AUTH_TRANSITION BOX_AUTH_RUNTIME BOX_STATE_CONFIG BOX_AUTH_HELPER BOX_BUNDLE_DIR
unset BOX_TEST_STATE_NS BOX_TEST_TASK_ROOT BOX_TEST_REAL_HOME BOX_TEST_PROJECT_HASH
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG DOCKER_TLS_VERIFY DOCKER_CERT_PATH
# Ambient account keys must not turn synthetic tests into account qualification.
unset OPENAI_API_KEY ANTHROPIC_API_KEY META_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
# Refuse protected production coordinates without reading their contents.
validate_qualification_parent() {
  local project=$qualification_root box_physical_home
  local -a box_credential_targets box_tool_targets
  box_preflight_denylist
  box_preflight_home
  box_preflight_credentials
  box_preflight_tool_dirs
}
validate_qualification_parent
for prerequisite in bash make git python3 jq shellcheck bats rg docker runsc; do
  command -v "$prerequisite" >/dev/null || die "Missing qualification prerequisite: $prerequisite"
done
python3 -I -c 'import tomllib' || die 'Qualification needs Python 3.11+.'
if ((check_only)); then
  printf 'Qualification paths and tools are ready; runtime and account behavior remain unqualified.\n'
  exit 0
fi
umask 077
task_root=$(mktemp -d "$qualification_root/box-ci.XXXXXXXX")
mkdir -m 700 "$task_root/home" "$task_root/projects" "$task_root/evidence"
export HOME="$task_root/home" BOX_TEST_PROJECT_ROOT="$task_root/projects"
evidence="$task_root/evidence"
failed=0
run_gate() {
  local name=$1 rc
  shift
  if "$@" >"$evidence/$name.log" 2>&1; then rc=0; else rc=$?; failed=1; fi
  if [[ "$rc" == 0 && ( "$name" == static || "$name" == live ) ]] &&
      grep -Eq '^ok [0-9]+ .*# skip' "$evidence/$name.log"; then
    printf 'Required qualification cases skipped; gate remains unmet.\n' >>"$evidence/$name.log"
    rc=3
    failed=1
  fi
  printf '%s\t%s\t%s\n' "$name" "$rc" "$(sha256sum "$evidence/$name.log" | cut -d ' ' -f 1)" >>"$evidence/gates.tsv"
  printf 'qualification %s: exit %s\n' "$name" "$rc"
  return "$rc"
}
printf 'head=%s\narchitecture=%s\nuid=%s\ngid=%s\n' \
  "$(git -C "${bundle_dir%/box}" rev-parse HEAD)" "$(uname -m)" "$host_uid" "$host_gid" >"$evidence/source.txt"
printf 'Disposable qualification coordinates: %s\n' "$task_root"
# Continue independent gates after failure, preserving their individual result.
run_gate static make -C "$bundle_dir" verify-static || true
run_gate pins make -C "$bundle_dir" pins || true
run_gate generated make -C "$bundle_dir" verify-generated || true
# Installation populates only the disposable HOME. Build is via Make only.
if run_gate install bash -p "$bundle_dir/setup.sh" --skip-build; then
  if run_gate build make -C "$bundle_dir" build; then
    # shellcheck disable=SC2317,SC2329 # invoked indirectly by run_gate
    record_images() (
      # shellcheck source=lib/build.sh
      source "$bundle_dir/lib/build.sh"
      local id tag
      for id in $box_tool_ids; do
        tag=$(box_image_tag "$id" "$bundle_dir" "$host_uid" "$host_gid")
        box_docker_cli "$HOME/.config/$(box_tool_field "$id" config_dir)/docker-cli"
        printf 'harness=%s tag=%s\n' "$id" "$tag"
        "${docker_cmd[@]}" image inspect --format '{{.Id}}|{{.Config.User}}|{{json .Config.Labels}}' "$tag" || return 1
      done
    )
    run_gate image-provenance record_images || true
    run_gate network python3 -I "$bundle_dir/tests/native/network-observations.py" || true
    run_gate live make -C "$bundle_dir" test-live || true
    run_gate opencode make -C "$bundle_dir" verify-native-opencode || true
    run_gate native make -C "$bundle_dir" verify-native || true
  else
    printf 'live\tnot-reached\tbuild failed\nopencode\tnot-reached\tbuild failed\nnative\tnot-reached\tbuild failed\n' >>"$evidence/gates.tsv"
  fi
else
  printf 'build\tnot-reached\tinstall failed\nlive\tnot-reached\tinstall failed\nopencode\tnot-reached\tinstall failed\nnative\tnot-reached\tinstall failed\n' >>"$evidence/gates.tsv"
fi
# This job cannot supply dedicated-account, power-loss or rollout evidence.
printf 'accounts\tunqualified\tdedicated-account driver required\npower-loss\tunqualified\tVM/filesystem qualification required\nrollout\tunqualified\tdisposable legacy qualification required\n' >>"$evidence/gates.tsv"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'Account-independent qualification evidence remains at %s.\n\nDedicated-account, power-loss and rollout gates remain unqualified.\n' "$evidence" >>"$GITHUB_STEP_SUMMARY"
fi
printf 'Evidence retained at %s; review exact run-owned resources before cleanup.\n' "$evidence"
exit "$failed"
