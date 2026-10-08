#!/usr/bin/env python3
"""Emit a read-only source inventory; no auth, Docker or native client access."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.run(
        ["git", "-C", str(ROOT), *args], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={"PATH": "/usr/bin:/bin", "GIT_OPTIONAL_LOCKS": "0"},
    ).stdout


def source_member(name):
    path = Path(name)
    # Inventory code and documentation only, including untracked implementation.
    # Provider files, homes, caches and downloaded artifacts are excluded.
    if any(part in {"__pycache__", "node_modules", ".git"} for part in path.parts):
        return False
    if path.name in {"providers.env", "meta-api-key", "auth.json", ".credentials.json"}:
        return False
    if path.name.endswith(".providers.env"):
        return False
    return (
        path.parts[0] in {"box", "specs", ".github"}
        or name in {"AGENTS.md", "README.md", "todo.md", ".gitignore", "LICENSE"}
    ) and (
        path.suffix in {".sh", ".py", ".bats", ".bash", ".md", ".json", ".toml", ".yml", ".yaml"}
        or path.name in {"Makefile", "Dockerfile", ".dockerignore", ".gitignore", "LICENSE"}
        or path.name.startswith("box-") and path.parent == Path("box")
        or path.name.startswith("version-") and path.suffix == ".env"
    )


def inventory():
    names = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    members = {}
    for name in sorted(set(os.fsdecode(n) for n in names.split(b"\0") if n)):
        if not source_member(name):
            continue
        path = ROOT / name
        try:
            before = path.lstat()
            if stat.S_ISLNK(before.st_mode):
                members[name] = {"kind": "symlink", "target": os.readlink(path)}
                continue
            if not stat.S_ISREG(before.st_mode):
                raise RuntimeError("non-regular source member: " + name)
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(fd, "rb") as stream:
                opened = os.fstat(stream.fileno())
                if (before.st_dev, before.st_ino) != (opened.st_dev, opened.st_ino):
                    raise RuntimeError("source replaced during capture: " + name)
                value = hashlib.file_digest(stream, "sha256").hexdigest()
                after = os.fstat(stream.fileno())
            current = path.lstat()
            identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
            if identity(opened) != identity(after) or identity(after) != identity(current):
                raise RuntimeError("source changed during capture: " + name)
            members[name] = {"kind": "file", "sha256": value,
                             "size": after.st_size, "mode": oct(stat.S_IMODE(after.st_mode))}
        except FileNotFoundError:
            members[name] = {"kind": "missing"}
    return members


def main():
    head = git("rev-parse", "HEAD").decode().strip()
    status = git("status", "--porcelain=v1", "-z", "--untracked-files=all")
    members = inventory()
    if head != git("rev-parse", "HEAD").decode().strip() or status != git(
        "status", "--porcelain=v1", "-z", "--untracked-files=all"
    ):
        raise RuntimeError("checkout changed during capture; retry while writers are idle")
    payload = json.dumps(members, sort_keys=True, separators=(",", ":")).encode()
    result = {
        "schema": 1,
        "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "scope": "source inventory only; not runtime, native, account, durability or CI acceptance",
        "root": str(ROOT), "head": head,
        "status_porcelain_v1_nul": os.fsdecode(status),
        "source_manifest_sha256": hashlib.sha256(payload).hexdigest(),
        "members": members,
        "host": {"system": platform.system(), "kernel": platform.release(),
                 "architecture": platform.machine(), "uid": os.getuid(), "gid": os.getgid(),
                 "python": platform.python_version()},
        "tools": {name: shutil.which(name) for name in
                  ("bash", "make", "jq", "python3", "shellcheck", "bats", "docker", "runsc")},
        "local_engine_socket_present": stat.S_ISSOCK(os.stat("/var/run/docker.sock").st_mode)
        if os.path.exists("/var/run/docker.sock") else False,
        "unqualified": ["Q02", "Q03", "Q04", "Q05", "Q06", "ARM64", "CI"],
    }
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
