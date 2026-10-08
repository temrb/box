load helpers

setup() {
  umask 022
  BOX_TOOL=test
  source "$BUNDLE_DIR/lib/build.sh"
  source "$BUNDLE_DIR/lib/pins.sh"
  TEST_TMP=$(mktemp -d /tmp/box-sync.XXXXXX)
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME/.config/box-o"
  host_uid=$(id -u); host_gid=$(id -g)
  cfg="$HOME/.config/box-o"
  dest="$cfg/version-opencode.env"
  src="$BUNDLE_DIR/harnesses/opencode/version-opencode.env"
  printf 'OBSOLETE=npm\n' > "$dest"
  cp "$dest" "$TEST_TMP/original"
  box_docker_cli() { docker_cmd=(fake_docker); }
  fake_docker() {
    [[ "${failure:-}" != missing ]] || return 1
    local fmt=$4 pair key value first=1 result=''
    if [[ "$fmt" == *Config.User* ]]; then
      value="$host_uid:$host_gid"
      [[ "${failure:-}" != user ]] || value="9:$host_gid"
      [[ "${failure:-}" != group ]] || value="$host_uid:9"
      printf '%s|%s|3\n' "$value" "$box_file_version"
    else
      for pair in $(box_tool_field opencode label_pins); do
        if ((first)); then first=0; continue; fi
        key=${pair%%:*}; value=${box_file_pin[$key]}
        [[ "${failure:-}" != "$key" ]] || value=wrong
        result+="${result:+|}$value"
      done
      printf '%s\n' "$result"
    fi
  }
}

teardown() { rm -rf "$TEST_TMP"; }

unchanged() {
  cmp "$dest" "$TEST_TMP/original"
  [ -z "$(find "$cfg" -name '*.tmp.*' -print)" ]
}

@test "sync replaces obsolete pins, creates missing pins, and keeps identical inode" {
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
  cmp "$src" "$dest"
  inode=$(stat -c %i "$dest")
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -eq 0 ]; [ "$(stat -c %i "$dest")" = "$inode" ]
  rm "$dest"
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -eq 0 ]; cmp "$src" "$dest"
}

@test "sync rejects absent image, wrong user, version, and each integrity label" {
  for failure in missing user group OPENCODE_SHA256_AMD64 OPENCODE_SHA256_ARM64; do
    run box_sync_installed_pins opencode "$BUNDLE_DIR"
    [ "$status" -ne 0 ]; unchanged
  done
  fake_docker() { printf '%s|wrong\n' "$host_uid:$host_gid"; }
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; unchanged
}

@test "sync cleans staging on copy chmod comparison and rename failure" {
  cp() { return 1; }
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; unchanged
  unset -f cp
  chmod() { return 1; }
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; unchanged
  unset -f chmod
  cmp() { return 2; }
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
  unset -f cmp
  unchanged
  mv() { return 1; }
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; unchanged
}

@test "sync rejects invalid bundled pins without touching installed pins" {
  mkdir -p "$TEST_TMP/bundle/harnesses/opencode"
  printf 'OPENCODE_VERSION=bad\n' > "$TEST_TMP/bundle/harnesses/opencode/version-opencode.env"
  run box_sync_installed_pins opencode "$TEST_TMP/bundle"
  [ "$status" -ne 0 ]; unchanged
}

@test "sync rejects unsafe ancestors ownership modes links and nonregular destination" {
  chmod 777 "$HOME"
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; unchanged
  chmod 700 "$HOME"
  chmod 666 "$dest"
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; unchanged
  chmod 644 "$dest"
  stat() {
    if [[ "$*" == *'%u'* && "${*: -1}" == "$dest" ]]; then printf '9\n'; else command stat "$@"; fi
  }
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; unchanged
  unset -f stat
  rm "$dest"; ln -s "$TEST_TMP/original" "$dest"
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; [ -L "$dest" ]
  rm "$dest"; mkdir "$dest"
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; [ -d "$dest" ]
  rm -rf "$cfg"
  mkdir "$TEST_TMP/linked-config"
  ln -s "$TEST_TMP/linked-config" "$cfg"
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]; [ -L "$cfg" ]
}

@test "sync requires installation while updater skips never installed harness" {
  rm -rf "$cfg"
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
  run box_sync_installed_pins opencode "$BUNDLE_DIR" 1
  [ "$status" -eq 0 ]; [[ "$output" == *'skipping installed-pin sync'* ]]
  run make -n -C "$BUNDLE_DIR" sync-pins-o
  [ "$status" -eq 0 ]; [[ "$output" == *'sync-pins.sh" "box-o"'* ]]
  run bash "$BUNDLE_DIR/sync-pins.sh" box-unknown
  [ "$status" -ne 0 ]
}

@test "updater uses shared validated sync after build and skips uninstalled harness" {
  # Loop over every registry tool: BOX_UPDATE_* seeds bypass the per-tool
  # resolvers (channel/manifest vs archive.py vs tar-listing), so the fetch
  # differences are out of scope here and the shared build+sync path under
  # test is identical for each tool. The docker stub is parameterized by
  # BOX_TEST_SYNC_ID; seeds, versions, and paths derive from the registry.
  for id in $box_tool_ids; do
    box_require_tool "$id"
    cfg="$HOME/.config/$(box_tool_field "$id" config_dir)"
    vf=$(box_tool_field "$id" version_file)
    dest="$cfg/$vf"
    vsource=$(box_tool_field "$id" version_source)
    read -r -a keys <<<"$(box_tool_field "$id" pin_keys)"
    vkey=${keys[0]} akey=${keys[1]} rkey=${keys[2]}
    prefix=${vkey%_VERSION}
    cur=$(box_print_pin "$BUNDLE_DIR" "$vkey")
    if [[ "$cur" == *-* ]]; then syn1=9.9.9-R999.9; syn2=8.8.8-R888.8; else syn1=9.9.9; syn2=8.8.8; fi
    if [[ "$cur" == "$syn1" || "$cur" == "$syn2" ]]; then
      if [[ "$cur" == *-* ]]; then syn1=7.7.7-R777.7; syn2=6.6.6-R666.6; else syn1=7.7.7; syn2=6.6.6; fi
    fi
    mkdir -p -- "$cfg"
    printf 'OBSOLETE=npm\n' >"$dest"
    copy="$TEST_TMP/bundle-$id"
    rm -rf -- "$copy"
    cp -r "$BUNDLE_DIR" "$copy"
    # Stub only image build and Docker transport; keep real sync and assertions.
    cat >>"$copy/lib/build.sh" <<'STUB'
box_build_image() { mkdir -p "$HOME/.config/$(box_tool_field "${1:?}" config_dir)/docker-cli"; printf 'fixture build\n'; }
box_docker_cli() { docker_cmd=(fixture_docker); }
fixture_docker() {
  local pair first=1 result=''
  case "$1" in
    info) printf '[]\n'; return ;;
    version) printf '29.0.0\n'; return ;;
  esac
  if [[ "$4" == *Config.User* ]]; then
    printf '%s:%s|%s|3\n' "$host_uid" "$host_gid" "$box_file_version"
  else
    for pair in $(box_tool_field "${BOX_TEST_SYNC_ID:?}" label_pins); do
      if ((first)); then first=0; continue; fi
      result+="${result:+|}${box_file_pin[${pair%%:*}]}"
    done
    printf '%s\n' "$result"
  fi
}
STUB
    unset BOX_UPDATE_MUSE_VERSION BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_MUSE_SHA256_ARM64
    unset BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
    unset BOX_UPDATE_CODEX_VERSION BOX_UPDATE_CODEX_SHA256_AMD64 BOX_UPDATE_CODEX_SHA256_ARM64
    export BOX_TEST_SYNC_ID="$id"
    export "BOX_UPDATE_${prefix}_VERSION=$syn1"
    export "BOX_UPDATE_${prefix}_SHA256_AMD64=$(box_print_pin "$BUNDLE_DIR" "$akey")"
    export "BOX_UPDATE_${prefix}_SHA256_ARM64=$(box_print_pin "$BUNDLE_DIR" "$rkey")"
    run bash "$copy/update-pins.sh" --only "$id"
    [ "$status" -eq 0 ] || { echo "sync-phase failed for $id: $output"; return 1; }
    [[ "$output" == *'fixture build'* ]] || { echo "no fixture build for $id"; return 1; }
    cmp "$copy/$vsource" "$dest" || { echo "installed pins differ for $id"; return 1; }
    rm -rf -- "$cfg"
    export "BOX_UPDATE_${prefix}_VERSION=$syn2"
    run bash "$copy/update-pins.sh" --only "$id"
    [ "$status" -eq 0 ] || { echo "skip-phase failed for $id: $output"; return 1; }
    [[ "$output" == *'skipping installed-pin sync'* ]] || { echo "no skip message for $id"; return 1; }
    [ ! -e "$dest" ] || { echo "dest recreated for $id"; return 1; }
  done
  unset BOX_UPDATE_MUSE_VERSION BOX_UPDATE_MUSE_SHA256_AMD64 BOX_UPDATE_MUSE_SHA256_ARM64
  unset BOX_UPDATE_OPENCODE_VERSION BOX_UPDATE_OPENCODE_SHA256_AMD64 BOX_UPDATE_OPENCODE_SHA256_ARM64
  unset BOX_UPDATE_CODEX_VERSION BOX_UPDATE_CODEX_SHA256_AMD64 BOX_UPDATE_CODEX_SHA256_ARM64
  unset BOX_TEST_SYNC_ID
}

@test "interrupted installed-pin validation preserves pins and removes staging" {
  box_assert_image() { kill -TERM "$BASHPID"; }
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -eq 143 ]
  unchanged
}
