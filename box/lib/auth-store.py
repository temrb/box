#!/usr/bin/env python3
"""Additive host-only schema-2 transaction primitive; no production cutover.

Trusted host callers supply identity coordinates and qualified semantic member
validators. Native payloads supply data only. This module has no Docker/native
projection authority and no credential-printing CLI. Current contract-3 callers
must not use it until their complete manifest and lifecycle gates are qualified.
"""
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import stat

_spec = importlib.util.spec_from_file_location('box_host_fs', Path(__file__).with_name('host-fs.py'))
fs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fs)

TOKEN = re.compile(r'[a-z][a-z0-9_-]{0,63}\Z')
TRANSACTION = re.compile(r'[0-9a-f]{32}\Z')
MANIFEST = re.compile(r'sha256:[0-9a-f]{64}\Z')
MAX_REVISION = (1 << 63) - 1


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                     allow_nan=False).encode()).hexdigest()


def integer(value):
    return type(value) is int and 0 <= value <= MAX_REVISION


def private_directory(path):
    with fs.open_directory(path) as fd:
        info = os.fstat(fd)
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise ValueError('auth authority directory must be owned and mode 700')
        return info.st_dev, info.st_ino


class Contract:
    """Host code supplies validators; source payloads never define manifests.

    A validator returns exactly True for a supported semantic payload. Manifest
    qualification/provenance is a caller prerequisite, not inferred from this
    constructor or from synthetic tests. No real-client manifests ship here.
    """
    def __init__(self, harness, manifest, validators):
        if not isinstance(harness, str) or not TOKEN.fullmatch(harness):
            raise ValueError('invalid trusted harness')
        if not isinstance(manifest, str) or not MANIFEST.fullmatch(manifest):
            raise ValueError('invalid trusted native manifest identifier')
        if (not isinstance(validators, dict) or not 1 <= len(validators) <= 64 or
                any(not isinstance(k, str) or not TOKEN.fullmatch(k) or not callable(v)
                    for k, v in validators.items())):
            raise ValueError('invalid trusted semantic member validators')
        self.harness, self.manifest = harness, manifest
        self.validators = dict(validators)

    def validate(self, envelope):
        fields = {'schema', 'harness', 'adapter_schema', 'native_manifest', 'revision',
                  'tombstone', 'members', 'transaction'}
        if type(envelope) is not dict or set(envelope) != fields:
            raise ValueError('unsupported canonical envelope authority')
        if (type(envelope['schema']) is not int or envelope['schema'] != 2 or
                type(envelope['adapter_schema']) is not int or envelope['adapter_schema'] != 2 or
                envelope['harness'] != self.harness or envelope['native_manifest'] != self.manifest or
                not integer(envelope['revision']) or type(envelope['tombstone']) is not bool):
            raise ValueError('incompatible canonical envelope')
        tx = envelope['transaction']
        if tx is not None and (not isinstance(tx, str) or not TRANSACTION.fullmatch(tx)):
            raise ValueError('invalid canonical transaction')
        if envelope['revision'] == 0 and tx is not None or envelope['revision'] > 0 and tx is None:
            raise ValueError('inconsistent canonical transaction revision')
        members = envelope['members']
        if type(members) is not dict or set(members) != set(self.validators):
            raise ValueError('unknown or missing semantic member')
        present = False
        for name, member in members.items():
            if type(member) is not dict or type(member.get('present')) is not bool:
                raise ValueError('invalid semantic member presence')
            if member['present']:
                if set(member) != {'present', 'payload'}:
                    raise ValueError('semantic member includes authority')
                try:
                    supported = self.validators[name](member['payload']) is True
                except Exception:
                    # Native parser errors must not disclose payload values.
                    supported = False
                if not supported:
                    raise ValueError('unsupported semantic member payload')
                present = True
            elif set(member) != {'present'}:
                raise ValueError('absent semantic member includes payload')
        if envelope['tombstone'] != (not present):
            raise ValueError('whole-identity tombstone disagrees with member presence')
        # Enforce serialization and bounds even for in-memory trusted calls.
        if len(json.dumps(envelope, allow_nan=False).encode()) > fs.MAX_CONTROL_BYTES:
            raise ValueError('canonical envelope exceeds bounded size')
        return envelope

    def envelope(self, revision, transaction, members):
        # Copy through serialization: later caller mutation cannot alter authority.
        members = json.loads(json.dumps(members, allow_nan=False))
        return self.validate({'schema': 2, 'harness': self.harness, 'adapter_schema': 2,
                              'native_manifest': self.manifest, 'revision': revision,
                              'transaction': transaction, 'members': members,
                              'tombstone': not any(m.get('present') for m in members.values())})


class Store:
    """One canonical identity, under an external stable host lock.

    Directories must already exist, be private, and be outside native mounts.
    Creation/location selection and ordered lifecycle lock sets belong to the
    future host supervisor. Every mutation requires this object's held lease.
    """
    def __init__(self, identity, lock, contract):
        self.identity = Path(fs.exact_path(identity))
        self.lock = Path(fs.exact_path(lock))
        if self.lock == self.identity or self.identity in self.lock.parents:
            raise ValueError('stable lock must be outside canonical identity')
        if not isinstance(contract, Contract):
            raise ValueError('trusted host contract is required')
        self.contract = contract
        self._lease = None

    @contextmanager
    def leased(self):
        if self._lease is not None:
            raise ValueError('nested authority lease')
        private_directory(self.identity)
        with fs.open_lock(self.lock) as fd:
            self._lease = (fd, private_directory(self.identity), os.getpid())
            try:
                yield self
            finally:
                self._lease = None

    def _authority(self):
        if self._lease is None:
            raise ValueError('host authority lease is required')
        fd, identity, owner_pid = self._lease
        if os.getpid() != owner_pid:
            raise ValueError('inherited host lease is not transaction authority')
        if private_directory(self.identity) != identity:
            raise ValueError('canonical authority directory was replaced')
        with fs.open_directory(self.identity) as directory:
            # A schema-1 object or an interrupted unacknowledged staging file
            # requires explicit preservation/recovery, never fresh auth.
            if set(os.listdir(directory)) - {'canonical.json', 'journal.json', 'pending.json'}:
                raise ValueError('unrecognized canonical directory member requires explicit recovery')
        with fs.open_directory(self.lock.parent) as parent:
            parent_info = os.fstat(parent)
            if parent_info.st_uid != os.getuid() or stat.S_IMODE(parent_info.st_mode) != 0o700:
                raise ValueError('stable authority lock parent changed protection')
            info = os.stat(self.lock.name, dir_fd=parent, follow_symlinks=False)
            fs.file_safe(info, os.getuid(), private=True)
            if stat.S_IMODE(info.st_mode) != 0o600:
                raise ValueError('stable authority lock changed protection')
            held = os.fstat(fd)
            if (info.st_dev, info.st_ino) != (held.st_dev, held.st_ino):
                raise ValueError('stable authority lock was replaced')

    def _read(self, name):
        self._authority()
        return fs.read_json(self.identity / name, required_mode=0o600)

    def _write(self, name, value):
        self._authority()
        fs.write_json(self.identity / name, value)

    def read(self):
        return self.contract.validate(self._read('canonical.json'))

    def initialize(self):
        self._authority()
        # Missing is legal only for explicit initialization, never collection.
        with fs.open_directory(self.identity) as directory:
            occupied = bool(os.listdir(directory))
        if occupied:
            raise ValueError('initialization refuses existing authority')
        envelope = self.contract.envelope(0, None, {n: {'present': False} for n in self.contract.validators})
        self._write('canonical.json', envelope)
        return envelope

    def journal(self):
        journal = self._read('journal.json')
        fields = {'schema', 'harness', 'native_manifest', 'transaction', 'base_revision',
                  'base_digest', 'stage', 'pending_digest'}
        if (set(journal) != fields or type(journal['schema']) is not int or journal['schema'] != 2 or
                journal['harness'] != self.contract.harness or journal['native_manifest'] != self.contract.manifest or
                not isinstance(journal['transaction'], str) or not TRANSACTION.fullmatch(journal['transaction']) or
                not integer(journal['base_revision']) or journal['base_revision'] == MAX_REVISION or
                not isinstance(journal['base_digest'], str) or not re.fullmatch('[0-9a-f]{64}', journal['base_digest']) or
                journal['stage'] not in ('reserved', 'pending', 'published', 'scrubbed', 'complete')):
            raise ValueError('invalid durable journal authority')
        pd = journal['pending_digest']
        if journal['stage'] == 'reserved':
            if pd is not None:
                raise ValueError('reservation includes unexpected pending authority')
        elif not isinstance(pd, str) or not re.fullmatch('[0-9a-f]{64}', pd):
            raise ValueError('journal lacks pending authority')
        return journal

    def begin(self, expected_revision):
        canonical = self.read()
        if not integer(expected_revision) or canonical['revision'] != expected_revision or expected_revision == MAX_REVISION:
            raise ValueError('canonical revision conflict or exhaustion')
        try:
            previous = self.journal()
        except FileNotFoundError:
            previous = None
        if previous is not None and previous['stage'] != 'complete':
            raise ValueError('incomplete transaction requires recovery')
        # Completed transactions retain pending evidence. Refuse displaced data.
        if previous is not None:
            self._pending(previous)
            if canonical['transaction'] != previous['transaction'] or digest(canonical) != previous['pending_digest']:
                raise ValueError('completed transaction authority disagrees')
        else:
            try:
                os.lstat(self.identity / 'pending.json')
            except FileNotFoundError:
                pass
            else:
                raise ValueError('orphan pending collection requires recovery')
        journal = {'schema': 2, 'harness': self.contract.harness, 'native_manifest': self.contract.manifest,
                   'transaction': secrets.token_hex(16), 'base_revision': expected_revision,
                   'base_digest': digest(canonical), 'stage': 'reserved', 'pending_digest': None}
        self._write('journal.json', journal)
        return journal['transaction']

    def _transaction(self, transaction):
        journal = self.journal()
        if transaction != journal['transaction']:
            raise ValueError('transaction authority mismatch')
        return journal

    def _base(self, journal):
        canonical = self.read()
        if canonical['revision'] != journal['base_revision'] or digest(canonical) != journal['base_digest']:
            raise ValueError('canonical base changed')
        return canonical

    def _pending(self, journal):
        pending = self.contract.validate(self._read('pending.json'))
        if (pending['transaction'] != journal['transaction'] or
                pending['revision'] != journal['base_revision'] + 1 or
                digest(pending) != journal['pending_digest']):
            raise ValueError('pending collection authority mismatch')
        return pending

    def collect(self, transaction, members):
        """Only the host calls this after verified stop and service quiescence."""
        journal = self._transaction(transaction)
        candidate = self.contract.envelope(journal['base_revision'] + 1, transaction, members)
        if journal['stage'] != 'reserved':
            if digest(candidate) != digest(self._pending(journal)):
                raise ValueError('collection retry changed validated export')
            return
        self._base(journal)
        # A crash between pending and journal is recoverable only by explicit
        # recollection of the exact same export; never manufacture a logout.
        try:
            old_pending = self.contract.validate(self._read('pending.json'))
        except FileNotFoundError:
            old_pending = None
        if old_pending is not None and old_pending['transaction'] == transaction and digest(old_pending) != digest(candidate):
            raise ValueError('interrupted collection changed export')
        if old_pending is not None and old_pending['transaction'] != transaction:
            if digest(old_pending) != journal['base_digest']:
                raise ValueError('unrelated pending collection authority')
        self._write('pending.json', candidate)
        journal.update(stage='pending', pending_digest=digest(candidate))
        self._write('journal.json', journal)

    def publish(self, transaction):
        journal = self._transaction(transaction)
        if journal['stage'] == 'reserved':
            raise ValueError('validated pending collection is required')
        pending = self._pending(journal)
        canonical = self.read()
        if digest(canonical) == digest(pending):
            pass  # Canonical rename may have succeeded before journal fsync.
        elif journal['stage'] == 'pending':
            self._base(journal)
            self._write('canonical.json', pending)
        else:
            raise ValueError('published canonical authority changed')
        if journal['stage'] == 'pending':
            journal['stage'] = 'published'
            self._write('journal.json', journal)
        return pending['revision']

    def acknowledge_scrub(self, transaction):
        """Trusted supervisor acknowledges verified scrub; payload cannot do so."""
        journal = self._transaction(transaction)
        if journal['stage'] not in ('published', 'scrubbed', 'complete'):
            raise ValueError('canonical publication must precede scrub acknowledgement')
        if digest(self.read()) != digest(self._pending(journal)):
            raise ValueError('scrub acknowledgement authority changed')
        if journal['stage'] == 'published':
            journal['stage'] = 'scrubbed'
            self._write('journal.json', journal)

    def complete(self, transaction):
        journal = self._transaction(transaction)
        if journal['stage'] not in ('scrubbed', 'complete'):
            raise ValueError('verified scrub must precede completion')
        if digest(self.read()) != digest(self._pending(journal)):
            raise ValueError('completion authority changed')
        if journal['stage'] == 'scrubbed':
            journal['stage'] = 'complete'
            self._write('journal.json', journal)
