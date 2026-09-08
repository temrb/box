# config-linkage.bats — lib/config.sh single-source linkage (§6) plus the
# opencode.json permission rationale (§10) and the containment/preflight
# credential-list parity (§10). Values are read from config.sh dynamically so
# pin bumps never rot these tests; live copies that cannot source config.sh
# (stdin-deliverable verify.d/ partials, JSON configs) are pinned by value.
load helpers

@test "config.sh resources feed the shared docker-run base" {
  args=()
  box_base_args testnet
  [[ " ${args[*]} " == *" --memory=$BOX_CONTAINER_MEMORY "* ]]
  [[ " ${args[*]} " == *" --memory-swap=$BOX_CONTAINER_MEMORY "* ]]
  [[ " ${args[*]} " == *" --cpus=$BOX_CONTAINER_CPUS "* ]]
  [[ " ${args[*]} " == *" --pids-limit=$BOX_CONTAINER_PIDS "* ]]
}

@test "registry probe hosts feed the runsc DNS probe (no literals)" {
  run grep -F 'box_tool_field muse probe_hosts' "$BUNDLE_DIR/box-m"
  [ "$status" -eq 0 ]
  run grep -F 'box_tool_field opencode probe_hosts' "$BUNDLE_DIR/box-o"
  [ "$status" -eq 0 ]
  run grep -F 'getent hosts $probe_host' "$BUNDLE_DIR/lib/launcher.sh"
  [ "$status" -eq 0 ]
  run grep -F 'timeout "$BOX_DNS_PROBE_TIMEOUT"' "$BUNDLE_DIR/lib/launcher.sh"
  [ "$status" -eq 0 ]
  run grep -F 'missing DNS probe hosts' "$BUNDLE_DIR/lib/launcher.sh"
  [ "$status" -eq 0 ]
}

@test "registry generic-egress host matches the verify harness probe" {
  host=$(box_tool_field opencode probe_hosts)
  [ "$host" = "registry.npmjs.org" ]
  run grep -Fq "$host" "$BUNDLE_DIR/verify.d/30-network-opencode.sh"
  [ "$status" -eq 0 ]
}

@test "registry label pairs feed the image build verify (no literals)" {
  run grep -F 'box_tool_field "$tool" label_pins' "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -eq 0 ]
  run grep -F 'box_tool_field "$tool" pin_keys' "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -eq 0 ]
  # No hardcoded vendor label roots left in the build path.
  run grep -F 'org.meta.muse.box.' "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -ne 0 ]
  run grep -F 'org.opencode.box.' "$BUNDLE_DIR/lib/build.sh"
  [ "$status" -ne 0 ]
}

@test "registry label pairs feed the run-time image assert (no literals)" {
  run grep -F 'box_tool_field "$tool" label_pins' "$BUNDLE_DIR/lib/docker.sh"
  [ "$status" -eq 0 ]
  run grep -F 'box_require_tool "$tool"' "$BUNDLE_DIR/lib/docker.sh"
  [ "$status" -eq 0 ]
  # No hardcoded vendor label roots left in the assert path.
  run grep -F 'org.meta.muse.box.' "$BUNDLE_DIR/lib/docker.sh"
  [ "$status" -ne 0 ]
  run grep -F 'org.opencode.box.' "$BUNDLE_DIR/lib/docker.sh"
  [ "$status" -ne 0 ]
  # Unknown ids fail closed before any daemon contact.
  run box_assert_image some-image:0 some-version some-file bogus 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool id"* ]]
}

@test "image assert resolves integrity labels in one combined inspect" {
  # M2: user+version plus all integrity labels must resolve in 2 daemon
  # calls total (1 user+version inspect + 1 combined label inspect),
  # not 1 per label — with per-key mismatch messages preserved.
  vf="$TEST_TMP/version-muse.env"
  make_muse_version_file "$vf"
  box_load_version_file "$vf" "$(box_tool_field muse version_format)" $(box_tool_field muse pin_keys)
  ver=$box_file_version
  log="$TEST_TMP/inspect-calls.txt"
  payload="$TEST_TMP/inspect-payload.txt"
  : >"$log"
  stub="$TEST_TMP/stub-docker"
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "$*" >>%q\n' "$log"
    printf 'n=$(wc -l <%q)\n' "$log"
    printf 'if [ "$n" -eq 1 ]; then printf "%%s\\n" %q; else cat -- %q; fi\n' \
      "$host_uid:$host_gid|$ver" "$payload"
  } >"$stub"
  chmod +x -- "$stub"
  printf '%s\n' "${box_file_pin[MUSE_SHA256_AMD64]}|${box_file_pin[MUSE_SHA256_ARM64]}" >"$payload"
  docker_cmd=("$stub")
  box_assert_image "some-image:tag" "$ver" "$vf" muse 0
  [ "$(wc -l <"$log")" -eq 2 ]
  second=$(sed -n '2p' -- "$log")
  [[ "$second" == *"org.meta.muse.box.sha256-amd64"* ]]
  [[ "$second" == *"org.meta.muse.box.sha256-arm64"* ]]
  # A mismatch still names the exact label.
  : >"$log"
  printf '%s\n' "${box_file_pin[MUSE_SHA256_AMD64]}|WRONG" >"$payload"
  run box_assert_image "some-image:tag" "$ver" "$vf" muse 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"org.meta.muse.box.sha256-arm64"* ]]
}

@test "registry networks and allowlist feed both launchers (no literals)" {
  run grep -F 'box_tool_field muse network' "$BUNDLE_DIR/box-m"
  [ "$status" -eq 0 ]
  run grep -F 'box_tool_field opencode network' "$BUNDLE_DIR/box-o"
  [ "$status" -eq 0 ]
  run grep -F 'box_tool_field muse forward_keys' "$BUNDLE_DIR/box-m"
  [ "$status" -eq 0 ]
  run grep -F 'box_tool_field opencode forward_keys' "$BUNDLE_DIR/box-o"
  [ "$status" -eq 0 ]
  run grep -F '$BOX_CRED_KEYS' "$BUNDLE_DIR/box-m"
  [ "$status" -eq 0 ]
  run grep -F '$BOX_CRED_KEYS' "$BUNDLE_DIR/box-o"
  [ "$status" -eq 0 ]
  # No hardcoded network/allowlist literals left in the launchers.
  run grep -n 'box_base_args box-m\|box_base_args box-o' \
    "$BUNDLE_DIR/box-m" "$BUNDLE_DIR/box-o"
  [ "$status" -ne 0 ]
  run grep -n 'box_load_credentials "$credentials" "$dry_run" MUSE_CODE_API_KEY' \
    "$BUNDLE_DIR/box-m" "$BUNDLE_DIR/box-o"
  [ "$status" -ne 0 ]
}

@test "config.sh credential allowlist is the single muse key" {
  [ "$BOX_CRED_KEYS" = "MUSE_CODE_API_KEY" ]
}

@test "registry endpoints match settings.json (muse)" {
  model=$(jq -r '.model' -- "$BUNDLE_DIR/settings.json")
  [ "$model" = "$(box_tool_field muse model)" ]
  base=$(jq -r '.api.base_url' -- "$BUNDLE_DIR/settings.json")
  [ "$base" = "$(box_tool_field muse api_base_url)" ]
}

@test "opencode ships no model or provider pins (pure /connect)" {
  # The shipped config is permission-only; auth/model are user-chosen via
  # native /connect, so the registry carries empty model/forward_keys.
  run jq -e 'has("model")' -- "$BUNDLE_DIR/opencode.json"
  [ "$status" -ne 0 ]
  run jq -e 'has("provider")' -- "$BUNDLE_DIR/opencode.json"
  [ "$status" -ne 0 ]
  run box_tool_field opencode model
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run box_tool_field opencode forward_keys
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(box_tool_field opencode pin_model)" = "0" ]
  # The registry base path resolves to the permission pin it cross-checks.
  base_path=$(box_tool_field opencode config_base_path)
  [ "$base_path" = ".permission.external_directory" ]
  [ "$(jq -r "$base_path" -- "$BUNDLE_DIR/opencode.json")" = "ask" ]
}

@test "registry endpoints match the verify harness probes" {
  for host in $(box_tool_field muse probe_hosts); do
    run grep -Fq "$host" "$BUNDLE_DIR/verify.d/30-network-muse.sh"
    [ "$status" -eq 0 ] || { echo "harness misses $host"; return 1; }
  done
  run grep -Fq "$(box_tool_field muse api_base_url)" "$BUNDLE_DIR/verify.d/30-network-muse.sh"
  [ "$status" -eq 0 ]
  # The Meta auth URL has no runtime consumer (only the harness probe), so it
  # lives as a pinned literal here rather than a registry field.
  run grep -Fq 'https://auth.meta.com/' "$BUNDLE_DIR/verify.d/30-network-muse.sh"
  [ "$status" -eq 0 ]
  for host in $(box_tool_field opencode probe_hosts); do
    run grep -Fq "$host" "$BUNDLE_DIR/verify.d/30-network-opencode.sh"
    [ "$status" -eq 0 ] || { echo "harness misses $host"; return 1; }
  done
  run grep -Fq "$(box_tool_field opencode api_base_url)" "$BUNDLE_DIR/verify.d/30-network-opencode.sh"
  [ "$status" -eq 0 ]
  # Opencode ships no model or provider pin: the readiness partial must not
  # reference the retired provider (a value grep here would reintroduce a
  # pin the stripped config cannot satisfy).
  run grep -iq 'bitdeer' "$BUNDLE_DIR/verify.d/40-readiness-opencode.sh"
  [ "$status" -ne 0 ]
  run grep -Fq 'api-inference' "$BUNDLE_DIR/verify.d/40-readiness-opencode.sh"
  [ "$status" -ne 0 ]
  # Muse model is a user-mutable seed default: the readiness partial must
  # shape-check .model, never pin the seed value (a value grep here would
  # forbid in-container /models changes).
  run grep -Fq "$(box_tool_field muse model)" "$BUNDLE_DIR/verify.d/40-readiness-muse.sh"
  [ "$status" -ne 0 ]
}

@test "opencode.json keeps the documented ask-default permission shape" {
  # Rationale (see docs/architecture.md Layer A): inside the outer
  # Docker/gVisor containment the agent needs broad read/edit to work, so the
  # default stays allow; only secret-adjacent and escape-adjacent surfaces
  # are ask. Any change here must be deliberate (regen-validation diffs the
  # effective merged config field-wise).
  run jq -e '.permission."*" == "allow"' -- "$BUNDLE_DIR/opencode.json"
  [ "$status" -eq 0 ]
  run jq -e '.permission.read["*"] == "allow" and .permission.edit["*"] == "allow"' \
    -- "$BUNDLE_DIR/opencode.json"
  [ "$status" -eq 0 ]
  for key in '"*.env"' '"*.env.*"'; do
    run jq -e ".permission.read[$key] == \"ask\" and .permission.edit[$key] == \"ask\"" \
      -- "$BUNDLE_DIR/opencode.json"
    [ "$status" -eq 0 ] || { echo "missing ask for $key"; return 1; }
  done
  run jq -e '.permission.read["*.env.example"] == "allow" and .permission.edit["*.env.example"] == "allow"' \
    -- "$BUNDLE_DIR/opencode.json"
  [ "$status" -eq 0 ]
  run jq -e '.permission.external_directory == "ask"' -- "$BUNDLE_DIR/opencode.json"
  [ "$status" -eq 0 ]
}

@test "opencode.json template exception coexists with the secret ask rules" {
  # `*.env.example` (allow) overlaps `*.env.*` (ask) for names like
  # `foo.env.example`. Static JSON cannot prove upstream matcher precedence,
  # so this pins the coexistence and the live gate stays `opencode debug
  # config` (regen-validation.sh diffs the effective merged config).
  read_ask=$(jq -r '.permission.read["*.env.*"]' -- "$BUNDLE_DIR/opencode.json")
  read_allow=$(jq -r '.permission.read["*.env.example"]' -- "$BUNDLE_DIR/opencode.json")
  [ "$read_ask" = "ask" ]
  [ "$read_allow" = "allow" ]
  edit_ask=$(jq -r '.permission.edit["*.env.*"]' -- "$BUNDLE_DIR/opencode.json")
  edit_allow=$(jq -r '.permission.edit["*.env.example"]' -- "$BUNDLE_DIR/opencode.json")
  [ "$edit_ask" = "ask" ]
  [ "$edit_allow" = "allow" ]
}

@test "containment credential list matches the preflight deny set" {
  # verify.d/50-containment.sh is stdin-deliverable (cannot source
  # lib/preflight.sh), so parity is pinned here behaviorally: every
  # credential dir the preflight actually guards must appear as
  # /home/box/<dir> in the harness absence loop. The count assert makes
  # this a tripwire: adding/dropping a guarded dir fails until both the
  # list below and the harness move together.
  for dir in .ssh .gnupg .aws .docker .git-credentials .netrc .config/gcloud; do
    mkdir -p -- "$HOME/$dir"
  done
  box_preflight_credentials
  [ "${#box_credential_targets[@]}" -eq 7 ]
  real_home=$(realpath -e -- "$HOME")
  for target in "${box_credential_targets[@]}"; do
    case "$target" in "$real_home/"*) : ;; *) echo "credential target outside home: $target"; return 1 ;; esac
    rel=${target#"$real_home"/}
    run grep -Fq "/home/box/$rel" "$BUNDLE_DIR/verify.d/50-containment.sh"
    [ "$status" -eq 0 ] || { echo "containment misses /home/box/$rel"; return 1; }
  done
  # The two legitimate writable config parents are asserted writable in §4
  # and must NOT be in the absence loop (omission by design, not drift).
  # Match only the `for _cred in` line: the comment above it names them.
  cred_line=$(grep -F 'for _cred in' -- "$BUNDLE_DIR/verify.d/50-containment.sh")
  [ -n "$cred_line" ]
  [[ "$cred_line" != *'.config/muse'* ]]
  [[ "$cred_line" != *'.config/opencode'* ]]
}

@test "architecture.md muse settings snippet mirrors settings.json" {
  snippet="$TEST_TMP/snippet.json"
  awk '/^#### Muse Settings/{flag=1} flag && /^```json/{capture=1; next} capture && /^```$/{exit} capture' \
    "$BUNDLE_DIR/docs/architecture.md" >"$snippet"
  [ -s "$snippet" ]
  run diff -- "$snippet" "$BUNDLE_DIR/settings.json"
  [ "$status" -eq 0 ]
}

@test "readiness harness mirrors version pins and muse safety keys" {
  # The harness embeds binary versions as literals and grades the four
  # enforced safety keys; gen-pins.sh --check gates the same contract, and
  # this test names it (see docs/upgrades.md §12 bump checklist).
  unset project
  for id in $box_tool_ids; do
    vkey=$(box_tool_field "$id" pin_keys); vkey=${vkey%% *}
    ver=$(box_print_pin "$BUNDLE_DIR" "$vkey")
    [ -n "$ver" ]
    run grep -Fq -- "$ver" "$BUNDLE_DIR/verify.d/40-readiness-$id.sh"
    [ "$status" -eq 0 ] || { echo "harness misses $vkey $ver"; return 1; }
  done
  seed="$BUNDLE_DIR/settings.json"
  harness="$BUNDLE_DIR/verify.d/40-readiness-muse.sh"
  mode=$(jq -e -r '.approval_mode | strings' -- "$seed")
  run grep -Fq -- ".approval_mode == \"$mode\"" "$harness"
  [ "$status" -eq 0 ]
  judge=$(jq -r '.approval_judge | tostring' -- "$seed")
  run grep -Fq -- ".approval_judge == $judge" "$harness"
  [ "$status" -eq 0 ]
  telemetry=$(jq -r '.telemetry.enabled | tostring' -- "$seed")
  run grep -Fq -- ".telemetry.enabled == $telemetry" "$harness"
  [ "$status" -eq 0 ]
  base=$(jq -e -r '.api.base_url | strings' -- "$seed")
  run grep -Fq -- "$base" "$harness"
  [ "$status" -eq 0 ]
}
