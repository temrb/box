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

@test "tool guards follow registry config directories and both containment directions" {
  _BOX_TOOL_REGISTRY[opencode,config_dir]=future-tool
  for path in "$HOME/.config/future-tool" "$HOME/.config/future-tool/child" "$HOME/.config"; do
    project="$path"
    run box_preflight_tool_dirs
    [ "$status" -ne 0 ]
    [[ "$output" == *"sandbox tool directory"* ]]
  done
}

@test "tool guards protect physical targets beneath symlinked parents" {
  mkdir -p "$TEST_PROJ/private"
  ln -s "$TEST_PROJ/private" "$HOME/.config"
  run box_preflight_tool_dirs
  [ "$status" -ne 0 ]
  [[ "$output" == *"would contain a sandbox tool directory"* ]]
}

@test "project symlinks cannot target tool directories, children, or their parents" {
  _BOX_TOOL_REGISTRY[opencode,config_dir]=future-tool
  for target in "$HOME/.config/future-tool" "$HOME/.config/future-tool/child" "$HOME/.config"; do
    ln -s "$target" "$TEST_PROJ/tool-link"
    run box_preflight_project
    [ "$status" -ne 0 ]
    [[ "$output" == *"sandbox tool directory"* ]]
    rm "$TEST_PROJ/tool-link"
  done
}

@test "tool directory guard works when only preflight is sourced" {
  run bash -c 'BOX_TOOL=test; source "$1/lib/preflight.sh"; HOME="$2"; project="$2/.config/box-o"; box_preflight_tool_dirs' _ "$BUNDLE_DIR" "$HOME"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sandbox tool directory"* ]]
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

@test "preflight symlink truncation succeeds when find inherits ignored SIGPIPE" {
  # Long paths force multiple pipe writes; ignored SIGPIPE makes GNU find
  # report a write error (status 1) if the collector closes its pipe early.
  project="$TEST_PROJ/$(printf '%0200d' 0)"
  mkdir -p -- "$project"
  for i in $(seq 1 3000); do ln -s "target-$i" -- "$project/link-$i"; done
  find() { (trap '' PIPE; command find "$@"); }
  box_preflight_home
  box_preflight_credentials
  run box_preflight_symlinks
  [ "$status" -eq 0 ]
  [[ "$output" == *"more than 500 symlinks"* ]]
  [[ "$output" != *"Broken pipe"* ]]
}

@test "preflight symlink scan fails closed when find reports an inspection error" {
  find() { printf '%s\n' "$project/link"; return 1; }
  run box_preflight_symlinks
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot inspect project for symlinks"* ]]
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

@test "preflight rejects mount paths with newlines" {
  proj_with_nl="$PROJ_ROOT/with
newline"
  mkdir -p -- "$proj_with_nl"
  project="$proj_with_nl"
  run box_preflight_project
  [ "$status" -ne 0 ]
}

@test "self-dir bootstrap copies keep the realpath-first fallback" {
  # Accepted duplication (Phase 2 finding 12, bootstrap paradox): no
  # helpers exist before the bootstrap runs, so lib/tools.sh pins the
  # canonical snippet and every ship-code site copies it. Drift fails here.
  local f failed=0
  while IFS= read -r f; do
    grep -q "realpath" "$f" || { echo "lost realpath-first fallback: ${f#$BUNDLE_DIR/}"; failed=1; }
  done < <(grep -rln "readlink -f" "$BUNDLE_DIR/lib" "$BUNDLE_DIR/harnesses" \
    "$BUNDLE_DIR/box-m" "$BUNDLE_DIR/box-o" "$BUNDLE_DIR/box-c" "$BUNDLE_DIR/box-m-login" \
    "$BUNDLE_DIR/setup.sh" "$BUNDLE_DIR/gen-verify.sh" "$BUNDLE_DIR/gen-pins.sh" \
    "$BUNDLE_DIR/check-pins.sh" "$BUNDLE_DIR/update-pins.sh")
  [ "$failed" -eq 0 ]
}

@test "preflight unsets GIT_* overrides before the worktree check" {
  if ! command -v git >/dev/null; then skip "git not installed"; fi
  # A standalone clone inside the project must pass even when hostile GIT_*
  # overrides point outside it: box_preflight_git unsets them first so
  # rev-parse cannot be redirected outside the project.
  git init -q -- "$TEST_PROJ/repo" 2>/dev/null
  project="$TEST_PROJ/repo"
  cd -- "$project"
  export GIT_DIR="$TEST_TMP/external/.git" GIT_WORK_TREE="$TEST_TMP/external" \
    GIT_COMMON_DIR="$TEST_TMP/external" GIT_CEILING_DIRECTORIES="$TEST_TMP" \
    GIT_INDEX_FILE="$TEST_TMP/external-index"
  run box_preflight_project
  [ "$status" -eq 0 ]
}

@test "hardlink inspection accepts multiple names entirely inside the project" {
  mkdir -p "$TEST_PROJ/one" "$TEST_PROJ/two"
  printf 'synthetic' > "$TEST_PROJ/one/original"
  ln "$TEST_PROJ/one/original" "$TEST_PROJ/two/alias"
  run box_preflight_project
  [ "$status" -eq 0 ]
}

@test "hardlink inspection refuses any external inode alias and preserves bytes" {
  printf 'foreign-sentinel' > "$PROJ_ROOT/foreign"
  ln "$PROJ_ROOT/foreign" "$TEST_PROJ/alias"
  run box_preflight_project
  [ "$status" -ne 0 ]
  [[ "$output" == *"external hardlinks"* ]]
  [ "$(cat "$PROJ_ROOT/foreign")" = foreign-sentinel ]
}

@test "hardlink inspection handles delimiter and shell shaped filenames as data" {
  local name=$'line\nbreak $(`touch marker`) *'
  printf 'synthetic' > "$TEST_PROJ/$name"
  ln "$TEST_PROJ/$name" "$TEST_PROJ/second alias"
  run box_preflight_hardlinks
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_PROJ/marker" ]
}

@test "hardlink inspection refuses unreadable subtrees rather than skipping them" {
  mkdir "$TEST_PROJ/closed"
  chmod 000 "$TEST_PROJ/closed"
  run box_preflight_hardlinks
  chmod 700 "$TEST_PROJ/closed"
  [ "$status" -ne 0 ]
}

@test "hardlink inspection never follows directory symlinks" {
  mkdir "$TEST_TMP/foreign-directory"
  chmod 000 "$TEST_TMP/foreign-directory"
  ln -s "$TEST_TMP/foreign-directory" "$TEST_PROJ/reference"
  run box_preflight_hardlinks
  chmod 700 "$TEST_TMP/foreign-directory"
  [ "$status" -eq 0 ]
}

@test "hardlink inspection refuses an observed mutation between inventories" {
  run python3 -I - "$BUNDLE_DIR/lib/project-links.py" "$TEST_PROJ" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("links", sys.argv[1])
links = importlib.util.module_from_spec(spec)
spec.loader.exec_module(links)
original = links.inventory
calls = 0
def changed(fd):
    global calls
    snapshot = original(fd)
    calls += 1
    if calls == 1:
        pathlib.Path(sys.argv[2], "new member").write_text("synthetic")
    return snapshot
links.inventory = changed
try:
    links.qualify(sys.argv[2])
except ValueError as exc:
    assert "changed" in str(exc)
else:
    raise AssertionError("changing inventory accepted")
PY
  [ "$status" -eq 0 ]
}
