#!/usr/bin/env python3
"""Durable exact-member manifest for resolver-authorized state removal."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

import importlib.util

_fs_spec = importlib.util.spec_from_file_location("box_host_fs", Path(__file__).with_name("host-fs.py"))
host_fs = importlib.util.module_from_spec(_fs_spec)
_fs_spec.loader.exec_module(host_fs)


def fail(message):
    raise ValueError(message)


def regular_file(path, uid):
    return host_fs.describe_file(path, uid)


def capture(root, uid):
    entries = {}
    with host_fs.open_directory(root, uid) as root_fd:
        def visit(fd, prefix, depth):
            if depth > 256 or len(entries) > 100_000:
                fail("reset tree exceeds bounded inventory limit")
            before = os.fstat(fd)
            if before.st_uid != uid or before.st_mode & 0o022:
                fail("unsafe reset directory")
            entries[prefix] = host_fs.describe_directory(before)
            for name in sorted(os.listdir(fd)):
                rel = name if prefix == "." else prefix + "/" + name
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    child_fd = os.open(name, host_fs.DIR_FLAGS, dir_fd=fd)
                    try:
                        if host_fs.signature(info) != host_fs.signature(os.fstat(child_fd)):
                            fail("reset directory changed while opening")
                        if host_fs.mount_id(child_fd) != host_fs.mount_id(root_fd):
                            fail("reset tree crosses mount boundary")
                        visit(child_fd, rel, depth + 1)
                    finally:
                        os.close(child_fd)
                else:
                    data, info = host_fs.read_at(fd, name, uid, limit=host_fs.MAX_MEMBER_BYTES)
                    entries[rel] = {"kind": "file", "dev": info.st_dev, "ino": info.st_ino,
                                    "mode": stat.S_IMODE(info.st_mode), "uid": info.st_uid,
                                    "size": info.st_size, "ctime_ns": info.st_ctime_ns,
                                    "sha256": hashlib.sha256(data).hexdigest()}
                if len(entries) > 100_000:
                    fail("reset tree exceeds bounded inventory limit")
            if host_fs.signature(os.fstat(fd)) != host_fs.signature(before):
                fail("reset directory changed during inventory")
        visit(root_fd, ".", 0)
        host_fs.verify_directory(root, root_fd, uid)
    return entries


def write_journal(path, doc):
    host_fs.write_json(path, doc)


def read_journal(path):
    doc = host_fs.read_json(path)
    if doc.get("format") != "box-reset-v1" or doc.get("stage") not in {
            "planned", "home_removed", "volume_removed", "auth_removed"}:
        fail("unknown or malformed reset journal")
    root = doc.get("root")
    if not isinstance(root, str) or (root and (not os.path.isabs(root) or os.path.normpath(root) != root)):
        fail("invalid reset root")
    for rel, item in doc.get("home", {}).items():
        if rel != "." and (not rel or rel.startswith("/") or any(p in ("", ".", "..") for p in rel.split("/"))):
            fail("escaping reset member")
        if item.get("kind") not in ("dir", "file"):
            fail("invalid reset member kind")
    return doc


def verify_remaining(root, entries):
    if not root.exists() and not root.is_symlink():
        return
    actual = capture(root, os.getuid())
    if not actual.keys() <= entries.keys():
        fail("reset home gained an unrecorded member")
    if any(item != entries[rel] for rel, item in actual.items()):
        fail("reset home member changed")


def remove_home(root, entries):
    verify_remaining(root, entries)
    if not root.exists():
        return
    for rel in sorted((x for x in entries if x != "."),
                      key=lambda value: (value.count("/"), value), reverse=True):
        path = root / rel
        if not path.exists() and not path.is_symlink():
            continue
        expected = entries[rel]
        info = path.lstat()
        if expected["kind"] == "file":
            host_fs.remove_file(path, expected)
        else:
            host_fs.remove_directory(path, expected)
    if root.exists():
        host_fs.remove_directory(root, entries["."])


def main():
    parser = argparse.ArgumentParser()
    subs = parser.add_subparsers(dest="command", required=True)
    prep = subs.add_parser("prepare")
    prep.add_argument("--journal", required=True)
    prep.add_argument("--root", required=True)
    prep.add_argument("--harness", required=True)
    prep.add_argument("--uid", required=True, type=int)
    prep.add_argument("--gid", required=True, type=int)
    prep.add_argument("--project-hash", required=True)
    prep.add_argument("--volume", required=True)
    prep.add_argument("--volume-identity", default="")
    prep.add_argument("--auth", default="")
    prep.add_argument("--keep-auth", action="store_true")
    prep.add_argument("--domain", default="production", choices=("production", "test"))
    remove = subs.add_parser("remove-home")
    remove.add_argument("--journal", required=True)
    stage = subs.add_parser("stage")
    stage.add_argument("--journal", required=True)
    stage.add_argument("--value", required=True,
                       choices=("planned", "home_removed", "volume_removed", "auth_removed"))
    finish = subs.add_parser("finish")
    finish.add_argument("--journal", required=True)
    verify_volume = subs.add_parser("verify-volume")
    verify_volume.add_argument("--journal", required=True)
    verify_volume.add_argument("--volume-identity", required=True)
    args = parser.parse_args()
    journal = Path(args.journal)
    if args.command == "prepare":
        root = Path(args.root) if args.root else None
        if root is not None and root.exists():
            entries = capture(root, args.uid)
        else:
            entries = {}
        expected = {"format": "box-reset-v1", "harness": args.harness,
                    "uid": args.uid, "gid": args.gid,
                    "project_hash": args.project_hash, "root": str(root) if root else "",
                    "auth": args.auth, "keep_auth": args.keep_auth, "domain": args.domain,
                    "volume": args.volume, "volume_identity": args.volume_identity, "stage": "planned", "home": entries}
        if journal.exists():
            old = read_journal(journal)
            for key in ("format", "harness", "uid", "gid", "project_hash", "root", "volume", "auth", "keep_auth", "domain"):
                if old.get(key) != expected[key]:
                    fail("reset recovery identity changed")
            if args.volume_identity and old.get("volume_identity", "") != args.volume_identity:
                fail("reset volume was replaced after checkpoint publication")
            if root is not None:
                verify_remaining(root, old["home"])
            return
        write_journal(journal, expected)
    elif args.command == "verify-volume":
        doc = read_journal(journal)
        # An absent volume is handled by the caller without deletion. A
        # surviving name needs the original, nonempty creation identity.
        if not args.volume_identity or not doc.get("volume_identity"):
            fail("volume deletion requires recorded creation identity")
        actual = json.loads(args.volume_identity, object_pairs_hook=host_fs.unique_object)
        recorded = json.loads(doc["volume_identity"], object_pairs_hook=host_fs.unique_object)
        if type(actual) is not dict or actual != recorded or actual.get("Name") != doc["volume"]:
            fail("volume was replaced before deletion")
    elif args.command == "remove-home":
        doc = read_journal(journal)
        if doc["root"]:
            remove_home(Path(doc["root"]), doc["home"])
    elif args.command == "stage":
        doc = read_journal(journal)
        doc["stage"] = args.value
        write_journal(journal, doc)
    else:
        doc = read_journal(journal)
        if doc["stage"] != "auth_removed":
            fail("reset operation is not complete")
        host_fs.remove_file(journal, host_fs.describe_file(journal))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"reset transaction refused: {exc}", file=sys.stderr)
        raise SystemExit(1)
