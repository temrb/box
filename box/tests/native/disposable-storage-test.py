#!/usr/bin/env python3
"""Artifact extraction/provenance regressions; no downloads or native execution."""
import importlib.util
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('disposable_storage', Path(__file__).with_name('disposable-storage.py'))
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class Artifacts(unittest.TestCase):
    def archive(self, root, members):
        path = root / 'package.tar.gz'
        with tarfile.open(path, 'w:gz') as package:
            for name, kind, contents in members:
                member = tarfile.TarInfo(name)
                member.mode = 0o755
                member.type = kind
                member.size = len(contents) if kind == tarfile.REGTYPE else 0
                member.linkname = '/foreign'
                package.addfile(member, io.BytesIO(contents) if kind == tarfile.REGTYPE else None)
        return path

    def test_extracts_only_expected_regular_executable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = self.archive(root, [('bin/codex', tarfile.REGTYPE, b'executable'),
                                          ('../../foreign', tarfile.REGTYPE, b'preserve')])
            storage.executable(archive, 'bin/codex', root / 'binary')
            self.assertEqual((root / 'binary').read_bytes(), b'executable')
            self.assertEqual((root / 'binary').stat().st_mode & 0o777, 0o700)
            self.assertEqual({p.name for p in root.iterdir()}, {'binary', 'package.tar.gz'})

    def test_duplicate_or_link_executable_refuses_before_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for members in ([('bin/codex', tarfile.SYMTYPE, b'')],
                            [('bin/codex', tarfile.LNKTYPE, b'')],
                            [('bin/codex', tarfile.REGTYPE, b'x')] * 2):
                archive = self.archive(root, members)
                with self.assertRaises(ValueError): storage.executable(archive, 'bin/codex', root / 'binary')
                self.assertFalse((root / 'binary').exists())

    def test_existing_executable_and_foreign_sentinel_survive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = self.archive(root, [('opencode', tarfile.REGTYPE, b'new')])
            sentinel = root / 'sentinel'
            sentinel.write_bytes(b'foreign')
            (root / 'binary').symlink_to(sentinel)
            with self.assertRaises(FileExistsError): storage.executable(archive, 'opencode', root / 'binary')
            self.assertEqual(sentinel.read_bytes(), b'foreign')

    def test_corrupt_artifact_and_invalid_digest_never_execute(self):
        with tempfile.TemporaryDirectory() as tmp:
            artifact = Path(tmp) / 'package'
            def fake_run(argv, **kwargs):
                artifact.write_bytes(b'corrupt')
                return subprocess.CompletedProcess(argv, 0)
            with patch.object(storage, 'run', side_effect=fake_run) as run:
                with self.assertRaises(ValueError): storage.download('https://fixture.invalid', artifact, 'a' * 64)
                self.assertEqual(run.call_count, 1)
                with self.assertRaises(ValueError): storage.download('https://fixture.invalid', artifact, 'not-a-pin')
                self.assertEqual(run.call_count, 1)


if __name__ == '__main__': unittest.main()
