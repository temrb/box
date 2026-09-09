# split.bats — split-lib helpers: shared denylist, owner/mode and
# outside-project guards, per-concern preflight steps, docker-CLI hardening,
# ensure_network, pins, build, run, and config helpers.
load helpers

@test "denylist helper rejects system paths, allows projects" {
  for dir in / /home /root /etc /etc/passwd /dev /proc /sys /run /usr /boot /var /tmp /tmp/foo /opt /mnt /media /snap /snap/foo /srv/foo /data/foo /workspace/foo; do
    run box_denylisted_system_path "$dir"
    [ "$status" -eq 0 ] || { echo "not denylisted: $dir"; return 1; }
  done
  for dir in "$TEST_PROJ" "$HOME/projects/foo" /homepage /tmpfoo; do
    run box_denylisted_system_path "$dir"
    [ "$status" -ne 0 ] || { echo "wrongly denylisted: $dir"; return 1; }
  done
}

@test "denylist step and symlink step share one pattern" {
  project=/etc
  run box_preflight_denylist
  [ "$status" -ne 0 ]
  # Reset to the scratch project before the symlink scan: without this the
  # scan walks /etc (environment-dependent: permission-denied vs first-link
  # target), not the planted TEST_PROJ/evil link this test means to grade.
  project="$TEST_PROJ"
  ln -s /etc -- "$TEST_PROJ/evil"
  box_preflight_home
  box_preflight_credentials
  run box_preflight_symlinks
  [ "$status" -ne 0 ]
  [[ "$output" == *"host system path"* ]]
}

@test "home step resolves and exports the physical home" {
  box_preflight_home
  [ "$box_physical_home" = "$(realpath -e -- "$HOME")" ]
}

@test "credentials step exports resolved targets" {
  mkdir -p -- "$HOME/.ssh"
  box_preflight_credentials
  [ "${#box_credential_targets[@]}" -eq 1 ]
  [ "${box_credential_targets[0]}" = "$(realpath -e -- "$HOME/.ssh")" ]
}

@test "owner/mode nowrite policy" {
  f="$TEST_TMP/f"
  printf x >"$f"
  chmod 644 -- "$f"
  run box_assert_owner_mode "$f" 'Configuration file' nowrite
  [ "$status" -eq 0 ]
  chmod 664 -- "$f"
  run box_assert_owner_mode "$f" 'Configuration file' nowrite
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be group/other-writable"* ]]
}

@test "owner/mode creds policy accepts 600 and 400 only" {
  f="$TEST_TMP/creds"
  printf x >"$f"
  chmod 600 -- "$f"
  run box_assert_owner_mode "$f" 'Credentials file' creds
  [ "$status" -eq 0 ]
  chmod 400 -- "$f"
  run box_assert_owner_mode "$f" 'Credentials file' creds
  [ "$status" -eq 0 ]
  chmod 644 -- "$f"
  run box_assert_owner_mode "$f" 'Credentials file' creds
  [ "$status" -ne 0 ]
  [[ "$output" == *"mode to 600"* ]]
}

@test "owner/mode dir700 policy" {
  d="$TEST_TMP/persist"
  mkdir -p -- "$d"
  chmod 700 -- "$d"
  run box_assert_owner_mode "$d" 'Persistent config dir' dir700
  [ "$status" -eq 0 ]
  chmod 755 -- "$d"
  run box_assert_owner_mode "$d" 'Persistent config dir' dir700
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be mode 700"* ]]
}

@test "owner/mode rejects unknown policies" {
  f="$TEST_TMP/f"
  printf x >"$f"
  run box_assert_owner_mode "$f" 'Configuration file' bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown owner/mode policy"* ]]
}

@test "outside-project guard honors label and unset project" {
  run box_assert_outside_project "$TEST_PROJ/x" 'Tool configuration'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Tool configuration must be outside the project"* ]]
  run box_assert_outside_project "$TEST_TMP/x" 'Tool configuration'
  [ "$status" -eq 0 ]
  unset project
  run box_assert_outside_project "$TEST_PROJ/x" 'Tool configuration'
  [ "$status" -eq 0 ]
}

@test "split libs expose every entry point (no monolith)" {
  [ ! -e "$BUNDLE_DIR/lib/common.sh" ]
  for fn in die box_realpath box_mktemp_file box_mktemp_dir box_preflight_project box_preflight_denylist box_preflight_home box_preflight_credentials box_preflight_tool_dirs box_preflight_ipc box_preflight_symlinks box_preflight_git box_assert_outside_project     box_assert_owner_mode box_resolve_config box_load_version_file box_load_credentials box_credentials_filled box_require_tool box_tool_field box_tool_id_for_launcher box_docker_cli box_assert_engine box_assert_image box_assert_network box_assert_network_policy box_ensure_network box_assert_runtime box_docker_exec box_parse_launcher_args box_check_fallback box_project_identity box_extra_gids box_ensure_persistent_config_dir box_seed_writable_config box_write_if_changed box_enforce_safe_settings box_sync_host_tui_theme box_classify_probe_rc box_probe_runsc_dns box_auto_runtime box_maybe_auto_runtime box_device_url_code box_git_identity box_infer_git_identity box_base_args box_forward_keys box_runtime_signal box_maybe_tty box_muse_bypass box_usage_common_flags box_load_all_pins box_print_pin box_docker_base_digest box_assert_no_default_args box_assert_tarball_pins box_assert_shell_placement box_assert_build_delegation box_pin_block box_image_tag box_image_tag_for_version box_build_image box_clean_image box_bundle_dir; do
    declare -F "$fn" >/dev/null || { echo "missing: $fn"; return 1; }
  done
}

@test "every lib file is linted (SHELL_FILES parity)" {
  shell_line=$(grep -E '^SHELL_FILES :=' "$BUNDLE_DIR/Makefile")
  [ -n "$shell_line" ] || { echo "cannot extract SHELL_FILES line from Makefile"; return 1; }
  for f in "$BUNDLE_DIR"/lib/*.sh; do
    base=$(basename -- "$f")
    [[ "$shell_line" == *"lib/$base"* ]] \
      || { echo "lib/$base missing from Makefile SHELL_FILES line"; return 1; }
  done
}

@test "verify.yml calls make targets (no duplicated step bodies)" {
  # m-23: CI must call `make verify-static` + `make pins` so a new gate added
  # to verify-static runs in CI automatically. Duplicated bash/shellcheck
  # file lists or json.tool bodies would silently miss new gates.
  run grep -Fq 'run: make verify-static' "$BUNDLE_DIR/.github/workflows/verify.yml"
  [ "$status" -eq 0 ] || { echo "verify.yml must call make verify-static"; return 1; }
  run grep -Fq 'run: make pins' "$BUNDLE_DIR/.github/workflows/verify.yml"
  [ "$status" -eq 0 ] || { echo "verify.yml must call make pins"; return 1; }
  run grep -F 'run: shellcheck ' "$BUNDLE_DIR/.github/workflows/verify.yml"
  [ "$status" -ne 0 ] || { echo "verify.yml must not duplicate shellcheck lists"; return 1; }
  run grep -F 'for f in lib/' "$BUNDLE_DIR/.github/workflows/verify.yml"
  [ "$status" -ne 0 ] || { echo "verify.yml must not duplicate bash -n lists"; return 1; }
  run grep -F 'json.tool' "$BUNDLE_DIR/.github/workflows/verify.yml"
  [ "$status" -ne 0 ] || { echo "verify.yml must not duplicate JSON checks"; return 1; }
}

@test "extra-gids appends to a caller-chosen array via nameref" {
  BOX_M_EXTRA_GIDS='100,200'
  export BOX_M_EXTRA_GIDS
  args=(--sentinel)
  custom=()
  box_extra_gids BOX_M_EXTRA_GIDS custom
  [ "${#args[@]}" -eq 1 ]
  [ "${custom[0]}" = "--group-add" ]
  [ "${custom[1]}" = "100" ]
  [ "${custom[2]}" = "--group-add" ]
  [ "${custom[3]}" = "200" ]
}

@test "docker-cli backs up unexpected configs (single .bak, mode-600)" {
  if [[ ! -x /usr/bin/docker && ! -x /usr/local/bin/docker ]]; then
    skip "no docker binary"
  fi
  if ! command -v docker >/dev/null; then
    skip "no docker on PATH"
  fi
  cli="$TEST_TMP/docker-cli"
  mkdir -p -- "$cli"
  printf '{"proxies":{}}\n' >"$cli/config.json"
  chmod 644 -- "$cli/config.json"
  run box_docker_cli "$cli"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config.json.bak"* ]]
  [ "$(cat -- "$cli/config.json")" = "{}" ]
  [ -f "$cli/config.json.bak" ]
  [ "$(stat -c %a -- "$cli/config.json.bak")" = "600" ]
  [ "$(stat -c %a -- "$cli/config.json")" = "600" ]
  # Second run is a no-op: no warning.
  run box_docker_cli "$cli"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ensure_network creates then verifies (live daemon)" {
  if ! docker info >/dev/null 2>&1; then skip "no reachable docker daemon"; fi
  box_docker_cli "$TEST_TMP/docker-cli"
  net="box-bats-$$"
  docker network rm -- "$net" >/dev/null 2>&1 || true
  result=$(box_ensure_network "$net" "${docker_cmd[@]}")
  [ "$result" = "created" ]
  result=$(box_ensure_network "$net" "${docker_cmd[@]}")
  [ "$result" = "verified" ]
  docker network rm -- "$net" >/dev/null
}

@test "ensure_network fails closed on wrong policy (live daemon)" {
  if ! docker info >/dev/null 2>&1; then skip "no reachable docker daemon"; fi
  box_docker_cli "$TEST_TMP/docker-cli"
  net="box-bats-policy-$$"
  docker network rm -- "$net" >/dev/null 2>&1 || true
  # Default bridge options violate the sandbox policy (icc enabled).
  "${docker_cmd[@]}" network create --driver=bridge -- "$net" >/dev/null
  run box_ensure_network "$net" "${docker_cmd[@]}"
  [ "$status" -ne 0 ]
  docker network rm -- "$net" >/dev/null
}

@test "dns probe fails closed on missing image (live daemon)" {
  if ! docker info >/dev/null 2>&1; then skip "no reachable docker daemon"; fi
  box_docker_cli "$TEST_TMP/docker-cli"
  run box_probe_runsc_dns "box-bats-no-such-image:0" box-m example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"build it first"* ]]
}
