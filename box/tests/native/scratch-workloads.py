"""Offline dependency/build/cache/server scratch matrix, using disposable paths only."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import tarfile
import tempfile
import time
import uuid


WORKLOAD = r'''
set -e
export HOME=/scratch TMPDIR=/scratch
trap 'if test -f /scratch/dependency/lib/payload.bin; then sha256sum /scratch/dependency/lib/payload.bin; fi' EXIT
cd /scratch
printf 'phase=install\n'
mkdir app; cd app
tar -xzf /input/fixture.tgz
make -C package install PREFIX=/scratch/dependency
/scratch/dependency/bin/fixture
printf '{"dependency":"fixture"}' > package.json
printf 'phase=compile\n'
mkdir build
for i in $(seq 1 48); do
  printf 'int f%s(void){return %s;}\n' "$i" "$i" > build/unit$i.c
  gcc -O2 -c build/unit$i.c -o build/unit$i.o
done
printf 'int main(void){return 0;}\n' > build/main.c
gcc build/main.c build/*.o -o build/app
./build/app
printf 'phase=cache\n'
cp /input/payload.bin cache.bin
sha256sum cache.bin
printf 'phase=server\n'
python3 - <<'SERVER'
import http.server, threading, urllib.request
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), http.server.SimpleHTTPRequestHandler)
thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
with urllib.request.urlopen('http://127.0.0.1:%s/package.json' % server.server_port, timeout=5) as r:
    assert r.status == 200 and b'fixture' in r.read()
server.shutdown(); server.server_close(); thread.join()
print('server=pass')
SERVER
printf 'phase=complete\n'
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    parser.add_argument('--scratch-root', required=True)
    args = parser.parse_args()
    if os.getuid() == 0:
        parser.error('normal user required')
    filesystem = subprocess.check_output(['findmnt', '-n', '-T', args.scratch_root, '-o', 'FSTYPE'], text=True).strip()
    if filesystem in ('tmpfs', 'ramfs'):
        parser.error('disk-backed scratch root required')
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)
    with tempfile.TemporaryDirectory(prefix='box-workloads-', dir=args.scratch_root) as directory:
        root = Path(directory)
        (root / 'config.json').write_text('{}\n')
        docker = ['docker', '--config', str(root), '--host', 'unix:///var/run/docker.sock']
        def call(*argv, check=True):
            return subprocess.run(docker + list(argv), capture_output=True, text=True, timeout=20, check=check)
        source = root / 'input'; source.mkdir()
        payload = b'x' * (20 * 1024 * 1024)
        (source / 'payload.bin').write_bytes(payload)
        with tarfile.open(source / 'fixture.tgz', 'w:gz') as archive:
            for name, data in [('fixture.c', b'int fixture(void){return 42;}\n'),
                               ('Makefile', b'install:\n\tgcc -O2 -c fixture.c -o fixture.o\n\tar rcs libfixture.a fixture.o\n\tmkdir -p $(PREFIX)/lib $(PREFIX)/bin\n\tcp libfixture.a payload.bin $(PREFIX)/lib/\n\tcp tool.py $(PREFIX)/bin/fixture\n\tchmod +x $(PREFIX)/bin/fixture\n'),
                               ('tool.py', b'#!/usr/bin/python3\nprint("tool=pass")\n'), ('payload.bin', payload)]:
                info = tarfile.TarInfo('package/' + name); info.size = len(data); info.mode = 0o755 if name == 'tool.py' else 0o644
                archive.addfile(info, io.BytesIO(data))
        expected = hashlib.sha256(payload).hexdigest()
        for runtime in ('runsc', 'runc'):
            for storage in ('tmpfs', 'sized-tmpfs', 'disk'):
                scratch = root / (runtime + '-' + storage); scratch.mkdir()
                name = 'box-workloads-' + uuid.uuid4().hex
                common = ['run', '--name', name, '--pull=never', '--runtime=' + runtime,
                          '--user', '%s:%s' % (os.getuid(), os.getgid()), '--network=none', '--read-only',
                          '--cap-drop=ALL', '--security-opt=no-new-privileges', '--ipc=private', '--cgroupns=private',
                          '--memory=256m', '--memory-swap=256m', '--cpus=1', '--pids-limit=64', '--log-driver=none',
                          '--mount', 'type=bind,src=%s,dst=/input,readonly,bind-recursive=disabled' % source]
                if storage == 'disk':
                    common += ['--mount', 'type=bind,src=%s,dst=/scratch,bind-recursive=disabled' % scratch]
                else:
                    common += ['--tmpfs', '/scratch:rw,nosuid,nodev,exec,mode=700,uid=%s,gid=%s%s' %
                               (os.getuid(), os.getgid(), ',size=32m' if storage == 'sized-tmpfs' else '')]
                common += ['--entrypoint=/bin/bash', args.image, '-c', WORKLOAD]
                proc = None; counters = {}; timed_out = False
                try:
                    proc = subprocess.Popen(docker + common, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    deadline = time.monotonic() + 90
                    while proc.poll() is None and time.monotonic() < deadline:
                        state = call('inspect', '--format', '{{.State.Pid}}', name, check=False)
                        if state.returncode == 0 and state.stdout.strip() != '0':
                            try:
                                group = Path('/proc/' + state.stdout.strip() + '/cgroup').read_text().split('0::', 1)[1].strip()
                                cg = Path('/sys/fs/cgroup') / group.lstrip('/')
                                for key in ('memory.current', 'memory.peak', 'memory.swap.current'):
                                    counters[key] = max(counters.get(key, 0), int((cg / key).read_text()))
                                counters['memory.events'] = (cg / 'memory.events').read_text().strip()
                            except (OSError, ValueError, IndexError):
                                pass
                        time.sleep(.15)
                    if proc.poll() is None:
                        timed_out = True; call('kill', name)
                    stdout, stderr = proc.communicate(timeout=10)
                    state = json.loads(call('inspect', '--format', '{{json .State}}', name).stdout)
                    # Stopped containers lose tmpfs; hash while the workload is alive.
                    installed_intact = any(line == expected + '  /scratch/dependency/lib/payload.bin'
                                           for line in stdout.splitlines())
                    call('rm', '-f', name)
                    # A new container starts with fresh tmpfs; disk scratch deliberately survives.
                    restart = list(common); restart[restart.index(name)] = name + '-restart'; restart[-1] = 'test -e /scratch/app/package.json'
                    restarted = subprocess.run(docker + restart, capture_output=True, text=True, timeout=30)
                    call('rm', '-f', name + '-restart')
                    print(json.dumps(dict(runtime=runtime, storage=storage, rc=proc.returncode, timed_out=timed_out,
                                          stdout=stdout.strip(), stderr=stderr[-2000:], state=state, counters=counters,
                                          installed_intact=installed_intact, restart_marker_rc=restarted.returncode)), flush=True)
                finally:
                    try:
                        call('rm', '-f', name, check=False); call('rm', '-f', name + '-restart', check=False)
                    finally:
                        if proc is not None and proc.poll() is None:
                            proc.kill(); proc.communicate(timeout=10)


if __name__ == '__main__':
    main()
