#!/usr/bin/env python3
"""Account-independent exact-ID DNS/TLS observations; no auth/project mounts."""
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys

BUNDLE = Path(__file__).parents[2]
CID = re.compile('[0-9a-f]{64}\\Z')


def run(argv, *, check=True, timeout=30):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                            env={'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
                                 'HOME': os.environ['HOME'], 'BOX_TOOL': 'network-observations'})
    if check and result.returncode:
        raise RuntimeError('network observation command failed (arguments/output withheld)')
    return result


def field(tool, name):
    return run(['bash', '-p', '-c', 'source "$1/lib/tools.sh"; box_tool_field "$2" "$3"',
                'observation', str(BUNDLE), tool, name]).stdout.strip()


def main():
    uid, gid = os.getuid(), os.getgid()
    if not uid or not gid:
        raise ValueError('normal qualification user required')
    cli = Path(os.environ['HOME']) / '.config/box-network-observations/docker-cli'
    run(['bash', '-p', '-c', 'source "$1/lib/docker.sh"; box_docker_cli "$2"',
         'observation', str(BUNDLE), str(cli)])
    docker = ['docker', '--config', str(cli), '--host', 'unix:///var/run/docker.sock']
    # Record resolver configuration as metadata, never query credential stores.
    for command in (['cat', '/etc/resolv.conf'], ['resolvectl', 'dns']):
        try:
            result = run(command, check=False, timeout=5)
            print(json.dumps({'case': 'host-dns', 'command': command[0], 'exit': result.returncode,
                              'metadata': result.stdout}), flush=True)
        except (OSError, subprocess.SubprocessError):
            print(json.dumps({'case': 'host-dns', 'command': command[0], 'result': 'unavailable'}), flush=True)
    failed = False
    ids = run(['bash', '-p', '-c', 'source "$1/lib/tools.sh"; printf "%s" "$box_tool_ids"',
               'observation', str(BUNDLE)]).stdout.split()
    for tool in ids:
        image = run(['bash', '-p', str(BUNDLE / 'lib/build.sh'), '--tag', tool]).stdout.strip()
        image_id = run(docker + ['image', 'inspect', '--format', '{{.Id}}', image]).stdout.strip()
        if not image_id.startswith('sha256:') or not CID.fullmatch(image_id[7:]):
            raise ValueError('invalid image identity')
        hosts = field(tool, 'probe_hosts').split()
        if not hosts or any(not re.fullmatch('[A-Za-z0-9.-]+', h) for h in hosts):
            raise ValueError('invalid registered probe hosts')
        network = field(tool, 'network')
        for runtime in ('runsc', 'runc'):
            nonce = secrets.token_hex(16)
            cid = None
            try:
                script = '''
set -u
printf 'resolver-configuration\\n'; cat /etc/resolv.conf
awk '/^(Uid|Gid|Groups|CapEff|CapPrm|CapBnd|CapAmb|NoNewPrivs|Seccomp):/' /proc/self/status
result=0
for host in "$@"; do
 if getent ahosts "$host" >/dev/null; then dns=0; else dns=$?; result=1; fi
 if code=$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 15 "https://$host/"); then tls=0; else tls=$?; result=1; fi
 printf 'host=%s dns_exit=%s tls_exit=%s http=%s\\n' "$host" "$dns" "$tls" "$code"
done
exit "$result"
'''
                created = run(docker + ['create', '--pull=never', '--init', '--runtime', runtime,
                    '--user', f'{uid}:{gid}', '--network', network, '--cap-drop=ALL',
                    '--security-opt=no-new-privileges', '--read-only', '--pids-limit=64',
                    '--memory=256m', '--memory-swap=256m', '--cpus=1', '--ulimit=core=0',
                    '--tmpfs=/tmp:rw,nosuid,nodev', '--log-driver=none',
                    '--label', 'org.box.network-observation=' + nonce,
                    '--entrypoint=/bin/bash', image_id, '-c', script, 'probe', *hosts])
                cid = created.stdout.strip()
                if not CID.fullmatch(cid):
                    raise ValueError('invalid created container identity')
                inspect = json.loads(run(docker + ['inspect', cid]).stdout)[0]
                if inspect['Id'] != cid or inspect['Config']['Labels'].get('org.box.network-observation') != nonce:
                    raise ValueError('container ownership mismatch')
                print(json.dumps({'case': 'network-provenance', 'tool': tool, 'runtime': runtime,
                                  'cid': cid, 'image': image_id, 'network': network,
                                  'actual_runtime': inspect['HostConfig']['Runtime'],
                                  'mounts': inspect['Mounts']}), flush=True)
                result = run(docker + ['start', '--attach', cid], check=False, timeout=90)
                # The only entrypoint is the fixed neutral script above.
                print(json.dumps({'case': 'network-observation', 'tool': tool, 'runtime': runtime,
                                  'exit': result.returncode, 'metadata': result.stdout}), flush=True)
                if result.returncode:
                    failed = True
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                failed = True
                print(json.dumps({'case': 'network-observation', 'tool': tool, 'runtime': runtime,
                                  'result': 'failed-or-unavailable'}), flush=True)
            finally:
                if cid is not None and CID.fullmatch(cid):
                    inspect = json.loads(run(docker + ['inspect', cid]).stdout)[0]
                    if inspect['Id'] != cid or inspect['Config']['Labels'].get('org.box.network-observation') != nonce:
                        raise ValueError('cleanup ownership mismatch')
                    run(docker + ['rm', '--force', '--volumes', cid])
    print('UNMET: native callbacks/accounts, LAN/metadata/IPv6 matrix and release networking policy')
    return int(failed)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
        print('Network observations refused; gate remains open (output withheld).', file=sys.stderr)
        sys.exit(1)
