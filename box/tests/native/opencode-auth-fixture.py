#!/usr/bin/env python3
"""Qualify auth projections against a database created by pinned OpenCode."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import sqlite3
import select
import re
import base64
import urllib.request
import subprocess
import tarfile
import tempfile
import time


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--scratch-root", required=True)
    args = parser.parse_args()
    arch = {"x86_64": "amd64", "aarch64": "arm64"}.get(platform.machine())
    if arch is None:
        raise SystemExit("BLOCKED: unsupported OpenCode native fixture architecture")
    bundle = Path(__file__).resolve().parents[2]
    binary, archive = Path(args.binary).resolve(strict=True), Path(args.archive).resolve(strict=True)
    pin = subprocess.run(["bash", "-p", "-c", 'source "$1/lib/pins.sh"; box_print_pin "$1" "$2"',
                          "fixture", str(bundle), "OPENCODE_SHA256_" + arch.upper()], env={"PATH": "/usr/bin:/bin", "BOX_TOOL": "fixture"},
                         check=True, capture_output=True, text=True).stdout
    if hashlib.sha256(archive.read_bytes()).hexdigest() != pin:
        raise ValueError("OpenCode archive does not match the pinned architecture artifact")
    subprocess.run(["python3", "-I", str(bundle / "harnesses/opencode/archive.py"), str(archive), arch], check=True)
    with tarfile.open(archive) as stream:
        artifact = stream.extractfile("opencode")
        if artifact is None or hashlib.sha256(artifact.read()).digest() != hashlib.sha256(binary.read_bytes()).digest():
            raise ValueError("OpenCode executable does not match the verified archive")
    helper = bundle / "harnesses/opencode/auth-state.py"
    with tempfile.TemporaryDirectory(prefix="opencode-auth-fixture-", dir=args.scratch_root) as directory:
        root = Path(directory)
        (root / "home").mkdir(mode=0o700)
        env = dict(PATH="/usr/bin:/bin", HOME=str(root / "home"), LANG="C.UTF-8",
                   XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
                   XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
                   HTTP_PROXY="http://127.0.0.1:9", HTTPS_PROXY="http://127.0.0.1:9",
                   NO_PROXY="localhost,127.0.0.1,::1", OPENCODE_DISABLE_AUTOUPDATE="1",
                   OPENCODE_DISABLE_MODELS_FETCH="1", OPENCODE_MODELS_PATH=str(root / "models.json"))
        (root / "models.json").write_text(json.dumps({"openai": {
            "id": "openai", "name": "OpenAI", "env": ["OPENAI_API_KEY"],
            "npm": "@ai-sdk/openai", "api": "http://127.0.0.1:9/v1", "models": {
                "fixture": {"id": "fixture", "name": "fixture", "release_date": "2026-01-01",
                            "attachment": False, "reasoning": False, "tool_call": False,
                            "limit": {"context": 1024, "output": 64}}}}}))
        (root / "opencode.json").write_text(json.dumps({"providers": {"openai": {
            "name": "OpenAI", "package": "@opencode/ai/providers/openai-compatible",
            "settings": {"baseURL": "http://127.0.0.1:9/v1"}, "models": {"fixture": {
                "name": "fixture", "capabilities": {"tools": True, "input": ["text"], "output": ["text"]},
                "limit": {"context": 1024, "output": 64}}}}}}))
        def run(argv, success=True):
            result = subprocess.run(argv, env=env, cwd=root, text=True,
                                    capture_output=True, timeout=30)
            if success and result.returncode:
                raise AssertionError("native OpenCode fixture failed (output withheld)")
            return result
        data = root / "data/opencode"
        data.mkdir(parents=True, mode=0o700, exist_ok=True)
        assert run([str(binary), "--version"]).stdout.strip() == "opencode v2.0.6"
        print("N: OpenCode archive SHA256=" + pin + "; arch=" + arch + "; native version=opencode v2.0.6")
        run([str(binary), "auth", "list", "--standalone"])
        db = data / "opencode.db"
        assert db.stat().st_mode & 0o777 == 0o600
        envelope, sidecar = root / "credentials.json", root / "selection.json"
        with sqlite3.connect(db) as con:
            # Fingerprint the client-created schema before synthetic additions.
            # No database rows or token values enter qualification diagnostics.
            schema = con.execute(
                "SELECT type,name,tbl_name,sql FROM sqlite_master "
                "WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name").fetchall()
            if not schema:
                raise AssertionError("native schema evidence is empty")
            print("N: client-created SQLite schema SHA256=" + hashlib.sha256(
                json.dumps(schema, separators=(",", ":")).encode()).hexdigest())
            print("N: synthetic rows and local credential service only; account/OAuth/importer gates open")
            first = 'cred_fixture_first'
            con.execute('INSERT INTO credential (id,integration_id,label,value,connector_id,method_id,active,time_created,time_updated) VALUES (?,?,?,?,?,?,?,?,?)',
                        (first, 'openai', 'Synthetic first', json.dumps(dict(type='key', key='synthetic-first')), None, None, 1, 1, 1))
            con.execute('INSERT INTO credential (id,integration_id,label,value,connector_id,method_id,active,time_created,time_updated) VALUES (?,?,?,?,?,?,?,?,?)',
                        ("cred_fixture_second", "openai", "Synthetic second", json.dumps(dict(type="key", key="synthetic-second")), None, None, 0, 1, 1))
            endpoint = "mcp_" + hashlib.sha256(b"fixture\nhttp://127.0.0.1:9/mcp").hexdigest()
            oauth = dict(type="oauth", methodID="oauth", refresh="synthetic-refresh", access="synthetic-access", expires=4102444800000)
            con.execute('INSERT INTO credential (id,integration_id,label,value,connector_id,method_id,active,time_created,time_updated) VALUES (?,?,?,?,?,?,?,?,?)',
                        ("cred_fixture_mcp", endpoint, "Synthetic MCP", json.dumps(oauth), None, "oauth", 0, 1, 1))
            con.execute('INSERT INTO account VALUES (?,?,?,?,?,?,?,?)',
                        ("fixture-account", "fixture@example.invalid", "https://fixture.invalid", "synthetic-access", "synthetic-refresh", None, 1, 1))
            con.execute('INSERT INTO control_account VALUES (?,?,?,?,?,?,?,?)',
                        ("fixture@example.invalid", "https://fixture.invalid", "synthetic-access", "synthetic-refresh", None, 1, 1, 1))
            con.execute('INSERT OR REPLACE INTO account_state VALUES (?,?,?)', (0, "fixture-account", "fixture-org"))
            con.execute('CREATE TABLE box_non_auth_marker (id TEXT PRIMARY KEY, value TEXT)')
            con.execute('INSERT INTO box_non_auth_marker VALUES (?,?)', ("session-approval", "preserve"))
        def op(command, *options, success=True):
            return run(["python3", "-I", str(helper), command, "--db", str(db), *map(str, options)], success=success)
        # Exercise the native credential service used by CLI switch/logout.
        # No provider/model call or interactive account is involved.
        service_env = dict(env, OPENCODE_SERVER_PASSWORD="synthetic-service-password")
        service = subprocess.Popen([str(binary), "serve", "--hostname", "127.0.0.1", "--port", "0"],
                                   env=service_env, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 15
            url = None
            while service.poll() is None and time.monotonic() < deadline:
                if select.select([service.stdout], [], [], 0.1)[0]:
                    line = service.stdout.readline()
                    match = re.search(r"http://127\.0\.0\.1:[0-9]+", line)
                    if match:
                        url = match.group()
                        break
            assert url is not None, "native service did not become ready"
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            auth = base64.b64encode(b"opencode:synthetic-service-password").decode()
            def request(path, method):
                req = urllib.request.Request(url + path, method=method,
                                             headers={"Authorization": "Basic " + auth})
                with opener.open(req, timeout=10) as response:
                    assert response.status == 204
            request("/api/credential/cred_fixture_second/activate", "POST")
            with sqlite3.connect(db) as con:
                assert con.execute('SELECT active FROM credential WHERE id=?', ("cred_fixture_second",)).fetchone()[0] == 1
            request("/api/credential/cred_fixture_second", "DELETE")
        finally:
            service.terminate()
            try:
                service.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                service.kill()
                service.communicate(timeout=5)
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT id FROM credential WHERE id=?', ("cred_fixture_second",)).fetchone() is None
            assert con.execute('SELECT active FROM credential WHERE id=?', (first,)).fetchone()[0] == 1
            tables = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")]
            unrelated = {t: con.execute('SELECT * FROM "' + t.replace('"', '""') + '"').fetchall()
                         for t in tables if t not in {"credential", "account", "control_account", "account_state"}}
        op("save-selection", "--sidecar", sidecar, "--auth-id", "project-one")
        op("export", "--out", envelope)
        run(["python3", "-I", str(helper), "verify-envelope", "--envelope", str(envelope)])
        doc = json.loads(envelope.read_text())
        assert len(doc["payload"]["credentials"]) == 2
        assert len(doc["payload"]["accounts"]) == len(doc["payload"]["control_accounts"]) == 1
        assert "active" not in json.dumps(doc["payload"]) and "fixture-org" not in json.dumps(doc["payload"])
        op("scrub")
        with sqlite3.connect(db) as con:
            assert all(con.execute('SELECT COUNT(*) FROM "' + t + '"').fetchone()[0] == 0
                       for t in ("credential", "account", "control_account"))
            assert con.execute('SELECT active_account_id FROM account_state WHERE id=0').fetchone()[0] is None
            assert all(con.execute('SELECT * FROM "' + t.replace('"', '""') + '"').fetchall() == rows for t, rows in unrelated.items())
        op("install", "--envelope", envelope)
        op("restore-selection", "--sidecar", sidecar, "--auth-id", "new-project")
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT COUNT(*) FROM credential WHERE active=1').fetchone()[0] == 0
        op("restore-selection", "--sidecar", sidecar, "--auth-id", "project-one")
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT active_account_id,active_org_id FROM account_state WHERE id=0').fetchone() == ("fixture-account", "fixture-org")
            assert con.execute('SELECT active FROM control_account').fetchone()[0] == 1
            assert con.execute('SELECT integration_id FROM credential WHERE id=?', ("cred_fixture_mcp",)).fetchone()[0] == endpoint
            con.execute('UPDATE account SET refresh_token=?', ("synthetic-rotated",))
        op("export", "--out", envelope)
        assert json.loads(envelope.read_text())["payload"]["accounts"][0]["refresh_token"] == "synthetic-rotated"
        before = envelope.read_bytes()
        with sqlite3.connect(db) as con:
            con.execute('CREATE TRIGGER box_hostile_auth AFTER DELETE ON credential BEGIN DELETE FROM box_non_auth_marker; END')
        source_before = db.read_bytes()
        assert op("scrub", success=False).returncode != 0
        assert db.read_bytes() == source_before and envelope.read_bytes() == before
        with sqlite3.connect(db) as con:
            assert con.execute('SELECT value FROM box_non_auth_marker').fetchone()[0] == "preserve"
            con.execute('DROP TRIGGER box_hostile_auth')
        with sqlite3.connect(db) as con:
            con.execute('ALTER TABLE account ADD COLUMN unknown_token TEXT')
        source_before = db.read_bytes()
        assert op("export", "--out", envelope, success=False).returncode != 0
        assert db.read_bytes() == source_before and envelope.read_bytes() == before
    print("PASS: pinned OpenCode native schema/credential activation/removal, account projections, selection/exclusion/unknown-schema checks; disposable state removed")


if __name__ == "__main__":
    main()
