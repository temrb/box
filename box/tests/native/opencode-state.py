"""Production installed-launcher persistence and source inspection, without accounts."""
import json
import os
import pathlib
import stat
import subprocess
import sys

config = pathlib.Path('/persist/config/opencode/opencode.json')
assert pathlib.Path('/workspace/.box-native-disposable').is_file()
try:
    with config.open('a'):
        pass
except OSError:
    pass
else:
    raise AssertionError('Global configuration must be read-only')
prefs = config.with_name('cli.json')
marker = pathlib.Path('/persist/state/opencode/box-persistence-marker')
if sys.argv[1] == 'first':
    prefs.write_text(json.dumps({'theme': 'system'}))
    marker.write_text('fixture')
else:
    assert not prefs.exists(), 'Saved UI preferences must reset before startup'
    backup = prefs.with_name('cli.json.box-legacy')
    assert json.loads(backup.read_text()) == {'theme': 'system'}
    assert stat.S_IMODE(backup.stat().st_mode) == 0o600
    assert marker.read_text() == 'fixture'
result = subprocess.run(['opencode', 'debug', 'config'], check=True,
                        capture_output=True, text=True, timeout=30)
sources = json.loads(result.stdout)
info = next(item['info'] for item in sources if item.get('path') == str(config))
expected = json.loads(config.read_text())
for field in ['permissions', 'default_agent', 'update']:
    assert info[field] == expected[field]
subprocess.run(['opencode', 'service', 'stop'], capture_output=True, timeout=30, check=True)
database = pathlib.Path('/persist/data/opencode/opencode/opencode.db')
assert not database.is_symlink() and database.is_file()
assert database.stat().st_uid == os.getuid() and stat.S_IMODE(database.stat().st_mode) == 0o600
print('PASS: installed OpenCode readonly config, reset cli.json with protected backup, persistent state and native v2 source inspection')
