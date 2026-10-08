#!/usr/bin/env python3
"""Real subprocess lock-set checks using disposable synthetic identities."""
import importlib.util
import os
import select
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).parents[2] / 'lib/host-locks.py'
spec = importlib.util.spec_from_file_location('host_locks', SOURCE)
locks = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = locks
spec.loader.exec_module(locks)


class LockSets(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.a = locks.Request('auth', '/synthetic/auth/a')
        self.b = locks.Request('auth', '/synthetic/auth/b')

    def tearDown(self):
        self.tmp.cleanup()

    def other(self, identities):
        code = '''import importlib.util,sys
s=importlib.util.spec_from_file_location('locks',sys.argv[1]); m=importlib.util.module_from_spec(s);sys.modules[s.name]=m;s.loader.exec_module(m)
try:
 with m.Lease(sys.argv[2],[m.Request('auth',v) for v in sys.argv[3:]]).held(): pass
except BlockingIOError: sys.exit(17)
'''
        return subprocess.run([sys.executable, '-I', '-c', code, str(SOURCE), str(self.root), *identities],
                              capture_output=True, timeout=5).returncode

    def test_order_deduplication_and_stable_resource_identity(self):
        lifecycle = locks.Request('lifecycle', 'fixture', 2)
        requests = [self.b, locks.Request('native', '/native'), lifecycle,
                    self.a, locks.Request('installation', 'global'), self.a]
        lease = locks.Lease(self.root, requests)
        self.assertEqual([r.category for r in lease.requests], ['installation', 'lifecycle', 'auth', 'auth', 'native'])
        self.assertEqual(lifecycle.member, locks.Request('lifecycle', 'fixture', 7).member)
        with lease.held():
            inode = os.fstat(lease.descriptor(self.a)).st_ino
            with self.assertRaises(ValueError):
                with lease.held(): pass
        with lease.held():
            self.assertEqual(os.fstat(lease.descriptor(self.a)).st_ino, inode)
            for request in lease.requests:
                self.assertFalse(os.get_inheritable(lease.descriptor(request)))
        self.assertEqual(len(list(self.root.iterdir())), 5)

    def test_opposite_direction_contenders_fail_and_release_partial_sets(self):
        with locks.Lease(self.root, [self.b]).held():
            self.assertEqual(self.other([self.b.identity, self.a.identity]), 17)
            # The contender acquired a before encountering b; it must release a.
            self.assertEqual(self.other([self.a.identity]), 0)
        self.assertEqual(self.other([self.b.identity, self.a.identity]), 0)

    def test_changed_lock_or_index_refuses_without_touching_foreign_bytes(self):
        lease = locks.Lease(self.root, [self.a])
        with lease.held():
            member = self.root / self.a.member
            original = self.root / 'retained-lock'
            member.rename(original)
            member.write_bytes(b'foreign')
            member.chmod(0o600)
            with self.assertRaises(ValueError): lease.verify()
            self.assertEqual(member.read_bytes(), b'foreign')
        with self.assertRaises(ValueError): lease.verify()
        self.root.chmod(0o770)
        with self.assertRaises(ValueError):
            with lease.held(): pass
        self.root.chmod(0o700)

    def test_fork_child_has_no_authority(self):
        lease = locks.Lease(self.root, [self.a])
        with lease.held():
            pid = os.fork()
            if pid == 0:
                try: lease.descriptor(self.a)
                except ValueError: os._exit(0)
                os._exit(1)
            _, status = os.waitpid(pid, 0)
            self.assertEqual(os.waitstatus_to_exitcode(status), 0)
            lease.verify()

    def test_sigkill_releases_complete_set_without_removing_inodes(self):
        code = '''import importlib.util,signal,sys
s=importlib.util.spec_from_file_location('locks',sys.argv[1]);m=importlib.util.module_from_spec(s);sys.modules[s.name]=m;s.loader.exec_module(m)
with m.Lease(sys.argv[2],[m.Request('auth',v) for v in sys.argv[3:]]).held():
 print('held',flush=True);signal.pause()
'''
        child = subprocess.Popen([sys.executable, '-I', '-c', code, str(SOURCE), str(self.root),
                                  self.a.identity, self.b.identity], stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL)
        try:
            self.assertTrue(select.select([child.stdout], [], [], 5)[0])
            self.assertEqual(child.stdout.readline(), b'held\n')
            before = {p.name: p.stat().st_ino for p in self.root.iterdir()}
            self.assertEqual(self.other([self.a.identity, self.b.identity]), 17)
            child.kill()
            child.wait(timeout=5)
            self.assertEqual(self.other([self.a.identity, self.b.identity]), 0)
            self.assertEqual({p.name: p.stat().st_ino for p in self.root.iterdir()}, before)
        finally:
            if child.poll() is None: child.kill()
            child.wait(timeout=5)
            child.stdout.close()

    def test_exec_child_cannot_keep_parent_lease_alive(self):
        lease = locks.Lease(self.root, [self.a, self.b])
        with lease.held():
            child = subprocess.Popen([sys.executable, '-I', '-c',
                                      "import signal; print('ready',flush=True); signal.pause()"],
                                     close_fds=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self.assertTrue(select.select([child.stdout], [], [], 5)[0])
            self.assertEqual(child.stdout.readline(), b'ready\n')
        try:
            self.assertEqual(self.other([self.b.identity, self.a.identity]), 0)
        finally:
            child.kill()
            child.wait(timeout=5)
            child.stdout.close()

    def test_invalid_and_conflicting_order_requests_refuse(self):
        for args in [('unknown','x'), ('auth',''), ('auth','x',True), ('native','x',1), ('auth','x\n')]:
            with self.assertRaises(ValueError): locks.Request(*args)
        with self.assertRaises(ValueError): locks.Lease(self.root, [])
        with self.assertRaises(ValueError):
            locks.Lease(self.root, [locks.Request('lifecycle','x',1),locks.Request('lifecycle','x',2)])
        self.assertEqual(list(self.root.iterdir()), [])


if __name__ == '__main__': unittest.main()
