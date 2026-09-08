# preflight.bats — box_preflight_project incl. the docs/operations.md §11 negative matrix.
load helpers

@test "preflight accepts a plain scratch project" {
  run box_preflight_project
  [ "$status" -eq 0 ]
}

@test "preflight rejects system-dir projects" {
  for dir in / /root /etc /dev /proc /sys /run /usr /boot /var /tmp /opt /mnt /media /snap /srv /data /workspace /tmp/foo /srv/foo /data/foo /snap/foo; do
    project="$dir"
    run box_preflight_project
    [ "$status" -ne 0 ] || { echo "accepted denylisted project: $dir"; return 1; }
  done
}

@test "preflight rejects the entire home directory" {
  project="$HOME"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"entire home directory"* ]]
}

@test "preflight rejects a project containing the home directory" {
  mkdir -p -- "$TEST_PROJ/nested-home"
  HOME="$TEST_PROJ/nested-home"
  export HOME
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not contain your home"* ]]
}

@test "preflight rejects a credential directory as project" {
  mkdir -p -- "$HOME/.ssh"
  project="$HOME/.ssh"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"credential directory"* ]]
}

@test "preflight rejects a project containing a credential path" {
  mkdir -p -- "$TEST_PROJ/stash"
  ln -s "$TEST_PROJ/stash" "$HOME/.ssh"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"would contain a credential path"* ]]
}

@test "preflight rejects tool directories as project" {
  for dir in "$HOME/.config/box" "$HOME/.config/box-m" "$HOME/.config/box-o" "$HOME/.local/bin"; do
    mkdir -p -- "$dir"
    project="$dir"
    run box_preflight_project
    [ "$status" -ne 0 ] || { echo "accepted tool dir: $dir"; return 1; }
  done
}

@test "preflight rejects mount paths with commas" {
  mkdir -p -- "$PROJ_ROOT/with,comma"
  project="$PROJ_ROOT/with,comma"
  run box_preflight_project
  [ "$status" -ne 0 ]
}

@test "preflight rejects sockets/FIFOs inside the project" {
  mkfifo -- "$TEST_PROJ/pipe"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"socket/device/FIFO"* ]]
}

@test "preflight rejects a project symlink into a system dir" {
  ln -s /etc -- "$TEST_PROJ/evil"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"host system path"* ]]
}

@test "preflight rejects a project symlink at the home directory" {
  ln -s "$HOME" -- "$TEST_PROJ/home-link"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"home directory"* ]]
}

@test "preflight rejects a project symlink at a credential path" {
  mkdir -p -- "$HOME/.ssh"
  ln -s "$HOME/.ssh" -- "$TEST_PROJ/creds-link"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"credential path"* ]]
}

@test "preflight symlink scan truncates with WARNING past 500 links" {
  for i in $(seq 1 600); do ln -s "../target-$i" -- "$TEST_PROJ/link-$i"; done
  box_preflight_home
  box_preflight_credentials
  run box_preflight_symlinks
  [ "$status" -eq 0 ]
  [[ "$output" == *"more than 500 symlinks"* ]]
}

@test "preflight rejects external git worktree metadata" {
  if ! command -v git >/dev/null; then skip "git not installed"; fi
  git init -q -- "$TEST_TMP/external" 2>/dev/null
  printf 'gitdir: %s\n' "$TEST_TMP/external/.git" >"$TEST_PROJ/.git"
  cd -- "$TEST_PROJ"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"external Git metadata"* ]]
}

@test "preflight requires a non-root invoking user" {
  host_uid=0
  host_gid=0
  run box_preflight_project
  [ "$status" -ne 0 ]
}

@test "preflight tool-dir guard resolves a symlinked HOME" {
  # The project is canonical (pwd -P) while $HOME may be a symlink: the
  # tool-dir guard must compare physical paths or the physical tool dir
  # evades it. Scratch lives under PROJ_ROOT (real home), never /tmp —
  # a /tmp project dies at the denylist before this guard runs.
  real="$PROJ_ROOT/realhome"
  mkdir -p -- "$real/.config/box"
  ln -s "$real" "$PROJ_ROOT/fakehome"
  HOME="$PROJ_ROOT/fakehome"
  export HOME
  project="$real/.config/box"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"sandbox tool directory"* ]]
}
