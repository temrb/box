#!/usr/bin/env python3
"""Synthetic schema-2 authority tests; never imports a native auth store."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).parents[2] / 'lib/auth-store.py'
spec = importlib.util.spec_from_file_location('auth_store', SOURCE)
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


def contract():
    return store.Contract('fixture', 'sha256:' + 'a' * 64,
                          {'provider': lambda p: type(p) is dict and set(p) == {'token'} and
                           isinstance(p['token'], str) and len(p['token']) < 1024,
                           'mcp': lambda p: type(p) is dict and set(p) == {'token'}})


def members(token='synthetic-private-sentinel'):
    return {'provider': {'present': True, 'payload': {'token': token}}, 'mcp': {'present': False}}


class HostAuthority(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='box-auth-store-')
        self.root = Path(self.temp.name)
        self.identity = self.root / 'identity'
        self.identity.mkdir(mode=0o700)
        self.lock = self.root / 'authority.lock'
        self.authority = store.Store(str(self.identity), str(self.lock), contract())
        with self.authority.leased():
            self.authority.initialize()

    def tearDown(self):
        self.temp.cleanup()

    def transaction(self):
        tx = self.authority.begin(self.authority.read()['revision'])
        self.authority.collect(tx, members())
        self.authority.publish(tx)
        self.authority.acknowledge_scrub(tx)
        self.authority.complete(tx)
        return tx

    def test_revision_member_absence_tombstone_and_private_metadata(self):
        with self.authority.leased():
            self.assertTrue(self.authority.read()['tombstone'])
            self.transaction()
            self.assertEqual(self.authority.read()['revision'], 1)
            tx = self.authority.begin(1)
            self.authority.collect(tx, {n: {'present': False} for n in contract().validators})
            self.authority.publish(tx)
            self.assertTrue(self.authority.read()['tombstone'])
            self.assertEqual(self.authority.read()['revision'], 2)
        journal = (self.identity / 'journal.json').read_text()
        self.assertNotIn('synthetic-private-sentinel', journal)
        self.assertNotIn('members', journal)
        for f in self.identity.iterdir():
            self.assertEqual(f.stat().st_mode & 0o777, 0o600)
            self.assertEqual(f.stat().st_nlink, 1)

    def test_no_mutation_without_external_stable_lease(self):
        before = (self.identity / 'canonical.json').read_bytes()
        for operation in (self.authority.read, self.authority.initialize, lambda: self.authority.begin(0)):
            with self.assertRaises(ValueError):
                operation()
        self.assertEqual((self.identity / 'canonical.json').read_bytes(), before)
        with self.authority.leased():
            identity = (self.lock.stat().st_dev, self.lock.stat().st_ino)
            self.transaction()
        with self.authority.leased():
            self.assertEqual(identity, (self.lock.stat().st_dev, self.lock.stat().st_ino))

    def test_legacy_or_unacknowledged_members_refuse_without_shadowing(self):
        for name in ('credentials.json', 'identity.json', '.box-control-' + 'a' * 32):
            with self.subTest(name=name):
                identity = self.root / ('legacy-' + name)
                identity.mkdir(mode=0o700)
                member = identity / name
                member.write_bytes(b'synthetic-displaced-authority')
                member.chmod(0o600)
                authority = store.Store(str(identity), str(self.root / (name + '.lock')), contract())
                with authority.leased():
                    for operation in (authority.initialize, authority.read, lambda: authority.begin(0)):
                        with self.assertRaises(ValueError):
                            operation()
                self.assertEqual(member.read_bytes(), b'synthetic-displaced-authority')
                self.assertFalse((identity / 'canonical.json').exists())

    def test_unknown_schema_authority_and_invalid_revisions_preserve_source(self):
        initial = json.loads((self.identity / 'canonical.json').read_text())
        mutants = [dict(initial, schema=1), dict(initial, schema=True), dict(initial, revision=True),
                   dict(initial, revision=-1), dict(initial, revision=1),
                   dict(initial, native_manifest='sha256:' + 'b' * 64), dict(initial, path='/foreign'),
                   dict(initial, members={'unknown': {'present': False}}),
                   dict(initial, tombstone=False)]
        for mutant in mutants:
            raw = json.dumps(mutant).encode()
            (self.identity / 'canonical.json').write_bytes(raw)
            with self.authority.leased():
                with self.assertRaises(ValueError):
                    self.authority.begin(0)
            self.assertEqual((self.identity / 'canonical.json').read_bytes(), raw)
        for raw in (b'{"schema":2,"schema":2}', b'not-json-private-sentinel', b'{"revision":NaN}'):
            (self.identity / 'canonical.json').write_bytes(raw)
            with self.authority.leased():
                with self.assertRaises(ValueError):
                    self.authority.read()
            self.assertEqual((self.identity / 'canonical.json').read_bytes(), raw)

    def test_native_data_cannot_select_paths_revisions_stages_or_members(self):
        with self.authority.leased():
            tx = self.authority.begin(0)
            for mutant in ({'provider': {'present': True, 'payload': {'token': 'x'}, 'path': '/foreign'},
                            'mcp': {'present': False}},
                           {'provider': {'present': False, 'payload': {}}, 'mcp': {'present': False}},
                           {'provider': {'present': True, 'payload': {'token': 'x', 'revision': 9}},
                            'mcp': {'present': False}}, {'unknown': {'present': False}}):
                with self.assertRaises(ValueError):
                    self.authority.collect(tx, mutant)
            self.assertEqual(self.authority.read()['revision'], 0)
            self.assertEqual(self.authority.journal()['stage'], 'reserved')
            self.assertFalse((self.identity / 'pending.json').exists())

    def test_conflicting_revision_transaction_and_incomplete_operation_refuse(self):
        with self.authority.leased():
            with self.assertRaises(ValueError):
                self.authority.begin(1)
            tx = self.authority.begin(0)
            with self.assertRaises(ValueError):
                self.authority.begin(0)
            with self.assertRaises(ValueError):
                self.authority.collect('b' * 32, members())
            with self.assertRaises(ValueError):
                self.authority.publish(tx)
            with self.assertRaises(ValueError):
                self.authority.complete(tx)
            self.authority.collect(tx, members())
            with self.assertRaises(ValueError):
                self.authority.acknowledge_scrub(tx)
            with self.assertRaises(ValueError):
                self.authority.collect(tx, members('changed'))
            self.assertEqual(self.authority.read()['revision'], 0)

    def test_pending_missing_corrupt_or_changed_never_becomes_logout(self):
        with self.authority.leased():
            tx = self.authority.begin(0)
            self.authority.collect(tx, members())
            raw = (self.identity / 'pending.json').read_bytes()
            for value in (b'{}', raw.replace(b'synthetic-private-sentinel', b'changed')):
                (self.identity / 'pending.json').write_bytes(value)
                with self.assertRaises(ValueError):
                    self.authority.publish(tx)
                self.assertEqual(self.authority.read()['revision'], 0)
            (self.identity / 'pending.json').unlink()
            with self.assertRaises(FileNotFoundError):
                self.authority.publish(tx)
            self.assertEqual(self.authority.journal()['stage'], 'pending')

    def test_symlink_shared_inode_unsafe_parent_and_lock_replacement_refuse(self):
        canonical = self.identity / 'canonical.json'
        canonical.rename(self.root / 'preserved')
        canonical.symlink_to(self.root / 'preserved')
        with self.authority.leased():
            with self.assertRaises((ValueError, OSError)):
                self.authority.read()
        canonical.unlink()
        os.link(self.root / 'preserved', canonical)
        with self.authority.leased():
            with self.assertRaises(ValueError):
                self.authority.read()
        canonical.unlink()
        (self.root / 'preserved').rename(canonical)
        with self.authority.leased():
            self.lock.rename(self.root / 'old-lock')
            self.lock.touch(mode=0o600)
            with self.assertRaises(ValueError):
                self.authority.begin(0)
        self.identity.chmod(0o755)
        with self.assertRaises(ValueError):
            with self.authority.leased():
                pass
        with self.assertRaises(ValueError):
            store.Store(str(self.identity), str(self.identity / 'lease.lock'), contract())

    def test_replaced_identity_and_changed_base_refuse(self):
        with self.authority.leased():
            tx = self.authority.begin(0)
            canonical = self.authority.read()
            canonical['revision'] = 1
            canonical['transaction'] = 'a' * 32
            store.fs.write_json(self.identity / 'canonical.json', canonical)
            with self.assertRaises(ValueError):
                self.authority.collect(tx, members())
            self.identity.rename(self.root / 'old-identity')
            self.identity.mkdir(mode=0o700)
            with self.assertRaises(ValueError):
                self.authority.read()

    def test_fsync_failure_retains_recoverable_canonical_and_pending(self):
        with self.authority.leased():
            tx = self.authority.begin(0)
            self.authority.collect(tx, members())
            original = store.fs.os.fsync
            calls = 0
            def fail_after_rename(fd):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError('synthetic directory fsync failure')
                return original(fd)
            with patch.object(store.fs.os, 'fsync', fail_after_rename):
                with self.assertRaises(OSError):
                    self.authority.publish(tx)
            self.assertEqual(self.authority.journal()['stage'], 'pending')
            self.assertEqual(self.authority.publish(tx), 1)
            self.authority.acknowledge_scrub(tx)
            self.authority.complete(tx)
            self.assertEqual(self.authority.read()['revision'], 1)

    def test_real_process_contention_does_not_publish(self):
        child_code = '''
import importlib.util,sys
s=importlib.util.spec_from_file_location('store',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
c=m.Contract('fixture','sha256:'+'a'*64,{'provider':lambda p: True,'mcp':lambda p: True})
a=m.Store(sys.argv[2],sys.argv[3],c)
try:
 with a.leased(): a.begin(0)
except BlockingIOError: sys.exit(23)
sys.exit(1)
'''
        with self.authority.leased():
            result = subprocess.run([sys.executable, '-I', '-c', child_code, str(SOURCE),
                                     str(self.identity), str(self.lock)], capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 23, result.stderr)
            self.assertFalse((self.identity / 'journal.json').exists())

    def test_forked_caller_cannot_use_inherited_authority(self):
        with self.authority.leased():
            pid = os.fork()
            if pid == 0:
                try:
                    self.authority.begin(0)
                except ValueError:
                    os._exit(23)
                os._exit(1)
            _, status = os.waitpid(pid, 0)
            self.assertEqual(os.waitstatus_to_exitcode(status), 23)
            self.assertFalse((self.identity / 'journal.json').exists())

    def test_sigkill_at_durable_boundaries_recovers_same_revision(self):
        child_code = '''
import importlib.util,sys,signal
s=importlib.util.spec_from_file_location('store',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
c=m.Contract('fixture','sha256:'+'a'*64,{'provider':lambda p: True,'mcp':lambda p: True})
a=m.Store(sys.argv[2],sys.argv[3],c)
original=a._write
def boundary(name,value):
 original(name,value)
 if (sys.argv[4]=='pending-file' and name=='pending.json' or
     sys.argv[4]=='canonical-file' and name=='canonical.json' or
     name=='journal.json' and value['stage']==sys.argv[4]):
  print('durable',flush=True);signal.pause()
a._write=boundary
with a.leased():
 tx=a.begin(0)
 a.collect(tx,{'provider':{'present':True,'payload':{'token':'synthetic-private-sentinel'}},'mcp':{'present':False}})
 a.publish(tx);a.acknowledge_scrub(tx);a.complete(tx)
'''
        for stage in ('reserved', 'pending-file', 'pending', 'canonical-file', 'published', 'scrubbed', 'complete'):
            with self.subTest(stage=stage):
                identity = self.root / stage
                identity.mkdir(mode=0o700)
                lock = self.root / (stage + '.lock')
                authority = store.Store(str(identity), str(lock), contract())
                with authority.leased():
                    authority.initialize()
                child = subprocess.Popen([sys.executable, '-I', '-c', child_code, str(SOURCE),
                                          str(identity), str(lock), stage], stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE)
                try:
                    self.assertTrue(select.select([child.stdout], [], [], 5)[0])
                    self.assertEqual(os.read(child.stdout.fileno(), 64), b'durable\n')
                    child.send_signal(signal.SIGKILL)
                    child.wait(timeout=5)
                    with authority.leased():
                        journal = authority.journal()
                        tx = journal['transaction']
                        if journal['stage'] == 'reserved':
                            authority.collect(tx, members())
                        authority.publish(tx)
                        authority.acknowledge_scrub(tx)
                        authority.complete(tx)
                        self.assertEqual(authority.read()['revision'], 1)
                        self.assertEqual(authority.journal()['stage'], 'complete')
                        with self.assertRaises(ValueError):
                            authority.begin(0)
                finally:
                    if child.poll() is None:
                        child.kill()
                    child.wait(timeout=5)
                    child.stdout.close()
                    child.stderr.close()

    def test_interrupted_pending_recollection_must_match(self):
        with self.authority.leased():
            tx = self.authority.begin(0)
            pending = contract().envelope(1, tx, members())
            store.fs.write_json(self.identity / 'pending.json', pending)
            with self.assertRaises(ValueError):
                self.authority.publish(tx)
            with self.assertRaises(ValueError):
                self.authority.collect(tx, members('different'))
            self.authority.collect(tx, members())
            self.assertEqual(self.authority.publish(tx), 1)


if __name__ == '__main__':
    unittest.main()
