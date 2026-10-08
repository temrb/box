#!/usr/bin/env python3
"""Stop supervised process groups and native services before auth collection.

Run in the container PID namespace. Never match command-line substrings;
identify detached native services by their exact executable and owner.
"""
import argparse
import os
from pathlib import Path
import signal
import sys
import time


def processes(group, native):
    result = {}
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        path = Path('/proc') / name
        try:
            if path.stat().st_uid != os.getuid():
                continue
            fields = (path / 'stat').read_text().rsplit(')', 1)[1].split()
            state, pgid, session, start = fields[0], int(fields[2]), int(fields[3]), fields[19]
            # Zombies have exited and hold no native auth/database descriptors;
            # the container init reaps orphan services.
            if state == 'Z':
                continue
            exe = os.path.realpath(path / 'exe')
            if (group is not None and (pgid == group or session == group or int(name) == group)) or exe == native:
                result[int(name)] = start
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return result


def stop(group, native):
    for sig, grace in ((signal.SIGTERM, 3), (signal.SIGKILL, 2)):
        deadline = time.monotonic() + grace
        while True:
            targets = processes(group, native)
            if not targets:
                return
            for pid, start in targets.items():
                # Never signal a recycled PID from an earlier scan.
                if processes(group, native).get(pid) != start:
                    continue
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
            if time.monotonic() >= deadline:
                break
            time.sleep(0.05)
    if processes(group, native):
        raise RuntimeError('native processes remain active; auth collection refused')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', type=int)
    parser.add_argument('--native-exe', required=True)
    args = parser.parse_args()
    if args.group is not None and (args.group <= 1 or args.group == os.getpgrp()):
        raise ValueError('invalid supervised process group')
    native = os.path.realpath(args.native_exe)
    if not os.path.isabs(args.native_exe) or not os.path.isfile(native):
        raise ValueError('missing exact native executable')
    stop(args.group, native)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError) as exc:
        print(f'process shutdown refused: {exc}', file=sys.stderr)
        sys.exit(1)
