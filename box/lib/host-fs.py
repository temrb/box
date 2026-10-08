#!/usr/bin/env python3
"""Descriptor-relative host control-file operations.

Only trusted callers supply coordinates and expected identity. JSON content is
never path or deletion authority. All descriptors close on exec. Observed
replacement, symlinks, shared inodes and unsafe ancestry refuse. Concurrent
same-user/root compromise remains outside the supported threat model.
"""
from contextlib import contextmanager
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import stat

DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
MAX_CONTROL_BYTES = 16 * 1024 * 1024
MAX_MEMBER_BYTES = 256 * 1024 * 1024


def exact_path(path):
    path = os.fspath(path)
    if not os.path.isabs(path) or os.path.normpath(path) != path or '\x00' in path:
        raise ValueError("host filesystem coordinates must be normalized absolute paths")
    return path


def signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def mount_id(fd):
    with open(f"/proc/self/fdinfo/{fd}", encoding="ascii") as stream:
        for line in stream:
            if line.startswith("mnt_id:"):
                return int(line.split()[1])
    raise ValueError("cannot identify host mount")


def directory_safe(info, uid):
    if not stat.S_ISDIR(info.st_mode) or info.st_uid not in (0, uid):
        raise ValueError("unsafe host directory type or ownership")
    if info.st_mode & 0o022 and not (info.st_uid == 0 and info.st_mode & stat.S_ISVTX):
        raise ValueError("unsafe writable host directory ancestor")


@contextmanager
def open_directory(path, uid=None):
    path = exact_path(path)
    uid = os.getuid() if uid is None else uid
    fd = os.open('/', DIR_FLAGS)
    try:
        directory_safe(os.fstat(fd), uid)
        for name in Path(path).parts[1:]:
            before = os.stat(name, dir_fd=fd, follow_symlinks=False)
            directory_safe(before, uid)
            child = os.open(name, DIR_FLAGS, dir_fd=fd)
            try:
                if (os.fstat(child).st_dev, os.fstat(child).st_ino) != (before.st_dev, before.st_ino):
                    raise ValueError("host directory changed while opening")
                directory_safe(os.fstat(child), uid)
            except BaseException:
                os.close(child)
                raise
            os.close(fd)
            fd = child
        yield fd
    finally:
        os.close(fd)


def verify_directory(path, fd, uid=None):
    with open_directory(path, uid) as current:
        a, b = os.fstat(fd), os.fstat(current)
        if (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):
            raise ValueError("host directory path was replaced")


def file_safe(info, uid, private=False):
    if not stat.S_ISREG(info.st_mode) or info.st_uid != uid or info.st_nlink != 1:
        raise ValueError("unsafe host file type, ownership or link count")
    if info.st_mode & (0o077 if private else 0o022):
        raise ValueError("unsafe host file permissions")


def read_at(parent_fd, name, uid, private=False, limit=MAX_CONTROL_BYTES):
    before = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    file_safe(before, uid, private)
    if before.st_size > limit:
        raise ValueError("host file exceeds bounded read limit")
    fd = os.open(name, FILE_FLAGS, dir_fd=parent_fd)
    try:
        opened = os.fstat(fd)
        file_safe(opened, uid, private)
        if signature(before) != signature(opened):
            raise ValueError("host file changed while opening")
        chunks, total = [], 0
        while True:
            chunk = os.read(fd, min(65536, limit + 1 - total))
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise ValueError("host file exceeds bounded read limit")
            chunks.append(chunk)
        if (signature(os.fstat(fd)) != signature(before) or
                signature(os.stat(name, dir_fd=parent_fd, follow_symlinks=False)) != signature(before)):
            raise ValueError("host file changed during read")
        return b''.join(chunks), before
    finally:
        os.close(fd)


def read_file(path, uid=None, private=False, limit=MAX_CONTROL_BYTES):
    path = Path(exact_path(path))
    uid = os.getuid() if uid is None else uid
    with open_directory(path.parent, uid) as parent_fd:
        data, info = read_at(parent_fd, path.name, uid, private, limit)
        verify_directory(path.parent, parent_fd, uid)
        return data, info


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate control JSON key")
        result[key] = value
    return result


def read_json(path, required_mode=None):
    data, info = read_file(path, private=True)
    if required_mode is not None and stat.S_IMODE(info.st_mode) != required_mode:
        raise ValueError("unexpected control file mode")
    def nonfinite(_):
        raise ValueError("nonfinite control JSON")
    doc = json.loads(data, object_pairs_hook=unique_object, parse_constant=nonfinite)
    if type(doc) is not dict:
        raise ValueError("control JSON must contain one object")
    return doc


def describe_file(path, uid=None):
    data, info = read_file(path, uid, limit=MAX_MEMBER_BYTES)
    return {"kind": "file", "dev": info.st_dev, "ino": info.st_ino,
            "mode": stat.S_IMODE(info.st_mode), "uid": info.st_uid,
            "size": info.st_size, "ctime_ns": info.st_ctime_ns,
            "sha256": hashlib.sha256(data).hexdigest()}


def publish_new(parent_fd, source, destination):
    # Linux renameat2 publishes an absent target atomically with link count one.
    # No link/unlink gap can leave a shared inode after abrupt termination.
    libc = ctypes.CDLL(None, use_errno=True)
    rename = getattr(libc, "renameat2", None)
    if rename is None:
        raise ValueError("atomic exclusive publication requires Linux renameat2")
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(parent_fd, os.fsencode(source), parent_fd, os.fsencode(destination), 1) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def write_json(path, doc):
    path = Path(exact_path(path))
    data = (json.dumps(doc, sort_keys=True, separators=(',', ':'), allow_nan=False) + '\n').encode()
    if len(data) > MAX_CONTROL_BYTES:
        raise ValueError("control JSON exceeds publication limit")
    uid = os.getuid()
    with open_directory(path.parent, uid) as parent_fd:
        if os.fstat(parent_fd).st_uid != uid:
            raise ValueError("control parent must be user owned")
        try:
            _, previous = read_at(parent_fd, path.name, uid, private=True)
        except FileNotFoundError:
            previous = None
        temporary = '.box-control-' + secrets.token_hex(16)
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                     0o600, dir_fd=parent_fd)
        try:
            os.fchmod(fd, 0o600)
            view = memoryview(data)
            while view:
                written = os.write(fd, view)
                if written <= 0:
                    raise OSError("short control write")
                view = view[written:]
            os.fsync(fd)
            verify_directory(path.parent, parent_fd, uid)
            if previous is None:
                # Exclusive creation cannot overwrite a newly appeared target.
                publish_new(parent_fd, temporary, path.name)
            else:
                if signature(os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)) != signature(previous):
                    raise ValueError("control target changed before publication")
                os.replace(temporary, path.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            os.fsync(parent_fd)
        finally:
            os.close(fd)
            try:
                os.unlink(temporary, dir_fd=parent_fd)
            except FileNotFoundError:
                pass


def remove_file(path, expected, uid=None):
    path = Path(exact_path(path))
    uid = os.getuid() if uid is None else uid
    with open_directory(path.parent, uid) as parent_fd:
        data, info = read_at(parent_fd, path.name, uid, limit=MAX_MEMBER_BYTES)
        actual = {"kind": "file", "dev": info.st_dev, "ino": info.st_ino,
                  "mode": stat.S_IMODE(info.st_mode), "uid": info.st_uid,
                  "size": info.st_size, "ctime_ns": info.st_ctime_ns,
            "sha256": hashlib.sha256(data).hexdigest()}
        if actual != expected:
            raise ValueError("exact host removal member changed")
        verify_directory(path.parent, parent_fd, uid)
        if signature(os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)) != signature(info):
            raise ValueError("host removal target changed before unlink")
        os.unlink(path.name, dir_fd=parent_fd)
        os.fsync(parent_fd)


def describe_directory(info):
    return {"kind": "dir", "dev": info.st_dev, "ino": info.st_ino,
            "mode": stat.S_IMODE(info.st_mode), "uid": info.st_uid}


def remove_directory(path, expected):
    path = Path(exact_path(path))
    with open_directory(path.parent) as parent_fd:
        before = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
        if not stat.S_ISDIR(before.st_mode) or describe_directory(before) != expected:
            raise ValueError("exact host removal directory changed")
        fd = os.open(path.name, DIR_FLAGS, dir_fd=parent_fd)
        try:
            if describe_directory(os.fstat(fd)) != expected or os.listdir(fd):
                raise ValueError("host removal directory changed or is not empty")
            verify_directory(path.parent, parent_fd)
            current = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
            if describe_directory(current) != expected:
                raise ValueError("host removal directory changed before rmdir")
            os.rmdir(path.name, dir_fd=parent_fd)
            os.fsync(parent_fd)
        finally:
            os.close(fd)


@contextmanager
def open_lock(path):
    """Hold one stable host lock nonblockingly; never remove its inode.

    Trusted lifecycle callers choose an external protected lock coordinate and
    hold the complete ordered lock set before publication or native mutation.
    """
    path = Path(exact_path(path))
    uid = os.getuid()
    with open_directory(path.parent) as parent_fd:
        if os.fstat(parent_fd).st_uid != uid or stat.S_IMODE(os.fstat(parent_fd).st_mode) != 0o700:
            raise ValueError("host lock parent must be private and user owned")
        fd = os.open(path.name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                     0o600, dir_fd=parent_fd)
        try:
            info = os.fstat(fd)
            file_safe(info, uid, private=True)
            if stat.S_IMODE(info.st_mode) != 0o600:
                raise ValueError("host lock must be mode 600")
            if signature(os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)) != signature(info):
                raise ValueError("host lock inode was replaced")
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            verify_directory(path.parent, parent_fd)
            if signature(os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)) != signature(info):
                raise ValueError("host lock changed during acquisition")
            os.fsync(fd)
            os.fsync(parent_fd)
            yield fd
        finally:
            os.close(fd)
