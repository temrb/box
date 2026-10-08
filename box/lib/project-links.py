#!/usr/bin/env python3
"""Refuse regular-file hardlinks outside a selected project, without reading bytes.

Two descriptor-relative inventories must agree. Symlinks are never traversed.
Nested mounts refuse because they do not describe the nonrecursive project bind.
This detects observed races; it does not defend against a compromised host user.
"""
import argparse
from collections import Counter
import os
import stat
import sys

MAX_ENTRIES = 1_000_000
MAX_DEPTH = 256
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink,
            info.st_uid, info.st_gid, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def mount_id(fd):
    with open(f"/proc/self/fdinfo/{fd}", encoding="ascii") as stream:
        for line in stream:
            if line.startswith("mnt_id:"):
                return int(line.split()[1])
    raise ValueError("cannot identify project mount")


def inventory(root_fd):
    entries = {}
    root_mount = mount_id(root_fd)

    def visit(fd, prefix, depth):
        if depth > MAX_DEPTH:
            raise ValueError("project directory depth exceeds inspection limit")
        before = os.fstat(fd)
        entries[prefix] = signature(before)
        if len(entries) > MAX_ENTRIES:
            raise ValueError("project entry count exceeds inspection limit")
        # scandir accepts the already opened directory. No filename delimiters
        # are interpreted, including newlines and undecodable filesystem bytes.
        with os.scandir(fd) as children:
            names = sorted(child.name for child in children)
        if len(entries) + len(names) > MAX_ENTRIES:
            raise ValueError("project entry count exceeds inspection limit")
        for name in names:
            rel = prefix + "/" + name
            info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(info.st_mode):
                child_fd = os.open(name, DIR_FLAGS, dir_fd=fd)
                try:
                    if signature(os.fstat(child_fd)) != signature(info):
                        raise ValueError("project directory changed during inspection")
                    if mount_id(child_fd) != root_mount:
                        raise ValueError("nested project mounts require an independent copy")
                    visit(child_fd, rel, depth + 1)
                finally:
                    os.close(child_fd)
            else:
                entries[rel] = signature(info)
                if stat.S_ISREG(info.st_mode):
                    # O_PATH neither reads contents nor blocks on a substituted
                    # FIFO. It also lets us detect a file bind mount.
                    child_fd = os.open(name, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
                    try:
                        if signature(os.fstat(child_fd)) != signature(info):
                            raise ValueError("project file changed during inspection")
                        if mount_id(child_fd) != root_mount:
                            raise ValueError("nested project mounts require an independent copy")
                    finally:
                        os.close(child_fd)
            if signature(os.stat(name, dir_fd=fd, follow_symlinks=False)) != signature(info):
                raise ValueError("project member changed during inspection")
            if len(entries) > MAX_ENTRIES:
                raise ValueError("project entry count exceeds inspection limit")
        if signature(os.fstat(fd)) != signature(before):
            raise ValueError("project directory changed during inspection")

    visit(root_fd, ".", 0)
    return entries


def qualify(path):
    root_fd = os.open(path, DIR_FLAGS)
    try:
        first = inventory(root_fd)
        second = inventory(root_fd)
        if first != second or signature(os.stat(path, follow_symlinks=False)) != first["."]:
            raise ValueError("project changed between hardlink inventories")
        counts = Counter((item[0], item[1]) for item in first.values() if stat.S_ISREG(item[2]))
        for item in first.values():
            if stat.S_ISREG(item[2]) and item[3] != counts[(item[0], item[1])]:
                raise ValueError("project has external hardlinks; use an independent copy or git clone --no-hardlinks")
    finally:
        os.close(root_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project")
    args = parser.parse_args()
    try:
        qualify(args.project)
    except (OSError, ValueError, RecursionError) as exc:
        # File contents and member names are intentionally absent from reports.
        print(f"project hardlink inspection refused: {type(exc).__name__}: "
              f"{exc if isinstance(exc, ValueError) else 'cannot inspect every project member'}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
