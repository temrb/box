#!/usr/bin/env python3
"""Real bounded filesystem exhaustion with synthetic host-only authority."""
import errno
import importlib.util
import os
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('auth_store', Path(__file__).parents[2] / 'lib/auth-store.py')
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


def qualify(root, kind):
    if kind not in ('blocks', 'inodes'):
        raise ValueError('unknown exhaustion fixture')
    root = Path(root)
    store.private_directory(root)
    stats = os.statvfs(root)
    if stats.f_blocks * stats.f_frsize > 40 * 1024 * 1024 or stats.f_files > 32768:
        raise ValueError('filesystem exceeds bounded disposable fixture')
    identity, locks, fillers = (root / n for n in ('identity', 'locks', 'fillers'))
    for directory in (identity, locks, fillers):
        directory.mkdir(mode=0o700)
    contract = store.Contract('fixture', 'sha256:' + 'c' * 64,
                              {'provider': lambda p: p == {'token': 'synthetic-exhaustion'}})
    authority = store.Store(str(identity), str(locks / 'auth.lock'), contract)
    created = []
    with authority.leased():
        authority.initialize()
        tx = authority.begin(0)
        original = (identity / 'canonical.json').read_bytes()
        exhausted = False
        try:
            if kind == 'blocks':
                path = fillers / 'blocks'
                created.append(path)
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                try:
                    # Consume every available block; loop bounds are independent
                    # of attacker-controlled disk geometry or free-space reports.
                    for _ in range(40 * 1024):
                        os.write(fd, b'x' * 1024)
                    raise ValueError('bounded filesystem did not exhaust blocks')
                finally:
                    os.close(fd)
            else:
                for number in range(32769):
                    path = fillers / str(number)
                    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                    os.close(fd)
                    created.append(path)
                raise ValueError('bounded filesystem did not exhaust inodes')
        except OSError as error:
            if error.errno != errno.ENOSPC:
                raise
            exhausted = True
        if not exhausted:
            raise ValueError('exhaustion not observed')
        full = os.statvfs(root)
        if kind == 'blocks' and full.f_bavail != 0 or kind == 'inodes' and full.f_favail != 0:
            raise ValueError('observed exhaustion does not match selected resource')
        members = {'provider': {'present': True, 'payload': {'token': 'synthetic-exhaustion'}}}
        try:
            authority.collect(tx, members)
        except OSError as error:
            if error.errno != errno.ENOSPC:
                raise
        else:
            raise ValueError('full filesystem unexpectedly accepted pending publication')
        if (identity / 'canonical.json').read_bytes() != original or authority.read()['revision'] != 0:
            raise ValueError('exhaustion changed canonical authority')
        if authority.journal()['stage'] != 'reserved':
            raise ValueError('failed collection acknowledged pending authority')
        # Only exact files created by this bounded fixture are removed.
        for path in reversed(created):
            path.unlink()
        directory_fd = os.open(fillers, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        authority.collect(tx, members)
        authority.publish(tx)
        authority.acknowledge_scrub(tx)
        authority.complete(tx)
        if authority.read()['revision'] != 1:
            raise ValueError('retry did not publish exactly one revision')
    print('P: ext4 ' + kind + ' ENOSPC preserves canonical and journal; same transaction retry commits revision 1')


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3:
            raise ValueError('expected private mounted fixture and exhaustion kind')
        qualify(sys.argv[1], sys.argv[2])
    except (OSError, ValueError, RecursionError):
        # No payload/path/native content is printed on refusal.
        print('Filesystem exhaustion qualification refused; gate remains open.', file=sys.stderr)
        sys.exit(1)
