#!/usr/bin/env python3
"""Re-resolve non-secret discovery records; never treat an index as authority."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys


import importlib.util

_fs_spec = importlib.util.spec_from_file_location("box_host_fs", Path(__file__).with_name("host-fs.py"))
host_fs = importlib.util.module_from_spec(_fs_spec)
_fs_spec.loader.exec_module(host_fs)

def read_record(path):
    return host_fs.read_json(path, required_mode=0o600)


def records(bundle, index, harness, snapshot=None, current_project=None):
    root = Path(index) / 'native' / harness
    if not root.exists() and snapshot is None and current_project is None:
        return []
    for parent in (root, *root.parents):
        if not parent.exists() and not parent.is_symlink():
            continue
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError('redirected discovery directory')
    if root.exists() and (root.stat().st_uid != os.getuid() or stat.S_IMODE(root.stat().st_mode) != 0o700):
        raise ValueError('unsafe discovery directory')
    result = []
    registry = subprocess.run(['bash', '-c', 'source "$1/lib/state.sh"; for s in $(box_tool_field "$2" states); do '
        'printf "%s=%s\\n" "$s" "$(box_state_field "$2" "$s" override)"; done', '_', bundle, harness],
        env=dict(os.environ, BOX_TOOL='inventory'), check=True, text=True, capture_output=True)
    allowed = dict(x.split('=', 1) for x in registry.stdout.splitlines())
    if snapshot:
        candidates = read_record(Path(snapshot))["records"]
    elif root.exists():
        candidates = [dict(read_record(p), record=str(p)) for p in sorted(root.iterdir())]
    else:
        candidates = []
    if current_project and not snapshot:
        # Include current coordinates in a read-only preview even before the
        # first live launch has written discovery metadata. Use the same
        # resolver and record shape as live discovery; never invent paths.
        project = os.path.realpath(current_project)
        domain = 'test' if os.environ.get('BOX_TEST_STATE_NS') else 'production'
        for state, variables in allowed.items():
            kind = subprocess.run(['bash', '-c', 'source "$1/lib/state.sh"; box_state_field "$2" "$3" class',
                                   '_', bundle, harness, state], env=dict(os.environ, BOX_TOOL='inventory'),
                                  check=True, text=True, capture_output=True).stdout
            if kind != 'non-auth':
                continue
            resolved = subprocess.run(['bash', str(Path(bundle) / 'lib/state.sh'), 'describe',
                                       harness, str(os.getuid()), str(os.getgid()), project, domain, state],
                                      env=dict(os.environ, BOX_TOOL='inventory'), check=True,
                                      text=True, capture_output=True)
            descriptor = dict(x.split('=', 1) for x in resolved.stdout.splitlines())
            name = hashlib.sha256((state + '\n' + descriptor['path'] + '\n' + descriptor['project_hash']).encode()).hexdigest() + '.json'
            record = str(root / name)
            if any(candidate['record'] == record for candidate in candidates):
                continue
            candidates.append(dict(descriptor=descriptor,
                                   overrides={v: os.environ[v] for v in variables.split() if v in os.environ},
                                   fixture_project='BOX_TEST_PROJECT_HASH' in os.environ, record=record))
    for candidate in candidates:
        path = Path(candidate["record"])
        doc = {k: v for k, v in candidate.items() if k != "record"}
        if path.exists() or path.is_symlink():
            if read_record(path) != doc:
                raise ValueError("discovery record changed during recovery")
        if set(doc) != {'descriptor', 'overrides', 'fixture_project'}:
            raise ValueError('invalid discovery record keys')
        if type(doc['fixture_project']) is not bool:
            raise ValueError('invalid fixture domain metadata')
        d, overrides = doc['descriptor'], doc['overrides']
        if (d.get('harness') != harness or d.get('class') != 'non-auth'
                or d.get('uid') != str(os.getuid()) or d.get('state') not in allowed):
            raise ValueError('foreign discovery identity')
        if any(k not in allowed[d['state']].split() for k in overrides):
            raise ValueError('undeclared discovery override')
        project = d['project']
        if (not project.startswith('/') or os.path.realpath(project) != project
                or hashlib.sha256(project.encode()).hexdigest()[:20] != d['project_hash']):
            raise ValueError('invalid physical project identity')
        expected_name = hashlib.sha256((d['state'] + '\n' + d['path'] + '\n' + d['project_hash']).encode()).hexdigest() + '.json'
        if path != root / expected_name:
            raise ValueError('invalid discovery filename')
        env = {k: v for k, v in os.environ.items() if not k.startswith('BOX_')}
        env.update(BOX_TOOL='inventory', **overrides)
        domain = 'test' if os.environ.get('BOX_TEST_STATE_NS') else 'production'
        if d['domain'] != domain:
            raise ValueError('foreign discovery domain')
        if domain == 'test':
            env.update({k: os.environ[k] for k in ('BOX_TEST_STATE_NS', 'BOX_TEST_TASK_ROOT')})
            if doc['fixture_project']:
                env['BOX_TEST_PROJECT_HASH'] = d['project_hash']
        # A removed/renamed project remains an exact historical identity.
        # Reuse the resolver with its recorded physical path and checked hash;
        # workspace discovery itself is never rerun against another project.
        code = 'source "$1/lib/state.sh"; box_require_tool "$2"; box_state_validate_uid_gid "$3" "$4"; '
        code += 'BOX_STATE_HARNESS=$2; BOX_STATE_UID=$3; BOX_STATE_GID=$4; BOX_STATE_PROJECT=$5; '
        code += 'BOX_STATE_PROJECT_HASH=$6; BOX_STATE_DOMAIN=$7; BOX_STATE_NS=${BOX_TEST_STATE_NS:-}; '
        code += 'BOX_STATE_TASK_ROOT=${BOX_TEST_TASK_ROOT:-}; box_state_resolve "$8"'
        resolved = subprocess.run(['bash', '-c', code, '_', bundle, harness, d['uid'], d['gid'],
                                   project, d['project_hash'], domain, d['state']], env=env,
                                  check=True, text=True, capture_output=True)
        if dict(x.split('=', 1) for x in resolved.stdout.splitlines()) != d:
            raise ValueError('discovery descriptor no longer resolves exactly')
        result.append(dict(doc, record=str(path)))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('bundle')
    parser.add_argument('index')
    parser.add_argument('harness')
    parser.add_argument('--snapshot')
    parser.add_argument('--current-project')
    args = parser.parse_args()
    print(json.dumps(records(args.bundle, args.index, args.harness, args.snapshot, args.current_project), sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
        print(f'state inventory refused: {exc}', file=sys.stderr)
        sys.exit(1)
