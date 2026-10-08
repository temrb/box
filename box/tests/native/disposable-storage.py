#!/usr/bin/env python3
"""Fetch pinned native artifacts and qualify synthetic stores on this CPU.

Explicit opt-in, no accounts, no image export, no production homes. Artifacts
and synthetic stores are removed with the exact TemporaryDirectory allocation.
This does not qualify containers, real OAuth rotation, or native cutover.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tarfile
import tempfile

BUNDLE = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('storage_fs', BUNDLE / 'lib/host-fs.py')
fs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fs)
MAX_ARTIFACT = 512 * 1024 * 1024


def run(argv, *, timeout=60):
    return subprocess.run(argv, capture_output=True, timeout=timeout,
                          env={'PATH': '/usr/local/bin:/usr/bin:/bin', 'LANG': 'C.UTF-8',
                               'BOX_TOOL': 'disposable-storage'})


def pin(name):
    result = run(['bash', '-p', '-c', 'source "$1/lib/pins.sh"; box_print_pin "$1" "$2"',
                  'storage', str(BUNDLE), name])
    if result.returncode:
        raise ValueError('registry pin resolution failed')
    value = result.stdout.decode().strip()
    if not re.fullmatch('[A-Za-z0-9._-]+', value):
        raise ValueError('invalid registry pin')
    return value


def checksum(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def download(url, destination, expected):
    if not re.fullmatch('[0-9a-f]{64}', expected):
        raise ValueError('invalid artifact digest')
    result = run(['curl', '--fail', '--silent', '--show-error', '--location',
                  '--proto', '=https', '--proto-redir', '=https', '--tlsv1.2',
                  '--connect-timeout', '15', '--max-time', '600',
                  '--max-filesize', str(MAX_ARTIFACT), '--output', str(destination), url], timeout=610)
    if result.returncode or not destination.is_file() or destination.stat().st_size > MAX_ARTIFACT:
        raise ValueError('pinned artifact download failed')
    if checksum(destination) != expected:
        raise ValueError('pinned artifact digest mismatch')


def executable(archive, name, destination):
    # Extract only the expected bounded regular executable, never archive paths.
    with tarfile.open(archive, 'r:gz') as package:
        members = [m for m in package.getmembers() if m.name == name]
        if (len(members) != 1 or not members[0].isfile() or not members[0].mode & 0o111 or
                not 0 < members[0].size <= MAX_ARTIFACT):
            raise ValueError('invalid native executable archive member')
        with package.extractfile(members[0]) as source, destination.open('xb') as output:
            remaining = members[0].size
            while remaining:
                data = source.read(min(1024 * 1024, remaining))
                if not data:
                    raise ValueError('truncated native executable')
                output.write(data)
                remaining -= len(data)
    destination.chmod(0o700)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch-root', required=True)
    args = parser.parse_args()
    os.umask(0o077)
    if not os.getuid() or not os.getgid():
        raise ValueError('normal non-root qualification user required')
    arch = {'x86_64': 'amd64', 'aarch64': 'arm64'}.get(platform.machine())
    if arch is None:
        raise ValueError('unsupported qualification architecture')
    root = Path(fs.exact_path(args.scratch_root))
    if root == BUNDLE or root in BUNDLE.parents or BUNDLE in root.parents:
        raise ValueError('disposable artifact scratch must be outside the source checkout')
    with fs.open_directory(root) as fd:
        info = os.fstat(fd)
        if info.st_uid != os.getuid() or info.st_mode & 0o777 != 0o700:
            raise ValueError('private owned scratch root required')
    failed = False
    with tempfile.TemporaryDirectory(prefix='box-native-storage-', dir=root) as tmp:
        scratch = Path(tmp)
        for harness in ('muse', 'opencode', 'codex'):
            try:
                directory = scratch / harness
                directory.mkdir(mode=0o700)
                version = pin(harness.upper() + '_VERSION')
                expected = pin(harness.upper() + '_SHA256_' + arch.upper())
                binary, archive = directory / harness, directory / 'package.tar.gz'
                if harness == 'muse':
                    cpu = 'x86' if arch == 'amd64' else 'aarch64'
                    url = f'https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version={version}&file=muse-{cpu}-linux'
                    download(url, binary, expected)
                    binary.chmod(0o700)
                elif harness == 'opencode':
                    cpu = 'x64-baseline' if arch == 'amd64' else 'arm64'
                    download(f'https://opencode.ai/files/bin/{version}/opencode-linux-{cpu}.tar.gz', archive, expected)
                    checked = run([sys.executable, '-I', str(BUNDLE / 'harnesses/opencode/archive.py'), str(archive), arch])
                    if checked.returncode:
                        raise ValueError('OpenCode archive layout refused')
                    executable(archive, 'opencode', binary)
                else:
                    cpu = 'x86_64' if arch == 'amd64' else 'aarch64'
                    download(f'https://github.com/openai/codex/releases/download/rust-v{version}/codex-package-{cpu}-unknown-linux-musl.tar.gz', archive, expected)
                    executable(archive, 'bin/codex', binary)
                argv = [sys.executable, '-I', str(BUNDLE / f'tests/native/{harness}-auth-fixture.py'),
                        '--binary', str(binary), '--scratch-root', str(directory)]
                if harness != 'muse':
                    argv += ['--archive', str(archive)]
                result = run(argv, timeout=300)
                # Fixture stdout is explicitly non-secret evidence; stderr stays
                # private because Python diagnostics may include command text.
                sys.stdout.buffer.write(result.stdout)
                sys.stdout.flush()
                print(json.dumps({'case': 'pinned-synthetic-storage', 'harness': harness,
                                  'architecture': arch, 'artifact': expected, 'exit': result.returncode}), flush=True)
                failed |= result.returncode != 0
            except (OSError, ValueError, subprocess.SubprocessError, tarfile.TarError):
                failed = True
                print(json.dumps({'case': 'pinned-synthetic-storage', 'harness': harness,
                                  'architecture': arch, 'result': 'failed-or-unavailable'}), flush=True)
    print('UNMET: dedicated accounts, callback/rotation, containment and complete native manifests')
    return int(failed)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError):
        print('Disposable native storage qualification refused (details withheld).', file=sys.stderr)
        sys.exit(1)
