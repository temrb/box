"""Bounded 0.160.0 app-server policy probe. Never starts a model turn.

RPC responses and stderr remain private. Emit only selected assertions.
"""
import argparse
import json
import os
import select
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urlparse


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


class Probe:
    def __init__(self, extra=()):
        self.err = tempfile.TemporaryFile()
        self.proc = subprocess.Popen(
            [os.environ.get("BOX_CODEX_BINARY", "codex"), "--strict-config", *extra, "app-server"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.err,
            start_new_session=True, bufsize=0,
        )
        self.counter = 0
        self.buffer = b""
        try:
            self.rpc("initialize", {"clientInfo": {"name": "box_policy_probe", "version": "1"},
                                "capabilities": {"experimentalApi": True}})
            self.send({"method": "initialized", "params": {}})
        except BaseException:
            self.close()
            raise

    def send(self, value):
        self.proc.stdin.write(json.dumps(value).encode() + b"\n")

    def rpc(self, method, params):
        self.counter += 1
        self.send({"id": self.counter, "method": method, "params": params})
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            if b"\n" not in self.buffer:
                ready, _, _ = select.select([self.proc.stdout], [], [], max(0, deadline-time.monotonic()))
                require(ready, "app-server policy inspection timed out")
                chunk = os.read(self.proc.stdout.fileno(), 65536)
                require(chunk, "app-server exited before policy inspection (strict config/startup failure)")
                self.buffer += chunk
                require(len(self.buffer) < 8_000_000, "app-server probe response exceeds bound")
                continue
            line, self.buffer = self.buffer.split(b"\n", 1)
            value = json.loads(line)
            if value.get("id") == self.counter:
                return value
        raise RuntimeError("app-server policy inspection timed out")

    def result(self, method, params):
        value = self.rpc(method, params)
        require("result" in value, method + " rejected; required policy inspection unavailable")
        return value["result"]

    def close(self):
        if self.proc.poll() is None:
            os.killpg(self.proc.pid, signal.SIGTERM)
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.proc.pid, signal.SIGKILL)
                self.proc.wait(timeout=3)
        self.err.close()


def check_thread(result):
    require(result.get("approvalPolicy") == "on-request", "normalized thread approval policy differs")
    require(result.get("approvalsReviewer") == "user", "normalized thread reviewer differs")
    require(result.get("sandbox", {}).get("type") == "dangerFullAccess", "normalized thread containment differs")
    require(result.get("thread", {}).get("ephemeral") is True, "probe thread must be ephemeral")


def check_config(result, expected):
    config = result.get("config", {})
    for key, value in expected.items():
        if key.startswith("allowed_"):
            continue
        require(config.get(key) == value, "effective configuration differs or is unavailable: " + key)
    require(config.get("approval_policy") == "on-request", "effective approval policy differs")
    require(config.get("approvals_reviewer") == "user", "effective reviewer differs")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy-json", required=True)
    parser.add_argument("--conflicts", action="store_true")
    args = parser.parse_args()
    expected = json.loads(args.policy_json)
    probe = None
    try:
        probe = Probe()
        # Inspect actual project layering too; never print native config contents.
        check_config(probe.result("config/read", {"includeLayers": True, "cwd": "/workspace"}), expected)
        req = probe.result("configRequirements/read", {})["requirements"]
        require(isinstance(req, dict), "managed requirements not loaded")
        fields = {"allowed_approval_policies": "allowedApprovalPolicies",
                  "allowed_permission_profiles": "allowedPermissionProfiles",
                  "default_permissions": "defaultPermissions",
                  "cli_auth_credentials_store": "cliAuthCredentialsStore",
                  "check_for_update_on_startup": "checkForUpdateOnStartup",
                  "sqlite_home": "sqliteHome"}
        for key, native in fields.items():
            value = req.get(native)
            if key == "sqlite_home" and isinstance(value, str) and value.startswith("file://"):
                uri = urlparse(value)
                require(uri.netloc == "", "SQLite path has a remote authority")
                value = unquote(uri.path)
            require(value == expected[key], "loaded requirement differs or is unavailable: " + key)
        check_thread(probe.result("thread/start", {"cwd": "/workspace", "ephemeral": True}))
        # Reviewer allowlists are not exposed by this release's requirements RPC.
        # Exercise native enforcement directly instead of claiming field visibility.
        reviewer = probe.rpc("thread/start", {"cwd": "/workspace", "ephemeral": True,
                                               "approvalsReviewer": "auto_review"})
        if "result" in reviewer:
            check_thread(reviewer["result"])
        else:
            require(reviewer.get("error", {}).get("code") in (-32600, -32602),
                    "reviewer rejection did not establish policy enforcement")
        print("PASS: native requirements loaded; thread on-request/user/dangerFullAccess; reviewer override constrained")
        if args.conflicts:
            cases = [
                {"approvalPolicy": "never"}, {"sandbox": "read-only"},
                {"sandbox": "workspace-write"}, {"permissions": ":workspace"},
                {"config": {"approval_policy": "never", "approvals_reviewer": "auto_review"}},
                {"config": {"cli_auth_credentials_store": "ephemeral", "check_for_update_on_startup": True,
                            "sqlite_home": "/tmp/forbidden-state"}},
            ]
            for case in cases:
                response = probe.rpc("thread/start", {"cwd": "/workspace", "ephemeral": True, **case})
                if "result" in response:
                    check_thread(response["result"])
                else:
                    require(response.get("error", {}).get("code") in (-32600, -32602), "unrelated conflict failure")
            print("PASS: native session/config/legacy/profile conflict probes constrained")
            # Thread policy alone cannot establish credential/update/SQLite
            # enforcement. Inspect the effective config under CLI conflicts.
            for key, value in [("cli_auth_credentials_store", '"ephemeral"'),
                               ("check_for_update_on_startup", "true"),
                               ("sqlite_home", '"/tmp/forbidden-state"')]:
                conflicting = None
                try:
                    conflicting = Probe(("-c", key + "=" + value))
                    check_config(conflicting.result("config/read", {"cwd": "/workspace"}), expected)
                    check_thread(conflicting.result("thread/start", {"cwd": "/workspace", "ephemeral": True}))
                finally:
                    if conflicting is not None:
                        conflicting.close()
            print("PASS: credential store, update check, and SQLite CLI conflicts constrained")
    finally:
        if probe is not None:
            probe.close()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, KeyError, ValueError) as exc:
        # Our own messages contain no config values or credential contents.
        print("FAIL: Codex native policy acceptance: " + str(exc), file=sys.stderr)
        sys.exit(1)
