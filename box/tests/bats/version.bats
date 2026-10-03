# version.bats — box_load_version_file (format-keyed LF/allowlist/regex parser).
load helpers

# Parse <file> as tool <id> via the registry format + pin keys.
_parse() {
  box_load_version_file "$2" "$(box_tool_field "$1" version_format)" $(box_tool_field "$1" pin_keys)
}

@test "version parser rejects duplicate keys even when values agree" {
  unset project
  vf="$TEST_TMP/version.env"
  make_synthetic_muse_version_file "$vf"
  printf 'MUSE_VERSION=9.9.9-R999.9\n' >>"$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Duplicate entry"*"MUSE_VERSION"* ]]
}

@test "version parser rejects CRLF comments and non-regular files" {
  unset project
  vf="$TEST_TMP/version.env"
  make_synthetic_muse_version_file "$vf"
  printf '# comment\r\n' >>"$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CRLF line endings"* ]]
  run _parse muse "$TEST_TMP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing readable pinned-version file"* ]]
}

@test "version parser accepts the bundled muse pins" {
  unset project
  run _parse muse "$BUNDLE_DIR/harnesses/muse/version-muse.env"
  [ "$status" -eq 0 ]
}

@test "version parser accepts the bundled opencode pins" {
  unset project
  run _parse opencode "$BUNDLE_DIR/harnesses/opencode/version-opencode.env"
  [ "$status" -eq 0 ]
}

@test "version parser accepts a minimal valid muse file and sets globals" {
  unset project
  vf="$TEST_TMP/version-muse.env"
  make_synthetic_muse_version_file "$vf"
  _parse muse "$vf"
  [ "$box_file_version" = "9.9.9-R999.9" ]
  [ "$box_file_sha_amd64" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]
  [ "$box_file_sha_arm64" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ]
}

@test "version parser accepts a minimal valid opencode file and sets globals" {
  unset project
  vf="$TEST_TMP/version-opencode.env"
  make_synthetic_opencode_version_file "$vf"
  _parse opencode "$vf"
  [ "$box_file_version" = "9.9.9" ]
  [ "$box_file_sha_amd64" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]
  [ "$box_file_sha_arm64" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ]
}

@test "version parser sets the generic pin map" {
  unset project
  vf="$TEST_TMP/version-muse.env"
  make_synthetic_muse_version_file "$vf"
  _parse muse "$vf"
  [ "${box_file_pin[MUSE_VERSION]}" = "9.9.9-R999.9" ]
  [ "${box_file_pin[MUSE_SHA256_AMD64]}" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]
  [ "${box_file_pin[MUSE_SHA256_ARM64]}" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ]
  vf="$TEST_TMP/version-opencode.env"
  make_synthetic_opencode_version_file "$vf"
  _parse opencode "$vf"
  [ "${box_file_pin[OPENCODE_VERSION]}" = "9.9.9" ]
  [ "${box_file_pin[OPENCODE_SHA256_AMD64]}" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]
  [ "${box_file_pin[OPENCODE_SHA256_ARM64]}" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ]
}

@test "version parser rejects a missing file" {
  unset project
  run _parse muse "$TEST_TMP/nope.env"
  [ "$status" -ne 0 ]
}

@test "version parser rejects an unknown format" {
  unset project
  vf="$TEST_TMP/version-muse.env"
  make_muse_version_file "$vf"
  run box_load_version_file "$vf" bogus SOME_KEY
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown version format"* ]]
}

@test "version parser rejects a wrong-arity or duplicated allowlist" {
  unset project
  vf="$TEST_TMP/version-muse.env"
  make_muse_version_file "$vf"
  run box_load_version_file "$vf" sha-pinned MUSE_VERSION MUSE_SHA256_AMD64
  [ "$status" -ne 0 ]
  run box_load_version_file "$vf" sha-pinned MUSE_VERSION MUSE_VERSION MUSE_SHA256_AMD64
  [ "$status" -ne 0 ]
}

@test "version parser rejects the retired npm-pinned format" {
  unset project
  vf="$TEST_TMP/version-muse.env"
  make_muse_version_file "$vf"
  run box_load_version_file "$vf" npm-pinned A B C D E F
  [ "$status" -ne 0 ]
  [[ "$output" == *"retired"* ]]
}

@test "version parser rejects cross-tool keys via the allowlist" {
  unset project
  vf="$TEST_TMP/version-muse.env"
  make_muse_version_file "$vf"
  run box_load_version_file "$vf" sha-pinned OPENCODE_VERSION OPENCODE_SHA256_AMD64 OPENCODE_SHA256_ARM64
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported entry"* ]]
}

@test "version parser rejects CRLF line endings" {
  unset project
  vf="$TEST_TMP/crlf.env"
  make_muse_version_file "$vf"
  printf 'MUSE_VERSION=9.9.9\r\n' >>"$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CRLF"* ]]
}

@test "version parser rejects unknown keys" {
  unset project
  vf="$TEST_TMP/unknown.env"
  make_muse_version_file "$vf"
  printf 'EVIL=1\n' >>"$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported entry"* ]]
}

@test "version parser rejects a bad muse version" {
  unset project
  vf="$TEST_TMP/badver.env"
  make_muse_version_file "$vf"
  printf 'MUSE_VERSION=not-a-version\n' >>"$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
}

@test "version parser rejects a bad sha256 pin" {
  unset project
  vf="$TEST_TMP/badsha.env"
  make_muse_version_file "$vf"
  printf 'MUSE_SHA256_AMD64=xyz\n' >>"$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
}

@test "version parser rejects a bad opencode sha pin" {
  unset project
  vf="$TEST_TMP/badint.env"
  make_opencode_version_file "$vf"
  printf 'OPENCODE_SHA256_AMD64=bad\n' >>"$vf"
  run _parse opencode "$vf"
  [ "$status" -ne 0 ]
}

@test "version parser rejects a bad opencode arm sha pin" {
  unset project
  vf="$TEST_TMP/badnode.env"
  make_opencode_version_file "$vf"
  printf 'OPENCODE_SHA256_ARM64=xyz\n' >>"$vf"
  run _parse opencode "$vf"
  [ "$status" -ne 0 ]
}

@test "version parser rejects a malformed opencode digest" {
  unset project
  vf="$TEST_TMP/badfpr.env"
  make_opencode_version_file "$vf"
  printf 'OPENCODE_SHA256_AMD64=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n' >>"$vf"
  run _parse opencode "$vf"
  [ "$status" -ne 0 ]
}

@test "version parser rejects an opencode file missing arch pins" {
  unset project
  vf="$TEST_TMP/nonode.env"
  {
    printf 'OPENCODE_VERSION=9.9.9\n'
    printf 'OPENCODE_SHA256_AMD64=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
  } >"$vf"
  chmod 600 -- "$vf"
  run _parse opencode "$vf"
  [ "$status" -ne 0 ]
}

@test "version parser rejects group-writable pin files" {
  vf="$TEST_TMP/world.env"
  make_muse_version_file "$vf"
  chmod 664 -- "$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
}

@test "version parser rejects an in-project pin file" {
  vf="$TEST_PROJ/version-muse.env"
  make_muse_version_file "$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the project"* ]]
}

@test "version parser tolerates comments and blank lines" {
  unset project
  vf="$TEST_TMP/comments.env"
  {
    printf '# a comment\n'
    printf '\n'
    cat "$BUNDLE_DIR/harnesses/muse/version-muse.env"
  } >"$vf"
  chmod 600 -- "$vf"
  run _parse muse "$vf"
  [ "$status" -eq 0 ]
}

@test "version parser rejects whitespace around the key or equals" {
  unset project
  vf="$TEST_TMP/space-key.env"
  make_muse_version_file "$vf"
  printf 'MUSE_VERSION =9.9.9-R999.9\n' >>"$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
  vf="$TEST_TMP/space-val.env"
  make_muse_version_file "$vf"
  printf 'MUSE_VERSION= 9.9.9-R999.9\n' >>"$vf"
  run _parse muse "$vf"
  [ "$status" -ne 0 ]
}
