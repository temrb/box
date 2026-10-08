"""Q06 driver regressions; run with python3 -I specs/test-qualify-host-filesystem.py."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "probe", Path(__file__).with_name("qualify-host-filesystem.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class QualificationTests(unittest.TestCase):
    def test_real_observations_and_exact_cleanup(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            sentinel = root / "foreign"
            sentinel.write_bytes(b"preserve")
            self.assertTrue(all(probe.probe(probe.validate_root(root)).values()))
            self.assertEqual(list(root.iterdir()), [sentinel])
            self.assertEqual(sentinel.read_bytes(), b"preserve")

    def test_symlink_and_writable_root_refuse(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            real = root / "real"
            real.mkdir(mode=0o700)
            link = root / "link"
            link.symlink_to(real, target_is_directory=True)
            with self.assertRaises(ValueError):
                probe.validate_root(link)
            nested = real / "nested"
            nested.mkdir(mode=0o700)
            with self.assertRaises(ValueError):
                probe.validate_root(link / "nested")
            real.chmod(0o770)
            with self.assertRaises(ValueError):
                probe.validate_root(real)

    def test_fsync_failure_cannot_be_reported_as_pass(self):
        with tempfile.TemporaryDirectory() as scratch:
            with patch.object(probe.os, "fsync", side_effect=OSError("injected I/O failure")):
                with self.assertRaises(OSError):
                    probe.probe(Path(scratch))
            self.assertEqual(list(Path(scratch).iterdir()), [])

    def test_inheritance_acknowledgement_failure_reaps_child_and_releases_lock(self):
        with tempfile.TemporaryDirectory() as scratch:
            lock = Path(scratch) / "lock"
            lock.touch(mode=0o600)
            with patch.object(probe, "wait_ready", side_effect=RuntimeError("injected timeout")):
                with self.assertRaises(RuntimeError):
                    probe.inheritance_observations(lock)
            self.assertFalse(probe.locked_elsewhere(lock))

    def test_exec_inheritance_is_observed_in_both_modes(self):
        with tempfile.TemporaryDirectory() as scratch:
            lock = Path(scratch) / "lock"
            lock.touch(mode=0o600)
            result = probe.inheritance_observations(lock)
            self.assertEqual(len(result), 4)
            self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
