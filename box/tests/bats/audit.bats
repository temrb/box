load helpers

codex_fixture() {
  export BOX_C_CONFIG="$TEST_TMP/config.toml"
  export BOX_C_VERSION_FILE="$TEST_TMP/version-codex.env"
  install -m 600 "$BUNDLE_DIR/harnesses/codex/config/config.toml" "$BOX_C_CONFIG"
  install -m 644 "$BUNDLE_DIR/harnesses/codex/version-codex.env" "$BOX_C_VERSION_FILE"
  export BOX_C_ENV_FILE="$TEST_TMP/providers.env"
  export BOX_C_STATE_ROOT="$TEST_TMP/codex-projects"
  unset BOX_C_STATE_DIR BOX_C_AUTH
  : >"$BOX_C_ENV_FILE"
  chmod 600 "$BOX_C_ENV_FILE"
  script_dir=$BUNDLE_DIR
  git -C "$TEST_PROJ" init -q
  cd "$TEST_PROJ"
}

@test "registry rejects duplicate destinations, missing consumers and escaping paths" {
  for defect in destination consumers source runtime owner; do
    run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; case "$2" in
      destination) _BOX_TOOL_REGISTRY[codex,config_dir]=box-m;;
      consumers) _BOX_ARTIFACTS[codex,policy,consumers]="validate verify";;
      source) _BOX_ARTIFACTS[codex,config,source]="../escape.toml";;
      runtime) _BOX_ARTIFACTS[codex,policy,runtime]="/etc/codex/..";;
      owner) _BOX_ARTIFACTS[codex,config,owner]=root;; esac
      box_validate_registry "$1"' _ "$BUNDLE_DIR" "$defect"
    [ "$status" -ne 0 ]
  done
}

@test "registry rejects symlinked sources and duplicate pins, labels, runtimes, dests" {
  copy="$TEST_TMP/bundle-symlink"
  cp -r "$BUNDLE_DIR" "$copy"
  rm "$copy/harnesses/codex/config/config.toml"
  ln -s "$BUNDLE_DIR/harnesses/codex/config/config.toml" "$copy/harnesses/codex/config/config.toml"
  run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; box_validate_registry "$1"' _ "$copy"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Missing regular source'* ]]
  for defect in pin label runtime dest state-root; do
    run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; case "$2" in
      pin) _BOX_TOOL_REGISTRY[codex,pin_keys]="CODEX_VERSION CODEX_VERSION CODEX_SHA256_ARM64";;
      label) _BOX_TOOL_REGISTRY[codex,label_pins]="CODEX_VERSION:org.openai.codex.box.version CODEX_VERSION:org.openai.codex.box.dup CODEX_SHA256_AMD64:org.openai.codex.box.sha256-amd64 CODEX_SHA256_ARM64:org.openai.codex.box.sha256-arm64";;
      runtime) _BOX_ARTIFACTS[codex,config,runtime]=/etc/codex/requirements.toml;;
      dest) _BOX_ARTIFACTS[codex,policy,role]=template; _BOX_ARTIFACTS[codex,policy,lifecycle]=refresh-seed-if-absent; _BOX_ARTIFACTS[codex,policy,installed]=config.toml; _BOX_ARTIFACTS[codex,policy,owner]=user; _BOX_ARTIFACTS[codex,policy,consumers]="setup launch validate verify";;
      state-root) _BOX_STATES[codex,volume,root]=.config/box-c/projects;;
      esac
      box_validate_registry "$1"' _ "$BUNDLE_DIR" "$defect"
    [ "$status" -ne 0 ]
  done
}

@test "registry rejects invalid formats, modes, lifecycles, consumers and names" {
  for defect in format mode lifecycle consumers unknown primary orphan-name; do
    run bash -c 'BOX_TOOL=test; source "$1/lib/tools.sh"; case "$2" in
      format) _BOX_ARTIFACTS[codex,config,format]=yaml;;
      mode) _BOX_ARTIFACTS[codex,config,mode]=755;;
      lifecycle) _BOX_ARTIFACTS[codex,config,lifecycle]=managed-image;;
      consumers) _BOX_ARTIFACTS[codex,config,consumers]="setup launch";;
      unknown) _BOX_ARTIFACTS[codex,config,consumers]="setup launch validate verify bogus";;
      primary) _BOX_TOOL_REGISTRY[opencode,config_file]=unconsumed.json;;
      orphan-name) _BOX_ARTIFACTS[codex,Bad_Name,source]=harnesses/codex/config/config.toml;;
      esac
      box_validate_registry "$1"' _ "$BUNDLE_DIR" "$defect"
    [ "$status" -ne 0 ]
  done
}

@test "registry requires every integrity pin to have an image label" {
  _BOX_TOOL_REGISTRY[codex,label_pins]='CODEX_VERSION:org.openai.codex.box.version'
  run box_validate_registry "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Missing pin label: codex/CODEX_SHA256_AMD64'* ]]
}

@test "registry rejects orphan artifacts and invalid state roots" {
  _BOX_ARTIFACTS[codex,unused,source]=unused.toml
  run box_validate_registry "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
  unset '_BOX_ARTIFACTS[codex,unused,source]'
  _BOX_STATES[codex,home,root]=../escape
  run box_validate_registry "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
}

@test "registry requires a primary config consumer and separates artifacts from pins" {
  _BOX_TOOL_REGISTRY[codex,config_file]=unconsumed.toml
  run box_validate_registry "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Missing primary configuration consumer'* ]]
  _BOX_TOOL_REGISTRY[codex,config_file]=config.toml
  _BOX_ARTIFACTS[codex,config,installed]=version-codex.env
  run box_validate_registry "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *'collides with installed pins'* ]]
}

@test "Docker CLI rejects redirected backup before changing directory metadata" {
  cli="$TEST_TMP/cli"
  mkdir -m 755 "$cli"
  printf '{"proxies":{}}\n' >"$cli/config.json"
  printf 'keep\n' >"$TEST_TMP/untouched"
  ln -s "$TEST_TMP/untouched" "$cli/config.json.bak"
  before=$(sha256sum "$cli/config.json" "$TEST_TMP/untouched")
  run box_docker_cli "$cli"
  [ "$status" -ne 0 ]
  [ "$(stat -c %a "$cli")" = 755 ]
  [ "$(sha256sum "$cli/config.json" "$TEST_TMP/untouched")" = "$before" ]
  [ -z "$(find "$cli" -name '.config.json.tmp.*' -print)" ]
}

@test "Codex rejects unsafe CLI destinations before creating project state" {
  codex_fixture
  cli="$HOME/.config/box-c/docker-cli"
  mkdir -p "$cli"
  ln -s "$TEST_TMP/missing" "$cli/config.json"
  run "$BUNDLE_DIR/box-c" --runsc --version
  [ "$status" -ne 0 ]
  [ ! -e "$BOX_C_STATE_ROOT" ]
  [ ! -e "$TEST_TMP/missing" ]
}

@test "Muse rejects redirected live settings before chmod or CLI creation" {
  muse_home="$TEST_TMP/muse-home"
  mkdir -m 755 "$muse_home"
  ln -s "$TEST_TMP/untouched" "$muse_home/settings.json"
  install -m 644 "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$TEST_TMP/seed.json"
  install -m 644 "$BUNDLE_DIR/harnesses/muse/version-muse.env" "$TEST_TMP/version-muse.env"
  export BOX_M_CONFIG="$TEST_TMP/seed.json" BOX_M_VERSION_FILE="$TEST_TMP/version-muse.env"
  export BOX_M_PERSIST_DIR="$muse_home"
  cd "$TEST_PROJ"
  run "$BUNDLE_DIR/box-m" --runsc --version
  [ "$status" -ne 0 ]
  [ "$(stat -c %a "$muse_home")" = 755 ]
  [ ! -e "$HOME/.config" ]
  [ ! -e "$TEST_TMP/untouched" ]
}

@test "native focused selector rejects unsupported options before creating fixtures" {
  run bash "$BUNDLE_DIR/tests/native/acceptance.sh" --only unsupported
  [ "$status" -ne 0 ]
  [ -z "$(find "$HOME" -name '.box-native.*' -print)" ]
}

@test "planning rejects parent symlinks and project containment without mutation" {
  mkdir "$TEST_TMP/target"
  ln -s "$TEST_TMP/target" "$TEST_TMP/parent"
  for path in "$TEST_TMP/parent/new/home" "$TEST_PROJ/new/home" "$PROJ_ROOT"; do
    run box_prepare_directory "$path"
    [ "$status" -ne 0 ]
  done
  [ ! -e "$TEST_TMP/target/new" ]
  [ ! -e "$TEST_PROJ/new" ]
  [ "$(stat -c %a "$PROJ_ROOT")" = 700 ]
}

@test "preparation secures missing intermediate parents under a permissive umask" {
  (umask 002; box_prepare_directory "$TEST_TMP/fresh/parents/home" >/dev/null)
  for path in fresh fresh/parents fresh/parents/home; do
    [ "$(stat -c %a "$TEST_TMP/$path")" = 700 ]
  done
}

@test "preparation applies the requested final mode while securing new parents and preserving existing ancestors" {
  mkdir -m 750 "$TEST_TMP/existing"
  (umask 002; box_prepare_directory "$TEST_TMP/existing/fresh/parents/home" 755 >/dev/null)
  [ "$(stat -c %a "$TEST_TMP/existing")" = 750 ]
  for path in fresh fresh/parents; do
    [ "$(stat -c %a "$TEST_TMP/existing/$path")" = 700 ]
  done
  [ "$(stat -c %a "$TEST_TMP/existing/fresh/parents/home")" = 755 ]
}

@test "seeding preserves empty TOML and concurrent publication has one complete winner" {
  : >"$TEST_TMP/config.toml"
  box_seed_writable_config "$BUNDLE_DIR/harnesses/codex/config/config.toml" "$TEST_TMP/config.toml" 600
  [ ! -s "$TEST_TMP/config.toml" ]
  for attempt in {1..12}; do
    box_seed_writable_config "$BUNDLE_DIR/harnesses/codex/config/config.toml" "$TEST_TMP/concurrent.toml" 600 &
  done
  wait
  cmp "$BUNDLE_DIR/harnesses/codex/config/config.toml" "$TEST_TMP/concurrent.toml"
  [ "$(stat -c %a "$TEST_TMP/concurrent.toml")" = 600 ]
  [ -z "$(find "$TEST_TMP" -name '.box-seed.*' -print)" ]
}

@test "unsafe native caches fail without mode repair or content diagnostics" {
  cache="$TEST_TMP/auth.json"
  printf 'private-fixture\n' >"$cache"
  for mode in 644 400; do
    chmod "$mode" "$cache"
    run box_assert_native_cache "$cache"
    [ "$status" -ne 0 ]
    [ "$(stat -c %a "$cache")" = "$mode" ]
    [[ "$output" != *private-fixture* ]]
  done
  chmod 600 "$cache"
  box_assert_native_cache "$cache"
}

@test "native cache rejects symlinks, directories and FIFOs directly" {
  ln -s "$TEST_TMP/missing-target" "$TEST_TMP/cache-link"
  run box_assert_native_cache "$TEST_TMP/cache-link"
  [ "$status" -ne 0 ]
  mkdir -p "$TEST_TMP/cache-dir"
  run box_assert_native_cache "$TEST_TMP/cache-dir"
  [ "$status" -ne 0 ]
  mkfifo "$TEST_TMP/cache-fifo"
  run box_assert_native_cache "$TEST_TMP/cache-fifo"
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_TMP/missing-target" ]
}

@test "group-writable ancestor rejection leaves metadata and state unchanged" {
  ancestor="$TEST_TMP/writable-ancestor"
  mkdir -m 775 "$ancestor"
  printf 'keep\n' >"$ancestor/keep.txt"
  before_mode=$(stat -c %a "$ancestor")
  before_hash=$(sha256sum "$ancestor/keep.txt")
  run box_plan_directory "$ancestor/new/home"
  [ "$status" -ne 0 ]
  [[ "$output" == *'must not be group/other-writable'* ]]
  [ "$(stat -c %a "$ancestor")" = "$before_mode" ]
  [ "$(sha256sum "$ancestor/keep.txt")" = "$before_hash" ]
  [ ! -e "$ancestor/new" ]
  chmod 755 "$ancestor"
  box_plan_directory "$ancestor/new/home" >/dev/null
  [ -d "$ancestor/new/home" ] || true
}

@test "Codex dry-run is read-only and isolates physical projects under an overridden root" {
  [[ -x /usr/bin/docker || -x /usr/local/bin/docker ]] || skip "no Docker CLI on launcher trusted PATH"
  codex_fixture
  run "$BUNDLE_DIR/box-c" --dry-run login
  [ "$status" -eq 0 ]
  [[ "$output" == *login*--device-auth* ]]
  hash=$(printf '%s' "$TEST_PROJ" | sha256sum); hash=${hash:0:20}
  [[ "$output" == *"$BOX_C_STATE_ROOT/$hash/codex-home"* ]]
  [ ! -e "$BOX_C_STATE_ROOT" ]
  [ ! -e "$HOME/.config" ]
  mkdir "$PROJ_ROOT/second"
  git -C "$PROJ_ROOT/second" init -q
  cd "$PROJ_ROOT/second"
  run "$BUNDLE_DIR/box-c" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" != *"$BOX_C_STATE_ROOT/$hash/codex-home"* ]]
  [[ "$output" != *--env\ OPENAI_API_KEY* ]]
}

@test "Codex protects both root spellings and rejects conflicts before mutation" {
  [[ -x /usr/bin/docker || -x /usr/local/bin/docker ]] || skip "no Docker CLI on launcher trusted PATH"
  codex_fixture
  export BOX_C_STATE_DIR="$TEST_TMP/legacy-root"
  run "$BUNDLE_DIR/box-c" --dry-run --version
  [ "$status" -ne 0 ]
  [ ! -e "$BOX_C_STATE_ROOT" ]
  [ ! -e "$BOX_C_STATE_DIR" ]
  unset BOX_C_STATE_ROOT
  run "$BUNDLE_DIR/box-c" --dry-run --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BOX_C_STATE_DIR/"*codex-home* ]]
  export BOX_C_STATE_DIR="$TEST_PROJ/forbidden"
  run "$BUNDLE_DIR/box-c" --dry-run --version
  [ "$status" -ne 0 ]
  [ ! -e "$BOX_C_STATE_DIR" ]
}

@test "Codex preparation resets preferences and preserves trust and state across restarts" {
  codex_fixture
  box_docker_cli() { docker_cmd=(true); }
  box_docker_exec() { exec {preferences_lock}>&-; }
  source "$BUNDLE_DIR/harnesses/codex/launch.sh" --shell -c true
  native="$codex_home/config.toml"
  printf 'model = "account-preference"\n[projects."/workspace/🌱"]\ntrust_level = "trusted"\n' >"$native"
  chmod 600 "$native"
  printf 'session fixture' >"$codex_home/history.jsonl"
  printf '{"synthetic":"auth"}' >"$codex_home/auth.json"
  chmod 600 "$codex_home/auth.json"
  sed -i 's/^model = .*/model = "refreshed-default"/' "$BOX_C_CONFIG"
  source "$BUNDLE_DIR/harnesses/codex/launch.sh" --shell -c true
  [[ " ${args[*]} " == *"src=$BOX_C_CONFIG,dst=/etc/codex/config.toml,readonly"* ]]
  [ "$(box_config_get "$config" .model)" = refreshed-default ]
  [[ "$(cat "$native")" == *'trust_level = "trusted"'* ]]
  [[ "$(cat "$native")" != *account-preference* ]]
  [[ "$(cat "$native.box-legacy")" == *account-preference* ]]
  [ "$(stat -c %a "$native.box-legacy")" = 600 ]
  [ "$(cat "$codex_home/history.jsonl")" = 'session fixture' ]
  [ "$(cat "$codex_home/auth.json")" = '{"synthetic":"auth"}' ]
  : >"$native"
  source "$BUNDLE_DIR/harnesses/codex/launch.sh" --shell -c true
  [ ! -s "$native" ]
}

@test "installed launchers work without bundle assets or the checkout" {
  [[ -x /usr/bin/docker || -x /usr/local/bin/docker ]] || skip "no Docker CLI on launcher trusted PATH"
  codex_fixture
  unset BOX_C_CONFIG BOX_C_VERSION_FILE
  mkdir -p "$TEST_TMP/installed/lib" "$TEST_TMP/installed/harnesses"
  cp "$BUNDLE_DIR"/box-{m,o,c} "$TEST_TMP/installed/"
  cp "$BUNDLE_DIR"/lib/*.sh "$TEST_TMP/installed/lib/"
  for id in $box_tool_ids; do
    mkdir "$TEST_TMP/installed/harnesses/$id"
    cp "$BUNDLE_DIR/harnesses/$id/"*.sh "$TEST_TMP/installed/harnesses/$id/"
    mkdir -p "$HOME/.config/$(box_tool_field "$id" config_dir)"
    cfg="$HOME/.config/$(box_tool_field "$id" config_dir)"
    cp "$BUNDLE_DIR/$(box_tool_field "$id" version_source)" "$cfg/$(box_tool_field "$id" version_file)"
    for artifact in $(box_tool_field "$id" artifacts); do
      leaf=$(box_artifact_field "$id" "$artifact" installed)
      [[ -n "$leaf" ]] || continue
      cp "$BUNDLE_DIR/$(box_artifact_field "$id" "$artifact" source)" "$cfg/$leaf"
    done
    run "$TEST_TMP/installed/$(box_tool_field "$id" launcher)" --dry-run --version
    [ "$status" -eq 0 ]
    [[ "$output" == *--runtime=runsc* ]]
  done
}

@test "setup rejects installed code symlinks before writing templates" {
  mkdir -p "$HOME/.local/bin/lib"
  printf 'keep\n' >"$TEST_TMP/untouched"
  ln -s "$TEST_TMP/untouched" "$HOME/.local/bin/lib/run.sh"
  run bash "$BUNDLE_DIR/setup.sh" --skip-build
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.config" ]
  [ "$(cat "$TEST_TMP/untouched")" = keep ]
}

@test "Codex validator rejects unsupported seed and policy fields" {
  copy="$TEST_TMP/bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  printf '\nunsupported_policy = true\n' >>"$copy/harnesses/codex/config/config.toml"
  run bash "$copy/gen-pins.sh" --check
  [ "$status" -ne 0 ]
}

@test "Codex native probe fails closed when policy inspection is unavailable" {
  BOX_CODEX_BINARY=/bin/false run python3 "$BUNDLE_DIR/harnesses/codex/native-probe.py" --policy-json '{}'
  [ "$status" -ne 0 ]
  [[ "$output" == *'app-server exited before policy inspection'* ]]
}

@test "Codex resolver rejects corrupted bytes and incomplete companion layouts" {
  source "$BUNDLE_DIR/harnesses/codex/update.sh"
  CODEX_VERSION=$(box_print_pin "$BUNDLE_DIR" CODEX_VERSION)
  declare -A new_pin=()
  mkdir -p "$TEST_TMP/archive/bin" "$HOME/.cache"
  printf fixture >"$TEST_TMP/archive/bin/codex-code-mode-host"
  tar -czf "$TEST_TMP/package.tar.gz" -C "$TEST_TMP/archive" bin
  fixture_digest=$(sha256sum "$TEST_TMP/package.tar.gz"); fixture_digest=${fixture_digest%% *}
  # Mock only transport; the real resolver must hash and inventory the bytes.
  assert_url_safe_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
  fetch_url() {
    jq -n --arg digest "sha256:$fixture_digest" '{tag_name:"rust-v9.9.9",prerelease:false,draft:false,assets:[
      {name:"codex-package-x86_64-unknown-linux-musl.tar.gz",digest:$digest},
      {name:"codex-package-aarch64-unknown-linux-musl.tar.gz",digest:$digest}]}'
  }
  curl() {
    while (($#)); do
      if [[ "$1" == -o ]]; then cp "$TEST_TMP/package.tar.gz" "$2"; return; fi
      # curl treats everything after -- as a URL, including misplaced -o.
      [[ "$1" != -- ]] || return 1
      shift
    done
    return 1
  }
  run box_harness_resolve 9.9.9
  [ "$status" -ne 0 ]
  [[ "$output" == *'Missing Codex companion'* ]]
  fixture_digest=$(printf '%064d' 1)
  run box_harness_resolve 9.9.9
  [ "$status" -ne 0 ]
  [[ "$output" == *'Corrupted/incomplete Codex asset'* ]]
  [ -z "$(find "$HOME/.cache" -name 'codex-artifact.*' -print)" ]
}

@test "updater only-selection ignores invalid nonselected seeds without a fetch" {
  export BOX_UPDATE_MUSE_VERSION=bad BOX_UPDATE_OPENCODE_VERSION=bad
  run bash "$BUNDLE_DIR/update-pins.sh" --check --only codex --codex "$(box_print_pin "$BUNDLE_DIR" CODEX_VERSION)"
  [ "$status" -eq 0 ]
  run bash "$BUNDLE_DIR/update-pins.sh" --check --only codex --opencode '../bad'
  [ "$status" -ne 0 ]
  [[ "$output" == *'--only cannot combine'* ]]
}
