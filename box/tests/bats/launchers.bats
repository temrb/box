# launchers.bats — --dry-run shape checks (NAME-only env forwarding, hardening
# flags). No daemon contact: --dry-run prints and exits before any assert.
load helpers

_muse_dry_run_env() {
  cfg="$TEST_TMP/muse-settings.json"
  cp -- "$BUNDLE_DIR/settings.json" "$cfg"
  chmod 644 -- "$cfg"
  vf="$TEST_TMP/version-muse.env"
  make_muse_version_file "$vf"
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY=test-value"
  export BOX_M_CONFIG="$cfg" BOX_M_VERSION_FILE="$vf" \
    BOX_M_ENV_FILE="$creds" BOX_M_PERSIST_DIR="$TEST_TMP/muse-config"
}

_opencode_dry_run_env() {
  cfg="$TEST_TMP/opencode.json"
  cp -- "$BUNDLE_DIR/opencode.json" "$cfg"
  chmod 644 -- "$cfg"
  vf="$TEST_TMP/version-opencode.env"
  make_opencode_version_file "$vf"
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY=test-value"
  export BOX_O_CONFIG="$cfg" BOX_O_VERSION_FILE="$vf" \
    BOX_O_ENV_FILE="$creds"
}

_need_docker() {
  if ! command -v docker >/dev/null; then
    skip "no docker binary (box_docker_cli needs one even for --dry-run)"
  fi
}

@test "box-m --dry-run: runsc default plus hardening flags" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--runtime=runsc"* ]]
  [[ "$output" == *"--cap-drop=ALL"* ]]
  [[ "$output" == *"no-new-privileges"* ]]
  [[ "$output" == *"--read-only"* ]]
}

@test "box-m --dry-run: no secret values leak into output" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run --version
  [ "$status" -eq 0 ]
  # --dry-run skips credentials loading entirely (fail-closed file access),
  # so no provider key may appear by name=value nor by value.
  [[ "$output" != *"MUSE_CODE_API_KEY="* ]]
  [[ "$output" != *"test-value"* ]]
}

@test "box-m --dry-run: forwards no provider keys (dry-run exports nothing)" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" != *"--env MUSE_CODE_API_KEY"* ]]
}

@test "box-m --dry-run: git identity inferred from global git config" {
  _need_docker
  if ! command -v git >/dev/null; then skip "no git binary"; fi
  _muse_dry_run_env
  unset BOX_M_GIT_NAME BOX_M_GIT_EMAIL BOX_O_GIT_NAME BOX_O_GIT_EMAIL
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-launcher-infer"
  git config --global user.name 'InferredName'
  git config --global user.email 'inferred@example.com'
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"GIT_AUTHOR_NAME=InferredName"* ]]
  [[ "$output" == *"GIT_AUTHOR_EMAIL=inferred@example.com"* ]]
  [[ "$output" == *"NOTICE: using git global identity"* ]]
}

@test "box-m --dry-run: explicit fallback selects runc with WARNING" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --docker-fallback --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--runtime=runc"* ]]
  [[ "$output" == *"explicit hardened-runc fallback"* ]]
}

@test "launchers --dry-run: --runsc stays on gVisor with runtime signal" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --runsc --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--runtime=runsc"* ]]
  [[ "$output" != *"explicit hardened-runc fallback"* ]]
  [[ "$output" == *"BOX_RUNTIME=runsc"* ]]
}

@test "launchers --dry-run: fallback carries runc runtime signal" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --docker-fallback --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"BOX_RUNTIME=runc"* ]]
}

@test "box-m --dry-run: --yolo counts as explicit opt-out (no double-inject)" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run -- --yolo
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yolo"* ]]
  [[ "$output" != *"--disable-sandbox"* ]]
}

@test "box-o --dry-run: runsc default plus hardening flags" {
  _need_docker
  _opencode_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-o" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--runtime=runsc"* ]]
  [[ "$output" == *"--cap-drop=ALL"* ]]
  [[ "$output" == *"no-new-privileges"* ]]
}

@test "box-o --dry-run: no secret values leak into output" {
  _need_docker
  _opencode_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-o" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" != *"MUSE_CODE_API_KEY="* ]]
  [[ "$output" != *"test-value"* ]]
}

@test "box-o --dry-run: forwards nothing (pure /connect)" {
  _need_docker
  _opencode_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-o" --dry-run --version
  [ "$status" -eq 0 ]
  # The live proof is the empty registry forward_keys (tools.bats) plus the
  # empty-set no-op (run.bats); dry-run must carry no NAME-only key lines.
  [[ "$output" != *"--env MUSE_CODE_API_KEY"* ]]
}

_installed_layout() {
  # Simulate ~/.local/bin: launchers + lib only, no bundle version files.
  inst="$TEST_TMP/installed"
  mkdir -p -- "$inst/lib"
  cp -- "$BUNDLE_DIR/box-m" "$BUNDLE_DIR/box-o" "$inst/"
  cp -- "$BUNDLE_DIR"/lib/*.sh "$inst/lib/"
}

@test "box-m --dry-run: installed layout tags from the config-file version" {
  _need_docker
  _muse_dry_run_env
  sed -i 's/^MUSE_VERSION=.*/MUSE_VERSION=9.9.9/' "$vf"
  _installed_layout
  cd -- "$TEST_PROJ"
  run "$inst/box-m" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"box-m:9.9.9-u$(id -u)-g$(id -g)"* ]]
}

@test "box-o --dry-run: installed layout tags from the config-file version" {
  _need_docker
  _opencode_dry_run_env
  sed -i 's/^OPENCODE_VERSION=.*/OPENCODE_VERSION=9.9.9/' "$vf"
  _installed_layout
  cd -- "$TEST_PROJ"
  run "$inst/box-o" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"box-o:9.9.9-u$(id -u)-g$(id -g)"* ]]
}

@test "box-m --dry-run: default bypass is injected for tool args" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run -- --foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"--disable-sandbox"* ]]
}

@test "box-m honors only BOX_M_INNER_FLAG (unknown flag vars ignored)" {
  # The bypass allowlist is exactly BOX_M_INNER_FLAG: a future `BOX_*_FLAG`
  # glob (or a misread of a similarly-named var) would silently honor
  # attacker-shaped env, so both the source allowlist and the behavior
  # are pinned here.
  run grep -rho 'BOX_M_[A-Z_]*FLAG[A-Z_]*' "$BUNDLE_DIR/box-m" "$BUNDLE_DIR/lib/"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sort -u)" = "BOX_M_INNER_FLAG" ]
  _need_docker
  _muse_dry_run_env
  BOX_M_BOX_FLAG='--evil-flag'
  export BOX_M_BOX_FLAG
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run -- --foo
  [ "$status" -eq 0 ]
  [[ "$output" != *"--evil-flag"* ]]
  [[ "$output" == *"--disable-sandbox"* ]]
}

@test "box-m honors an empty INNER_FLAG (bypass disabled)" {
  _need_docker
  _muse_dry_run_env
  BOX_M_INNER_FLAG=
  export BOX_M_INNER_FLAG
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run -- --foo
  [ "$status" -eq 0 ]
  [[ "$output" != *"--disable-sandbox"* ]]
}

@test "box-m --dry-run: reverts downgraded safety keys in persisted settings" {
  _need_docker
  _muse_dry_run_env
  persist="$TEST_TMP/muse-config"
  mkdir -p -- "$persist"
  jq '.approval_mode = "never" | .approval_judge = false
      | .telemetry.enabled = true | .api.base_url = "https://evil.example"
      | .model = "user-model"' \
    -- "$cfg" >"$persist/settings.json"
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --dry-run --version
  [ "$status" -eq 0 ]
  [ "$(jq -r '.approval_mode' -- "$persist/settings.json")" = "on-request" ]
  [ "$(jq -r '.approval_judge' -- "$persist/settings.json")" = "true" ]
  [ "$(jq -r '.telemetry.enabled' -- "$persist/settings.json")" = "false" ]
  [ "$(jq -r '.api.base_url' -- "$persist/settings.json")" = "https://api.meta.ai/v1" ]
  [ "$(jq -r '.model' -- "$persist/settings.json")" = "user-model" ]
}

@test "launchers reject a launcher flag after --shell" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --shell --dry-run
  [ "$status" -ne 0 ]
}

@test "box-m-login --help prints usage without daemon contact" {
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m-login" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--docker-fallback"* ]]
  [[ "$output" == *"--runsc"* ]]
}

@test "box-m-login rejects login arguments" {
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m-login" extra-arg
  [ "$status" -ne 0 ]
}

@test "box-m-login rejects --shell (shared parser, login only)" {
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m-login" --shell
  [ "$status" -ne 0 ]
}

@test "box-m-login rejects unknown flags via the shared parser" {
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m-login" --bogus
  [ "$status" -ne 0 ]
}

@test "box-m-login --dry-run delegates to the launcher default runtime" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m-login" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--runtime=runsc"* ]]
}

@test "box-m-login --runsc --dry-run threads explicit gVisor" {
  _need_docker
  _muse_dry_run_env
  cd -- "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m-login" --runsc --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--runtime=runsc"* ]]
  [[ "$output" != *"explicit hardened-runc fallback"* ]]
}

_muse_login_stub() {
  # Live-path rig with a stubbed sibling launcher (canned output + exit,
  # no daemon contact). Sets $stub to a dir holding box-m-login + lib/ and
  # a caller-written box-m stub.
  stub="$TEST_TMP/login-stub"
  mkdir -p -- "$stub/lib"
  cp -- "$BUNDLE_DIR/box-m-login" "$stub/"
  cp -- "$BUNDLE_DIR"/lib/*.sh "$stub/lib/"
}

@test "box-m-login hints when login succeeds without a device URL" {
  _muse_login_stub
  printf '#!/bin/bash\nprintf "signed in (no URL printed)\\n"\nexit 0\n' >"$stub/box-m"
  chmod +x -- "$stub/box-m"
  mkdir -p -- "$TEST_TMP/sentinel-tmp"
  cd -- "$TEST_PROJ"
  TMPDIR="$TEST_TMP/sentinel-tmp" run "$stub/box-m-login"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no device URL was detected"* ]]
  [[ "$output" == *"already logged in"* ]]
  leftover=$(ls -- "$TEST_TMP/sentinel-tmp"/box-m-login-banner.* 2>/dev/null) || true
  [ -z "$leftover" ]
}

@test "box-m-login shows the banner and no hint on a device URL" {
  _muse_login_stub
  printf '#!/bin/bash\nprintf "Visit https://auth.meta.com/oauth/device/?code=ABCD-1234 to sign in\\n"\nexit 0\n' >"$stub/box-m"
  chmod +x -- "$stub/box-m"
  cd -- "$TEST_PROJ"
  run "$stub/box-m-login"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIGN IN"* ]]
  [[ "$output" == *"code: ABCD-1234"* ]]
  [[ "$output" != *"no device URL was detected"* ]]
}

@test "box-m-login stays silent on failure without a device URL" {
  _muse_login_stub
  printf '#!/bin/bash\nprintf "login failed: boom\\n" >&2\nexit 1\n' >"$stub/box-m"
  chmod +x -- "$stub/box-m"
  cd -- "$TEST_PROJ"
  run "$stub/box-m-login"
  [ "$status" -eq 1 ]
  [[ "$output" == *"login failed: boom"* ]]
  [[ "$output" != *"no device URL was detected"* ]]
}
