"""Disposable synthetic auth lifecycle matrix; never imports production auth."""
import argparse
import time
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', choices=('opencode',))
    args = parser.parse_args()
    bundle = Path(__file__).resolve().parents[2]
    if shutil.which("docker") is None:
        raise RuntimeError("Docker CLI/Engine required for native auth lifecycle acceptance")
    real_home = Path.home()
    uid, gid = str(os.getuid()), str(os.getgid())
    if uid == '0' or gid == '0':
        raise RuntimeError('run as the normal host user')
    with tempfile.TemporaryDirectory(prefix='.box-auth-native-', dir=os.environ.get("BOX_TEST_PROJECT_ROOT", str(real_home))) as tmp:
        root = Path(tmp)
        home = root / 'home'
        home.mkdir(mode=0o700)
        projects = [root / 'a', root / 'b']
        for project in projects:
            project.mkdir(mode=0o700)
        env = {k: v for k, v in os.environ.items() if not k.startswith('BOX_')}
        env.update(HOME=str(home), BOX_TEST_REAL_HOME=str(real_home), BOX_TEST_TASK_ROOT=str(root))
        for prefix in ('BOX_M', 'BOX_O', 'BOX_C'):
            env[prefix + '_GIT_NAME'] = 'Auth Fixture'
            env[prefix + '_GIT_EMAIL'] = 'fixture@example.invalid'
        def run(argv, *, cwd=None, call_env=None, check=True):
            return subprocess.run(argv, cwd=cwd, env=call_env or env, check=check,
                                  capture_output=True, text=True, timeout=60)
        def test_state(*argv, call_env=None):
            return run(['bash', str(bundle / 'lib/test-state.sh'), *argv],
                       call_env=dict(call_env or env, BOX_TOOL='auth-native')).stdout.strip()
        run(['bash', str(bundle / 'setup.sh'), '--skip-build'])
        docker = ['docker', '--config', str(home / '.config/box-m/docker-cli'),
                  '--host', 'unix:///var/run/docker.sock']
        volumes = []
        file_paths = {'muse': '/home/box/.config/muse/auth.json', 'codex': '/home/box/.codex/auth.json'}
        db = '/persist/data/opencode/opencode/opencode.db'
        try:
            for harness, stem in (('muse', 'm'), ('opencode', 'o'), ('codex', 'c')):
                if args.only and args.only != harness:
                    continue
                for runtime in ('--runsc', '--docker-fallback'):
                    for scope in ('global', 'project'):
                        ns = test_state('new-ns')
                        call_env = dict(env, BOX_TEST_STATE_NS=ns, BOX_AUTH_SCOPE=scope,
                                        BOX_C_STATE_ROOT=str(root / ns),
                                        BOX_AUTH_RUNTIME='runsc' if runtime == '--runsc' else 'runc')
                        launcher = str(home / '.local/bin' / ('box-' + stem))
                        def project_env(project, **extra):
                            h = run(['bash', str(bundle / 'lib/state.sh'), 'project-hash', str(project)],
                                    call_env=dict(env, BOX_TOOL='auth-native')).stdout.strip()
                            result = dict(call_env, BOX_TEST_PROJECT_HASH=h, **extra)
                            if harness == 'codex':
                                native_home = test_state('codex-home', call_env=result)
                                result['BOX_C_STATE_ROOT'] = str(Path(native_home).parent)
                            return result
                        def remember_volume(project):
                            e = project_env(project)
                            volume = test_state('volume', harness, ns, uid, gid, call_env=e)
                            if not any(v[0] == volume for v in volumes):
                                volumes.append((volume, harness, ns, e))
                        for project in projects:
                            remember_volume(project)
                        def launch(project, command, *, check=True, **extra):
                            return run([launcher, runtime, '--shell', '-c', command],
                                       cwd=project, call_env=project_env(project, **extra), check=check)
                        def operate(action, project, *options):
                            coordinates = [harness] if action == 'uninstall-code' else [harness, str(project)]
                            return run(['bash', str(bundle / 'lib/auth-ops.sh'), action, *coordinates, *options],
                                       call_env=dict(project_env(project), BOX_TOOL='auth-native', BUNDLE_DIR=str(bundle)))
                        def canonical(project):
                            output = run([launcher, '--dry-run'], cwd=project, call_env=project_env(project)).stdout
                            return Path(next(line.split(': ', 1)[1] for line in output.splitlines()
                                             if line.startswith('Canonical auth directory: ')))
                        if harness == 'opencode':
                            seed = "import sqlite3; c=sqlite3.connect(%r); c.execute('INSERT INTO credential (id,integration_id,label,value,time_created,time_updated,active) VALUES (?,?,?,?,?,?,?)', ('fixture','openai','Fixture','{\"type\":\"key\",\"key\":\"synthetic\"}',1,1,1)); c.commit()" % db
                            def check(present):
                                code = "import sqlite3; c=sqlite3.connect(%r); assert c.execute('SELECT COUNT(*) FROM credential').fetchone()[0] == %d" % (db, int(present))
                                return 'python3 -c ' + shlex.quote(code)
                            seed = 'python3 -c ' + shlex.quote(seed)
                            logout = 'python3 -c ' + shlex.quote("import sqlite3; c=sqlite3.connect(%r); c.execute('DELETE FROM credential'); c.commit()" % db)
                        else:
                            path = shlex.quote(file_paths[harness])
                            payload = '{"schema_version":1,"providers":{"meta":{"api_key":"synthetic"}}}' if harness == 'muse' else '{"OPENAI_API_KEY":"synthetic"}'
                            seed = 'umask 077; printf %s ' + shlex.quote(payload) + ' > ' + path
                            def check(present):
                                return ('test -f ' if present else 'test ! -e ') + path
                            logout = 'rm -f -- ' + path
                        # Seed, restart, second-project scope behavior, and logout.
                        launch(projects[0], seed)
                        first = canonical(projects[0])
                        doc = json.loads((first / 'credentials.json').read_text())
                        assert doc['tombstone'] is False
                        launch(projects[0], check(True))
                        # Cleanup authorization is exact to the owned namespace.
                        first_volume = test_state('volume', harness, ns, uid, gid,
                                                  call_env=project_env(projects[0]))
                        foreign_ns = test_state('new-ns')
                        foreign = run(['bash', str(bundle / 'lib/test-state.sh'), 'guard-cleanup',
                                       first_volume, harness, foreign_ns, uid, gid],
                                      call_env=dict(project_env(projects[0]), BOX_TOOL='auth-native'), check=False)
                        assert foreign.returncode != 0
                        if harness == 'opencode':
                            before_capture = (first / 'credentials.json').read_bytes()
                            run(['bash', str(bundle / 'harnesses/opencode/capture-validation.sh'),
                                 '--output-dir', str(root / (ns + '-capture')), runtime],
                                cwd=projects[0], call_env=project_env(projects[0]))
                            assert (first / 'credentials.json').read_bytes() == before_capture
                        marker = '/persist/box-auth-lifecycle-marker'
                        launch(projects[0], 'printf retained > ' + marker)
                        # Installed setup rerun preserves canonical bytes and policy.
                        before = (first / 'credentials.json').read_bytes()
                        run(['bash', str(bundle / 'setup.sh'), '--skip-build'])
                        assert (first / 'credentials.json').read_bytes() == before
                        # Switching scopes requires acknowledgment and preserves
                        # both the source credentials and unrelated project state.
                        alternate = 'project' if scope == 'global' else 'global'
                        changed = launch(projects[0], 'true', check=False, BOX_AUTH_SCOPE=alternate)
                        assert changed.returncode != 0 and 'transition' in changed.stderr.lower()
                        launch(projects[0], check(False) + ' && test "$(cat ' + marker + ')" = retained',
                               BOX_AUTH_SCOPE=alternate, BOX_AUTH_TRANSITION='fresh')
                        assert json.loads((first / 'credentials.json').read_text())['tombstone'] is False
                        launch(projects[0], check(True), BOX_AUTH_TRANSITION='use-existing')
                        # An explicit copy into a different non-empty identity
                        # must preserve both stores and refuse to merge accounts.
                        if harness != 'muse':
                            different_seed = seed.replace('synthetic', 'synthetic-other')
                            launch(projects[0], different_seed, BOX_AUTH_SCOPE=alternate,
                                   BOX_AUTH_TRANSITION='use-existing')
                            alt_output = run([launcher, '--dry-run'], cwd=projects[0],
                                             call_env=project_env(projects[0], BOX_AUTH_SCOPE=alternate)).stdout
                            alternate_dir = Path(next(line.split(': ', 1)[1] for line in alt_output.splitlines()
                                                      if line.startswith('Canonical auth directory: ')))
                            originals = {p: (p / 'credentials.json').read_bytes() for p in (first, alternate_dir)}
                            project_hash = project_env(projects[0])['BOX_TEST_PROJECT_HASH']
                            conflict = run(['bash', str(bundle / 'lib/auth-ops.sh'), 'copy', harness,
                                            scope, project_hash, alternate, project_hash],
                                           call_env=dict(project_env(projects[0]), BOX_TOOL='auth-native', BUNDLE_DIR=str(bundle)),
                                           check=False)
                            assert conflict.returncode != 0 and 'conflict' in conflict.stderr.lower()
                            assert all((p / 'credentials.json').read_bytes() == data for p, data in originals.items())
                            launch(projects[0], check(True), BOX_AUTH_TRANSITION='use-existing')
                        # Alias retains the physical identity.
                        alias = root / (ns + '-alias')
                        alias.symlink_to(projects[0], target_is_directory=True)
                        assert canonical(alias) == first
                        launch(alias, check(True))
                        alias.unlink()
                        # Busy writer fails promptly while the first client owns
                        # auth and native projection leases.
                        ready = projects[0] / 'busy-ready'
                        busy = subprocess.Popen([launcher, runtime, '--shell', '-c',
                                                 'touch /workspace/busy-ready; sleep 30'],
                                                cwd=projects[0], env=project_env(projects[0]),
                                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                        try:
                            deadline = time.monotonic() + 30
                            while not ready.exists() and busy.poll() is None and time.monotonic() < deadline:
                                time.sleep(0.1)
                            assert ready.exists(), 'first native writer never became ready'
                            start = time.monotonic()
                            other = launch(projects[0], 'true', check=False)
                            assert other.returncode != 0 and 'busy' in other.stderr.lower()
                            assert time.monotonic() - start < 10
                        finally:
                            busy.terminate()
                            busy.communicate(timeout=30)
                            ready.unlink(missing_ok=True)
                        # Startup refusal collects/scrubs any reserved projection
                        # and leaves canonical state usable on the next run.
                        bad_image = {'muse': 'BOX_M_IMAGE', 'opencode': 'BOX_O_IMAGE', 'codex': 'BOX_C_IMAGE'}[harness]
                        refused = launch(projects[0], 'true', check=False,
                                         **{bad_image: 'box-auth-nonexistent-fixture:missing'})
                        assert refused.returncode != 0
                        launch(projects[0], check(True))
                        unsafe = launch(projects[0], 'true', check=False,
                                        BOX_AUTH_ROOT=str(projects[0] / 'unsafe-auth'))
                        assert unsafe.returncode != 0 and not (projects[0] / 'unsafe-auth').exists()
                        # Interrupt supervision while a projection is
                        # authoritative. Stop the exact dependent container, then
                        # prove stale canonical auth cannot be restored before
                        # recovery collects and scrubs the preserved native store.
                        ready = projects[0] / 'crash-ready'
                        crash_seed = (logout + '; ' if harness == 'opencode' else '') + seed
                        crashed = subprocess.Popen([launcher, runtime, '--shell', '-c',
                            crash_seed + '; touch /workspace/crash-ready; sleep 30'],
                            cwd=projects[0], env=project_env(projects[0]),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                        deadline = time.monotonic() + 30
                        try:
                            while not ready.exists() and crashed.poll() is None and time.monotonic() < deadline:
                                time.sleep(0.1)
                            assert ready.exists(), 'interruption fixture never became ready'
                            holders = run(docker + ['ps', '-q', '--filter', 'volume=' + str(first)]).stdout.splitlines()
                            assert len(holders) == 1
                            crashed.kill()
                            for container in holders:
                                if harness == 'opencode':
                                    # Kill the in-image supervisor too, leaving
                                    # SQLite authoritative for explicit recovery.
                                    run(docker + ['kill', '--signal', 'KILL', container])
                                else:
                                    run(docker + ['stop', '--time', '1', container])
                            crashed.communicate(timeout=30)
                        finally:
                            if crashed.poll() is None:
                                crashed.kill()
                                crashed.communicate(timeout=30)
                            ready.unlink(missing_ok=True)
                        stale = launch(projects[0], 'true', check=False)
                        assert stale.returncode != 0 and 'recover' in stale.stderr.lower()
                        operate('recover', projects[0])
                        launch(projects[0], check(True))
                        for container in holders:
                            run(docker + ['rm', container], check=False)
                        # Reset with auth retention drops the native volume/home,
                        # then reconstructs a fresh projection from canonical auth.
                        operate('reset', projects[0], '--keep-auth', '--execute')
                        launch(projects[0], check(True) + ' && test ! -e ' + marker)
                        launch(projects[1], check(scope == 'global') + ' && test ! -e ' + marker)
                        second = canonical(projects[1])
                        assert (first == second) == (scope == 'global')
                        launch(projects[0], logout)
                        launch(projects[0], check(False))
                        assert json.loads((first / 'credentials.json').read_text())['tombstone'] is True
                        assert json.loads((first / 'lease.json').read_text())['state'] == 'idle'
                        # Default reset removes project auth only. Global auth
                        # remains available to both projects after native reset.
                        launch(projects[0], seed)
                        operate('reset', projects[0], '--execute')
                        assert first.exists() == (scope == 'global')
                        launch(projects[0], check(scope == 'global'))
                        launch(projects[0], logout)
                        # Physical rename changes project identity; global auth
                        # still shares while project auth starts empty.
                        renamed = root / (ns + '-renamed')
                        projects[1].rename(renamed)
                        remember_volume(renamed)
                        assert (canonical(renamed) == second) == (scope == 'global')
                        launch(renamed, check(False))  # global was logged out above
                        renamed.rename(projects[1])
                        # Code-only uninstall preserves every canonical object;
                        # reinstall restores the launcher for the full removal case.
                        saved = (first / 'credentials.json').read_bytes()
                        operate('uninstall-code', projects[0], '--execute')
                        assert (first / 'credentials.json').read_bytes() == saved
                        run(['bash', str(bundle / 'setup.sh'), '--skip-build'])
                        operate('remove-full', projects[0], '--execute')
                        assert not first.exists() and not second.exists()
                        print(json.dumps(dict(case='synthetic-auth-lifecycle', harness=harness,
                                              runtime=runtime, scope=scope, result='pass',
                                              restart=True, second_project=True, logout=True, transitions=True, alias=True, rename=True,
                                              setup_rerun=True, keep_auth_reset=True, default_reset=True,
                                              copy_conflict=harness != 'muse', busy=True, code_uninstall=True,
                                              full_removal=True, unsafe_bind=True, startup_refusal=True,
                                              foreign_cleanup_refusal=True, capture_independence=harness == 'opencode',
                                              interruption_recovery=True)), flush=True)
        finally:
            for volume, harness, ns, volume_env in volumes:
                test_state('guard-cleanup', volume, harness, ns, uid, gid, call_env=volume_env)
                existing = run(docker + ['volume', 'inspect', volume], check=False)
                if existing.returncode == 0:
                    holders = run(docker + ['ps', '-aq', '--filter', 'volume=' + volume])
                    for container in holders.stdout.splitlines():
                        run(docker + ['rm', '-f', container])
                    run(docker + ['volume', 'rm', volume])
    print('UNMET: real login/refresh/model/resume, additional credential backends, ARM64 and remote CI')


if __name__ == '__main__':
    main()
