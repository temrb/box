# creds.bats — box_load_credentials (never-source KEY=value parser).
load helpers

@test "creds parser exports allowlisted keys" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY=secret-123"
  box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "${MUSE_CODE_API_KEY:-}" = "secret-123" ]
}

@test "creds parser takes last-wins on duplicates" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY=first" "MUSE_CODE_API_KEY=second"
  box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "${MUSE_CODE_API_KEY:-}" = "second" ]
}

@test "creds parser unsets inherited allowlisted values first" {
  MUSE_CODE_API_KEY='injected-by-host-env'
  export MUSE_CODE_API_KEY
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "# empty on purpose"
  box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ -z "${MUSE_CODE_API_KEY:-}" ]
}

@test "creds parser rejects a missing file" {
  run box_load_credentials "$TEST_TMP/nope.env" 0 MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing credentials file"* ]]
}

@test "creds parser rejects unknown keys" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "EVIL_KEY=oops"
  run box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported credential variable"* ]]
}

@test "creds parser rejects empty values" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY="
  run box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
  [[ "$output" == *"Empty value"* ]]
}

@test "creds parser rejects glob-looking keys" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_*=oops"
  run box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
}

@test "creds parser rejects wrong file mode" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY=x"
  chmod 644 -- "$creds"
  run box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
  [[ "$output" == *"mode to 600"* ]]
}

@test "creds parser accepts mode 400" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY=x"
  chmod 400 -- "$creds"
  run box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "$status" -eq 0 ]
}

@test "creds parser rejects an in-project credentials file" {
  creds="$TEST_PROJ/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY=x"
  run box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the project"* ]]
}

@test "creds parser skips all file access under dry-run and forwards nothing" {
  MUSE_CODE_API_KEY='injected-by-host-env'
  export MUSE_CODE_API_KEY
  box_load_credentials "$TEST_TMP/does-not-exist.env" 1 MUSE_CODE_API_KEY
  [ -z "${MUSE_CODE_API_KEY:-}" ]
}

@test "creds parser rejects CRLF lines" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY=x"
  printf 'OTHER_KEY=y\r\n' >>"$creds"
  run box_load_credentials "$creds" 0 MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
}

@test "creds filled probe accepts one allowlisted entry" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "# comment" "" "MUSE_CODE_API_KEY=x"
  run box_credentials_filled "$creds" MUSE_CODE_API_KEY
  [ "$status" -eq 0 ]
}

@test "creds filled probe rejects unknown keys and CR tails" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "UNKNOWN_KEY=x"
  run box_credentials_filled "$creds" MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
  printf 'MUSE_CODE_API_KEY=x\r\n' >"$creds"
  chmod 600 -- "$creds"
  run box_credentials_filled "$creds" MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
}

@test "creds filled probe rejects empty values and a missing file" {
  creds="$TEST_TMP/providers.env"
  make_creds_file "$creds" "MUSE_CODE_API_KEY="
  run box_credentials_filled "$creds" MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
  run box_credentials_filled "$TEST_TMP/nope.env" MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
}

@test "creds parser follows a symlink to a valid target (same guards)" {
  # Symlink policy (preflight.sh): the path is resolved with realpath -e and
  # every guard (outside-project, owner, mode) runs on the RESOLVED path, so
  # a dotfile-managed providers.env keeps working.
  real="$TEST_TMP/real-providers.env"
  make_creds_file "$real" "MUSE_CODE_API_KEY=symlinked-secret"
  link="$TEST_TMP/link-providers.env"
  ln -s "$real" "$link"
  box_load_credentials "$link" 0 MUSE_CODE_API_KEY
  [ "${MUSE_CODE_API_KEY:-}" = "symlinked-secret" ]
}

@test "creds parser rejects a symlink to a bad-mode target" {
  real="$TEST_TMP/real-badmode.env"
  make_creds_file "$real" "MUSE_CODE_API_KEY=x"
  chmod 644 -- "$real"
  link="$TEST_TMP/link-badmode.env"
  ln -s "$real" "$link"
  run box_load_credentials "$link" 0 MUSE_CODE_API_KEY
  [ "$status" -ne 0 ]
  [[ "$output" == *"mode to 600"* ]]
}
