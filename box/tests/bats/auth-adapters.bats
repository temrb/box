# auth-adapters.bats — pinned adapter contracts over synthetic fixtures:
# file import/export/logout/refresh, SQLite auth-only projection, and
# mixed-store exclusions. No Docker, no network, no real credentials.
load helpers

_make_opencode_database() {
  python3 -I - "$1" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE credential (id TEXT PRIMARY KEY, integration_id TEXT, label TEXT, value TEXT, method_id TEXT, connector_id TEXT, time_created INTEGER, time_updated INTEGER, active INTEGER)')
for ident, integration in (("one", "provider-a"), ("two", "mcp-endpoint-b")):
    con.execute('INSERT INTO credential VALUES (?, ?, ?, ?, NULL, NULL, 1, 1, 1)',
                (ident, integration, "fixture", '{"type":"key","key":"synthetic"}'))
con.commit(); con.close()
PY
}

@test "opencode validation rejection preserves database bytes and journal mode" {
  db="$TEST_TMP/rejected.db"
  _make_opencode_database "$db"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE unknown_oauth (id TEXT, refresh_token TEXT)')
con.commit(); con.close()
PY
  before=$(sha256sum "$db")
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" validate --db "$db"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$db")" = "$before" ]
  [ ! -e "$db-wal" ]
  [ ! -e "$db-shm" ]
}

@test "opencode rejects redirected WAL and unsupported payload before export" {
  db="$TEST_TMP/rejected.db"
  _make_opencode_database "$db"
  printf 'foreign bytes' >"$TEST_TMP/foreign"
  ln -s "$TEST_TMP/foreign" "$db-wal"
  before=$(sha256sum "$db" "$TEST_TMP/foreign")
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" validate --db "$db"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$db" "$TEST_TMP/foreign")" = "$before" ]
  rm "$db-wal"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('UPDATE credential SET value=?', ('{"type":"oauth","refresh":"unknown"}',))
con.commit(); con.close()
PY
  printf 'prior envelope' >"$TEST_TMP/envelope"
  before=$(sha256sum "$db" "$TEST_TMP/envelope")
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" export --db "$db" --out "$TEST_TMP/envelope"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$db" "$TEST_TMP/envelope")" = "$before" ]
  [ ! -e "$db-wal" ]
}

@test "opencode selections preserve every integration and ignore a redirected temporary sidecar" {
  db="$TEST_TMP/selections.db"
  sidecar="$TEST_TMP/selection.json"
  _make_opencode_database "$db"
  printf 'foreign bytes' >"$TEST_TMP/foreign"
  ln -s "$TEST_TMP/foreign" "$sidecar.tmp"
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" save-selection --db "$db" --sidecar "$sidecar" --auth-id shared
  jq -e '.shared.credentials == {"provider-a":"one", "mcp-endpoint-b":"two"}' "$sidecar"
  [ "$(cat "$TEST_TMP/foreign")" = 'foreign bytes' ]
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('UPDATE credential SET active=0')
con.commit(); con.close()
PY
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" restore-selection --db "$db" --sidecar "$sidecar" --auth-id shared
  [ "$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM credential WHERE active=1").fetchone()[0])' "$db")" = 2 ]
}

@test "opencode multiple unselected credentials require a choice before a model run" {
  db="$TEST_TMP/choice.db"
  _make_opencode_database "$db"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as c:
    c.execute('INSERT INTO credential VALUES (?, ?, ?, ?, NULL, NULL, 1, 1, 0)',
              ('three','provider-a','fixture','{"type":"key","key":"synthetic-third"}'))
    c.execute('UPDATE credential SET active=0')
PY
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" require-selection --db "$db"
  [ "$status" -ne 0 ]
  [[ "$output" == *'explicit selection'* ]]
  python3 -I - "$db" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as c:
    c.execute('UPDATE credential SET active=1 WHERE id=?', ('one',))
PY
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" require-selection --db "$db"
  [ "$status" -eq 0 ]
}

@test "muse file adapter round-trips and tombstones logout" {
  source "$BUNDLE_DIR/harnesses/muse/auth.sh"
  native="$TEST_TMP/muse-auth.json"
  out="$TEST_TMP/muse-env.json"
  rm -f -- "$native"
  box_adapter_export "$native" "$out"
  jq -e '.tombstone == true and .payload == null' -- "$out" >/dev/null
  printf '%s' '{"schema_version":1,"providers":{"meta":{"api_key":"synthetic"}}}' >"$native"
  box_adapter_export "$native" "$out"
  jq -e '.tombstone == false and .payload.providers.meta.api_key == "synthetic"' -- "$out" >/dev/null
  box_adapter_install "$out" "$native"
  printf '{"unknown":"credential"}' >"$native"
  run box_adapter_collect "$native" "$out"
  [ "$status" -ne 0 ]
  jq -e '.payload.providers.meta.api_key == "synthetic"' "$out" >/dev/null
  # Logout (native removal) exports a tombstone; scrub removes the file.
  rm -f -- "$native"
  box_adapter_collect "$native" "$out"
  jq -e '.tombstone == true' -- "$out" >/dev/null
  printf '{"tok":"x"}' >"$native"
  box_adapter_scrub "$native"
  [ ! -e "$native" ]
  # Trust/settings siblings are never touched by the adapter.
  printf '{"trust":true}' >"$TEST_TMP/muse-trust.json"
  box_adapter_export "$native" "$out" || true
  [ "$(cat -- "$TEST_TMP/muse-trust.json")" = '{"trust":true}' ]
}

@test "codex file adapter rejects malformed auth" {
  source "$BUNDLE_DIR/harnesses/codex/auth.sh"
  native="$TEST_TMP/codex-auth.json"
  out="$TEST_TMP/codex-env.json"
  printf 'not-json{' >"$native"
  run box_adapter_export "$native" "$out"
  [ "$status" -ne 0 ]
  printf '{"tok":"ok"}' >"$native"
  ln -sf "$native" "$TEST_TMP/codex-link.json"
  run box_adapter_validate "$TEST_TMP/codex-link.json"
  [ "$status" -ne 0 ]
}

@test "opencode sqlite adapter exports auth only and scrubs auth only" {
  db="$TEST_TMP/oc.db"
  out="$TEST_TMP/oc-env.json"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("PRAGMA journal_mode=WAL;")
con.execute('CREATE TABLE "credential" ("id" TEXT PRIMARY KEY, "integration_id" TEXT NOT NULL, "label" TEXT NOT NULL DEFAULT "fixture", "value" TEXT NOT NULL, "method_id" TEXT, "connector_id" TEXT, "time_created" INTEGER NOT NULL DEFAULT 1, "time_updated" INTEGER NOT NULL DEFAULT 1, "active" INTEGER DEFAULT 0)')
con.execute('CREATE TABLE "session" ("id" TEXT PRIMARY KEY, "title" TEXT)')
con.execute('CREATE TABLE "approval" ("id" TEXT PRIMARY KEY, "granted" INTEGER)')
con.execute('INSERT INTO "credential" ("id","integration_id","value","active") VALUES (?,?,?,?)', ("c1", "openai", '{"type":"key","key":"v1"}', 1))
con.execute('INSERT INTO "credential" ("id","integration_id","value","active") VALUES (?,?,?,?)', ("c2", "gh", '{"type":"key","key":"v2"}', 0))
con.execute('INSERT INTO "session" ("id","title") VALUES (?,?)', ("s1", "keep me"))
con.execute('INSERT INTO "approval" ("id","granted") VALUES (?,?)', ("a1", 1))
con.commit(); con.close()
PY
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" export --db "$db" --out "$out"
  jq -e '.tombstone == false and (.payload.credentials | length) == 2' -- "$out" >/dev/null
  # Sessions/approvals never appear in the envelope.
  [[ "$(cat -- "$out")" != *"keep me"* ]]
  # Install replaces the credential set; selection restores separately.
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" scrub --db "$db"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute('SELECT COUNT(*) FROM "credential"').fetchone()[0])
print(con.execute('SELECT title FROM "session"').fetchone()[0])
PY
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" install --db "$db" --envelope "$out"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
assert con.execute('SELECT COUNT(*) FROM "credential"').fetchone()[0] == 2
assert con.execute('SELECT title FROM "session"').fetchone()[0] == "keep me"
assert con.execute('SELECT COUNT(*) FROM "approval"').fetchone()[0] == 1
PY
}

@test "opencode selection sidecar is keyed by auth identity" {
  db="$TEST_TMP/oc-sel.db"
  sidecar="$TEST_TMP/box-auth-selection.json"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE "credential" ("id" TEXT PRIMARY KEY, "integration_id" TEXT NOT NULL, "value" TEXT NOT NULL, "label" TEXT NOT NULL DEFAULT "fixture", "method_id" TEXT, "connector_id" TEXT, "time_created" INTEGER NOT NULL DEFAULT 1, "time_updated" INTEGER NOT NULL DEFAULT 1, "active" INTEGER DEFAULT 0)')
con.execute('INSERT INTO "credential" (id,integration_id,value,active) VALUES (?,?,?,?)', ("c1", "openai", '{"type":"key","key":"fixture-1"}', 1))
con.execute('INSERT INTO "credential" (id,integration_id,value,active) VALUES (?,?,?,?)', ("c2", "gh", '{"type":"key","key":"fixture-2"}', 0))
con.commit(); con.close()
PY
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" save-selection --db "$db" --sidecar "$sidecar" --auth-id scope-A
  [ "$(jq -r '."scope-A".credentials.openai' -- "$sidecar")" = "c1" ]
  # Saving another identity records its current selection independently.
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" save-selection --db "$db" --sidecar "$sidecar" --auth-id scope-B
  [ "$(jq -r '."scope-B".credentials.openai' -- "$sidecar")" = "c1" ]
  # Restoring a missing credential leaves the database unselected.
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('DELETE FROM "credential" WHERE "id"="c1"')
con.execute('UPDATE "credential" SET "active"=0')
con.commit(); con.close()
PY
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" restore-selection --db "$db" --sidecar "$sidecar" --auth-id scope-A
  [ "$(python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM \"credential\" WHERE \"active\"=1").fetchone()[0])' "$db")" = "0" ]
}

@test "opencode account tokens follow auth while account and org selection stays per project" {
  db="$TEST_TMP/account.db"
  out="$TEST_TMP/account-envelope.json"
  sidecar="$TEST_TMP/account-selection.json"
  _make_opencode_database "$db"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as c:
    c.execute('CREATE TABLE account (id TEXT PRIMARY KEY, email TEXT NOT NULL, url TEXT NOT NULL, access_token TEXT NOT NULL, refresh_token TEXT NOT NULL, token_expiry INTEGER, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL)')
    c.execute('CREATE TABLE control_account (email TEXT NOT NULL, url TEXT NOT NULL, access_token TEXT NOT NULL, refresh_token TEXT NOT NULL, token_expiry INTEGER, active INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, PRIMARY KEY(email,url))')
    c.execute('CREATE TABLE account_state (id INTEGER PRIMARY KEY, active_account_id TEXT REFERENCES account(id) ON DELETE SET NULL, active_org_id TEXT)')
    c.execute('CREATE TABLE session_marker (id TEXT PRIMARY KEY, body TEXT)')
    c.execute('INSERT INTO session_marker VALUES (?,?)', ('session','retained'))
    c.execute('INSERT INTO account VALUES (?,?,?,?,?,?,?,?)', ('account','fixture@example.invalid','https://fixture.invalid','synthetic-access','synthetic-refresh',None,1,1))
    c.execute('INSERT INTO control_account VALUES (?,?,?,?,?,?,?,?)', ('legacy@example.invalid','https://fixture.invalid','synthetic-access','synthetic-refresh',None,1,1,1))
    c.execute('INSERT INTO account_state VALUES (?,?,?)', (0,'account','org'))
PY
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" save-selection --db "$db" --sidecar "$sidecar" --auth-id project-a
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" export --db "$db" --out "$out"
  jq -e '.payload.accounts[0].refresh_token == "synthetic-refresh" and (.payload.control_accounts[0] | has("active") | not)' "$out"
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" scrub --db "$db"
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" install --db "$db" --envelope "$out"
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" restore-selection --db "$db" --sidecar "$sidecar" --auth-id new-project
  python3 -I - "$db" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as c:
    assert c.execute('SELECT active_account_id,active_org_id FROM account_state').fetchone() == (None,None)
    assert c.execute('SELECT active FROM control_account').fetchone()[0] == 0
    assert c.execute('SELECT body FROM session_marker').fetchone()[0] == 'retained'
PY
  python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" restore-selection --db "$db" --sidecar "$sidecar" --auth-id project-a
  python3 -I - "$db" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as c:
    assert c.execute('SELECT active_account_id,active_org_id FROM account_state').fetchone() == ('account','org')
    assert c.execute('SELECT active FROM control_account').fetchone()[0] == 1
    assert c.execute('SELECT body FROM session_marker').fetchone()[0] == 'retained'
PY
}

@test "opencode adapter rejects unknown schema and payload" {
  db="$TEST_TMP/oc-bad.db"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE "other" ("id" TEXT PRIMARY KEY)')
con.commit(); con.close()
PY
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" validate --db "$db"
  [ "$status" -ne 0 ]
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" install --db "$TEST_TMP/oc-fresh.db" --envelope /dev/null
  [ "$status" -ne 0 ]
}

@test "file adapters reject keychain pointers explicitly" {
  source "$BUNDLE_DIR/harnesses/muse/auth.sh"
  native="$TEST_TMP/muse-keychain.json"
  printf '{"keychain":"pointer","tok":"x"}' >"$native"
  run box_adapter_validate "$native"
  [ "$status" -ne 0 ]
  source "$BUNDLE_DIR/harnesses/codex/auth.sh"
  native="$TEST_TMP/codex-keyring.json"
  printf '{"keyring":"pointer"}' >"$native"
  run box_adapter_validate "$native"
  [ "$status" -ne 0 ]
}

@test "opencode adapter fails closed on account tables and extra columns" {
  db="$TEST_TMP/oc-acct.db"
  python3 -I - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE "credential" ("id" TEXT PRIMARY KEY, "integration_id" TEXT NOT NULL, "value" TEXT NOT NULL)')
con.execute('CREATE TABLE "account" ("id" TEXT PRIMARY KEY)')
con.execute('INSERT INTO "account" VALUES (?)', ("a1",))
con.commit(); con.close()
PY
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" validate --db "$db"
  [ "$status" -ne 0 ]
  db2="$TEST_TMP/oc-extra.db"
  python3 -I - "$db2" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE "credential" ("id" TEXT PRIMARY KEY, "integration_id" TEXT NOT NULL, "value" TEXT NOT NULL, "refresh_token" TEXT)')
con.commit(); con.close()
PY
  run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" validate --db "$db2"
  [ "$status" -ne 0 ]
}

@test "adapters are declared once per harness in the registry" {
  [ "$(box_state_field muse auth adapter)" = "harnesses/muse/auth.sh" ]
  [ "$(box_state_field opencode auth adapter)" = "harnesses/opencode/auth.sh" ]
  [ "$(box_state_field codex auth adapter)" = "harnesses/codex/auth.sh" ]
  [ -f "$BUNDLE_DIR/harnesses/muse/auth.sh" ]
  [ -f "$BUNDLE_DIR/harnesses/opencode/auth.sh" ]
  [ -f "$BUNDLE_DIR/harnesses/codex/auth.sh" ]
  [ -f "$BUNDLE_DIR/harnesses/opencode/auth-state.py" ]
  [ -f "$BUNDLE_DIR/lib/supervisor.sh" ]
}

@test "codex validates supported key and OAuth shapes before replacing native auth" {
  source "$BUNDLE_DIR/harnesses/codex/auth.sh"
  native="$TEST_TMP/auth.json"
  printf '{"OPENAI_API_KEY":"fixture"}' >"$native"
  box_adapter_validate "$native"
  box_adapter_export "$native" "$TEST_TMP/envelope.json"
  before=$(sha256sum "$native")
  jq '.payload = {unknown:"credential"}' "$TEST_TMP/envelope.json" >"$TEST_TMP/bad.json"
  run box_adapter_install "$TEST_TMP/bad.json" "$native"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$native")" = "$before" ]
  printf '{"auth_mode":"chatgpt","tokens":{"id_token":"e30.e30.signature","access_token":"access","refresh_token":"refresh","account_id":"account"}}' >"$native"
  box_adapter_validate "$native"
  for payload in '{}' '{"OPENAI_API_KEY":1}' '{"tokens":{"access_token":"a"}}' '{"OPENAI_API_KEY":"key","keyring":"pointer"}'; do
    printf '%s' "$payload" >"$native"
    run box_adapter_validate "$native"
    [ "$status" -ne 0 ]
  done
}

@test "file adapters preserve foreign destinations and predictable temporary links" {
  for harness in muse codex; do
    source "$BUNDLE_DIR/harnesses/$harness/auth.sh"
    native="$TEST_TMP/$harness-native.json"
    envelope="$TEST_TMP/$harness-envelope.json"
    if [[ "$harness" == muse ]]; then printf '%s' '{"schema_version":1,"providers":{"meta":{"api_key":"synthetic"}}}' >"$native"
    else printf '{"OPENAI_API_KEY":"synthetic"}' >"$native"; fi
    box_adapter_export "$native" "$envelope"
    printf 'foreign bytes' >"$TEST_TMP/foreign"
    ln -s "$TEST_TMP/foreign" "$native.tmp.$$"
    box_adapter_install "$envelope" "$native"
    [ "$(cat "$TEST_TMP/foreign")" = 'foreign bytes' ]
    redirected="$TEST_TMP/$harness-redirected"
    ln -s "$TEST_TMP/foreign" "$redirected"
    before=$(sha256sum "$envelope" "$native" "$TEST_TMP/foreign")
    run box_adapter_export "$native" "$redirected"
    [ "$status" -ne 0 ]
    run box_adapter_install "$envelope" "$redirected"
    [ "$status" -ne 0 ]
    rm "$redirected"
    ln "$TEST_TMP/foreign" "$redirected"
    run box_adapter_export "$native" "$redirected"
    [ "$status" -ne 0 ]
    run box_adapter_install "$envelope" "$redirected"
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$envelope" "$native" "$TEST_TMP/foreign")" = "$before" ]
    rm "$redirected"
    mkdir "$TEST_TMP/$harness-parent"
    ln -s "$TEST_TMP/$harness-parent" "$TEST_TMP/$harness-parent-link"
    run box_adapter_export "$native" "$TEST_TMP/$harness-parent-link/envelope.json"
    [ "$status" -ne 0 ]
    [ ! -e "$TEST_TMP/$harness-parent/envelope.json" ]
    [ -z "$(find "$TEST_TMP" -name '.box-auth-*' -print)" ]
  done
}

@test "OpenCode canonical verification is pure and needs no native database" {
  envelope="$TEST_TMP/envelope.json"
  printf '%s\n' '{"schema_version":1,"harness":"opencode","adapter_schema":1,"revision":3,"tombstone":false,"payload":{"credentials":[{"id":"synthetic","integration_id":"test","label":"test","value":"{\"type\":\"key\",\"key\":\"synthetic\"}","method_id":null,"connector_id":null,"time_created":1,"time_updated":1}]}}' > "$envelope"
  chmod 600 "$envelope"
  before=$(sha256sum "$envelope")
  run box_auth_verify_envelope opencode "$envelope" "$BUNDLE_DIR"
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$envelope")" = "$before" ]
  [ "$(find "$TEST_TMP" -name '.validate.*' -o -name '*.db' | wc -l)" -eq 0 ]
  run python3 -I - "$BUNDLE_DIR/harnesses/opencode/auth-state.py" "$envelope" <<'PY'
import argparse, importlib.util, sys
spec = importlib.util.spec_from_file_location("adapter", sys.argv[1])
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
def forbidden(*args):
    raise AssertionError("database accessed during envelope verification")
adapter._connect = forbidden
adapter._read_database = forbidden
assert adapter.cmd_verify_envelope(argparse.Namespace(envelope=sys.argv[2])) == 0
PY
  [ "$status" -eq 0 ]
}

@test "OpenCode pure verification refuses malformed members duplicate keys and revision types" {
  envelope="$TEST_TMP/envelope.json"
  for payload in '{"schema_version":1,"harness":"opencode","adapter_schema":1,"revision":1,"tombstone":true,"payload":null}' '{"schema_version":1,"harness":"opencode","adapter_schema":1,"revision":2,"tombstone":false,"payload":{"credentials":[]}}'; do
    printf '%s\n' "$payload" > "$envelope"
    chmod 600 "$envelope"
    run box_auth_verify_envelope opencode "$envelope" "$BUNDLE_DIR"
    [ "$status" -eq 0 ]
  done
  for payload in '{"schema_version":1,"harness":"opencode","adapter_schema":1,"revision":true,"tombstone":true,"payload":null}' '{"schema_version":1,"harness":"opencode","adapter_schema":1,"revision":1.0,"tombstone":true,"payload":null}' '{"schema_version":1,"harness":"opencode","adapter_schema":1,"revision":1,"revision":2,"tombstone":true,"payload":null}' '{"schema_version":1,"harness":"opencode","adapter_schema":1,"revision":1,"tombstone":false,"payload":{"credentials":[],"unqualified":[]}}'; do
    printf '%s\n' "$payload" > "$envelope"
    run box_auth_verify_envelope opencode "$envelope" "$BUNDLE_DIR"
    [ "$status" -ne 0 ]
  done
}

@test "file envelope validation uses semantic payloads without scratch projections" {
  for id in muse codex; do
    if [[ "$id" == muse ]]; then payload='{"schema_version":1,"providers":{"meta":{"api_key":"synthetic"}}}'; else payload='{"OPENAI_API_KEY":"synthetic"}'; fi
    envelope="$TEST_TMP/$id-envelope.json"
    jq -n --arg h "$id" --argjson p "$payload" '{schema_version:1,harness:$h,adapter_schema:1,revision:2,tombstone:false,payload:$p}' > "$envelope"
    chmod 600 "$envelope"
    # An inherited different adapter hook must not select the wrong validator.
    source "$BUNDLE_DIR/harnesses/opencode/auth.sh"
    run box_auth_verify_envelope "$id" "$envelope" "$BUNDLE_DIR"
    [ "$status" -eq 0 ]
    [ "$(find "$TEST_TMP" -name '.validate.*' | wc -l)" -eq 0 ]
    jq '.payload={"unqualified_backend":"synthetic"}' "$envelope" > "$TEST_TMP/invalid"
    chmod 600 "$TEST_TMP/invalid"
    run box_auth_verify_envelope "$id" "$TEST_TMP/invalid" "$BUNDLE_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" != *synthetic* ]]
  done
}

@test "canonical envelope duplicate keys unknown authority and redirected input refuse" {
  envelope="$TEST_TMP/envelope.json"
  for payload in '{"schema_version":1,"harness":"codex","adapter_schema":1,"revision":0,"tombstone":true,"payload":null,"host_path":"synthetic"}' '{"schema_version":1,"harness":"codex","adapter_schema":1,"revision":0,"tombstone":false,"payload":{"OPENAI_API_KEY":"synthetic","OPENAI_API_KEY":"other"}}'; do
    printf '%s\n' "$payload" > "$envelope"
    chmod 600 "$envelope"
    run box_auth_verify_envelope codex "$envelope" "$BUNDLE_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" != *synthetic* ]]
  done
  ln -s "$envelope" "$TEST_TMP/link"
  run box_auth_verify_envelope codex "$TEST_TMP/link" "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
  ln "$envelope" "$TEST_TMP/shared"
  run box_auth_verify_envelope codex "$envelope" "$BUNDLE_DIR"
  [ "$status" -ne 0 ]
}

@test "OpenCode envelope reads permit access-time updates while retaining integrity checks" {
  run python3 -I - "$BUNDLE_DIR/harnesses/opencode/auth-state.py" "$TEST_TMP" <<'PY'
import argparse, importlib.util, os, pathlib, sys
spec = importlib.util.spec_from_file_location('adapter', sys.argv[1])
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
p = pathlib.Path(sys.argv[2]) / 'envelope'
p.write_text('{"schema_version":1,"harness":"opencode","adapter_schema":1,"revision":0,"tombstone":true,"payload":null}')
p.chmod(0o600)
os.utime(p, ns=(1, p.stat().st_mtime_ns))
assert a.cmd_verify_envelope(argparse.Namespace(envelope=str(p))) == 0
PY
  [ "$status" -eq 0 ]
}

@test "opencode refuses credential and selection triggers before source mutation" {
  for table in credential account_state; do
    db="$TEST_TMP/trigger-$table.db"
    _make_opencode_database "$db"
    python3 -I - "$db" "$table" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as con:
    con.execute('CREATE TABLE unrelated (marker TEXT)')
    con.execute("INSERT INTO unrelated VALUES ('preserve')")
    if sys.argv[2] == 'account_state':
        con.execute('CREATE TABLE account (id TEXT, email TEXT, url TEXT, access_token TEXT, refresh_token TEXT, token_expiry INTEGER, time_created INTEGER, time_updated INTEGER)')
        con.execute('CREATE TABLE account_state (id INTEGER, active_account_id TEXT, active_org_id TEXT)')
    con.execute('CREATE TRIGGER hostile AFTER DELETE ON ' + sys.argv[2] + ' BEGIN DELETE FROM unrelated; END')
PY
    before=$(sha256sum "$db")
    run python3 -I "$BUNDLE_DIR/harnesses/opencode/auth-state.py" scrub --db "$db"
    [ "$status" -ne 0 ]
    [[ "$output" == *'unsupported auth/selection trigger'* ]]
    [ "$(sha256sum "$db")" = "$before" ]
    [ ! -e "$db-wal" ]
    [ ! -e "$db-shm" ]
  done
}
