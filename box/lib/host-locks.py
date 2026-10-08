#!/usr/bin/env python3
"""Ordered host lifecycle leases; additive until qualified production cutover.

Trusted host code supplies resource identities, never credential payloads. All
locks live in one existing private host index outside agent projections. Resource
keys retain their inode across state deletion; acquiring a set never deletes a
lock. Registry ordinals belong to the caller's validated registry snapshot.
"""
from contextlib import ExitStack, contextmanager
from dataclasses import dataclass
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat

_spec = importlib.util.spec_from_file_location('box_lock_fs', Path(__file__).with_name('host-fs.py'))
fs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fs)
RANKS = {'installation': 0, 'lifecycle': 1, 'auth': 2, 'native': 3}


@dataclass(frozen=True)
class Request:
    category: str
    identity: str
    registry_order: int = 0

    def __post_init__(self):
        if (type(self.category) is not str or self.category not in RANKS or type(self.identity) is not str or
                not self.identity or len(self.identity.encode()) > 4096 or
                any(ord(c) < 32 or ord(c) == 127 for c in self.identity) or
                type(self.registry_order) is not int or not 0 <= self.registry_order < 1024 or
                self.category != 'lifecycle' and self.registry_order != 0):
            raise ValueError('invalid trusted host lock request')

    @property
    def order(self):
        return RANKS[self.category], self.registry_order, self.identity

    @property
    def member(self):
        # Include the category but not ordering metadata: changing a registry
        # order must never create a second inode for the same lifecycle identity.
        key = json.dumps([self.category, self.identity], separators=(',', ':')).encode()
        return self.category + '-' + hashlib.sha256(key).hexdigest() + '.lock'


class Lease:
    """A complete ordered set held by one host process, close-on-exec."""
    def __init__(self, root, requests):
        self.root = Path(fs.exact_path(root))
        requests = tuple(requests)
        if not requests or len(requests) > 256 or any(type(r) is not Request for r in requests):
            raise ValueError('bounded nonempty host lock set required')
        by_member = {}
        for request in requests:
            previous = by_member.get(request.member)
            if previous is not None and previous != request:
                raise ValueError('inconsistent ordering for one host lock identity')
            by_member[request.member] = request
        self.requests = tuple(sorted(by_member.values(), key=lambda r: r.order))
        self._held = None

    def _root(self):
        with fs.open_directory(self.root) as fd:
            info = os.fstat(fd)
            if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
                raise ValueError('host lock index must be private and owned')
            return info.st_dev, info.st_ino

    @contextmanager
    def held(self):
        if self._held is not None:
            raise ValueError('nested host lock acquisition refused')
        root_identity = self._root()
        with ExitStack() as stack:
            descriptors = {}
            # ExitStack unwinds all preceding acquisitions on contention or
            # validation failure. Native mutation starts only after this yield.
            for request in self.requests:
                fd = stack.enter_context(fs.open_lock(self.root / request.member))
                descriptors[request] = fd
            self._held = os.getpid(), root_identity, descriptors
            try:
                self.verify()
                yield self
            finally:
                self._held = None

    def verify(self):
        if self._held is None or self._held[0] != os.getpid():
            raise ValueError('current process does not own a complete host lease')
        _, root_identity, descriptors = self._held
        if self._root() != root_identity:
            raise ValueError('host lock index was replaced')
        with fs.open_directory(self.root) as parent:
            for request, fd in descriptors.items():
                current = os.stat(request.member, dir_fd=parent, follow_symlinks=False)
                fs.file_safe(current, os.getuid(), private=True)
                if stat.S_IMODE(current.st_mode) != 0o600:
                    raise ValueError('host lock protection changed')
                original = os.fstat(fd)
                if (current.st_dev, current.st_ino) != (original.st_dev, original.st_ino):
                    raise ValueError('held host lock inode was replaced')

    def descriptor(self, request):
        """Trusted integration may share this lease; consumers must call verify."""
        self.verify()
        if request not in self._held[2]:
            raise ValueError('resource is outside the held host lock set')
        return self._held[2][request]
