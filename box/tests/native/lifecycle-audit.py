"""Disposable installed-launcher moves, aliases, resets and uninstall evidence."""
import hashlib
import json
import os
import subprocess
from pathlib import Path
import shutil
import tempfile


STEM_IDS = {'m': 'muse', 'o': 'opencode', 'c': 'codex'}


def main():
    bundle = Path(__file__).resolve().parents[2]
    subprocess.run(["python3", "-I", str(bundle / "tests/native/auth-lifecycle.py")], check=True)
    tstate_lib = bundle / 'lib' / 'test-state.sh'
    real_home = Path.home()
    with tempfile.TemporaryDirectory(prefix='.box-lifecycle-', dir=os.environ.get('BOX_TEST_PROJECT_ROOT', str(real_home))) as directory:
        root = Path(directory); home = root / 'home'; home.mkdir(mode=0o700)
        project = root / 'project'; project.mkdir(mode=0o700)
        env = dict(os.environ, HOME=str(home))
        # Explicitly avoid caller credentials, caches, pins and config overrides.
        for key in list(env):
            if key.startswith(('BOX_M_', 'BOX_O_', 'BOX_C_')):
                del env[key]
        for key in ('BOX_AUTH_SCOPE', 'BOX_AUTH_ROOT', 'BOX_STATE_CONFIG', 'BOX_AUTH_TRANSITION', 'BOX_TEST_PROJECT_HASH'):
            env.pop(key, None)
        for prefix in ('BOX_M', 'BOX_O', 'BOX_C'):
            env[prefix + '_GIT_NAME'] = 'Lifecycle Fixture'
            env[prefix + '_GIT_EMAIL'] = 'fixture@example.invalid'
        # Phase-S disposable test namespace (specs/plan.md §0 B0): every
        # launcher invocation resolves to `box-test-<ns>-` identities only,
        # so lifecycle tests can never mount or remove production globals.
        env['BOX_TEST_REAL_HOME'] = str(real_home)
        env['BOX_TEST_TASK_ROOT'] = str(root)
        cli_base = dict(os.environ, BOX_TOOL='lifecycle-audit.py')
        docker = ['docker', '--config', str(home / '.config/box-m/docker-cli'), '--host', 'unix:///var/run/docker.sock']
        volumes = []
        volume_spec = {}
        uid_gid = (str(os.getuid()), str(os.getgid()))
        def tstate(*args):
            p = subprocess.run(['bash', str(tstate_lib), *args], env=cli_base,
                               capture_output=True, text=True, timeout=60)
            if p.returncode:
                raise RuntimeError('test-state %s: %s' % (' '.join(args), p.stderr[-1000:]))
            return p.stdout
        def new_ns():
            return tstate('new-ns').strip()
        def codex_home(ns):
            return Path(tstate('codex-home', str(root), ns).strip())
        def volume(stem, ns):
            vol = tstate('volume', STEM_IDS[stem], ns, *uid_gid).strip()
            volume_spec[vol] = (STEM_IDS[stem], ns)
            return vol
        def guard(volume_name):
            if volume_name not in volume_spec:
                raise RuntimeError('untracked cleanup volume: %s' % volume_name)
            stem_id, ns = volume_spec[volume_name]
            tstate('guard-cleanup', volume_name, stem_id, ns, *uid_gid)
        def run(argv, cwd=None, check=True):
            p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, timeout=60)
            if check and p.returncode:
                raise RuntimeError('%s: %s' % (argv, p.stderr[-1000:]))
            return p
        def record(case, **data):
            print(json.dumps(dict(case=case, **data)), flush=True)
        def identity(path):
            return subprocess.run(['bash', str(bundle / 'lib/state.sh'), 'project-hash', str(path)],
                                  env=dict(env, BOX_TOOL='lifecycle'), check=True, text=True,
                                  capture_output=True).stdout.strip()
        def launch(stem, path, command, ns, flag='--runsc', check=True):
            call_env = dict(env, BOX_TEST_STATE_NS=ns)
            if stem == 'c':
                # Test Codex root selects exactly <task-root>/<ns>/codex-home.
                call_env['BOX_C_STATE_ROOT'] = str(codex_home(ns).parent)
            p = subprocess.run([str(home / '.local/bin' / ('box-' + stem)), flag, '--shell', '-c', command],
                               cwd=path, env=call_env, capture_output=True, text=True, timeout=60)
            if check and p.returncode:
                raise RuntimeError('%s: %s' % (command, p.stderr[-1000:]))
            return p
        def inventory(path):
            return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in path.rglob('*') if p.is_file() and not p.is_symlink()}
        def dryrun(stem, path, ns, scope):
            # Non-secret auth identity only: no containers, no credentials.
            call_env = dict(env, BOX_TEST_STATE_NS=ns, BOX_AUTH_SCOPE=scope)
            if stem == 'c':
                call_env['BOX_C_STATE_ROOT'] = str(codex_home(ns).parent)
            p = subprocess.run([str(home / '.local/bin' / ('box-' + stem)), '--dry-run'],
                               cwd=path, env=call_env, capture_output=True, text=True, timeout=60)
            if p.returncode:
                raise RuntimeError('%s dry-run: %s' % (stem, p.stderr[-1000:]))
            for line in p.stdout.splitlines():
                if line.startswith('Canonical auth directory: '):
                    return line.split(': ', 1)[1]
            raise RuntimeError('%s dry-run hid its canonical auth directory' % stem)
        try:
            run(['bash', str(bundle / 'setup.sh'), '--skip-build'])
            providers = home / '.config/box/providers.env'
            assert providers.read_bytes() == b''
            old_hash = identity(project)
            ns_main = new_ns()
            for stem in 'moc':
                vol = volume(stem, ns_main)
                volumes.append(vol)
                for flag in ('--runsc', '--docker-fallback'):
                    launch(stem, project, 'printf fixture > /persist/lifecycle-marker', ns_main, flag)
                    launch(stem, project, 'test "$(cat /persist/lifecycle-marker)" = fixture', ns_main, flag)
                record('restart', harness=stem, runtimes=['runsc', 'runc'], result='pass', volume=vol)
            alias = root / 'alias'; alias.symlink_to(project, target_is_directory=True)
            for stem in 'moc':
                launch(stem, alias, 'test "$(cat /persist/lifecycle-marker)" = fixture', ns_main)
            record('physical-alias', result='pass', identity=old_hash)
            # Auth-scope identity: global shared across projects, project
            # isolated, scopes distinct — via dry-run (no containers).
            second_identity = root / 'second-identity'; second_identity.mkdir(mode=0o700)
            for stem in 'moc':
                g_a = dryrun(stem, project, ns_main, 'global')
                g_b = dryrun(stem, second_identity, ns_main, 'global')
                assert g_a == g_b, stem
                p_a = dryrun(stem, project, ns_main, 'project')
                p_b = dryrun(stem, second_identity, ns_main, 'project')
                assert p_a != p_b, stem
                assert g_a != p_a, stem
                record('auth-scope-identity', harness=stem, result='pass',
                       global_shared=True, project_isolated=True)
            moved = root / 'moved'; project.rename(moved)
            new_hash = identity(moved)
            assert new_hash != old_hash
            # Phase-S isolation: the moved project owns a fresh namespace so
            # per-project move/reset assertions keep passing. (Phases 5/7
            # collapse moves onto the shared namespace with scope-aware
            # sharing expectations.)
            ns_moved = new_ns()
            for stem in 'moc':
                vol = volume(stem, ns_moved)
                volumes.append(vol)
                launch(stem, moved, 'test ! -e /persist/lifecycle-marker; printf moved > /persist/lifecycle-marker', ns_moved)
                assert run(docker + ['volume', 'inspect', vol], check=False).returncode == 0
                record('physical-move', harness=stem, old_state_retained=True, new_identity=new_hash, result='pass')
                guard(vol)
                run(docker + ['volume', 'rm', vol])
                if stem == 'c':
                    shutil.rmtree(codex_home(ns_moved))
                launch(stem, moved, 'test ! -e /persist/lifecycle-marker', ns_moved)
                record('project-reset', harness=stem, result='pass', providers_retained=providers.exists(),
                       muse_global_home_retained=(home / '.config/box-m/muse-config').exists())
            configs_before = inventory(home / '.config')
            unrelated = home / '.local/bin/unrelated'; unrelated.write_text('keep\n')
            # Disposable code-only installation tree, retain unrelated executable.
            for p in (home / '.local/bin').iterdir():
                if p == unrelated:
                    continue
                if p.is_dir() and not p.is_symlink():
                    shutil.rmtree(p)
                else:
                    p.unlink()
            assert inventory(home / '.config') == configs_before
            assert unrelated.read_text() == 'keep\n'
            for vol in volumes:
                assert run(docker + ['volume', 'inspect', vol], check=False).returncode == 0
            record('code-only-uninstall', result='pass', configuration_and_stores_retained=True, unrelated_retained=True)
            seen = set()
            for vol in volumes:
                if vol in seen:
                    continue
                seen.add(vol)
                guard(vol)
                run(docker + ['volume', 'rm', vol])
            volumes.clear()
            codex_homes = [codex_home(ns) for ns in (ns_main, ns_moved)]
            for path in codex_homes:
                shutil.rmtree(path)
            shutil.rmtree(home / '.config')
            assert all(not path.exists() for path in codex_homes)
            assert not providers.exists() and unrelated.exists() and bundle.exists()
            record('full-uninstall-state', result='pass', fixture_credentials_homes_volumes_removed=True,
                   source_retained=True, shared_images_and_networks_retained=True)
        finally:
            inventory_result = run(docker + ['volume', 'ls', '-q'])
            existing = set(inventory_result.stdout.splitlines())
            failures = []
            for vol in dict.fromkeys(volumes):
                guard(vol)
                if vol in existing and run(docker + ['volume', 'rm', vol], check=False).returncode:
                    failures.append(vol)
            record('cleanup', remaining_owned_volumes=failures)
            if failures:
                raise RuntimeError('owned volume cleanup failed: %s' % ', '.join(failures))


if __name__ == '__main__':
    main()
