#!/usr/bin/env python3
"""Bounded Q06 observations on synthetic files; never reads auth or Docker state."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import stat
import subprocess
import sys
import tempfile


def validate_root(root):
    root = Path(os.path.abspath(root))
    for path in (*reversed(root.parents), root):
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError("scratch ancestry must contain real directories")
    info = root.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("scratch root must be owned by the invoking user with mode 700")
    return root


def locked_elsewhere(path):
    with open(path, "rb") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
    return False


def wait_ready(child, expected):
    if not select.select([child.stdout], [], [], 5)[0]:
        raise RuntimeError("child acknowledgement timed out")
    # A single bounded read avoids waiting for an unterminated diagnostic line.
    if os.read(child.stdout.fileno(), 64) != expected:
        raise RuntimeError("child acknowledgement failed")


def reap(child):
    if child.poll() is None:
        child.kill()
    child.wait(timeout=5)
    child.stdout.close()


def inheritance_observations(lock):
    observations = {}
    code = "import signal; print('ready', flush=True); signal.pause()"
    for inherit in (False, True):
        fd = os.open(lock, os.O_RDONLY | os.O_NOFOLLOW)
        child = None
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            child = subprocess.Popen(
                [sys.executable, "-I", "-c", code],
                pass_fds=(fd,) if inherit else (), close_fds=True,
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                env={"PATH": "/usr/bin:/bin"},
            )
            wait_ready(child, b"ready\n")
            os.close(fd)
            fd = None
            key = "explicit_exec_inheritance_retains_lock" if inherit else "default_exec_drops_lock"
            observations[key] = locked_elsewhere(lock) == inherit
            child.kill()
            child.wait(timeout=5)
            observations[key + "_final_release"] = not locked_elsewhere(lock)
        finally:
            if fd is not None:
                os.close(fd)
            if child is not None:
                reap(child)
    return observations


def probe(root):
    observations = {}
    with tempfile.TemporaryDirectory(prefix="box-q06-", dir=root) as scratch:
        directory = Path(scratch)
        lock = directory / "stable.lock"
        lock.touch(mode=0o600)
        identity = (lock.stat().st_dev, lock.stat().st_ino)
        # Child acknowledges acquisition before the parent tests contention.
        child_code = """
import fcntl, signal, sys
with open(sys.argv[1], 'rb') as stream:
    fcntl.flock(stream, fcntl.LOCK_EX)
    print('locked', flush=True)
    signal.pause()
"""
        child = subprocess.Popen(
            [sys.executable, "-I", "-c", child_code, str(lock)],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env={"PATH": "/usr/bin:/bin"},
        )
        try:
            wait_ready(child, b"locked\n")
            observations["independent_process_contention"] = locked_elsewhere(lock)
            child.send_signal(signal.SIGKILL)
            child.wait(timeout=5)
            observations["sigkill_releases_lock"] = not locked_elsewhere(lock)
        finally:
            reap(child)
        observations.update(inheritance_observations(lock))
        target = directory / "revision.json"
        target.write_bytes(b'{"revision":0}\n')
        # An open reader must retain the old complete inode after publication.
        with open(target, "rb") as old_reader:
            staging = directory / "pending.json"
            fd = os.open(staging, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as stream:
                stream.write(b'{"revision":1}\n')
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(staging, target)
            directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
            observations["fsynced_replacement_readers"] = (
                old_reader.read() == b'{"revision":0}\n'
                and target.read_bytes() == b'{"revision":1}\n'
            )
        observations["stable_lock_inode"] = identity == (lock.stat().st_dev, lock.stat().st_ino)
        if not all(observations.values()):
            raise RuntimeError("host filesystem observation failed")
    return observations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-root", required=True)
    args = parser.parse_args()
    try:
        root = validate_root(args.scratch_root)
        observations = probe(root)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("host filesystem probe refused: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps({
        "schema": 1, "uid": os.getuid(), "gid": os.getgid(),
        "scratch_root": str(root), "observations": observations,
        "unqualified": ["power_loss", "vm_restart", "disk_full", "inode_full",
                        "production_descriptor_inheritance", "docker_client_loss", "daemon_failure",
                        "production_transaction_recovery", "filesystem_support_policy"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
