#!/usr/bin/env python3
"""Pinned Muse file-backend qualification in a disposable synthetic home."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import subprocess
import tempfile


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--scratch-root", required=True)
    args = parser.parse_args()
    arch = {"x86_64": "AMD64", "aarch64": "ARM64"}.get(platform.machine())
    if arch is None:
        raise SystemExit("BLOCKED: unsupported Muse native fixture architecture")
    bundle = Path(__file__).resolve().parents[2]
    binary = Path(args.binary).resolve(strict=True)
    pin = subprocess.run(["bash", "-p", "-c", 'source "$1/lib/pins.sh"; box_print_pin "$1" "$2"',
                          "fixture", str(bundle), "MUSE_SHA256_" + arch], env={"PATH": "/usr/bin:/bin", "BOX_TOOL": "fixture"},
                         check=True, capture_output=True, text=True).stdout
    if hashlib.sha256(binary.read_bytes()).hexdigest() != pin:
        raise ValueError("Muse binary does not match the pinned architecture artifact")
    with tempfile.TemporaryDirectory(prefix="muse-auth-fixture-", dir=args.scratch_root) as directory:
        root = Path(directory)
        env = dict(PATH="/usr/bin:/bin", HOME=str(root / "home"), LANG="C.UTF-8",
                   XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
                   XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
                   TBH_CREDENTIAL_BACKEND="file", HTTP_PROXY="http://127.0.0.1:9",
                   HTTPS_PROXY="http://127.0.0.1:9", NO_PROXY="localhost,127.0.0.1")
        (root / "home").mkdir(mode=0o700)
        def run(argv, input_text=None, success=True):
            result = subprocess.run(argv, env=env, cwd=root, input=input_text,
                                    text=True, capture_output=True, timeout=30)
            if success and result.returncode:
                raise AssertionError("native Muse fixture failed (output withheld)")
            return result
        version = run([str(binary), "--version"]).stdout.strip()
        assert version == "Muse Code 1.4.0 (1.4.0-R4161.1)"
        print("N: Muse artifact SHA256=" + pin + "; arch=" + arch.lower() + "; native version=" + version)
        print("N: synthetic file API-key checks only; device/OAuth/MCP/trust membership unqualified")
        native = root / "config/muse/auth.json"
        envelope = root / "credentials.json"
        def adapter(function, *paths, success=True):
            return run(["bash", "-c", 'source "$1"; shift; "$@"', "fixture",
                        str(bundle / "harnesses/muse/auth.sh"), function,
                        *(str(p) for p in paths)], success=success)
        run([str(binary), "auth", "set", "--api-key-stdin"], "synthetic-muse-key\n")
        assert json.loads(native.read_text()) == {
            "schema_version": 1, "providers": {"meta": {"api_key": "synthetic-muse-key"}}}
        assert native.stat().st_mode & 0o777 == 0o600
        markers = {"settings.json": b"{}\n", "trust.json": b"{}\n", ".trust.json": b"{}\n"}
        for name, data in markers.items():
            (native.parent / name).write_bytes(data)
        adapter("box_adapter_export", native, envelope)
        adapter("box_adapter_verify_envelope", envelope)
        saved = envelope.read_bytes()
        run([str(binary), "logout"])
        assert json.loads(native.read_text()) == {"schema_version": 1, "providers": {}}
        adapter("box_adapter_export", native, envelope)
        assert json.loads(envelope.read_text())["tombstone"] is True
        envelope.write_bytes(saved)
        adapter("box_adapter_install", envelope, native)
        assert json.loads(native.read_text())["providers"]["meta"]["api_key"] == "synthetic-muse-key"
        # Native replacement, rather than a mirror of adapter publication.
        run([str(binary), "auth", "set", "--api-key-stdin"], "synthetic-muse-rotated\n")
        adapter("box_adapter_collect", native, envelope)
        assert json.loads(envelope.read_text())["payload"]["providers"]["meta"]["api_key"] == "synthetic-muse-rotated"
        before = envelope.read_bytes()
        for bad in ('{"providers":', '{"schema_version":1,"providers":{"meta":{"storage":"keychain"}}}',
                    '{"schema_version":1,"providers":{"unknown":{"api_key":"synthetic"}}}'):
            native.write_text(bad)
            assert adapter("box_adapter_export", native, envelope, success=False).returncode != 0
            assert envelope.read_bytes() == before and native.read_text() == bad
        adapter("box_adapter_install", envelope, native)
        run([str(binary), "logout"])
        adapter("box_adapter_collect", native, envelope)
        assert json.loads(envelope.read_text())["tombstone"] is True
        adapter("box_adapter_scrub", native)
        assert not native.exists()
        for name, data in markers.items():
            assert (native.parent / name).read_bytes() == data
    print("PASS: pinned Muse file API-key save/replacement/logout, adapter recovery, exclusions; disposable state removed")


if __name__ == "__main__":
    main()
