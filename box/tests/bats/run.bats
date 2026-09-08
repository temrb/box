# run.bats — lib/run.sh shared helpers: git identity, base args, key
# forwarding, runtime signal, tty, muse bypass, image tags.
load helpers

@test "git identity resolves primary with fallback" {
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-unused"
  BOX_M_GIT_NAME='Primary' BOX_M_GIT_EMAIL='p@example.com' \
    BOX_O_GIT_NAME='Fallback' BOX_O_GIT_EMAIL='f@example.com' \
    box_git_identity BOX_M BOX_O
  [ "$identity_name" = "Primary" ]
  [ "$identity_email" = "p@example.com" ]
  unset BOX_O_GIT_NAME BOX_O_GIT_EMAIL
  BOX_M_GIT_NAME='Fallback' BOX_M_GIT_EMAIL='f@example.com' \
    box_git_identity BOX_O BOX_M
  [ "$identity_name" = "Fallback" ]
}

@test "git identity rejects multiline values" {
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-unused"
  BOX_M_GIT_NAME=$'a\nb' BOX_M_GIT_EMAIL='a@example.com' \
  BOX_O_GIT_NAME='x' BOX_O_GIT_EMAIL='x@example.com' \
  run box_git_identity BOX_M BOX_O
  [ "$status" -ne 0 ]
}

@test "git identity infers missing fields from global git config" {
  if ! command -v git >/dev/null; then skip "no git binary"; fi
  unset BOX_M_GIT_NAME BOX_M_GIT_EMAIL BOX_O_GIT_NAME BOX_O_GIT_EMAIL
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-infer-both"
  git config --global user.name 'Inferred Name'
  git config --global user.email 'inferred@example.com'
  box_git_identity BOX_M BOX_O 2>"$TEST_TMP/identity-stderr.txt"
  [ "$identity_name" = 'Inferred Name' ]
  [ "$identity_email" = 'inferred@example.com' ]
  [[ "$(cat -- "$TEST_TMP/identity-stderr.txt")" == *"NOTICE: using git global identity for GIT_NAME and GIT_EMAIL"* ]]
}

@test "git identity prefers fallback env over inference" {
  if ! command -v git >/dev/null; then skip "no git binary"; fi
  unset BOX_M_GIT_NAME BOX_M_GIT_EMAIL
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-infer-shadowed"
  git config --global user.name 'Shadowed Name'
  git config --global user.email 'shadowed@example.com'
  BOX_O_GIT_NAME='Fallback' BOX_O_GIT_EMAIL='f@example.com' \
    box_git_identity BOX_M BOX_O 2>"$TEST_TMP/identity-stderr.txt"
  [ "$identity_name" = "Fallback" ]
  [ "$identity_email" = "f@example.com" ]
  [ ! -s "$TEST_TMP/identity-stderr.txt" ]
}

@test "git identity resolves fields independently (env name plus inferred email)" {
  if ! command -v git >/dev/null; then skip "no git binary"; fi
  unset BOX_M_GIT_EMAIL BOX_O_GIT_NAME BOX_O_GIT_EMAIL
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-infer-split"
  git config --global user.name 'Shadowed Name'
  git config --global user.email 'inferred@example.com'
  BOX_M_GIT_NAME='Primary' \
    box_git_identity BOX_M BOX_O 2>"$TEST_TMP/identity-stderr.txt"
  [ "$identity_name" = "Primary" ]
  [ "$identity_email" = 'inferred@example.com' ]
  notice=$(cat -- "$TEST_TMP/identity-stderr.txt")
  [[ "$notice" == *"NOTICE: using git global identity for GIT_EMAIL"* ]]
  [[ "$notice" != *"GIT_NAME"* ]]
}

@test "git identity NOTICE goes to stderr with empty stdout" {
  if ! command -v git >/dev/null; then skip "no git binary"; fi
  unset BOX_M_GIT_NAME BOX_M_GIT_EMAIL BOX_O_GIT_NAME BOX_O_GIT_EMAIL
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-infer-streams"
  git config --global user.name 'Inferred Name'
  git config --global user.email 'inferred@example.com'
  box_git_identity BOX_M BOX_O >"$TEST_TMP/identity-stdout.txt" 2>"$TEST_TMP/identity-stderr.txt"
  [ ! -s "$TEST_TMP/identity-stdout.txt" ]
  [[ "$(cat -- "$TEST_TMP/identity-stderr.txt")" == *"NOTICE: using git global identity for GIT_NAME and GIT_EMAIL"* ]]
  [ "$identity_name" = 'Inferred Name' ]
  [ "$identity_email" = 'inferred@example.com' ]
}

@test "git identity ignores invalid inferred values" {
  unset BOX_M_GIT_NAME BOX_M_GIT_EMAIL BOX_O_GIT_NAME BOX_O_GIT_EMAIL
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-unused"
  mkdir -p -- "$TEST_TMP/stubbin-identity-bad"
  cat >"$TEST_TMP/stubbin-identity-bad/git" <<'EOF'
#!/bin/bash
if [[ "${3:-}" == "user.name" ]]; then printf 'a\nb\n'; else printf 'bad\x01mail@example.com\n'; fi
EOF
  chmod +x -- "$TEST_TMP/stubbin-identity-bad/git"
  saved_path=$PATH
  PATH="$TEST_TMP/stubbin-identity-bad:$PATH"
  run box_git_identity BOX_M BOX_O
  PATH=$saved_path
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing git identity"* ]]
}

@test "git identity still fails closed when env and inference are empty" {
  unset BOX_M_GIT_NAME BOX_M_GIT_EMAIL BOX_O_GIT_NAME BOX_O_GIT_EMAIL
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-empty"
  : >"$TEST_TMP/gitconfig-empty"
  run box_git_identity BOX_M BOX_O
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing git identity (GIT_NAME and GIT_EMAIL)"* ]]
  [[ "$output" == *"git config --global"* ]]
  [[ "$output" == *"export BOX_M_GIT_NAME=..."* ]]
  BOX_M_GIT_NAME='Only Name' run box_git_identity BOX_M BOX_O
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing git identity (GIT_EMAIL)"* ]]
}

@test "git inference reads global user.name and user.email" {
  if ! command -v git >/dev/null; then skip "no git binary"; fi
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-both"
  git config --global user.name "O'Brien, Test"
  git config --global user.email 'test@example.com'
  box_infer_git_identity
  [ "$inferred_git_name" = "O'Brien, Test" ]
  [ "$inferred_git_email" = 'test@example.com' ]
}

@test "git inference is per-field independent" {
  if ! command -v git >/dev/null; then skip "no git binary"; fi
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-partial"
  git config --global user.name 'Only Name'
  box_infer_git_identity
  [ "$inferred_git_name" = 'Only Name' ]
  [ -z "$inferred_git_email" ]
  git config --global user.email 'only@example.com'
  git config --global --unset user.name
  box_infer_git_identity
  [ -z "$inferred_git_name" ]
  [ "$inferred_git_email" = 'only@example.com' ]
}

@test "git inference yields empty when no global identity is set" {
  if ! command -v git >/dev/null; then skip "no git binary"; fi
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig-never-created"
  box_infer_git_identity
  [ -z "$inferred_git_name" ]
  [ -z "$inferred_git_email" ]
  run box_infer_git_identity
  [ "$status" -eq 0 ]
}

@test "git inference yields empty when git is missing" {
  mkdir -p -- "$TEST_TMP/empty-bin"
  saved_path=$PATH
  PATH="$TEST_TMP/empty-bin"
  box_infer_git_identity
  PATH=$saved_path
  [ -z "$inferred_git_name" ]
  [ -z "$inferred_git_email" ]
}

@test "git inference accepts stubbed single-line printable values" {
  mkdir -p -- "$TEST_TMP/stubbin-ok"
  cat >"$TEST_TMP/stubbin-ok/git" <<'EOF'
#!/bin/bash
if [[ "${3:-}" == "user.name" ]]; then printf 'Stub User\n'; else printf 'stub@example.com\n'; fi
EOF
  chmod +x -- "$TEST_TMP/stubbin-ok/git"
  saved_path=$PATH
  PATH="$TEST_TMP/stubbin-ok:$PATH"
  box_infer_git_identity
  PATH=$saved_path
  [ "$inferred_git_name" = 'Stub User' ]
  [ "$inferred_git_email" = 'stub@example.com' ]
}

@test "git inference rejects multiline and non-printable values" {
  mkdir -p -- "$TEST_TMP/stubbin-bad"
  cat >"$TEST_TMP/stubbin-bad/git" <<'EOF'
#!/bin/bash
if [[ "${3:-}" == "user.name" ]]; then printf 'a\nb\n'; else printf 'bad\x01mail@example.com\n'; fi
EOF
  chmod +x -- "$TEST_TMP/stubbin-bad/git"
  saved_path=$PATH
  PATH="$TEST_TMP/stubbin-bad:$PATH"
  box_infer_git_identity
  PATH=$saved_path
  [ -z "$inferred_git_name" ]
  [ -z "$inferred_git_email" ]
}

@test "base args append containment in canonical order" {
  args=(run)
  box_base_args box-m
  [[ " ${args[*]} " == *" --cap-drop=ALL "* ]]
  [[ " ${args[*]} " == *" --read-only "* ]]
  [[ " ${args[*]} " == *" --network=box-m "* ]]
}

@test "forward keys passes NAME-only when set" {
  args=()
  FWD_TEST_KEY_ONE=secret-value
  export FWD_TEST_KEY_ONE
  unset FWD_TEST_KEY_TWO || true
  box_forward_keys FWD_TEST_KEY_ONE FWD_TEST_KEY_TWO
  [ "${#args[@]}" -eq 2 ]
  [ "${args[0]}" = "--env" ]
  [ "${args[1]}" = "FWD_TEST_KEY_ONE" ]
}

@test "forward keys no-ops on an empty set (pure /connect)" {
  args=()
  box_forward_keys
  [ "${#args[@]}" -eq 0 ]
}

@test "runtime signal follows fallback_requested" {
  args=()
  fallback_requested=0
  box_runtime_signal
  [[ " ${args[*]} " == *" BOX_RUNTIME=runsc "* ]]
  args=()
  fallback_requested=1
  box_runtime_signal
  [[ " ${args[*]} " == *" BOX_RUNTIME=runc "* ]]
}

@test "muse bypass injects by default, honors denylist and opt-out" {
  unset BOX_M_INNER_FLAG || true
  run box_muse_bypass --foo
  [ "$status" -eq 0 ]
  [ "$output" = "--disable-sandbox" ]
  run box_muse_bypass login
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run box_muse_bypass -- --yolo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  BOX_M_INNER_FLAG=
  export BOX_M_INNER_FLAG
  run box_muse_bypass --foo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "muse bypass injects for non-first-position login" {
  # Only $1 is denylisted (documented): `muse --verbose login` keeps the
  # bypass while bare first-position `login` stays bare (pinned above).
  unset BOX_M_INNER_FLAG || true
  run box_muse_bypass --verbose login
  [ "$status" -eq 0 ]
  [ "$output" = "--disable-sandbox" ]
}

@test "maybe-tty appends --tty only on a live terminal run" {
  args=()
  dry_run=1
  box_maybe_tty
  [ "${#args[@]}" -eq 0 ]
  args=()
  dry_run=0
  box_maybe_tty
  # bats stdout is captured (no tty), so a non-terminal live run stays bare.
  [ "${#args[@]}" -eq 0 ]
  if ! command -v script >/dev/null; then skip "no script(1) for pty allocation"; fi
  export -f box_maybe_tty
  out=$(printf '' | script -qec "bash -c 'args=(); dry_run=0; box_maybe_tty; printf \"%s\" \"\${args[*]}\"'" /dev/null)
  [[ "$out" == *"--tty"* ]]
}

@test "image tags embed version and IDs" {
  unset project
  tag=$(box_image_tag muse "$BUNDLE_DIR" 1000 1000)
  [[ "$tag" == box-m:*-u1000-g1000 ]]
  [[ "$tag" == *"$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)"* ]]
  tag=$(box_image_tag opencode "$BUNDLE_DIR" 1000 1000)
  [[ "$tag" == box-o:*-u1000-g1000 ]]
}

@test "version-fed tags match bundle-fed tags and reject bad input" {
  unset project
  ver=$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)
  [ "$(box_image_tag_for_version muse "$ver" 1000 1000)" = "$(box_image_tag muse "$BUNDLE_DIR" 1000 1000)" ]
  [ "$(box_image_tag_for_version muse 1.2.3 1000 1000)" = "box-m:1.2.3-u1000-g1000" ]
  [ "$(box_image_tag_for_version opencode 1.2.3 1000 1000)" = "box-o:1.2.3-u1000-g1000" ]
  run box_image_tag_for_version bogus 1.2.3 1000 1000
  [ "$status" -ne 0 ]
  run box_image_tag_for_version muse "" 1000 1000
  [ "$status" -ne 0 ]
}
