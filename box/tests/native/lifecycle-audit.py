"""Disposable installed-launcher moves, aliases, resets and uninstall evidence."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    bundle = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='.box-lifecycle-', dir=Path.home()) as directory:
        root = Path(directory); home = root / 'home'; home.mkdir(mode=0o700)
        project = root / 'project'; project.mkdir(mode=0o700)
        env = dict(os.environ, HOME=str(home))
        # Explicitly avoid caller credentials, caches, pins and config overrides.
        for key in list(env):
            if key.startswith(('BOX_M_', 'BOX_O_', 'BOX_C_')):
                del env[key]
        for prefix in ('BOX_M', 'BOX_O', 'BOX_C'):
            env[prefix + '_GIT_NAME'] = 'Lifecycle Fixture'
            env[prefix + '_GIT_EMAIL'] = 'fixture@example.invalid'
        docker = ['docker', '--config', str(home / '.config/box-m/docker-cli'), '--host', 'unix:///var/run/docker.sock']
        volumes = []
        def run(argv, cwd=None, check=True):
            p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, timeout=60)
            if check and p.returncode:
                raise RuntimeError('%s: %s' % (argv, p.stderr[-1000:]))
            return p
        def record(case, **data):
            print(json.dumps(dict(case=case, **data)), flush=True)
        def identity(path):
            return hashlib.sha256(str(path.resolve()).encode()).hexdigest()[:20]
        def launch(stem, path, command, flag='--runsc', check=True):
            return run([str(home / '.local/bin' / ('box-' + stem)), flag, '--shell', '-c', command], path, check)
        def inventory(path):
            return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in path.rglob('*') if p.is_file() and not p.is_symlink()}
        try:
            run(['bash', str(bundle / 'setup.sh'), '--skip-build'])
            providers = home / '.config/box/providers.env'
            assert providers.read_bytes() == b''
            old_hash = identity(project)
            for stem, prefix in [('m', 'box-m'), ('o', 'box-o-v2'), ('c', 'box-c')]:
                volume = '%s-u%s-g%s-%s' % (prefix, os.getuid(), os.getgid(), old_hash)
                volumes.append(volume)
                for flag in ('--runsc', '--docker-fallback'):
                    launch(stem, project, 'printf fixture > /persist/lifecycle-marker', flag)
                    launch(stem, project, 'test "$(cat /persist/lifecycle-marker)" = fixture', flag)
                record('restart', harness=stem, runtimes=['runsc', 'runc'], result='pass', volume=volume)
            alias = root / 'alias'; alias.symlink_to(project, target_is_directory=True)
            for stem in 'moc':
                launch(stem, alias, 'test "$(cat /persist/lifecycle-marker)" = fixture')
            record('physical-alias', result='pass', identity=old_hash)
            moved = root / 'moved'; project.rename(moved)
            new_hash = identity(moved)
            assert new_hash != old_hash
            for stem, prefix in [('m', 'box-m'), ('o', 'box-o-v2'), ('c', 'box-c')]:
                volume = '%s-u%s-g%s-%s' % (prefix, os.getuid(), os.getgid(), new_hash)
                volumes.append(volume)
                launch(stem, moved, 'test ! -e /persist/lifecycle-marker; printf moved > /persist/lifecycle-marker')
                assert run(docker + ['volume', 'inspect', volumes['moc'.index(stem)]], check=False).returncode == 0
                record('physical-move', harness=stem, old_state_retained=True, new_identity=new_hash, result='pass')
                run(docker + ['volume', 'rm', volume])
                if stem == 'c':
                    shutil.rmtree(home / '.config/box-c/projects' / new_hash / 'codex-home')
                launch(stem, moved, 'test ! -e /persist/lifecycle-marker')
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
            for volume in volumes:
                assert run(docker + ['volume', 'inspect', volume], check=False).returncode == 0
            record('code-only-uninstall', result='pass', configuration_and_stores_retained=True, unrelated_retained=True)
            for volume in volumes:
                run(docker + ['volume', 'rm', volume])
            volumes.clear()
            shutil.rmtree(home / '.config')
            assert not providers.exists() and unrelated.exists() and bundle.exists()
            record('full-uninstall-state', result='pass', fixture_credentials_homes_volumes_removed=True,
                   source_retained=True, shared_images_and_networks_retained=True)
        finally:
            for volume in volumes:
                run(docker + ['volume', 'rm', volume], check=False)
            record('cleanup', remaining_owned_volumes=[v for v in volumes if run(docker + ['volume', 'inspect', v], check=False).returncode == 0])


if __name__ == '__main__':
    main()
