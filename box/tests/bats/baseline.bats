@test "baseline inventory hashes source drift without following credential symlinks" {
  run python3 -I - "$BATS_TEST_DIRNAME/../../../specs/capture-baseline.py" <<'PY'
import hashlib
import importlib.util
import pathlib
import sys
import tempfile

spec = importlib.util.spec_from_file_location('baseline', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='box-baseline-unit-') as scratch:
    module.ROOT = pathlib.Path(scratch)
    (module.ROOT / 'box').mkdir()
    source = module.ROOT / 'box/source.py'
    source.write_bytes(b'original source\n')
    secret = module.ROOT / 'box/providers.env'
    secret.write_bytes(b'not source\n')
    (module.ROOT / 'box/link.py').symlink_to(secret)
    module.git = lambda *args: b'box/source.py\0box/providers.env\0box/link.py\0box/missing.py\0'
    first = module.inventory()
    assert 'box/providers.env' not in first
    assert first['box/link.py'] == {'kind': 'symlink', 'target': str(secret)}
    assert first['box/missing.py'] == {'kind': 'missing'}
    assert first['box/source.py']['sha256'] == hashlib.sha256(source.read_bytes()).hexdigest()
    source.write_bytes(b'changed source\n')
    assert module.inventory()['box/source.py']['sha256'] != first['box/source.py']['sha256']
    assert not module.source_member('box/harnesses/codex/auth.json')
    assert not module.source_member('box/example.providers.env')
    assert module.source_member('box/harnesses/codex/version-codex.env')
PY
  [ "$status" -eq 0 ]
}

@test "transfer comparison detects member, mode, symlink, HEAD and status drift" {
  run python3 -I - "$BATS_TEST_DIRNAME/../../../specs/compare-baselines.py" <<'PY'
import copy
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

def seal(data):
    data['source_manifest_sha256'] = hashlib.sha256(json.dumps(
        data['members'], sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return data

base = seal({'schema': 1, 'head': 'a' * 40, 'status_porcelain_v1_nul': ' M box/a.py\0',
             'members': {'box/a.py': {'kind': 'file', 'sha256': 'b' * 64,
                                     'size': 10, 'mode': '0o644'},
                         'box/link.py': {'kind': 'symlink', 'target': 'a.py'},
                         'box/deleted.py': {'kind': 'missing'}}})
with tempfile.TemporaryDirectory() as scratch:
    source, destination = [pathlib.Path(scratch) / n for n in ('source.json', 'dest.json')]
    source.write_text(json.dumps(base))
    def check(data, expected, field=None):
        destination.write_text(json.dumps(seal(data)))
        result = subprocess.run([sys.executable, '-I', sys.argv[1], str(source), str(destination)],
                                capture_output=True, text=True)
        assert result.returncode == expected, result.stderr
        report = json.loads(result.stdout)
        assert report['source_matches'] == (expected == 0)
        if field:
            assert any(d['field'] == field for d in report['differences'])
    same = copy.deepcopy(base)
    same.update(root='/different/checkout', host={'uid': 999}, captured_at='later')
    check(same, 0)
    for field, value in [('head', 'c' * 40), ('status_porcelain_v1_nul', '')]:
        changed = copy.deepcopy(base)
        changed[field] = value
        check(changed, 1, field)
    for field, value in [('sha256', 'd' * 64), ('mode', '0o755'), ('size', 11)]:
        changed = copy.deepcopy(base)
        changed['members']['box/a.py'][field] = value
        check(changed, 1, 'member')
    changed = copy.deepcopy(base)
    changed['members']['box/link.py']['target'] = 'other.py'
    check(changed, 1, 'member')
    changed = copy.deepcopy(base)
    del changed['members']['box/deleted.py']
    check(changed, 1, 'member')
    changed['members']['box/extra.py'] = {'kind': 'missing'}
    check(changed, 1, 'member')
PY
  [ "$status" -eq 0 ]
}

@test "transfer comparison refuses malformed, forged and nonregular inventories without content output" {
  run python3 -I - "$BATS_TEST_DIRNAME/../../../specs/compare-baselines.py" <<'PY'
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as scratch:
    root = pathlib.Path(scratch)
    source, destination = root / 'source.json', root / 'dest.json'
    members = {'box/a.py': {'kind': 'missing'}}
    base = {'schema': 1, 'head': 'a' * 40, 'status_porcelain_v1_nul': '', 'members': members,
            'source_manifest_sha256': hashlib.sha256(json.dumps(
                members, sort_keys=True, separators=(',', ':')).encode()).hexdigest()}
    source.write_text(json.dumps(base))
    def refuses(path):
        result = subprocess.run([sys.executable, '-I', sys.argv[1], str(source), str(path)],
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 2, result
        assert not result.stdout
        assert 'private-sentinel' not in result.stderr
    for raw in ['private-sentinel', '{"schema":1,"schema":1}', '[]',
                json.dumps(dict(base, schema=True)),
                json.dumps(dict(base, source_manifest_sha256='f' * 64)),
                json.dumps(dict(base, members={'../escape': {'kind': 'missing'}})),
                json.dumps(dict(base, members={'box/a.py': {'kind': 'unknown'}}))]:
        destination.write_text(raw)
        refuses(destination)
    link = root / 'link.json'
    link.symlink_to(source)
    refuses(link)
    fifo = root / 'fifo'
    os.mkfifo(fifo)
    refuses(fifo)
    refuses(root)
    refuses(root / 'absent.json')
    with destination.open('wb') as stream:
        stream.truncate(32 * 1024 * 1024 + 1)
    refuses(destination)
PY
  [ "$status" -eq 0 ]
}

@test "baseline capture refuses changing checkout status before emitting evidence" {
  run python3 -I - "$BATS_TEST_DIRNAME/../../../specs/capture-baseline.py" <<'PY'
import contextlib
import importlib.util
import io
import sys

spec = importlib.util.spec_from_file_location('baseline', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
responses = iter([b'head\n', b'initial', b'head\n', b'changed'])
module.git = lambda *args: next(responses)
module.inventory = lambda: {}
output = io.StringIO()
with contextlib.redirect_stdout(output):
    try:
        module.main()
    except RuntimeError as error:
        assert 'checkout changed' in str(error)
    else:
        raise AssertionError('changing checkout accepted')
assert output.getvalue() == ''
PY
  [ "$status" -eq 0 ]
}

@test "publication comparison permits only Git metadata and permission normalization" {
  run python3 -I - "$BATS_TEST_DIRNAME/../../../specs/compare-baselines.py" <<'PY'
import copy
import importlib.util
import sys
spec = importlib.util.spec_from_file_location('comparison', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = {'head': 'a' * 40, 'status_porcelain_v1_nul': ' M box/a.py\0',
          'members': {'box/a.py': {'kind': 'file', 'mode': '0o600', 'size': 1, 'sha256': 'b' * 64},
                      'box/run.sh': {'kind': 'file', 'mode': '0o700', 'size': 1, 'sha256': 'c' * 64}}}
destination = copy.deepcopy(source)
destination.update(head='d' * 40, status_porcelain_v1_nul='')
destination['members']['box/a.py']['mode'] = '0o644'
destination['members']['box/run.sh']['mode'] = '0o755'
assert module.compare(source, destination)
assert not module.compare(source, destination, publication=True)
for key, value in [('mode', '0o644'), ('size', 2), ('sha256', 'e' * 64), ('kind', 'missing')]:
    changed = copy.deepcopy(destination)
    changed['members']['box/run.sh'][key] = value
    assert module.compare(source, changed, publication=True)
changed = copy.deepcopy(destination)
del changed['members']['box/a.py']
assert module.compare(source, changed, publication=True)
PY
  [ "$status" -eq 0 ]
}
