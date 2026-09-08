# extra-gids.bats — box_extra_gids (opt-in supplementary groups).
load helpers

@test "extra-gids appends --group-add flags" {
  BOX_M_EXTRA_GIDS='100,200'
  export BOX_M_EXTRA_GIDS
  args=()
  box_extra_gids BOX_M_EXTRA_GIDS
  [ "${args[0]}" = "--group-add" ]
  [ "${args[1]}" = "100" ]
  [ "${args[2]}" = "--group-add" ]
  [ "${args[3]}" = "200" ]
}

@test "extra-gids is a no-op when unset" {
  unset BOX_M_EXTRA_GIDS || true
  args=(--sentinel)
  box_extra_gids BOX_M_EXTRA_GIDS
  [ "${#args[@]}" -eq 1 ]
}

@test "extra-gids rejects GID 0" {
  BOX_M_EXTRA_GIDS='0'
  export BOX_M_EXTRA_GIDS
  args=()
  run box_extra_gids BOX_M_EXTRA_GIDS
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not include GID 0"* ]]
}

@test "extra-gids rejects GID 0 inside a list" {
  BOX_M_EXTRA_GIDS='100,0,200'
  export BOX_M_EXTRA_GIDS
  args=()
  run box_extra_gids BOX_M_EXTRA_GIDS
  [ "$status" -ne 0 ]
}

@test "extra-gids rejects non-numeric input" {
  BOX_M_EXTRA_GIDS='abc'
  export BOX_M_EXTRA_GIDS
  args=()
  run box_extra_gids BOX_M_EXTRA_GIDS
  [ "$status" -ne 0 ]
  [[ "$output" == *"comma-separated numeric GIDs"* ]]
}

@test "extra-gids rejects empty elements" {
  BOX_M_EXTRA_GIDS='100,,200'
  export BOX_M_EXTRA_GIDS
  args=()
  run box_extra_gids BOX_M_EXTRA_GIDS
  [ "$status" -ne 0 ]
}

@test "extra-gids rejects out-of-range GIDs" {
  BOX_M_EXTRA_GIDS='4294967295'
  export BOX_M_EXTRA_GIDS
  args=()
  run box_extra_gids BOX_M_EXTRA_GIDS
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of range"* ]]
  BOX_M_EXTRA_GIDS='4294967294'
  export BOX_M_EXTRA_GIDS
  args=()
  box_extra_gids BOX_M_EXTRA_GIDS
  [ "${args[1]}" = "4294967294" ]
}
