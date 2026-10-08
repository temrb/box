#!/usr/bin/env python3
"""Synthetic adversarial regression tests for the host filesystem primitives."""
import importlib.util
import json
import os
import select
import signal
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('host_fs', Path(__file__).parents[2] / 'lib/host-fs.py')
fs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fs)


class HostFilesystem(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='box-host-fs-')
        self.root = Path(self.temp.name)
        self.target = self.root / 'control.json'
        self.foreign = self.root / 'sentinel'
        self.foreign.write_bytes(b'foreign bytes')
        self.foreign.chmod(0o600)

    def tearDown(self):
        self.assertEqual(self.foreign.read_bytes(), b'foreign bytes')
        self.temp.cleanup()

    def seed(self):
        fs.write_json(self.target, {'revision': 1})

    def test_roundtrip_revision_mode_and_exact_removal(self):
        self.seed()
        fs.write_json(self.target, {'revision': 2})
        self.assertEqual(fs.read_json(self.target), {'revision': 2})
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.target.stat().st_nlink, 1)
        fs.remove_file(self.target, fs.describe_file(self.target))
        self.assertFalse(self.target.exists())
        self.assertFalse(list(self.root.glob('.box-control-*')))

    def test_shared_inode_symlink_fifo_and_unsafe_permissions_refuse(self):
        for kind in ('hardlink', 'symlink', 'fifo', 'writable'):
            with self.subTest(kind=kind):
                if kind == 'hardlink':
                    os.link(self.foreign, self.target)
                elif kind == 'symlink':
                    self.target.symlink_to(self.foreign)
                elif kind == 'fifo':
                    os.mkfifo(self.target, 0o600)
                else:
                    self.target.write_bytes(b'{}')
                    self.target.chmod(0o666)
                for operation in (lambda: fs.read_json(self.target),
                                  lambda: fs.write_json(self.target, {}),
                                  lambda: fs.describe_file(self.target)):
                    with self.assertRaises((OSError, ValueError)):
                        operation()
                self.target.unlink()

    def test_unsafe_ancestor_and_symlink_parent_refuse(self):
        parent = self.root / 'parent'
        parent.mkdir(mode=0o777)
        parent.chmod(0o777)
        with self.assertRaises(ValueError):
            fs.write_json(parent / 'control', {})
        parent.chmod(0o700)
        parent.rmdir()
        parent.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises((ValueError, OSError)):
            fs.write_json(parent / 'control', {})
        self.assertFalse((self.root / 'control').exists())

    def test_parent_replacement_refuses_before_publication(self):
        parent = self.root / 'parent'
        parent.mkdir(mode=0o700)
        original = fs.verify_directory
        def replace(path, fd, uid=None):
            if Path(path) == parent:
                parent.rename(self.root / 'displaced')
                parent.symlink_to(self.root, target_is_directory=True)
            return original(path, fd, uid)
        with patch.object(fs, 'verify_directory', replace):
            with self.assertRaises((ValueError, OSError)):
                fs.write_json(parent / 'new-control', {})
        self.assertFalse((self.root / 'new-control').exists())
        self.assertFalse(list((self.root / 'displaced').iterdir()))

    def test_failed_file_fsync_preserves_previous_revision_and_cleans_stage(self):
        self.seed()
        with patch.object(fs.os, 'fsync', side_effect=OSError('synthetic fsync failure')):
            with self.assertRaises(OSError):
                fs.write_json(self.target, {'revision': 2})
        self.assertEqual(fs.read_json(self.target), {'revision': 1})
        self.assertFalse(list(self.root.glob('.box-control-*')))

    def test_exclusive_publication_preserves_newly_appeared_target(self):
        original = fs.publish_new
        def competitor(fd, source, destination):
            self.target.write_bytes(b'competitor')
            self.target.chmod(0o600)
            original(fd, source, destination)
        with patch.object(fs, 'publish_new', competitor):
            with self.assertRaises(FileExistsError):
                fs.write_json(self.target, {})
        self.assertEqual(self.target.read_bytes(), b'competitor')
        self.assertFalse(list(self.root.glob('.box-control-*')))

    def test_truncated_duplicate_nonfinite_and_oversize_control_json_refuse(self):
        for payload in (b'{', b'{"revision":1,"revision":2}', b'{"n":NaN}', b'[]'):
            self.target.write_bytes(payload)
            self.target.chmod(0o600)
            with self.assertRaises((ValueError, json.JSONDecodeError)):
                fs.read_json(self.target)
        with self.assertRaises(ValueError):
            fs.read_file(self.target, limit=1)

    def test_change_during_read_refuses(self):
        self.seed()
        original = fs.os.read
        changed = False
        def mutation(fd, size):
            nonlocal changed
            data = original(fd, size)
            if not changed:
                changed = True
                self.target.write_bytes(b'{"revision":9}')
            return data
        with patch.object(fs.os, 'read', mutation):
            with self.assertRaises(ValueError):
                fs.read_json(self.target)

    def test_recreated_or_modified_removal_member_is_preserved(self):
        self.seed()
        expected = fs.describe_file(self.target)
        self.target.write_bytes(b'{"revision":2}')
        with self.assertRaises(ValueError):
            fs.remove_file(self.target, expected)
        self.target.rename(self.root / 'original')
        self.seed()
        with self.assertRaises(ValueError):
            fs.remove_file(self.target, expected)
        self.assertTrue(self.target.exists())

    def test_rewriting_identical_bytes_does_not_reuse_old_removal_authority(self):
        self.seed()
        expected = fs.describe_file(self.target)
        data = self.target.read_bytes()
        self.target.write_bytes(data)
        with self.assertRaises(ValueError):
            fs.remove_file(self.target, expected)
        self.assertEqual(self.target.read_bytes(), data)

    def test_descriptors_are_not_inheritable_and_relative_coordinates_refuse(self):
        with fs.open_directory(self.root) as fd:
            self.assertFalse(os.get_inheritable(fd))
        for path in ('relative', str(self.root) + '/../escape'):
            with self.assertRaises(ValueError):
                fs.write_json(path, {})

    def test_real_lock_contention_sigkill_release_and_stable_inode(self):
        lock = self.root / 'stable.lock'
        code = """import importlib.util, sys, time
spec = importlib.util.spec_from_file_location('fs', sys.argv[1])
fs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fs)
with fs.open_lock(sys.argv[2]):
    print('locked', flush=True)
    time.sleep(30)
"""
        child = subprocess.Popen([sys.executable, '-I', '-c', code, spec.origin, str(lock)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertTrue(select.select([child.stdout], [], [], 5)[0], 'child failed to acknowledge lock')
            self.assertEqual(os.read(child.stdout.fileno(), 7), b'locked\n')
            inode = lock.stat().st_ino
            with self.assertRaises(BlockingIOError):
                with fs.open_lock(lock):
                    self.fail('contender acquired a held lock')
            child.send_signal(signal.SIGKILL)
            child.wait(timeout=5)
            with fs.open_lock(lock) as fd:
                self.assertEqual(os.fstat(fd).st_ino, inode)
                self.assertFalse(os.get_inheritable(fd))
        finally:
            if child.poll() is None:
                child.kill()
            child.communicate(timeout=5)

    def test_lock_descriptor_is_closed_by_exec_even_without_close_fds(self):
        lock = self.root / 'stable.lock'
        with fs.open_lock(lock) as fd:
            code = """import os, sys
try:
    os.fstat(int(sys.argv[1]))
except OSError:
    print('closed')
else:
    sys.exit(1)
"""
            child = subprocess.run([sys.executable, '-I', '-c', code, str(fd)],
                                   close_fds=False, capture_output=True, timeout=5)
            self.assertEqual(child.returncode, 0)
            self.assertEqual(child.stdout, b'closed\n')

    def test_exact_directory_removal_refuses_recreated_or_nonempty_directory(self):
        directory = self.root / 'directory'
        directory.mkdir(mode=0o700)
        expected = fs.describe_directory(directory.stat())
        (directory / 'member').write_bytes(b'synthetic')
        with self.assertRaises(ValueError):
            fs.remove_directory(directory, expected)
        (directory / 'member').unlink()
        directory.rename(self.root / 'old-directory')
        directory.mkdir(mode=0o700)
        with self.assertRaises(ValueError):
            fs.remove_directory(directory, expected)
        fs.remove_directory(directory, fs.describe_directory(directory.stat()))
        self.assertFalse(directory.exists())


if __name__ == '__main__':
    unittest.main()
