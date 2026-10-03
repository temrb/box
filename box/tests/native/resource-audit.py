"""Bounded scratch-storage experiment; no accounts, installed homes or live projects.

Run with Python 3 and access to the local rootful Docker socket. The image must
already exist (build only through Make). JSON output contains metadata/counters,
never environments or credentials. Each case moves a disposable 160 MiB tree.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import uuid


def storage_workload():
    # Prerequisites must succeed before measuring the expected move failure.
    return (
        'set -e; export TMPDIR=/scratch; cd /scratch; '
        'printf "#!/bin/sh\\nexit 0\\n" > tool; chmod +x tool; ./tool; '
        'gcc -x c -o compiled - <<< "int main(void){return 0;}"; ./compiled; '
        'printf "executable_and_compile=pass\\n"; '
        'sleep 1; set +e; mv /source/dependencies /scratch/; rc=$?; '
        'printf "move_rc=%s source_files=%s dest_files=%s\\n" "$rc" '
        '"$(find /source -type f | wc -l)" "$(find /scratch -type f | wc -l)"; '
        'sleep 1; exit "$rc"'
    )


def cleanup_case(call, name, proc):
    try:
        call("rm", "-f", name)
    finally:
        # A daemon error must not skip reaping the experiment's Docker client.
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.communicate(timeout=10)


def main():
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--scratch-root", required=True,
                        help="writable disk-backed parent for disposable source/scratch")
    options = parser.parse_args()
    if os.getuid() == 0:
        parser.error("run as the normal host user")
    filesystem = subprocess.check_output(
        ["findmnt", "-n", "-T", options.scratch_root, "-o", "FSTYPE"], text=True).strip()
    if filesystem in ("tmpfs", "ramfs"):
        parser.error("scratch-root must be disk-backed; a tmpfs bind is still memory-backed")
    with tempfile.TemporaryDirectory(prefix="box-resource-audit-", dir=options.scratch_root) as root:
        root = Path(root)
        (root / "config.json").write_text("{}\n")
        docker = ["docker", "--config", str(root), "--host", "unix:///var/run/docker.sock"]

        def call(*args, check=True):
            return subprocess.run(docker + list(args), check=check, text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)

        call("image", "inspect", options.image, "--format", "{{.Config.User}}")
        for runtime in ("runc", "runsc"):
            for storage in ("tmpfs", "sized-tmpfs", "disk"):
                case = root / f"{runtime}-{storage}"
                source = case / "source" / "dependencies"
                scratch = case / "scratch"
                source.mkdir(parents=True)
                scratch.mkdir()
                block = b"dependency-fixture\n" * (1024 * 1024 // 19)
                # Non-sparse files: resident destination storage matters here.
                for index in range(160):
                    (source / f"package-{index:03}.bin").write_bytes(block)
                expected = hashlib.sha256(block).hexdigest()
                name = "box-resource-audit-" + uuid.uuid4().hex
                command = ["run", "--name", name, "--pull=never", f"--runtime={runtime}",
                           "--user", f"{os.getuid()}:{os.getgid()}", "--network=none",
                           "--cap-drop=ALL", "--security-opt=no-new-privileges", "--read-only",
                           "--memory=128m", "--memory-swap=128m", "--cpus=1", "--pids-limit=64",
                           "--log-driver=none", "--mount", f"type=bind,src={source.parent},dst=/source,bind-recursive=disabled"]
                if storage == "disk":
                    command += ["--mount", f"type=bind,src={scratch},dst=/scratch,bind-recursive=disabled"]
                else:
                    size = ",size=32m" if storage == "sized-tmpfs" else ""
                    command += ["--tmpfs", f"/scratch:rw,nosuid,nodev,exec,uid={os.getuid()},gid={os.getgid()},mode=700{size}"]
                command += ["--entrypoint=/bin/bash", options.image, "-c", storage_workload()]
                proc = None
                counters = {}
                try:
                    proc = subprocess.Popen(docker + command, stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE, text=True)
                    deadline = time.monotonic() + 45
                    while proc.poll() is None and time.monotonic() < deadline:
                        result = call("inspect", "--format", "{{.State.Pid}}", name, check=False)
                        if result.returncode == 0 and result.stdout.strip() != "0":
                            try:
                                pid = result.stdout.strip()
                                group = Path(f"/proc/{pid}/cgroup").read_text().split("0::", 1)[1].strip()
                                cg = Path("/sys/fs/cgroup") / group.lstrip("/")
                                for filename in ("memory.current", "memory.peak", "memory.swap.current"):
                                    value = int((cg / filename).read_text())
                                    counters[filename] = max(counters.get(filename, 0), value)
                                for line in (cg / "memory.stat").read_text().splitlines():
                                    key, value = line.split()
                                    if key in ("anon", "file", "shmem"):
                                        counters[key] = max(counters.get(key, 0), int(value))
                                counters["memory.events"] = (cg / "memory.events").read_text().strip()
                            except (OSError, ValueError, IndexError):
                                pass
                        time.sleep(0.1)
                    if proc.poll() is None:
                        call("rm", "-f", name)
                    stdout, stderr = proc.communicate(timeout=10)
                    state = call("inspect", "--format", "{{json .State}}", name, check=False)
                    # Verify remaining source bytes after failure, without printing data.
                    intact = all(hashlib.sha256(p.read_bytes()).hexdigest() == expected
                                 for p in source.glob("*.bin"))
                    destination = scratch / "dependencies"
                    destination_intact = None
                    if storage == "disk":
                        files = list(destination.glob("*.bin"))
                        destination_intact = len(files) == 160 and all(
                            hashlib.sha256(p.read_bytes()).hexdigest() == expected for p in files)
                    print(json.dumps({"runtime": runtime, "storage": storage,
                                      "host_filesystem": filesystem,
                                      "rc": proc.returncode, "stdout": stdout.strip(),
                                      "stderr": stderr[-500:], "counters": counters,
                                      "state": json.loads(state.stdout) if state.returncode == 0 else None,
                                      "remaining_source_files": len(list(source.glob("*.bin"))),
                                      "disk_destination_intact": destination_intact,
                                      "remaining_source_intact": intact}), flush=True)
                finally:
                    cleanup_case(call, name, proc)


if __name__ == "__main__":
    main()
