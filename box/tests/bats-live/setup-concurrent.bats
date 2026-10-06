# setup-concurrent.bats — live-daemon concurrent-install test (make
# test-live only, never verify-static: runs two real setup.sh installs and
# needs a reachable Docker Engine).
load ../bats/helpers

@test "concurrent setup preserves a consistent installed package" {
  command -v docker >/dev/null || skip 'no docker binary'
  box_docker_cli "$TEST_TMP/docker-cli"
  "${docker_cmd[@]}" info >/dev/null 2>&1 || skip 'local Docker Engine unavailable'
  bash "$BUNDLE_DIR/setup.sh" --skip-build > "$TEST_TMP/setup-first.log" 2>&1 &
  first=$!
  bash "$BUNDLE_DIR/setup.sh" --skip-build > "$TEST_TMP/setup-second.log" 2>&1 &
  second=$!
  wait "$first" && first_rc=0 || first_rc=$?
  wait "$second" && second_rc=0 || second_rc=$?
  if (( first_rc != 0 || second_rc != 0 )); then
    cat "$TEST_TMP/setup-first.log" "$TEST_TMP/setup-second.log" >&2
  fi
  [ "$first_rc" -eq 0 ]
  [ "$second_rc" -eq 0 ]
  for lib in "$BUNDLE_DIR"/lib/*.sh; do cmp "$lib" "$HOME/.local/bin/lib/${lib##*/}"; done
  for id in $box_tool_ids; do
    launcher=$(box_tool_field "$id" launcher)
    cmp "$BUNDLE_DIR/$launcher" "$HOME/.local/bin/$launcher"
    pin=$(box_tool_field "$id" version_file)
    cmp "$BUNDLE_DIR/$(box_tool_field "$id" version_source)" "$HOME/.config/$(box_tool_field "$id" config_dir)/$pin"
  done
  [ ! -s "$HOME/.config/box/providers.env" ]
}
