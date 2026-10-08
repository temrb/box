#!/usr/bin/env python3
"""Compare source inventories before qualification; host facts may differ."""
import argparse
import hashlib
import json
import os
from pathlib import PurePosixPath
import re
import stat
import sys


MAX_BYTES = 32 * 1024 * 1024
HEX = re.compile(r"[0-9a-f]{64}\Z")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def load_inventory(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_BYTES:
            raise ValueError("inventory must be a bounded regular file")
        raw = stream.read(MAX_BYTES + 1)
        after = os.fstat(stream.fileno())
    if len(raw) > MAX_BYTES:
        raise ValueError("inventory exceeds size limit")
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    if identity(before) != identity(after) or identity(after) != identity(os.lstat(path)):
        raise ValueError("inventory changed during read")
    data = json.loads(raw, object_pairs_hook=unique_object)
    if not isinstance(data, dict) or type(data.get("schema")) is not int or data["schema"] != 1:
        raise ValueError("unsupported inventory schema")
    if not isinstance(data.get("head"), str) or not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", data["head"]):
        raise ValueError("invalid HEAD")
    if not isinstance(data.get("status_porcelain_v1_nul"), str):
        raise ValueError("missing checkout status")
    members = data.get("members")
    if not isinstance(members, dict) or not members:
        raise ValueError("missing source members")
    for name, member in members.items():
        path_name = PurePosixPath(name)
        if not name or path_name.is_absolute() or ".." in path_name.parts or "\0" in name:
            raise ValueError("invalid source member path")
        if not isinstance(member, dict):
            raise ValueError("invalid source member")
        kind = member.get("kind")
        if kind == "file":
            if (set(member) != {"kind", "sha256", "size", "mode"}
                    or not isinstance(member["sha256"], str) or not HEX.fullmatch(member["sha256"])
                    or type(member["size"]) is not int or member["size"] < 0
                    or not isinstance(member["mode"], str)
                    or not re.fullmatch(r"0o[0-7]{1,4}", member["mode"])):
                raise ValueError("invalid file member")
        elif kind == "symlink":
            if set(member) != {"kind", "target"} or not isinstance(member["target"], str):
                raise ValueError("invalid symlink member")
        elif kind == "missing":
            if set(member) != {"kind"}:
                raise ValueError("invalid missing member")
        else:
            raise ValueError("unsupported source member kind")
    payload = json.dumps(members, sort_keys=True, separators=(",", ":")).encode()
    digest = hashlib.sha256(payload).hexdigest()
    if data.get("source_manifest_sha256") != digest:
        raise ValueError("source manifest digest mismatch")
    return data


def compare(source, destination, publication=False):
    differences = []
    for field in ("head", "status_porcelain_v1_nul"):
        if not publication and source[field] != destination[field]:
            differences.append({"field": field})
    for name in sorted(source["members"].keys() | destination["members"].keys()):
        left, right = source["members"].get(name), destination["members"].get(name)
        if publication:
            # Git preserves executable intent, not host read/write permission bits.
            # Compare content, type, size and executable intent for every member.
            def git_member(member):
                if member is not None and member.get("kind") == "file":
                    return dict(member, mode="0o755" if int(member["mode"], 8) & 0o111 else "0o644")
                return member
            left, right = git_member(left), git_member(right)
        if left != right:
            differences.append({"field": "member", "path": name})
    return differences


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--publication", action="store_true",
                        help="compare a dirty source to a committed Git snapshot; ignore HEAD/status and normalize Git modes")
    args = parser.parse_args()
    try:
        source = load_inventory(args.source)
        destination = load_inventory(args.destination)
        differences = compare(source, destination, args.publication)
    except (OSError, ValueError, RecursionError) as error:
        # Do not echo malformed JSON, file contents or credential-shaped values.
        print("Invalid inventory: " + type(error).__name__, file=sys.stderr)
        return 2
    json.dump({"schema": 1, "source_matches": not differences,
               "comparison": "git-publication" if args.publication else "checkout",
               "differences": differences,
               "scope": "source comparison only; qualification gates remain open"},
              sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main())
