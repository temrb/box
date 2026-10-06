# network.bats — live-daemon network/DNS tests (make test-live only, never
# verify-static: these create/remove real Docker networks and run probe
# containers whenever a daemon is reachable).
load ../bats/helpers

@test "ensure_network creates then verifies (live daemon)" {
  if ! docker info >/dev/null 2>&1; then skip "no reachable docker daemon"; fi
  box_docker_cli "$TEST_TMP/docker-cli"
  net="box-bats-$$"
  docker network rm -- "$net" >/dev/null 2>&1 || true
  result=$(box_ensure_network "$net" "${docker_cmd[@]}")
  [ "$result" = "created" ]
  result=$(box_ensure_network "$net" "${docker_cmd[@]}")
  [ "$result" = "verified" ]
  docker network rm -- "$net" >/dev/null
}

@test "ensure_network fails closed on wrong policy (live daemon)" {
  if ! docker info >/dev/null 2>&1; then skip "no reachable docker daemon"; fi
  box_docker_cli "$TEST_TMP/docker-cli"
  net="box-bats-policy-$$"
  docker network rm -- "$net" >/dev/null 2>&1 || true
  # Default bridge options violate the sandbox policy (icc enabled).
  "${docker_cmd[@]}" network create --driver=bridge -- "$net" >/dev/null
  run box_ensure_network "$net" "${docker_cmd[@]}"
  [ "$status" -ne 0 ]
  docker network rm -- "$net" >/dev/null
}

@test "dns probe fails closed on missing image (live daemon)" {
  if ! docker info >/dev/null 2>&1; then skip "no reachable docker daemon"; fi
  box_docker_cli "$TEST_TMP/docker-cli"
  run box_probe_runsc_dns "box-bats-no-such-image:0" box-m example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"build it first"* ]]
}
