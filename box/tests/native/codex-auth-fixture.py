#!/usr/bin/env python3
"""Pinned Codex file-storage checks, using only disposable synthetic auth.

No model calls, device login or remote token rotation. Network configuration
points at a closed loopback port. This is storage evidence, not account acceptance.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--scratch-root", required=True)
    args = parser.parse_args()
    bundle = Path(__file__).resolve().parents[2]
    binary = Path(args.binary).resolve(strict=True)
    archive = Path(args.archive).resolve(strict=True)
    arch = {"x86_64": "AMD64", "aarch64": "ARM64"}.get(platform.machine())
    if arch is None:
        raise SystemExit("BLOCKED: unsupported native fixture architecture")
    # Verify provenance before executing even --version. A matching version
    # string alone cannot identify the pinned executable.
    def pin(name):
        return subprocess.run(
            ["bash", "-p", "-c", 'source "$1/lib/pins.sh"; box_print_pin "$1" "$2"',
             "fixture", str(bundle), name],
            env={"PATH": "/usr/bin:/bin", "BOX_TOOL": "fixture"},
            check=True, capture_output=True, text=True).stdout

    expected_digest = pin("CODEX_SHA256_" + arch)
    def digest(stream):
        value = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
        return value.hexdigest()

    with archive.open("rb") as stream:
        if digest(stream) != expected_digest:
            raise SystemExit("BLOCKED: Codex package does not match the pinned artifact")
    with tarfile.open(archive, "r:gz") as package:
        members = [m for m in package.getmembers() if m.name == "bin/codex"]
        if len(members) != 1 or not members[0].isfile() or not members[0].mode & 0o111:
            raise SystemExit("BLOCKED: invalid Codex executable member")
        with package.extractfile(members[0]) as stream, binary.open("rb") as executable:
            if digest(stream) != digest(executable):
                raise SystemExit("BLOCKED: Codex executable differs from the verified package")
    expected_version = "codex-cli " + pin("CODEX_VERSION")
    adapter = bundle / "harnesses/codex/auth.sh"
    with tempfile.TemporaryDirectory(prefix="codex-auth-fixture-", dir=args.scratch_root) as root:
        root = Path(root)
        home = root / "codex-home"
        home.mkdir(mode=0o700)
        env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin", "HOME": str(root),
            "CODEX_HOME": str(home), "XDG_CONFIG_HOME": str(root / "config"),
            "XDG_DATA_HOME": str(root / "data"), "XDG_STATE_HOME": str(root / "state"),
            "XDG_CACHE_HOME": str(root / "cache"), "LANG": "C.UTF-8",
            "OPENAI_BASE_URL": "http://127.0.0.1:9", "TERM": "dumb",
            "HTTP_PROXY": "http://127.0.0.1:9", "HTTPS_PROXY": "http://127.0.0.1:9",
        }

        def run(*argv, input_text=None, success=True):
            result = subprocess.run(argv, env=env, cwd=root, input=input_text,
                                    text=True, capture_output=True, timeout=30)
            if success and result.returncode:
                raise AssertionError("native fixture command failed (output withheld)")
            return result

        version = run(binary, "--version").stdout.strip()
        if version != expected_version:
            raise SystemExit("BLOCKED: fixture requires the pinned Codex version")
        print("N: verified Codex package SHA256=" + expected_digest + " arch=" + arch.lower())
        print("N: native version=" + version + "; synthetic provider checks only")
        native = home / "auth.json"
        envelope = root / "envelope.json"

        def adapter_call(function, *paths, success=True):
            return run("bash", "-c", 'source "$1"; shift; "$@"', "fixture",
                       str(adapter), function, *(str(p) for p in paths), success=success)

        markers = {"history.jsonl": b"synthetic history\n", "config.toml": b"# trust fixture\n"}
        for name, contents in markers.items():
            (home / name).write_bytes(contents)
        run(binary, "login", "-c", 'cli_auth_credentials_store="file"',
            "--with-api-key", input_text="box-synthetic-native-key\n")
        assert json.loads(native.read_text())["OPENAI_API_KEY"] == "box-synthetic-native-key"
        assert native.stat().st_mode & 0o777 == 0o600
        adapter_call("box_adapter_export", native, envelope)
        adapter_call("box_adapter_verify_envelope", envelope)
        run(binary, "logout", "-c", 'cli_auth_credentials_store="file"')
        assert not native.exists()
        adapter_call("box_adapter_install", envelope, native)
        run(binary, "login", "status", "-c", 'cli_auth_credentials_store="file"')

        claims = base64.urlsafe_b64encode(b'{"email":"fixture@example.invalid"}').decode().rstrip("=")
        oauth = {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
                 "tokens": {"id_token": "e30." + claims + ".synthetic",
                            "access_token": "synthetic-access", "refresh_token": "synthetic-refresh",
                            "account_id": "synthetic-account"},
                 "last_refresh": "2026-10-07T00:00:00Z"}
        native.write_text(json.dumps(oauth))
        os.chmod(native, 0o600)
        adapter_call("box_adapter_export", native, envelope)
        run(binary, "login", "status", "-c", 'cli_auth_credentials_store="file"')
        # Refresh-shaped local writes test adapter round-trip, not remote rotation.
        oauth["tokens"]["refresh_token"] = "synthetic-rotated-refresh"
        native.write_text(json.dumps(oauth))
        adapter_call("box_adapter_export", native, envelope)
        before = envelope.read_bytes()
        native.write_text('{"tokens":')
        assert adapter_call("box_adapter_export", native, envelope, success=False).returncode
        assert envelope.read_bytes() == before
        assert native.read_text() == '{"tokens":'
        adapter_call("box_adapter_install", envelope, native)
        assert json.loads(native.read_text())["tokens"]["refresh_token"] == "synthetic-rotated-refresh"
        # Unsupported modes must preserve both the authoritative source and
        # the prior canonical envelope. These are adapter refusals; no unsupported
        # native backend is invoked or inspected.
        for mode in ("agent_identity", "pat", "bedrock", "keyring", "auto"):
            unsupported = {"auth_mode": mode, "OPENAI_API_KEY": "synthetic"}
            native.write_text(json.dumps(unsupported))
            source_before = native.read_bytes()
            envelope_before = envelope.read_bytes()
            assert adapter_call("box_adapter_export", native, envelope, success=False).returncode
            assert native.read_bytes() == source_before
            assert envelope.read_bytes() == envelope_before
        adapter_call("box_adapter_install", envelope, native)
        run(binary, "logout", "-c", 'cli_auth_credentials_store="file"')
        adapter_call("box_adapter_export", native, envelope)
        assert json.loads(envelope.read_text())["tombstone"]
        for name, contents in markers.items():
            assert (home / name).read_bytes() == contents
        print("PASS: pinned Codex native API-key storage, synthetic OAuth load, logout,")
        print("adapter round-trip, refresh-shaped write, truncated-write/unsupported-mode preservation, unrelated markers")
    print("Cleanup: disposable native home and synthetic credentials removed")


if __name__ == "__main__":
    main()
