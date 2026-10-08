# auth-migration.bats — journaled migration/copy/init/recover over
# synthetic fixtures. No Docker, no production paths, no secret output.
load helpers

# Explicit daemon fixture: successful liveness queries with no native clients.
docker() { return 0; }

_legacy_codex() {
  local home="$HOME/.config/box-c/projects/$(box_state_project_hash "$project")/codex-home"
  mkdir -p -- "$home"
  printf '%s' "$1" >"$home/auth.json"
  printf '%s/auth.json' "$home"
}

@test "migrate imports legacy file auth and retires the source" {
  legacy=$(_legacy_codex '{"OPENAI_API_KEY":"legacy-1"}')
  BOX_AUTH_SCOPE=global run box_ops_migrate codex "$project"
  [ "$status" -eq 0 ]
  dir=$(BOX_AUTH_SCOPE= BOX_C_AUTH_SCOPE= box_auth_object_dir codex global "$host_uid")
  jq -e '.tombstone == false' -- "$dir/credentials.json" >/dev/null
  [ -f "$dir/migration.json" ]
  [ -f "$dir/rollback-credentials.json" ]
  jq -e '.stage == "complete"' -- "$dir/migration-journal.json" >/dev/null
  [ ! -e "$legacy" ]
  [ -f "$dir/legacy-auth-rollback.json" ]
}

@test "migrate refuses a conflicting non-empty destination" {
  _legacy_codex '{"OPENAI_API_KEY":"legacy-new"}' >/dev/null
  dir=$(box_auth_object_dir codex global "$host_uid")
  box_auth_ensure_object "$dir" codex global "$host_uid" "$(box_state_project_hash "$project")" >/dev/null
  python3 -I - "$dir/credentials.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    doc = json.load(f)
doc.update({"tombstone": False, "payload": {"OPENAI_API_KEY": "existing"}, "revision": 3})
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f)
PY
  BOX_AUTH_SCOPE=global run box_ops_migrate codex "$project"
  [ "$status" -ne 0 ]
  [[ "$output" == *"conflict"* ]]
}

@test "init acknowledges a fresh identity without importing" {
  run box_ops_init opencode "$project"
  [ "$status" -eq 0 ]
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir opencode project "$host_uid" "$h")
  jq -e '.tombstone == true' -- "$dir/credentials.json" >/dev/null
  [ -f "$dir/migration.json" ]
}

@test "copy moves one explicit identity without merging" {
  h=$(box_state_project_hash "$project")
  src=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$src" codex project "$host_uid" "$h" >/dev/null
  python3 -I - "$src/credentials.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    doc = json.load(f)
doc.update({"tombstone": False, "payload": {"OPENAI_API_KEY": "src-acct"}, "revision": 5})
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f)
PY
  dst=$(box_auth_object_dir codex global "$host_uid")
  box_auth_ensure_object "$dst" codex global "$host_uid" "$h" >/dev/null
  box_auth_transition_plan codex "$host_uid" "$h" "$project"
  BOX_AUTH_SCOPE=global run box_ops_copy codex project "$h" global "" --project "$project"
  [ "$status" -eq 0 ]
  BOX_AUTH_SCOPE=global run box_auth_transition_plan codex "$host_uid" "$h" "$project"
  [ "$status" -eq 0 ]
  jq -e '.payload.OPENAI_API_KEY == "src-acct"' -- "$dst/credentials.json" >/dev/null
  # Source preserved; no merge: destination holds exactly the source payload.
  jq -e '.payload.OPENAI_API_KEY == "src-acct"' -- "$src/credentials.json" >/dev/null
  # Second copy over a differing destination refuses instead of merging.
  python3 -I - "$dst/credentials.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    doc = json.load(f)
doc["payload"] = {"OPENAI_API_KEY": "someone-else"}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f)
PY
  run box_ops_copy codex project "$h" global ""
  [ "$status" -ne 0 ]
}

@test "recover collects an interrupted projection and releases the lease" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h" >/dev/null
  native="$TEST_TMP/native-auth.json"
  printf '{"OPENAI_API_KEY":"rotated"}' >"$native"
  proj_lock="$TEST_TMP/rec.lock"
  box_auth_lease_reserve "$dir" "$proj_lock" "$native"
  box_supervisor_phase "$dir" projected
  # Model a dead launcher: reservation metadata remains, kernel locks do not.
  exec {BOX_AUTH_FD}>&-
  exec {BOX_AUTH_PROJ_FD}>&-
  box_auth_release_stable_locks
  docker() { return 0; }
  export -f docker
  run box_ops_recover codex "$project" --native "$native"
  [ "$status" -eq 0 ]
  jq -e '.payload.OPENAI_API_KEY == "rotated"' -- "$dir/credentials.json" >/dev/null
  [ ! -e "$native" ]
  jq -e '.state == "idle"' -- "$dir/lease.json" >/dev/null
}

@test "opencode migrates through an explicit db export" {
  db="$TEST_TMP/opencode.db"
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" install --db "$db" --envelope /dev/null 2>/dev/null || true
  python3 -I - "$db" <<'PY'
import sqlite3
con = sqlite3.connect(__import__("sys").argv[1])
con.execute("PRAGMA journal_mode=WAL;")
con.execute('CREATE TABLE IF NOT EXISTS "credential" ("id" TEXT PRIMARY KEY, "integration_id" TEXT NOT NULL, "label" TEXT NOT NULL DEFAULT "fixture", "value" TEXT NOT NULL, "method_id" TEXT, "connector_id" TEXT, "time_created" INTEGER NOT NULL DEFAULT 1, "time_updated" INTEGER NOT NULL DEFAULT 1, "active" INTEGER DEFAULT 0)')
con.execute('INSERT OR REPLACE INTO "credential" ("id","integration_id","value") VALUES (?,?,?)', ("cred-1", "openai", '{"type":"key","key":"k1"}'))
con.commit(); con.close()
PY
  run box_ops_migrate opencode "$project" --db-path "$db"
  [ "$status" -eq 0 ]
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir opencode project "$host_uid" "$h")
  jq -e '.payload.credentials[0].id == "cred-1"' -- "$dir/credentials.json" >/dev/null
}

@test "recovery completes source retirement with a raw file rollback" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  legacy="$TEST_TMP/retired.json"
  printf '{"OPENAI_API_KEY":"retired"}' >"$legacy"
  source "$BUNDLE_DIR/harnesses/codex/auth.sh"
  box_adapter_export "$legacy" "$TEST_TMP/staged.json"
  box_ops_publish_envelope "$TEST_TMP/staged.json" "$dir"
  box_adapter_retire "$legacy" "$dir/legacy-auth-rollback.json"
  box_ops_write_journal "$dir" verified "$legacy" "$dir"
  docker() { return 0; }
  export -f docker
  run box_ops_recover codex "$project"
  [ "$status" -eq 0 ]
  jq -e '.payload.OPENAI_API_KEY == "retired"' "$dir/credentials.json"
  jq -e '.stage == "complete"' "$dir/migration-journal.json"
}

@test "recovery preserves committed refresh after projection scrub" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  native="$TEST_TMP/scrubbed.json"
  printf '{"state":"active","projection":"%s","projection_lock":"%s"}\n' "$native" "$TEST_TMP/projection.lock" >"$dir/lease.json"
  printf '{"schema_version":1,"harness":"codex","adapter_schema":1,"revision":2,"tombstone":false,"payload":{"OPENAI_API_KEY":"refreshed"}}' >"$dir/collection-pending.json"
  chmod 600 "$dir/collection-pending.json"
  docker() { return 0; }
  export -f docker
  run box_ops_recover codex "$project"
  [ "$status" -eq 0 ]
  jq -e '.payload.OPENAI_API_KEY == "refreshed"' "$dir/credentials.json"
  [ ! -e "$dir/collection-pending.json" ]
  jq -e '.state == "idle"' "$dir/lease.json"
}

@test "unsupported pending collection preserves canonical revision and active lease" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  native="$TEST_TMP/native.json"
  printf '{"state":"active","projection":"%s","projection_lock":"%s"}\n' "$native" "$TEST_TMP/recovery.lock" >"$dir/lease.json"
  printf '{"schema_version":1,"harness":"codex","adapter_schema":1,"revision":2,"tombstone":false,"payload":{"unknown":"secret"}}' >"$dir/collection-pending.json"
  chmod 600 "$dir/collection-pending.json"
  before=$(sha256sum "$dir/credentials.json")
  docker() { return 0; }
  export -f docker
  run box_ops_recover codex "$project"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$dir/credentials.json")" = "$before" ]
  [ -f "$dir/collection-pending.json" ]
  jq -e '.state == "active"' "$dir/lease.json"
}

@test "differing destination refuses copy before changing any destination file" {
  h=$(box_state_project_hash "$project")
  src=$(box_auth_object_dir codex project "$host_uid" "$h")
  dst=$(box_auth_object_dir codex global "$host_uid")
  box_auth_ensure_object "$src" codex project "$host_uid" "$h"
  box_auth_ensure_object "$dst" codex global "$host_uid" "$h"
  source "$BUNDLE_DIR/harnesses/codex/auth.sh"
  printf '{"OPENAI_API_KEY":"synthetic-source"}' >"$TEST_TMP/source-auth"
  printf '{"OPENAI_API_KEY":"synthetic-destination"}' >"$TEST_TMP/destination-auth"
  box_adapter_export "$TEST_TMP/source-auth" "$src/credentials.json"
  box_adapter_export "$TEST_TMP/destination-auth" "$dst/credentials.json"
  before=$(sha256sum "$dst/"*)
  run box_ops_copy codex project "$h" global ''
  [ "$status" -ne 0 ]
  [ "$before" = "$(sha256sum "$dst/"*)" ]
  [ ! -e "$dst/migration-journal.json" ]
  [ ! -e "$dst/rollback-credentials.json" ]
}

@test "failed liveness query refuses migration before source inspection or retirement" {
  legacy=$(_legacy_codex '{"OPENAI_API_KEY":"synthetic-retained"}')
  before=$(sha256sum "$legacy")
  docker() { return 1; }
  run box_ops_migrate codex "$project"
  [ "$status" -ne 0 ]
  [[ "$output" == *"liveness"* ]]
  [ "$before" = "$(sha256sum "$legacy")" ]
}

@test "missing prepared projection cannot silently become a recovered logout" {
  h=$(box_state_project_hash "$project")
  dir=$(box_auth_object_dir codex project "$host_uid" "$h")
  box_auth_ensure_object "$dir" codex project "$host_uid" "$h"
  native="$HOME/missing-native.json"
  box_auth_lease_reserve "$dir" "$HOME/projection.lock" "$native"
  box_supervisor_phase "$dir" projected
  exec {BOX_AUTH_FD}>&-
  exec {BOX_AUTH_PROJ_FD}>&-
  box_auth_release_stable_locks
  unset BOX_AUTH_FD BOX_AUTH_PROJ_FD
  before=$(sha256sum "$dir/credentials.json")
  run box_ops_recover codex "$project"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing projection"* ]]
  [ "$before" = "$(sha256sum "$dir/credentials.json")" ]
  jq -e '.state == "active"' "$dir/lease.json"
}
