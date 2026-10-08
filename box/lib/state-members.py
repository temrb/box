#!/usr/bin/env python3
"""Checkpoint and remove an explicitly enumerated set of user-owned files."""
import os
from pathlib import Path
import stat
import sys
import importlib.util

spec = importlib.util.spec_from_file_location("transaction", Path(__file__).with_name("state-transaction.py"))
transaction = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transaction)


def describe(path):
    with transaction.host_fs.open_directory(path.parent) as parent_fd:
        info = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
        if info.st_uid != os.getuid():
            raise ValueError("foreign removal file")
        if stat.S_ISLNK(info.st_mode):
            # Only the exact setup-managed default symlink is removable here.
            target = os.readlink(path.name, dir_fd=parent_fd)
            if path.name != "box" or target != os.environ.get("BOX_STATE_DEFAULT_TARGET"):
                raise ValueError("unmanaged removal symlink")
            transaction.host_fs.verify_directory(path.parent, parent_fd)
            if transaction.host_fs.signature(os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)) != transaction.host_fs.signature(info):
                raise ValueError("removal symlink changed during inspection")
            return dict(kind="symlink", dev=info.st_dev, ino=info.st_ino, uid=info.st_uid, target=target)
    return transaction.regular_file(path, os.getuid())


def main():
    prepare_only = sys.argv[1] == "--prepare"
    argv = sys.argv[2:] if prepare_only else sys.argv[1:]
    journal = Path(argv[0])
    targets = sorted(set(argv[1:]))
    if any(not p.startswith("/") or os.path.normpath(p) != p for p in targets):
        raise ValueError("removal members must be exact absolute paths")
    if journal.exists() or journal.is_symlink():
        transaction.regular_file(journal, os.getuid())
        if stat.S_IMODE(journal.stat().st_mode) != 0o600:
            raise ValueError("unsafe member checkpoint mode")
        doc = transaction.host_fs.read_json(journal)
        if doc.get("format") != "box-members-v1" or doc.get("targets") != targets:
            raise ValueError("member recovery inventory changed")
    else:
        doc = dict(format="box-members-v1", targets=targets, members={})
        for name in targets:
            path = Path(name)
            if path.exists() or path.is_symlink():
                doc["members"][name] = describe(path)
        transaction.write_journal(journal, doc)
    # Validate every remaining member before removing the first one.
    for name in targets:
        path = Path(name)
        if path.exists() or path.is_symlink():
            if name not in doc["members"] or describe(path) != doc["members"][name]:
                raise ValueError("removal member changed")
    if prepare_only:
        return
    for name in targets:
        path = Path(name)
        if path.exists() or path.is_symlink():
            if describe(path) != doc["members"][name]:
                raise ValueError("removal member changed during deletion")
            if doc["members"][name]["kind"] == "file":
                transaction.host_fs.remove_file(path, doc["members"][name])
            else:
                with transaction.host_fs.open_directory(path.parent) as parent_fd:
                    transaction.host_fs.verify_directory(path.parent, parent_fd)
                    if describe(path) != doc["members"][name]:
                        raise ValueError("removal symlink changed before unlink")
                    os.unlink(path.name, dir_fd=parent_fd)
                    os.fsync(parent_fd)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"exact member removal refused: {exc}", file=sys.stderr)
        sys.exit(1)
