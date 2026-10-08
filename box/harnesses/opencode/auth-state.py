#!/usr/bin/env python3
"""harnesses/opencode/auth-state.py — schema-bound SQLite auth projection.

Managed store: verified credential/account/control_account auth rows. Never exports sessions,
messages, events, approvals, workspace/project rows, configuration, caches
or logs. Active selections are stored separately in project state
(/persist/state/opencode/box-auth-selection.json), keyed by auth identity.

Envelope (credentials.json):
  {schema_version:1, harness:"opencode", adapter_schema:1, revision:N,
   tombstone:bool, payload:{credentials:[...]} | null}

Credential row export preserves id, integration id, label, value,
method/connection metadata and timestamps. Unknown payload/schema versions
fail closed.
"""
import argparse
import contextlib
import json
import os
import shutil
import sqlite3
import stat
import sys
import tempfile

ADAPTER_SCHEMA = 1
ENVELOPE_SCHEMA = 1

# Explicit auth column allowlist. Active flag is selection, exported
# separately and never used to pick a credential implicitly.
CREDENTIAL_COLUMNS = [
    "id",
    "integration_id",
    "label",
    "value",
    "method_id",
    "connector_id",
    "time_created",
    "time_updated",
]
ACCOUNT_COLUMNS = ["id", "email", "url", "access_token", "refresh_token",
                   "token_expiry", "time_created", "time_updated"]
CONTROL_COLUMNS = ["email", "url", "access_token", "refresh_token",
                   "token_expiry", "time_created", "time_updated"]
ACCOUNT_SELECTION_COLUMNS = ["id", "active_account_id", "active_org_id"]


def _connect(db_path):
    con = sqlite3.connect(db_path, timeout=10, isolation_level=None)
    con.execute("PRAGMA journal_mode=WAL;")
    con.execute("PRAGMA busy_timeout=10000;")
    con.execute("PRAGMA foreign_keys=ON;")
    return con


@contextlib.contextmanager
def _read_database(db_path):
    """Inspect a stopped database and WAL without changing the source.

    SQLite can create SHM or checkpoint WAL even during inspection. Perform
    those operations on private copies; reject redirected sidecars and a
    source that changes while copying. The caller must stop the native service.
    """
    if os.path.realpath(db_path) != os.path.abspath(db_path):
        raise ValueError("redirected database path")
    with tempfile.TemporaryDirectory(prefix="box-auth-db-") as scratch:
        target = os.path.join(scratch, "opencode.db")
        signatures = {}
        for suffix in ("", "-wal", "-shm"):
            path = db_path + suffix
            if not os.path.lexists(path):
                continue
            before = os.lstat(path)
            if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
                    or before.st_nlink != 1 or stat.S_IMODE(before.st_mode) & 0o022):
                raise ValueError("unsafe database or sidecar")
            with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as source:
                if os.fstat(source.fileno()) != before:
                    raise ValueError("database changed before snapshot")
                with open(target + suffix, "wb") as dest:
                    shutil.copyfileobj(source, dest)
            os.chmod(target + suffix, 0o600)
            signatures[path] = before
        for path, before in signatures.items():
            after = os.lstat(path)
            if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns,
                    before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size,
                                          after.st_mtime_ns, after.st_ctime_ns):
                raise ValueError("database changed during snapshot")
        for suffix in ("", "-wal", "-shm"):
            if os.path.lexists(db_path + suffix) != (db_path + suffix in signatures):
                raise ValueError("database membership changed during snapshot")
        con = _connect(target)
        try:
            yield con
        finally:
            con.close()


def _tables(con):
    return {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}


def _columns(con, table):
    quoted = table.replace('"', '""')
    return [r[1] for r in con.execute(f'PRAGMA table_info("{quoted}")')]


def cmd_validate(args):
    db = args.db
    if not os.path.lexists(db):
        return 0
    if os.path.islink(db) or not os.path.isfile(db):
        print("unsafe database path", file=sys.stderr)
        return 1
    try:
        snapshot = _read_database(db)
        con = snapshot.__enter__()
    except Exception as e:  # noqa: BLE001
        print(f"cannot open database: {e}", file=sys.stderr)
        return 1
    try:
        tables = _tables(con)
        # New auth-bearing stores cannot silently escape the projection.
        token_columns = {"access_token", "refresh_token", "id_token", "api_key",
                         "client_secret", "password", "secret"}
        for table in tables - {"credential", "account", "control_account"}:
            if token_columns.intersection(_columns(con, table)):
                print("unsupported token-bearing table", file=sys.stderr)
                return 1
        if "credential" not in tables:
            print("missing credential table", file=sys.stderr)
            return 1
        cols = set(_columns(con, "credential"))
        for need in CREDENTIAL_COLUMNS + ["active"]:
            if need not in cols:
                print(f"missing credential column: {need}", file=sys.stderr)
                return 1
        # Fail closed on unexpected credential columns: silently ignoring a
        # new auth-bearing column would lose credentials. Only the explicit
        # allowlist plus the `active` selection column are supported.
        allowed = set(CREDENTIAL_COLUMNS) | {"active"}
        extra = cols - allowed
        if extra:
            print(f"unsupported credential columns: {sorted(extra)}", file=sys.stderr)
            return 1
        # Exact schemas from the pinned source and native-created database.
        for table, columns in (("account", ACCOUNT_COLUMNS),
                               ("control_account", CONTROL_COLUMNS + ["active"]),
                               ("account_state", ACCOUNT_SELECTION_COLUMNS)):
            if table in tables and set(_columns(con, table)) != set(columns):
                print("unsupported account/selection schema", file=sys.stderr)
                return 1
        if "account_state" in tables and "account" not in tables:
            print("orphan account selection schema", file=sys.stderr)
            return 1
        # Never cascade auth deletion into unrelated project records.
        for table in tables:
            quoted = table.replace('"', '""')
            for fk in con.execute(f'PRAGMA foreign_key_list("{quoted}")'):
                if fk[2] in ("credential", "account", "control_account"):
                    if table != "account_state" or fk[6].upper() != "SET NULL":
                        print("unsupported auth foreign-key dependency", file=sys.stderr)
                        return 1
        payload = _export_payload(con)
        if payload is None or not _validate_envelope({
            "schema_version": 1, "harness": "opencode", "adapter_schema": 1,
            "revision": 0,
            "tombstone": not any(payload.values()), "payload": payload if any(payload.values()) else None,
        }):
            print("unsupported native credential payload", file=sys.stderr)
            return 1
        return 0
    finally:
        snapshot.__exit__(None, None, None)


def _export_credentials(con):
    cols = _columns(con, "credential")
    select = [c for c in CREDENTIAL_COLUMNS if c in cols]
    if not select:
        select = ["id", "integration_id", "value"]
    quoted = ", ".join(f'"{c}"' for c in select)
    rows = []
    try:
        cur = con.execute(f'SELECT {quoted} FROM "credential" ORDER BY "id"')
    except sqlite3.Error as e:
        print(f"credential select failed: {e}", file=sys.stderr)
        return None
    names = [d[0] for d in cur.description]
    for row in cur.fetchall():
        rec = dict(zip(names, row))
        # JSON round-trip to ensure serializable values only.
        try:
            json.dumps(rec)
        except (TypeError, ValueError):
            print("non-serializable credential value", file=sys.stderr)
            return None
        rows.append(rec)
    return rows


def _export_payload(con):
    credentials = _export_credentials(con)
    if credentials is None:
        return None
    result = {"credentials": credentials}
    for table, key, columns in (("account", "accounts", ACCOUNT_COLUMNS),
                                 ("control_account", "control_accounts", CONTROL_COLUMNS)):
        if table not in _tables(con):
            continue
        quoted = ', '.join(f'"{c}"' for c in columns)
        order = '"id"' if table == "account" else '"email", "url"'
        rows = [dict(zip(columns, row)) for row in con.execute(f'SELECT {quoted} FROM "{table}" ORDER BY {order}')]
        if rows:
            result[key] = rows
    return result


def cmd_export(args):
    db = args.db
    out = args.out
    if not os.path.lexists(db):
        env = {
            "schema_version": ENVELOPE_SCHEMA,
            "harness": "opencode",
            "adapter_schema": ADAPTER_SCHEMA,
            "revision": 1,
            "tombstone": True,
            "payload": None,
        }
        with open(out, "w", encoding="utf-8") as f:
            json.dump(env, f, separators=(",", ":"))
            f.write("\n")
        os.chmod(out, 0o600)
        return 0
    if cmd_validate(args) != 0:
        return 1
    try:
        snapshot = _read_database(db)
        con = snapshot.__enter__()
    except (OSError, ValueError, sqlite3.Error):
        print("cannot snapshot native database", file=sys.stderr)
        return 1
    try:
        # Consistent read boundary: single transaction snapshot.
        con.execute("BEGIN IMMEDIATE;")
        try:
            payload = _export_payload(con)
            if payload is None:
                con.execute("ROLLBACK;")
                return 1
            con.execute("COMMIT;")
        except Exception:  # noqa: BLE001
            try:
                con.execute("ROLLBACK;")
            except Exception:  # noqa: BLE001
                pass
            return 1
    finally:
        snapshot.__exit__(None, None, None)
    tombstone = not any(payload.values())
    env = {
        "schema_version": ENVELOPE_SCHEMA,
        "harness": "opencode",
        "adapter_schema": ADAPTER_SCHEMA,
        "revision": 1,
        "tombstone": tombstone,
        "payload": None if tombstone else payload,
    }
    if not _validate_envelope(env):
        print("unsupported native credential payload", file=sys.stderr)
        return 1
    with open(out, "w", encoding="utf-8") as f:
        json.dump(env, f, separators=(",", ":"))
        f.write("\n")
    os.chmod(out, 0o600)
    return 0


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate envelope key")
        result[key] = value
    return result


def _envelope_signature(info):
    # Reading can update atime; it is not evidence that credential bytes changed.
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def _read_envelope(path):
    info = os.lstat(path)
    if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or
            info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size > 16 * 1024 * 1024):
        raise ValueError("unsafe or oversized envelope")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    with os.fdopen(fd, "rb") as stream:
        if _envelope_signature(os.fstat(stream.fileno())) != _envelope_signature(info):
            raise ValueError("envelope changed before read")
        data = stream.read(16 * 1024 * 1024 + 1)
        if (len(data) > 16 * 1024 * 1024 or
                _envelope_signature(os.fstat(stream.fileno())) != _envelope_signature(info) or
                _envelope_signature(os.lstat(path)) != _envelope_signature(info)):
            raise ValueError("envelope changed during read")
    def nonfinite(_):
        raise ValueError("nonfinite envelope JSON")
    return json.loads(data, object_pairs_hook=_unique_object, parse_constant=nonfinite)


def cmd_verify_envelope(args):
    try:
        valid = _validate_envelope(_read_envelope(args.envelope))
    except (OSError, ValueError, TypeError, KeyError):
        valid = False
    if not valid:
        print("unsupported or invalid envelope schema/payload", file=sys.stderr)
    return 0 if valid else 1


def _validate_envelope(env):
    if not isinstance(env, dict) or set(env) != {"schema_version", "harness", "adapter_schema", "revision", "tombstone", "payload"}:
        return False
    if type(env.get("schema_version")) is not int or env["schema_version"] != ENVELOPE_SCHEMA:
        return False
    if env.get("harness") != "opencode":
        return False
    if type(env.get("adapter_schema")) is not int or env["adapter_schema"] != ADAPTER_SCHEMA:
        return False
    if type(env.get("revision")) is not int or env["revision"] < 0:
        return False
    if not isinstance(env.get("tombstone"), bool):
        return False
    if env["tombstone"]:
        return env.get("payload") is None
    payload = env.get("payload")
    if (not isinstance(payload, dict) or "credentials" not in payload
            or set(payload) - {"credentials", "accounts", "control_accounts"}
            or not isinstance(payload.get("credentials"), list)):
        return False
    for key, columns in (("accounts", ACCOUNT_COLUMNS), ("control_accounts", CONTROL_COLUMNS)):
        records = payload.get(key, [])
        if not isinstance(records, list):
            return False
        seen = set()
        for rec in records:
            if not isinstance(rec, dict) or set(rec) != set(columns):
                return False
            identity = rec.get("id") if key == "accounts" else (rec["email"], rec["url"])
            if any(not isinstance(rec[c], str) or not rec[c] for c in columns
                   if c not in ("token_expiry", "time_created", "time_updated")):
                return False
            if identity in seen:
                return False
            seen.add(identity)
            if any(type(rec[c]) is not int for c in ("time_created", "time_updated")):
                return False
            if rec["token_expiry"] is not None and type(rec["token_expiry"]) is not int:
                return False
    ids = set()
    for rec in payload["credentials"]:
        if not isinstance(rec, dict):
            return False
        if set(rec) != set(CREDENTIAL_COLUMNS):
            return False
        if not isinstance(rec["id"], str) or not rec["id"]:
            return False
        if rec["id"] in ids:
            return False
        ids.add(rec["id"])
        if not isinstance(rec["integration_id"], str) or not rec["integration_id"]:
            return False
        for col in ("method_id", "connector_id"):
            if rec[col] is not None and not isinstance(rec[col], str):
                return False
        if not isinstance(rec["label"], str) or not isinstance(rec["value"], str):
            return False
        try:
            value = json.loads(rec["value"], object_pairs_hook=_unique_object)
        except ValueError:
            return False
        if not isinstance(value, dict) or value.get("type") not in ("key", "oauth"):
            return False
        # Bounded subset of pinned packages/schema/src/credential.ts.
        if value["type"] == "key":
            if (set(value) - {"type", "key", "metadata", "configuration"}
                    or not isinstance(value.get("key"), str)):
                return False
        else:
            if set(value) - {"type", "methodID", "refresh", "access", "expires", "metadata"}:
                return False
            if any(not isinstance(value.get(k), str) for k in ("methodID", "refresh", "access")):
                return False
            if type(value.get("expires")) is not int or value["expires"] < 0:
                return False
        for k in ("metadata", "configuration"):
            if k in value and not isinstance(value[k], dict):
                return False
        for col in ("time_created", "time_updated"):
            if type(rec[col]) is not int:
                return False
    return True



def _scrub_auth(con):
    con.execute('DELETE FROM "credential"')
    if "account_state" in _tables(con):
        con.execute('UPDATE "account_state" SET "active_account_id"=NULL, "active_org_id"=NULL')
    for table in ("account", "control_account"):
        if table in _tables(con):
            con.execute(f'DELETE FROM "{table}"')


def cmd_install(args):
    db = args.db
    envelope_path = args.envelope
    try:
        env = _read_envelope(envelope_path)
    except (OSError, ValueError) as e:
        print(f"invalid envelope: {e}", file=sys.stderr)
        return 1
    if not _validate_envelope(env):
        print("unsupported envelope schema/payload", file=sys.stderr)
        return 1
    if not os.path.isfile(db) or cmd_validate(args) != 0:
        print("native database initialization required before auth install", file=sys.stderr)
        return 1
    con = _connect(db)
    try:
        payload = env["payload"] if not env["tombstone"] else {}
        for table, key in (("account", "accounts"), ("control_account", "control_accounts")):
            if payload.get(key) and table not in _tables(con):
                print("native account schema initialization required", file=sys.stderr)
                return 1
        cols = set(_columns(con, "credential"))
        con.execute("BEGIN IMMEDIATE;")
        try:
            # Scrub managed rows only, then restore canonical set.
            _scrub_auth(con)
            if not env["tombstone"]:
                for rec in env["payload"]["credentials"]:
                    names = [k for k in CREDENTIAL_COLUMNS if k in rec and k in cols]
                    if "id" not in names:
                        raise ValueError("credential missing id")
                    placeholders = ", ".join("?" for _ in names)
                    quoted = ", ".join(f'"{k}"' for k in names)
                    con.execute(
                        f'INSERT OR REPLACE INTO "credential" ({quoted}) VALUES ({placeholders})',
                        [rec[k] if not isinstance(rec[k], (dict, list)) else json.dumps(rec[k]) for k in names],
                    )
                    # Preserve active=0 on install; selection is restored
                    # separately from the project-state sidecar.
                    if "active" in cols:
                        con.execute('UPDATE "credential" SET "active"=0 WHERE "id"=?', (rec["id"],))
                for table, key, columns in (("account", "accounts", ACCOUNT_COLUMNS),
                                             ("control_account", "control_accounts", CONTROL_COLUMNS)):
                    for rec in payload.get(key, []):
                        names = columns + (["active"] if table == "control_account" else [])
                        values = [rec[c] for c in columns] + ([0] if table == "control_account" else [])
                        quoted = ', '.join(f'"{c}"' for c in names)
                        placeholders = ', '.join('?' for _ in names)
                        con.execute(f'INSERT INTO "{table}" ({quoted}) VALUES ({placeholders})', values)
            con.execute("COMMIT;")
        except Exception as e:  # noqa: BLE001
            try:
                con.execute("ROLLBACK;")
            except Exception:  # noqa: BLE001
                pass
            print(f"install failed: {e}", file=sys.stderr)
            return 1
    finally:
        con.close()
    return 0


def cmd_scrub(args):
    db = args.db
    if not os.path.lexists(db):
        return 0
    if cmd_validate(args) != 0:
        return 1
    con = _connect(db)
    try:
        con.execute("BEGIN IMMEDIATE;")
        try:
            _scrub_auth(con)
            con.execute("COMMIT;")
        except Exception as e:  # noqa: BLE001
            try:
                con.execute("ROLLBACK;")
            except Exception:  # noqa: BLE001
                pass
            print(f"scrub failed: {e}", file=sys.stderr)
            return 1
    finally:
        con.close()
    return 0


def _read_sidecar(sidecar):
    if not os.path.lexists(sidecar):
        return {}
    st = os.lstat(sidecar)
    if (os.path.realpath(sidecar) != os.path.abspath(sidecar)
            or not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid()
            or st.st_nlink != 1 or stat.S_IMODE(st.st_mode) not in (0o400, 0o600)):
        print("unsafe selection sidecar", file=sys.stderr)
        return None
    try:
        with open(sidecar, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError) as e:
        print(f"invalid selection sidecar: {e}", file=sys.stderr)
        return None
    if not isinstance(doc, dict):
        print("invalid selection sidecar", file=sys.stderr)
        return None
    return doc


def _write_sidecar(sidecar, doc):
    parent = os.path.dirname(os.path.abspath(sidecar))
    if os.path.realpath(parent) != parent:
        raise ValueError("redirected selection parent")
    os.makedirs(parent, mode=0o700, exist_ok=True)
    st = os.lstat(parent)
    if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o022:
        raise ValueError("unsafe selection parent")
    fd, tmp = tempfile.mkstemp(prefix=".selection-", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(doc, f, separators=(",", ":"))
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, sidecar)
        fd = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)


def cmd_save_selection(args):
    active = {}
    accounts = []
    control_accounts = []
    if os.path.lexists(args.db):
        if cmd_validate(args) != 0:
            return 1
        with _read_database(args.db) as con:
            for integration, credential in con.execute(
                'SELECT "integration_id", "id" FROM "credential" WHERE "active"=1 ORDER BY "id"'
            ):
                if integration in active:
                    print("ambiguous selection within integration", file=sys.stderr)
                    return 1
                active[integration] = credential
            if "account_state" in _tables(con):
                accounts = [dict(zip(ACCOUNT_SELECTION_COLUMNS, row)) for row in con.execute(
                    'SELECT "id", "active_account_id", "active_org_id" FROM "account_state" ORDER BY "id"')]
            if "control_account" in _tables(con):
                control_accounts = [list(row) for row in con.execute(
                    'SELECT "email", "url" FROM "control_account" WHERE "active"=1 ORDER BY "email", "url"')]
    doc = _read_sidecar(args.sidecar)
    if doc is None:
        return 1
    doc[args.auth_id] = dict(schema_version=2, credentials=active,
                            accounts=accounts, control_accounts=control_accounts)
    try:
        _write_sidecar(args.sidecar, doc)
    except OSError:
        print("cannot write selection sidecar", file=sys.stderr)
        return 1
    return 0


def cmd_restore_selection(args):
    doc = _read_sidecar(args.sidecar)
    if doc is None:
        return 1
    want = doc.get(args.auth_id)
    if want is None:
        return 0
    accounts = []
    control_accounts = []
    if isinstance(want, dict) and type(want.get("schema_version")) is int:
        if (want["schema_version"] != 2 or set(want) != {
                "schema_version", "credentials", "accounts", "control_accounts"}
                or not isinstance(want["accounts"], list)
                or not isinstance(want["control_accounts"], list)):
            print("unsupported account selection", file=sys.stderr)
            return 1
        accounts, control_accounts = want["accounts"], want["control_accounts"]
        for rec in accounts:
            if (not isinstance(rec, dict) or set(rec) != set(ACCOUNT_SELECTION_COLUMNS)
                    or type(rec["id"]) is not int
                    or any(rec[c] is not None and not isinstance(rec[c], str)
                           for c in ("active_account_id", "active_org_id"))):
                print("invalid account selection", file=sys.stderr)
                return 1
        if any(not isinstance(rec, list) or len(rec) != 2 or
               any(not isinstance(x, str) for x in rec) for rec in control_accounts):
            print("invalid control account selection", file=sys.stderr)
            return 1
        want = want["credentials"]
    # Older sidecars held one credential. Resolve its integration from the
    # current validated native rows; it never selects a different credential.
    if not isinstance(want, (str, dict)) or (isinstance(want, dict) and any(
        not isinstance(k, str) or not isinstance(v, str) for k, v in want.items()
    )):
        print("unsupported saved selection", file=sys.stderr)
        return 1
    if cmd_validate(args) != 0:
        return 1
    con = _connect(args.db)
    try:
        cols = set(_columns(con, "credential"))
        if "active" not in cols or "id" not in cols:
            return 0
        con.execute("BEGIN IMMEDIATE;")
        try:
            con.execute('UPDATE "credential" SET "active"=0')
            if isinstance(want, str):
                row = con.execute(
                    'SELECT "integration_id" FROM "credential" WHERE "id"=?', (want,)
                ).fetchone()
                want = {row[0]: want} if row else {}
            for integration, credential in want.items():
                con.execute(
                    'UPDATE "credential" SET "active"=1 WHERE "id"=? AND "integration_id"=?',
                    (credential, integration),
                )
            if "account_state" in _tables(con):
                for rec in accounts:
                    exists = con.execute('SELECT 1 FROM "account" WHERE "id"=?', (rec["active_account_id"],)).fetchone()
                    con.execute('UPDATE "account_state" SET "active_account_id"=?, "active_org_id"=? WHERE "id"=?',
                                (rec["active_account_id"] if exists else None,
                                 rec["active_org_id"] if exists else None, rec["id"]))
            if "control_account" in _tables(con):
                con.execute('UPDATE "control_account" SET "active"=0')
                for email, url in control_accounts:
                    con.execute('UPDATE "control_account" SET "active"=1 WHERE "email"=? AND "url"=?', (email, url))
            con.execute("COMMIT;")
        except Exception as e:  # noqa: BLE001
            try:
                con.execute("ROLLBACK;")
            except Exception:  # noqa: BLE001
                pass
            print(f"restore failed: {e}", file=sys.stderr)
            return 1
    finally:
        con.close()
    return 0


def cmd_require_selection(args):
    if not os.path.lexists(args.db):
        return 0
    if cmd_validate(args) != 0:
        return 1
    with _read_database(args.db) as con:
        ambiguous = con.execute('SELECT 1 FROM "credential" GROUP BY "integration_id" '
                                'HAVING COUNT(*)>1 AND SUM(CASE WHEN "active"=1 THEN 1 ELSE 0 END)=0 LIMIT 1').fetchone()
        if ambiguous:
            print("Multiple saved credentials require explicit selection: run native auth switch before a model run.", file=sys.stderr)
            return 1
    return 0


def main(argv=None):
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    pure = sub.add_parser("verify-envelope")
    pure.add_argument("--envelope", required=True)
    v = sub.add_parser("validate")
    v.add_argument("--db", required=True)
    e = sub.add_parser("export")
    e.add_argument("--db", required=True)
    e.add_argument("--out", required=True)
    i = sub.add_parser("install")
    i.add_argument("--db", required=True)
    i.add_argument("--envelope", required=True)
    s = sub.add_parser("scrub")
    s.add_argument("--db", required=True)
    sv = sub.add_parser("save-selection")
    sv.add_argument("--db", required=True)
    sv.add_argument("--sidecar", required=True)
    sv.add_argument("--auth-id", required=True)
    rs = sub.add_parser("restore-selection")
    rs.add_argument("--db", required=True)
    rs.add_argument("--sidecar", required=True)
    rs.add_argument("--auth-id", required=True)
    choice = sub.add_parser("require-selection")
    choice.add_argument("--db", required=True)
    args = p.parse_args(argv)
    if args.cmd == "verify-envelope":
        return cmd_verify_envelope(args)
    if args.cmd == "validate":
        return cmd_validate(args)
    if args.cmd == "export":
        return cmd_export(args)
    if args.cmd == "install":
        return cmd_install(args)
    if args.cmd == "scrub":
        return cmd_scrub(args)
    if args.cmd == "save-selection":
        return cmd_save_selection(args)
    if args.cmd == "restore-selection":
        return cmd_restore_selection(args)
    if args.cmd == "require-selection":
        return cmd_require_selection(args)
    return 2


if __name__ == "__main__":
    sys.exit(main())
