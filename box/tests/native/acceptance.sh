#!/bin/bash
# Disposable, unauthenticated acceptance evidence; unmet gates remain failures.
# shellcheck disable=SC2016 # quoted scripts run inside the container
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
BOX_TOOL=acceptance.sh
bundle_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
# shellcheck source=lib/tools.sh
source "$bundle_dir/lib/tools.sh"
# shellcheck source=lib/pins.sh
source "$bundle_dir/lib/pins.sh"
# shellcheck source=lib/build.sh
source "$bundle_dir/lib/build.sh"
# shellcheck source=lib/docker.sh
source "$bundle_dir/lib/docker.sh"
selected_ids=$box_tool_ids
focused=0
if (($#)); then
  [[ $# == 2 && $1 == --only && $2 == opencode ]] || die 'Usage: acceptance.sh [--only opencode]'
  selected_ids=opencode
  focused=1
fi
# Keep caller overrides and identity out of disposable fixture state.
for id in $box_tool_ids; do
  prefix=$(box_tool_field "$id" git_prefix)
  for suffix in CONFIG VERSION_FILE ENV_FILE IMAGE EXTRA_GIDS; do unset "${prefix}_$suffix"; done
  printf -v "${prefix}_GIT_NAME" '%s' 'Acceptance Fixture'
  printf -v "${prefix}_GIT_EMAIL" '%s' 'fixture@example.invalid'
  export "${prefix}_GIT_NAME" "${prefix}_GIT_EMAIL"
  for state in $(box_tool_field "$id" states); do
    for override in $(box_state_field "$id" "$state" override); do unset "$override"; done
  done
done
host_uid=$(id -u); host_gid=$(id -g)
((host_uid > 0 && host_gid > 0)) || die 'Run acceptance as your normal user.'
task_root=$(mktemp -d "$HOME/.box-native.XXXXXX")
test_home="$task_root/home"
mkdir -m 700 "$test_home"
volumes=()
# Fixture removal must succeed; absence is allowed for tools never launched.
remove_fixture_volumes() {
  local volume cid inventory
  local -A seen=()
  inventory=$("${docker_cmd[@]}" volume ls -q) || return 1
  for volume in "${volumes[@]}"; do
    [[ -z "${seen[$volume]:-}" ]] || continue
    seen[$volume]=1
    [[ $'\n'"$inventory"$'\n' == *$'\n'"$volume"$'\n'* ]] || continue
    while IFS= read -r cid; do
      [[ -z "$cid" ]] || "${docker_cmd[@]}" rm -f "$cid" >/dev/null || return 1
    done < <("${docker_cmd[@]}" ps -aq --filter "volume=$volume")
    "${docker_cmd[@]}" volume rm "$volume" >/dev/null || return 1
  done
}
# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap (SC2317 for shellcheck 0.9, SC2329 for 0.11+)
cleanup_native() {
  local status=$?
  if ! remove_fixture_volumes; then
    printf 'FAIL: disposable native fixture cleanup\n' >&2
    status=1
  else
    printf 'PASS: disposable native fixture containers and volumes removed\n'
  fi
  rm -rf -- "$task_root"
  exit "$status"
}
trap cleanup_native EXIT
box_docker_cli "$test_home/.config/acceptance/docker-cli"
env HOME="$test_home" bash "$bundle_dir/setup.sh" --skip-build >"$task_root/setup.log" 2>&1
project="$task_root/project"
mkdir -m 700 "$project"
touch "$project/.box-native-disposable"
printf 'Disposable native acceptance fixture\n' >"$project/README.md"
git -c init.defaultBranch=main init -q "$project"
git -C "$project" add README.md
git -C "$project" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
  -c user.name='Acceptance Fixture' -c user.email=fixture@example.invalid \
  commit -qm 'Disposable fixture'
hash=$(printf '%s' "$project" | sha256sum); hash=${hash:0:20}
for id in $box_tool_ids; do
  prefix=$(box_tool_field "$id" network)
  [[ "$id" != opencode ]] || prefix=box-o-v2
  volumes+=("$prefix-u$host_uid-g$host_gid-$hash")
done
cd "$project"
unmet=0
# Production launcher checks, separate from account-dependent generated readiness.
check_opencode() {
  local flag=$1 iteration second second_hash legacy
  for iteration in first restart; do
    env HOME="$test_home" "$test_home/.local/bin/box-o" "$flag" --shell \
      -c 'python3 - "$1"' _ "$iteration" <"$bundle_dir/tests/native/opencode-state.py" || return 1
  done
  # Account presence is an independent readiness gate even when local policy passes.
  sed -n '/^echo "=== 4\. OpenCode/,/^echo "=== 5\./p' "$bundle_dir/verify-opencode.sh" >"$task_root/readiness.sh"
  if env HOME="$test_home" "$test_home/.local/bin/box-o" "$flag" --shell -e -s \
      <"$task_root/readiness.sh" >"$task_root/readiness.log" 2>&1; then
    die 'Empty native credential store incorrectly passed readiness.'
  fi
  grep -Fq 'FAIL: no provider auth: connect natively via /connect' "$task_root/readiness.log" || return 1
  printf 'PASS: opencode/%s empty native credential store fails readiness\n' "$flag"
  env HOME="$test_home" bash "$bundle_dir/harnesses/opencode/capture-validation.sh" "$flag" || return 1
  env HOME="$test_home" bash "$bundle_dir/harnesses/opencode/capture-validation.sh" --check "$flag" || return 1
  legacy="box-o-u$host_uid-g$host_gid-$hash"
  volumes+=("$legacy")
  # Seed only a disposable legacy fixture; the launcher must leave it untouched.
  "${docker_cmd[@]}" volume create "$legacy" >/dev/null || return 1
  # shellcheck disable=SC2046 # ordered registry keys intentionally split
  box_load_version_file "$test_home/.config/box-o/version-opencode.env" "$(box_tool_field opencode version_format)" $(box_tool_field opencode pin_keys) || return 1
  local image
  image=$(box_image_tag_for_version opencode "$box_file_version" "$host_uid" "$host_gid")
  # Legacy fixture ownership is seeded by Docker from the production image.
  "${docker_cmd[@]}" run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
    --user "$host_uid:$host_gid" --mount "type=volume,src=$legacy,dst=/persist" \
    --entrypoint /bin/sh "$image" -c 'printf legacy > /persist/legacy-marker' || return 1
  env HOME="$test_home" "$test_home/.local/bin/box-o" "$flag" --shell \
    -c 'python3' <"$bundle_dir/harnesses/opencode/native-probe.py" || return 1
  "${docker_cmd[@]}" run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
    --user "$host_uid:$host_gid" --mount "type=volume,src=$legacy,dst=/persist,readonly" \
    --entrypoint /bin/sh "$image" -c 'test "$(cat /persist/legacy-marker)" = legacy' || return 1
  printf 'PASS: opencode/%s legacy fixture remains untouched\n' "$flag"
  for phase in saved-seed saved-restart; do
    env HOME="$test_home" "$test_home/.local/bin/box-o" "$flag" --shell \
      -c 'python3 - "$1"' _ "$phase" <"$bundle_dir/harnesses/opencode/native-probe.py" || return 1
  done
  second="$task_root/opencode-second-${flag#--}"
  mkdir -m 700 "$second"
  local before after
  before=$("${docker_cmd[@]}" volume ls -q)
  (cd "$second"; env HOME="$test_home" "$test_home/.local/bin/box-o" --dry-run >/dev/null) || return 1
  after=$("${docker_cmd[@]}" volume ls -q)
  [[ "$before" == "$after" ]] || return 1
  [[ -z "$(find "$second" -mindepth 1 -print -quit)" ]] || return 1
  printf 'PASS: opencode/%s dry-run creates no project files or volumes\n' "$flag"
  second_hash=$(printf '%s' "$second" | sha256sum); second_hash=${second_hash:0:20}
  volumes+=("box-o-v2-u$host_uid-g$host_gid-$second_hash")
  (
    cd "$second"
    env HOME="$test_home" "$test_home/.local/bin/box-o" "$flag" --shell \
      -c 'test ! -e /persist/config/opencode/cli.json && test ! -e /persist/state/opencode/box-persistence-marker' || return 1
    touch .box-native-disposable
    env HOME="$test_home" "$test_home/.local/bin/box-o" "$flag" --shell \
      -c 'python3 - saved-isolation' <"$bundle_dir/harnesses/opencode/native-probe.py" || return 1
  ) || return 1
  printf 'PASS: opencode/%s preferences reset while state and approvals persist and isolate physical projects\n' "$flag"
}
check_opencode_pin_recovery() {
  local dest src before
  dest="$test_home/.config/box-o/version-opencode.env"
  src="$bundle_dir/harnesses/opencode/version-opencode.env"
  before=$(sha256sum "$test_home/.config/box-o/opencode.json" "$test_home/.local/bin/box-o")
  printf 'OPENCODE_VERSION=1.18.34\n' >"$dest"
  if env HOME="$test_home" bash "$bundle_dir/setup.sh" --skip-build >"$task_root/incompatible.log" 2>&1; then
    die 'Setup accepted an incompatible installed pin contract.'
  fi
  [[ "$(sha256sum "$test_home/.config/box-o/opencode.json" "$test_home/.local/bin/box-o")" == "$before" ]] || die 'Setup changed installed files before pin rejection.'
  env HOME="$test_home" make -C "$bundle_dir" sync-pins-o
  cmp "$src" "$dest"
  env HOME="$test_home" bash "$bundle_dir/setup.sh" --skip-build >"$task_root/recovery.log" 2>&1
  sed -i 's/^OPENCODE_VERSION=.*/OPENCODE_VERSION=2.0.999/' "$dest"
  before=$(sha256sum "$dest")
  env HOME="$test_home" bash "$bundle_dir/setup.sh" --skip-build >"$task_root/preserved.log" 2>&1
  [[ "$(sha256sum "$dest")" == "$before" ]] || die 'Setup replaced valid differing v2 pins.'
  env HOME="$test_home" make -C "$bundle_dir" sync-pins-o
  cmp "$src" "$dest"
  printf 'PASS: incompatible installed pins reject before refresh; validated atomic v2 pin sync then setup recovers\n'
}
if ((focused)); then
  check_opencode_pin_recovery
  for runtime_flag in --runsc --docker-fallback; do
    env HOME="$test_home" "$test_home/.local/bin/box-o" "$runtime_flag" --version
    # Separate runtime fixtures prevent saved approvals contaminating the matrix.
    check_opencode "$runtime_flag"
    remove_fixture_volumes
  done
  printf 'UNMET: real provider login/model/resume, native ARM64, actual GitHub workflow run (separate gates)\n'
  exit 0
fi
declare -A seen=()
for runtime in runsc runc; do
  runtime_flag=--runsc
  [[ "$runtime" != runc ]] || runtime_flag=--docker-fallback
  for id in $selected_ids; do
    launcher="$test_home/.local/bin/$(box_tool_field "$id" launcher)"
    env HOME="$test_home" "$launcher" "$runtime_flag" --version >"$task_root/version.log" 2>&1
    printf 'PASS: %s/%s native version startup (installed package)\n' "$id" "$runtime"
    if [[ "$id" == muse ]]; then
      if env HOME="$test_home" "$launcher" "$runtime_flag" exec --provider echo 'Return a fixture reply' >"$task_root/muse-echo.log" 2>&1; then
        printf 'PASS: muse/%s native echo startup with shipped settings and bypass (no external inference/auth)\n' "$runtime"
      else printf 'UNMET: muse/%s native echo startup\n' "$runtime"; unmet=1; fi
    fi
    # Check shared containment independently when full native readiness lacks auth.
    cat "$bundle_dir/harnesses/$id/verify.d/00-header-$id.sh" \
      "$bundle_dir/verify.d/10-workspace.sh" "$bundle_dir/verify.d/20-toolchain.sh" \
      "$bundle_dir/verify.d/50-containment.sh" >"$task_root/containment.sh"
    if env HOME="$test_home" "$launcher" "$runtime_flag" --shell -s -- README.md \
        <"$task_root/containment.sh" >"$task_root/containment.log" 2>&1; then
      printf 'PASS: %s/%s shared containment (native readiness separate)\n' "$id" "$runtime"
    else
      printf 'FAIL: %s/%s shared containment\n' "$id" "$runtime"; unmet=1
      grep -E '^FAIL:|^WARNING:|command not found|Permission denied' "$task_root/containment.log" || true
    fi
    if env HOME="$test_home" "$launcher" "$runtime_flag" --shell -s -- README.md \
        <"$bundle_dir/verify-$id.sh" >"$task_root/full.log" 2>&1; then
      printf 'PASS: %s/%s full generated verification\n' "$id" "$runtime"
    else
      printf 'UNMET: %s/%s full generated verification (no account imported)\n' "$id" "$runtime"; unmet=1
      grep -E '^FAIL:|command not found|Permission denied' "$task_root/full.log" || true
    fi
  done
  policy=$(python3 -c 'import json,tomllib,sys; print(json.dumps(tomllib.load(open(sys.argv[1],"rb"))))' "$bundle_dir/harnesses/codex/policy/requirements.toml")
  # shellcheck disable=SC2016 # literal script runs inside the container
  if env HOME="$test_home" "$test_home/.local/bin/box-c" "$runtime_flag" --shell \
    -c 'python3 - --policy-json "$1" --conflicts' _ "$policy" \
    <"$bundle_dir/harnesses/codex/native-probe.py"; then
    printf 'PASS: codex/%s native policy conflicts\n' "$runtime"
  else unmet=1; fi
  if check_opencode "$runtime_flag"; then
    printf 'PASS: opencode/%s native permission and state checks\n' "$runtime"
  else unmet=1; fi
  rm -f -- "$project/opencode.json"
  for volume in "${volumes[@]}"; do
    [[ -z "${seen[$volume]:-}" ]] || continue
    seen[$volume]=1
    [[ "$volume" != box-o-v2-* && "$volume" != box-o-u* ]] || "${docker_cmd[@]}" volume rm "$volume" >/dev/null 2>&1 || true
  done
done
# Two-project Codex host-home and volume persistence without auth/transcripts.
for iteration in first second; do
  # shellcheck disable=SC2016 # literal script runs inside the container
  env HOME="$test_home" "$test_home/.local/bin/box-c" --runsc --shell -c '
    if test "$1" = first; then
      printf fixture > "$CODEX_HOME/box-persistence-marker"
      printf fixture > /persist/state/codex/box-persistence-marker
    else
      test "$(cat "$CODEX_HOME/box-persistence-marker")" = fixture
      test "$(cat /persist/state/codex/box-persistence-marker)" = fixture
    fi' _ "$iteration"
done
second_project="$task_root/second-project"
mkdir -m 700 "$second_project"
cd "$second_project"
second_hash=$(printf '%s' "$second_project" | sha256sum); second_hash=${second_hash:0:20}
volumes+=("box-c-u$host_uid-g$host_gid-$second_hash")
# shellcheck disable=SC2016 # literal script runs inside the container
env HOME="$test_home" "$test_home/.local/bin/box-c" --runsc --shell -c '
  test ! -e "$CODEX_HOME/box-persistence-marker"
  test ! -e /persist/state/codex/box-persistence-marker'
printf 'PASS: Codex both stores persist on restart and isolate two physical projects (unauthenticated)\n'
# Exercise setup reruns against controlled fixture state, never real auth.
first_home="$test_home/.config/box-c/projects/$hash/codex-home"
printf 'model = "fixture-preference"\n' >"$first_home/config.toml"
printf '{"fixture":true}\n' >"$first_home/auth.json"
chmod 600 "$first_home/auth.json"
before=$(sha256sum "$first_home/config.toml" "$first_home/auth.json")
printf '# installed fixture pin annotation\n' >>"$test_home/.config/box-c/version-codex.env"
pins_before=$(sha256sum "$test_home/.config/box-c/version-codex.env")
printf '# obsolete installed adapter\n' >"$test_home/.local/bin/harnesses/codex/obsolete.sh"
chmod 644 "$test_home/.local/bin/harnesses/codex/obsolete.sh"
env HOME="$test_home" bash "$bundle_dir/setup.sh" --default codex --skip-build >"$task_root/rerun.log" 2>&1
env HOME="$test_home" bash "$bundle_dir/setup.sh" --skip-build >>"$task_root/rerun.log" 2>&1
[[ "$(sha256sum "$first_home/config.toml" "$first_home/auth.json")" == "$before" ]]
[[ "$(sha256sum "$test_home/.config/box-c/version-codex.env")" == "$pins_before" ]]
[[ "$(readlink "$test_home/.local/bin/box")" == box-c ]]
[[ ! -e "$test_home/.local/bin/harnesses/codex/obsolete.sh" ]]
printf 'PASS: setup reruns preserve default/pins/preferences/fixture auth and remove obsolete package code\n'
printf 'UNMET: authenticated login/model/resume, native ARM64, and actual GitHub workflow run\n'
((unmet == 0)) || printf 'FAIL: one or more account-independent native gates failed\n'
# This driver cannot certify account, architecture, or remote CI gates.
exit 1
