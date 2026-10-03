"""Fault proxy delays real Docker create/start HTTP handoff; no accounts."""
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time


def main():
    bundle = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='box-probe-race-') as directory:
        root = Path(directory); (root / 'config.json').write_text('{}\n')
        direct = ['docker', '--config', str(root), '--host', 'unix:///var/run/docker.sock']
        def call(*args):
            return subprocess.run(direct + list(args), capture_output=True, text=True, timeout=15)
        for stage in ('before-create', 'created-before-cid', 'before-start'):
            reached = threading.Event(); release = threading.Event(); stopping = threading.Event()
            owned = []; errors = []; workers = []
            sockpath = root / (stage + '.sock')
            listener = socket.socket(socket.AF_UNIX); listener.bind(str(sockpath)); listener.listen(); listener.settimeout(.1)
            def handle(client):
                upstream = socket.socket(socket.AF_UNIX)
                try:
                    upstream.connect('/var/run/docker.sock')
                    create = threading.Event()
                    def requests():
                        history = b''
                        try:
                            while True:
                                data = client.recv(65536)
                                if not data: break
                                history = (history + data)[-100000:]
                                if b'/containers/create' in history and b'POST ' in history:
                                    create.set()
                                    if stage == 'before-create':
                                        reached.set(); release.wait(8)
                                    history = b''
                                if stage == 'before-start' and re.search(rb'POST /[^ ]*/start', history):
                                    reached.set(); release.wait(8); history = b''
                                upstream.sendall(data)
                        except OSError:
                            pass
                        finally:
                            try: upstream.shutdown(socket.SHUT_WR)
                            except OSError: pass
                    thread = threading.Thread(target=requests, daemon=True); thread.start()
                    response = b''; delayed = False
                    while True:
                        data = upstream.recv(65536)
                        if not data: break
                        if create.is_set():
                            response += data
                            match = re.search(rb'"Id":"([0-9a-f]{64})"', response)
                            if match and not delayed:
                                owned.append(match.group(1).decode()); delayed = True
                                if stage == 'created-before-cid':
                                    reached.set(); release.wait(8)
                        client.sendall(data)
                except OSError:
                    pass
                finally:
                    client.close(); upstream.close()
            def accept():
                while not stopping.is_set():
                    try: client, _ = listener.accept()
                    except socket.timeout: continue
                    except OSError: break
                    thread = threading.Thread(target=handle, args=(client,), daemon=True)
                    workers.append(thread); thread.start()
            server = threading.Thread(target=accept, daemon=True); server.start()
            script = '''set -e
BOX_TOOL=probe-race
source "$1/lib/preflight.sh"
source "$1/lib/config.sh"
source "$1/lib/launcher.sh"
host_uid=$(id -u); host_gid=$(id -g)
docker_cmd=(docker --config "$2" --host "unix://$3")
BOX_DNS_PROBE_TIMEOUT=2
BOX_CONTAINER_MEMORY=128m
BOX_CONTAINER_CPUS=1
BOX_CONTAINER_PIDS=64
box_probe_runsc_dns box-m:1.4.0-R4161.1-u1000-g1000 box-m localhost
'''
            proc = subprocess.Popen(['bash', '-c', script, '_', str(bundle), str(root), str(sockpath)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                hit = reached.wait(8)
                if hit: proc.send_signal(signal.SIGTERM)
                else: proc.kill()
                stdout, stderr = proc.communicate(timeout=15)
                # Release the delayed real-daemon handoff, then inspect exact owned IDs.
                release.set(); time.sleep(.3)
                leftovers = [cid for cid in owned if call('inspect', cid).returncode == 0]
                print(json.dumps(dict(stage=stage, boundary_reached=hit, rc=proc.returncode,
                                      owned=owned, leftovers=leftovers, stdout=stdout, stderr=stderr)), flush=True)
            finally:
                release.set()
                if proc.poll() is None: proc.kill(); proc.communicate(timeout=10)
                stopping.set(); listener.close(); server.join(timeout=2)
                for thread in workers: thread.join(timeout=2)
                for cid in owned: call('rm', '-f', cid)


if __name__ == '__main__':
    main()
