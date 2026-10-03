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
      printf '%s|%s\n' "$value" "$box_file_version"
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
  copy="$TEST_TMP/bundle"
  cp -r "$BUNDLE_DIR" "$copy"
  # Stub only image build and Docker transport; keep real sync and assertions.
  cat >> "$copy/lib/build.sh" <<'STUB'
box_build_image() { mkdir -p "$HOME/.config/box-o/docker-cli"; printf 'fixture build\n'; }
box_docker_cli() { docker_cmd=(fixture_docker); }
fixture_docker() {
  local pair first=1 result=''
  case "$1" in
    info) printf '[]\n'; return ;;
    version) printf '29.0.0\n'; return ;;
  esac
  if [[ "$4" == *Config.User* ]]; then
    printf '%s:%s|%s\n' "$host_uid" "$host_gid" "$box_file_version"
  else
    for pair in $(box_tool_field opencode label_pins); do
      if ((first)); then first=0; continue; fi
      result+="${result:+|}${box_file_pin[${pair%%:*}]}"
    done
    printf '%s\n' "$result"
  fi
}
STUB
  export BOX_UPDATE_OPENCODE_VERSION=2.0.999
  export BOX_UPDATE_OPENCODE_SHA256_AMD64=$(box_print_pin "$BUNDLE_DIR" OPENCODE_SHA256_AMD64)
  export BOX_UPDATE_OPENCODE_SHA256_ARM64=$(box_print_pin "$BUNDLE_DIR" OPENCODE_SHA256_ARM64)
  run bash "$copy/update-pins.sh" --only opencode
  [ "$status" -eq 0 ]; [[ "$output" == *'fixture build'* ]]
  cmp "$copy/harnesses/opencode/version-opencode.env" "$dest"
  rm -rf "$cfg"
  export BOX_UPDATE_OPENCODE_VERSION=2.0.998
  run bash "$copy/update-pins.sh" --only opencode
  [ "$status" -eq 0 ]; [[ "$output" == *'skipping installed-pin sync'* ]]
  [ ! -e "$dest" ]
}

@test "interrupted installed-pin validation preserves pins and removes staging" {
  box_assert_image() { kill -TERM "$BASHPID"; }
  run box_sync_installed_pins opencode "$BUNDLE_DIR"
  [ "$status" -eq 143 ]
  unchanged
}
