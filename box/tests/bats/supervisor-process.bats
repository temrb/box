load helpers

@test "supervisor stops its group and detached native services but preserves other executables" {
  run python3 -I - "$BUNDLE_DIR/lib/supervisor-process.py" "$TEST_TMP" <<'PY'
import os, pathlib, shutil, signal, subprocess, sys
helper, root = sys.argv[1:]
exe = pathlib.Path(root) / 'native-service'
shutil.copyfile('/bin/sleep', exe)
exe.chmod(0o700)
children = [subprocess.Popen([str(exe), '30'], start_new_session=True),
            subprocess.Popen([str(exe), '30'], start_new_session=True),
            subprocess.Popen(['/bin/sleep', '30'], start_new_session=True)]
try:
    subprocess.run(['python3', '-I', helper, '--group', str(children[0].pid), '--native-exe', str(exe)], check=True, timeout=10)
    assert children[0].wait(timeout=2) < 0
    assert children[1].wait(timeout=2) < 0
    assert children[2].poll() is None
finally:
    for child in children:
        if child.poll() is None:
            child.kill()
        child.wait()
PY
  [ "$status" -eq 0 ]
}

@test "supervisor escalates a TERM-resistant native process and refuses its own process group" {
  run python3 -I - "$BUNDLE_DIR/lib/supervisor-process.py" "$TEST_TMP" <<'PY'
import os, pathlib, shutil, signal, subprocess, sys
helper, root = sys.argv[1:]
exe = pathlib.Path(root) / 'native-service'
shutil.copyfile('/bin/sleep', exe)
exe.chmod(0o700)
child = subprocess.Popen([str(exe), '30'], start_new_session=True,
                         preexec_fn=lambda: signal.signal(signal.SIGTERM, signal.SIG_IGN))
try:
    subprocess.run(['python3', '-I', helper, '--group', str(child.pid), '--native-exe', str(exe)], check=True, timeout=10)
    assert child.wait(timeout=2) == -signal.SIGKILL
    refused = subprocess.run(['python3', '-I', helper, '--group', str(os.getpgrp()), '--native-exe', str(exe)], capture_output=True)
    assert refused.returncode != 0
finally:
    if child.poll() is None:
        child.kill()
    child.wait()
PY
  [ "$status" -eq 0 ]
}

@test "OpenCode EXIT collection survives repeated TERM during durable collection" {
  run python3 -I - "$BUNDLE_DIR/harnesses/opencode/entrypoint.sh" <<'PY'
import os, pathlib, signal, subprocess, sys, tempfile, time
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('  box_auth_collect() {')
end = source.index('\n  trap box_auth_collect EXIT', start)
function = source[start:end]
for protected in (False, True):
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        tested = function if protected else function.replace("    trap '' INT TERM HUP\n", '')
        code = '''set -eu
FIXTURE_ROOT=$1
BOX_NATIVE_GROUP=''; BOX_AUTH_HELPER=fixture; BOX_DB=fixture; BOX_SIDECAR=fixture; BOX_AUTH_ID=fixture; BOX_AUTH_DIR=fixture; BOX_ADAPTER=fixture
python3() { return 0; }
box_supervisor_collect() { touch "$FIXTURE_ROOT/ready"; sleep .4; touch "$FIXTURE_ROOT/collected"; }
''' + tested + '''
trap box_auth_collect EXIT
trap 'exit 143' TERM
touch "$1/started"
while :; do sleep .05; done
'''
        child = subprocess.Popen(['bash', '-p', '-c', code, 'fixture', str(root)],
                                 env={'PATH':'/usr/bin:/bin'}, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic()+5
            while not (root/'started').exists() and child.poll() is None and time.monotonic()<deadline:
                time.sleep(.01)
            assert (root/'started').exists()
            child.send_signal(signal.SIGTERM)
            while not (root/'ready').exists() and child.poll() is None and time.monotonic()<deadline:
                time.sleep(.01)
            assert (root/'ready').exists()
            child.send_signal(signal.SIGTERM)
            assert child.wait(timeout=5)==143
            assert (root/'collected').exists()==protected
        finally:
            if child.poll() is None: child.kill()
            child.wait(timeout=5)
PY
  [ "$status" -eq 0 ]
}
