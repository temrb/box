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
