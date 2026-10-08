load helpers

volume_auth_fixture() {
  hash=$(box_state_project_hash "$project")
  auth_dir=$(box_auth_object_dir opencode project "$host_uid" "$hash")
  box_auth_ensure_object "$auth_dir" opencode project "$host_uid" "$hash"
  fixture_volume=$(box_state_volume_name opencode "$host_uid" "$host_gid" "$hash")
  db="$TEST_TMP/volume/data/opencode/opencode.db"
  sidecar="$TEST_TMP/volume/state/opencode/selection.json"
  mkdir -p -m 700 "${db%/*}" "${sidecar%/*}"
  python3 -I - "$db" <<'PY'
import os, sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE credential (id TEXT PRIMARY KEY, integration_id TEXT NOT NULL, label TEXT NOT NULL, value TEXT NOT NULL, method_id TEXT, connector_id TEXT, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, active INTEGER NOT NULL)')
con.execute('INSERT INTO credential VALUES (?,?,?,?,?,?,?,?,?)', ('fixture', 'openai', 'Synthetic', '{"type":"key","key":"synthetic"}', None, None, 1, 1, 1))
con.execute('CREATE TABLE unrelated (id TEXT PRIMARY KEY, body TEXT NOT NULL)')
con.execute('INSERT INTO unrelated VALUES (?,?)', ('session', 'retained'))
con.commit()
con.close()
os.chmod(sys.argv[1], 0o600)
PY
  box_auth_lease_reserve "$auth_dir" "$TEST_TMP/volume.lock" "volume:$fixture_volume"
}

volume_auth_operation() {
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-volume.py" "$1" --auth-dir "$auth_dir" \
    --db "$db" --source "volume:$fixture_volume" --host-auth-dir "$auth_dir" --sidecar "$sidecar"
}

@test "contained migration scrubs actual auth rows, preserves unrelated rows and selection, and keeps auth-only rollback" {
  volume_auth_fixture
  run volume_auth_operation migrate
  [ "$status" -eq 0 ]
  jq -e '.payload.credentials[0].value == "{\"type\":\"key\",\"key\":\"synthetic\"}"' "$auth_dir/credentials.json"
  jq -e '.stage == "complete"' "$auth_dir/migration-journal.json"
  jq -e '.state == "idle"' "$auth_dir/lease.json"
  [ -f "$sidecar" ]
  [ -f "$auth_dir/legacy-auth-rollback.json" ]
  run python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
assert con.execute('SELECT COUNT(*) FROM credential').fetchone()[0] == 0
assert con.execute('SELECT body FROM unrelated').fetchone()[0] == 'retained'
PY
  [ "$status" -eq 0 ]
}

@test "contained migration recovers every journal and publication boundary without stale tombstones" {
  for stage in preparing stage-published planned staged canonical-published destination-committed verified native-scrubbed source-retired complete; do
    volume_auth_fixture
    BOX_AUTH_VOLUME_FAULT=$stage run volume_auth_operation migrate
    [ "$status" -ne 0 ]
    run volume_auth_operation recover
    [ "$status" -eq 0 ]
    jq -e '.tombstone == false and .payload.credentials[0].id == "fixture"' "$auth_dir/credentials.json"
    jq -e '.state == "idle"' "$auth_dir/lease.json"
    [ ! -e "$auth_dir/migration-staged.json" ]
    # End this synthetic reservation and remove only its exact fixture objects.
    exec {BOX_AUTH_FD}>&-
    exec {BOX_AUTH_PROJ_FD}>&-
    box_auth_release_stable_locks
    unset BOX_AUTH_FD BOX_AUTH_PROJ_FD
    rm -rf -- "$auth_dir" "$TEST_TMP/volume"
  done
}

@test "contained recovery collects rotation-shaped writes from the native database before scrubbing" {
  volume_auth_fixture
  box_supervisor_phase "$auth_dir" projected
  run volume_auth_operation recover
  [ "$status" -eq 0 ]
  jq -e '.tombstone == false' "$auth_dir/credentials.json"
  jq -e '.state == "idle"' "$auth_dir/lease.json"
}

@test "contained migration rejects conflicting canonical auth and preserves source and destination bytes" {
  volume_auth_fixture
  python3 -I - "$auth_dir/credentials.json" <<'PY'
import json, sys
p=sys.argv[1]
d=json.load(open(p)); d['tombstone']=False
d['payload']={'credentials':[{'id':'other','integration_id':'openai','label':'Synthetic','value':'{"type":"key","key":"other"}','method_id':None,'connector_id':None,'time_created':1,'time_updated':1}]}
with open(p,'w') as f: json.dump(d,f)
PY
  before=$(sha256sum "$db" "$auth_dir/credentials.json")
  run volume_auth_operation migrate
  [ "$status" -ne 0 ]
  [ "$before" = "$(sha256sum "$db" "$auth_dir/credentials.json")" ]
  [ ! -e "$auth_dir/migration-journal.json" ]
}

@test "host migration opens the exact resolved volume through the contained adapter without a database path" {
  volume_auth_fixture
  box_auth_lease_release "$auth_dir"
  mkdir -p -m 700 "$HOME/.config/box-o" "$TEST_TMP/bin"
  cp "$BUNDLE_DIR/harnesses/opencode/version-opencode.env" "$HOME/.config/box-o/version-opencode.env"
  export FAKE_VOLUME="$fixture_volume" FAKE_DB="$db" FAKE_SIDECAR="$sidecar" FAKE_AUTH_DIR="$auth_dir"
  export FAKE_VOLUME_HELPER="$BUNDLE_DIR/harnesses/opencode/auth-volume.py" FAKE_DOCKER_ARGS="$TEST_TMP/docker-args"
  cat >"$TEST_TMP/bin/docker" <<'DOCKER'
#!/bin/bash
while [[ "$1" == --config || "$1" == --host ]]; do shift 2; done
case "$1 $2" in
  'ps -q') exit 0 ;;
  'volume ls') printf '%s\n' "$FAKE_VOLUME" ;;
  'run --rm')
    printf '%s\n' "$@" >"$FAKE_DOCKER_ARGS"
    found=0
    for arg in "$@"; do [[ "$arg" != "type=volume,src=$FAKE_VOLUME,dst=/persist" ]] || found=1; done
    ((found)) || exit 2
    exec python3 -I "$FAKE_VOLUME_HELPER" migrate --auth-dir "$FAKE_AUTH_DIR" --db "$FAKE_DB" --source "volume:$FAKE_VOLUME" --host-auth-dir "$FAKE_AUTH_DIR" --sidecar "$FAKE_SIDECAR"
    ;;
  *) exit 1 ;;
esac
DOCKER
  chmod 755 "$TEST_TMP/bin/docker"
  export PATH="$TEST_TMP/bin:$PATH"
  # Image/Engine assertions have their own fixture classes. This case runs
  # the actual contained adapter against a volume-backed synthetic database.
  box_assert_engine() { :; }
  box_assert_runtime() { :; }
  box_assert_image() { :; }
  run box_ops_migrate opencode "$project"
  [ "$status" -eq 0 ]
  [ -f "$FAKE_DOCKER_ARGS" ]
  jq -e '.tombstone == false' "$auth_dir/credentials.json"
  [[ "$(cat "$FAKE_DOCKER_ARGS")" == *"--network"$'\n'"none"* ]]
  [[ "$(cat "$FAKE_DOCKER_ARGS")" == *"bind-recursive=disabled,bind-propagation=rprivate"* ]]
}
