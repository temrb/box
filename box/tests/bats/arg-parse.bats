# arg-parse.bats — box_parse_launcher_args + box_check_fallback.
load helpers

usage() { printf 'test usage\n'; }

@test "arg-parse defaults to runsc without fallback" {
  box_parse_launcher_args
  [ "$fallback_requested" -eq 0 ]
  [ "$explicit_runsc" -eq 0 ]
  [ "${runtime_args[0]}" = "--runtime=runsc" ]
  [ "$dry_run" -eq 0 ]
  [ "$shell_mode" -eq 0 ]
  [ "${#launcher_rest[@]}" -eq 0 ]
}

@test "arg-parse handles --docker-fallback" {
  box_parse_launcher_args --docker-fallback
  [ "$fallback_requested" -eq 1 ]
  [ "$explicit_runsc" -eq 0 ]
  [ "${runtime_args[0]}" = "--runtime=runc" ]
}

@test "arg-parse handles --runsc (explicit gVisor, no probe)" {
  box_parse_launcher_args --runsc
  [ "$fallback_requested" -eq 0 ]
  [ "$explicit_runsc" -eq 1 ]
  [ "${runtime_args[0]}" = "--runtime=runsc" ]
}

@test "arg-parse --docker-fallback after --runsc wins (clears explicit)" {
  box_parse_launcher_args --runsc --docker-fallback
  [ "$fallback_requested" -eq 1 ]
  [ "$explicit_runsc" -eq 0 ]
  [ "${runtime_args[0]}" = "--runtime=runc" ]
}

@test "arg-parse handles --dry-run" {
  box_parse_launcher_args --dry-run
  [ "$dry_run" -eq 1 ]
}

@test "arg-parse splits at --shell" {
  box_parse_launcher_args --shell -c 'echo hi'
  [ "$shell_mode" -eq 1 ]
  [ "${launcher_rest[0]}" = "-c" ]
  [ "${launcher_rest[1]}" = "echo hi" ]
}

@test "arg-parse splits at bare --" {
  box_parse_launcher_args -- --dry-run
  [ "$dry_run" -eq 0 ]
  [ "${launcher_rest[0]}" = "--dry-run" ]
}

@test "arg-parse stops at the first non-flag" {
  box_parse_launcher_args --dry-run login
  [ "$dry_run" -eq 1 ]
  [ "${launcher_rest[0]}" = "login" ]
}

@test "arg-parse rejects a launcher flag as the first arg after --shell" {
  run box_parse_launcher_args --shell --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"before --shell"* ]]
  run box_parse_launcher_args --shell --runsc
  [ "$status" -ne 0 ]
  [[ "$output" == *"before --shell"* ]]
}

@test "arg-parse allows tool flags deeper in shell passthrough" {
  box_parse_launcher_args --shell opencode --dry-run
  [ "$shell_mode" -eq 1 ]
  [ "${launcher_rest[0]}" = "opencode" ]
  [ "${launcher_rest[1]}" = "--dry-run" ]
}

@test "fallback kill-switch refuses explicit fallback" {
  fallback_requested=1
  BOX_M_ALLOW_FALLBACK=0
  export BOX_M_ALLOW_FALLBACK
  run box_check_fallback BOX_M_ALLOW_FALLBACK
  [ "$status" -ne 0 ]
  [[ "$output" == *"disabled via"* ]]
}

@test "fallback check warns on explicit fallback" {
  fallback_requested=1
  unset BOX_M_ALLOW_FALLBACK || true
  run box_check_fallback BOX_M_ALLOW_FALLBACK
  [ "$status" -eq 0 ]
  [[ "$output" == *"explicit hardened-runc fallback"* ]]
}

@test "fallback check is silent without fallback" {
  fallback_requested=0
  run box_check_fallback BOX_M_ALLOW_FALLBACK
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "device-url helper extracts the URL and short code" {
  run box_device_url_code 'Visit https://auth.meta.com/oauth/device/?code=ABCD-1234_~.9 to sign in'
  [ "$status" -eq 0 ]
  url=${lines[0]}
  code=${lines[1]}
  [ "$url" = "https://auth.meta.com/oauth/device/?code=ABCD-1234_~.9" ]
  [ "$code" = "ABCD-1234_~.9" ]
}

@test "device-url helper tolerates extra params and strips trailing punctuation" {
  run box_device_url_code 'open https://auth.meta.com/oauth/device/?foo=1&code=XYZ789&bar=2).'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "https://auth.meta.com/oauth/device/?foo=1&code=XYZ789" ]
  [ "${lines[1]}" = "XYZ789" ]
}

@test "device-url helper rejects lines without a device URL" {
  run box_device_url_code 'login failed: device flow transport error'
  [ "$status" -ne 0 ]
  run box_device_url_code ''
  [ "$status" -ne 0 ]
}
