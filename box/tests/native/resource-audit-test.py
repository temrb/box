"""Offline regressions for the disposable storage experiment."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location(
    "resource_audit", Path(__file__).with_name("resource-audit.py"))
audit = importlib.util.module_from_spec(spec)
# Avoid producing cache artifacts in the source tree.
exec(compile(Path(spec.origin).read_text(), spec.origin, "exec"), audit.__dict__)


class WorkloadTests(unittest.TestCase):
    def test_failed_compiler_stops_before_move(self):
        with tempfile.TemporaryDirectory() as root:
            # Shell functions inject a failed prerequisite and record any move;
            # only disposable paths are used, with no Docker access.
            workload = audit.storage_workload().replace("/scratch", root).replace("/source", root)
            result = subprocess.run(
                ["bash", "-c", 'gcc() { return 42; }; '
                 'mv() { touch moved; return 0; }; ' + workload],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 42)
            self.assertNotIn("executable_and_compile=pass", result.stdout)
            self.assertFalse((Path(root) / "moved").exists())

    def test_move_failure_remains_the_exit_status(self):
        with tempfile.TemporaryDirectory() as root:
            workload = audit.storage_workload().replace("/scratch", root).replace("/source", root)
            result = subprocess.run(
                ["bash", "-c", 'gcc() { printf "#!/bin/sh\\nexit 0\\n" > compiled; '
                 'chmod +x compiled; }; sleep() { :; }; mv() { return 28; }; ' + workload],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 28)
            self.assertIn("executable_and_compile=pass", result.stdout)
            self.assertIn("move_rc=28", result.stdout)


class CleanupTests(unittest.TestCase):
    def test_daemon_error_still_reaps_client(self):
        call = Mock(side_effect=subprocess.TimeoutExpired("docker rm", 15))
        proc = Mock()
        proc.poll.return_value = None
        with self.assertRaises(subprocess.TimeoutExpired):
            audit.cleanup_case(call, "fixture-owned-name", proc)
        call.assert_called_once_with("rm", "-f", "fixture-owned-name")
        proc.kill.assert_called_once_with()
        proc.communicate.assert_called_once_with(timeout=10)


if __name__ == "__main__":
    unittest.main()
