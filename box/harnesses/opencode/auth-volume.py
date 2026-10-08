#!/usr/bin/env python3
"""Contained, journaled auth operations on the resolved OpenCode v2 volume."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
module_path = HERE / 'auth-state.py'
if not module_path.exists():
    module_path = HERE / 'box-auth-state.py'
spec = importlib.util.spec_from_file_location('native_auth', module_path)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def fault(stage):
    if os.environ.get('BOX_AUTH_VOLUME_FAULT') == stage:
        raise RuntimeError('injected contained auth interruption at ' + stage)


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def safe_file(path):
    for parent in path.parents:
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError('redirected auth parent')
    info = path.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) not in (0o400, 0o600)):
        raise ValueError('unsafe auth operation file')


def read_json(path):
    safe_file(path)
    return json.loads(path.read_text(encoding='utf-8'))


def publish(path, doc):
    if path.exists() or path.is_symlink():
        safe_file(path)
    fd, tmp = tempfile.mkstemp(prefix='.volume-auth.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(doc, stream, separators=(',', ':'))
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
        sync_dir(path.parent)
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)


def export(db):
    if not db.exists() or db.is_symlink():
        raise ValueError('missing native projection database')
    with tempfile.TemporaryDirectory(prefix='box-auth-export-') as tmp:
        path = Path(tmp) / 'envelope.json'
        if native.cmd_export(SimpleNamespace(db=str(db), out=str(path))) != 0:
            raise ValueError('native auth export rejected')
        doc = read_json(path)
    if not native._validate_envelope(doc):
        raise ValueError('unsupported native auth envelope')
    return doc


def same_auth(left, right):
    return left['tombstone'] == right['tombstone'] and left['payload'] == right['payload']


def idle(root):
    lease = read_json(root / 'lease.json')
    lease['state'] = 'idle'
    for key in ('projection', 'projection_lock', 'phase', 'operation'):
        lease.pop(key, None)
    publish(root / 'lease.json', lease)
    pending = root / 'collection-pending.json'
    if pending.exists():
        safe_file(pending)
        pending.unlink()
        sync_dir(root)


def save_selection(args, identity):
    key = {name: identity.get(name) for name in ('harness', 'uid', 'scope', 'project_hash')}
    auth_id = hashlib.sha256((json.dumps(key, separators=(',', ':')) + '\n').encode()).hexdigest()
    result = native.cmd_save_selection(SimpleNamespace(db=args.db, sidecar=args.sidecar, auth_id=auth_id))
    if result != 0:
        raise ValueError('cannot preserve project auth selection')


def scrub(db):
    if native.cmd_scrub(SimpleNamespace(db=str(db))) != 0:
        raise ValueError('native auth scrub rejected; recover before reuse')


def journal(root, stage, args):
    publish(root / 'migration-journal.json', dict(stage=stage, source=args.source,
                                                destination=args.host_auth_dir,
                                                format='box-volume-migration-v1'))
    fault(stage)


def finish_migration(args, root, db, identity, checkpoint):
    stage = checkpoint['stage']
    saved = read_json(root / 'migration-staged.json')
    if not native._validate_envelope(saved):
        raise ValueError('invalid retained migration envelope')
    committed = read_json(root / 'credentials.json')
    if stage in ('planned', 'staged'):
        if not same_auth(export(db), saved):
            raise ValueError('retained migration source changed; destination preserved')
        # Publication may have preceded its journal update. A matching winner
        # is safe to verify; a different winner is never overwritten.
        if not committed['tombstone'] and not same_auth(saved, committed):
            raise ValueError('auth destination conflict')
        if not same_auth(saved, committed):
            saved['revision'] = committed['revision'] + 1
            publish(root / 'credentials.json', saved)
            fault('canonical-published')
        journal(root, 'destination-committed', args)
        stage = 'destination-committed'
    if stage == 'destination-committed':
        if not same_auth(read_json(root / 'credentials.json'), saved):
            raise ValueError('committed migration destination changed')
        publish(root / 'legacy-auth-rollback.json', saved)
        journal(root, 'verified', args)
        stage = 'verified'
    if stage == 'verified':
        current = export(db)
        # A crash after scrub but before the journal update is recoverable.
        if not current['tombstone'] and not same_auth(current, saved):
            raise ValueError('migration source changed; source retained')
        if not current['tombstone']:
            save_selection(args, identity)
            scrub(db)
            fault('native-scrubbed')
        journal(root, 'source-retired', args)
        stage = 'source-retired'
    if stage == 'source-retired':
        publish(root / 'migration.json', dict(mode='migrated', source=args.source,
                                              destination=args.host_auth_dir))
        journal(root, 'complete', args)
    (root / 'migration-staged.json').unlink(missing_ok=True)
    sync_dir(root)
    idle(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('migrate', 'recover'))
    parser.add_argument('--auth-dir', required=True)
    parser.add_argument('--db', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--host-auth-dir', required=True)
    parser.add_argument('--sidecar', required=True)
    args = parser.parse_args()
    root, db = Path(args.auth_dir), Path(args.db)
    for path in (root, *root.parents):
        if not stat.S_ISDIR(path.lstat().st_mode):
            raise ValueError('redirected canonical directory')
    if root.stat().st_uid != os.getuid() or stat.S_IMODE(root.stat().st_mode) != 0o700:
        raise ValueError('unsafe canonical directory')
    for suffix in ('', '-wal', '-shm'):
        path = Path(str(db) + suffix)
        if path.exists() or path.is_symlink():
            safe_file(path)
    identity, lease = read_json(root / 'identity.json'), read_json(root / 'lease.json')
    if (identity.get('harness') != 'opencode' or identity.get('uid') != os.getuid()
            or identity.get('schema_version') != 1 or lease.get('state') != 'active'
            or lease.get('projection') != args.source or not args.source.startswith('volume:')):
        raise ValueError('contained operation identity/lease mismatch')
    committed = read_json(root / 'credentials.json')
    if not native._validate_envelope(committed):
        raise ValueError('unsupported canonical auth envelope')
    checkpoint_path = root / 'migration-journal.json'
    checkpoint = read_json(checkpoint_path) if checkpoint_path.exists() else None
    if checkpoint and checkpoint.get('stage') != 'complete':
        if (checkpoint.get('format') != 'box-volume-migration-v1'
                or checkpoint.get('source') != args.source
                or checkpoint.get('destination') != args.host_auth_dir
                or checkpoint.get('stage') not in ('planned', 'staged', 'destination-committed', 'verified', 'source-retired')):
            raise ValueError('foreign or unsupported migration checkpoint')
        finish_migration(args, root, db, identity, checkpoint)
        return
    if checkpoint and checkpoint.get('stage') == 'complete' and lease.get('operation') == 'migrate':
        if checkpoint.get('source') != args.source or checkpoint.get('destination') != args.host_auth_dir:
            raise ValueError('completed migration identity changed')
        (root / 'migration-staged.json').unlink(missing_ok=True)
        idle(root)
        return
    if args.operation == 'migrate' or lease.get('operation') == 'migrate':
        if (root / 'migration.json').exists():
            raise ValueError('auth identity already has a migration record')
        saved = export(db)
        if (root / 'migration-staged.json').exists():
            retained = read_json(root / 'migration-staged.json')
            if not native._validate_envelope(retained) or not same_auth(retained, saved):
                raise ValueError('interrupted migration source changed; source retained')
        if not committed['tombstone'] and not same_auth(saved, committed):
            raise ValueError('auth destination conflict; source retained')
        # No persistent credential mutation precedes conflict validation.
        lease['phase'] = 'preparing'
        lease['operation'] = 'migrate'
        publish(root / 'lease.json', lease)
        fault('preparing')
        publish(root / 'migration-staged.json', saved)
        fault('stage-published')
        journal(root, 'planned', args)
        journal(root, 'staged', args)
        finish_migration(args, root, db, identity, dict(stage='staged'))
    else:
        pending_path = root / 'collection-pending.json'
        if pending_path.exists():
            pending = read_json(pending_path)
            if not native._validate_envelope(pending):
                raise ValueError('unsupported pending collection')
        else:
            pending = export(db)
            pending['revision'] = committed['revision'] + 1
            save_selection(args, identity)
            publish(pending_path, pending)
        publish(root / 'credentials.json', pending)
        scrub(db)
        idle(root)
    print('PASS: contained auth operation; project selection retained, native auth scrubbed')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as exc:
        print(f'contained auth operation refused: {exc}', file=sys.stderr)
        sys.exit(1)
