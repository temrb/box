"""Release acceptance only, in a disposable project/container, without credentials.
A loopback scripted provider exercises the binary's real v2 tool permission
path. No real model or external service is called and no output is dumped.
"""
import base64
import select
import socket
import time
import urllib.request
import json
import os
import pathlib
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

WORKSPACE = pathlib.Path("/workspace")
OUTSIDE = pathlib.Path("/tmp/box-policy-outside.fixture")

SCENARIOS = [
    {"name": "build", "agent": "build"},
    {"name": "explore", "agent": "explore"},
    {"name": "custom-agent", "agent": "audit_override", "agentConfig": {
        "audit_override": {"mode": "all", "permissions": [
            {"action": "*", "resource": "*", "effect": "allow"},
        ]},
    }},
    {"name": "project-override", "agent": "build", "projectPermissions": [
        {"action": "*", "resource": "*", "effect": "allow"},
    ]},
    {"name": "session-auto", "agent": "build", "flags": ["--auto"]},
]

OPERATIONS = [
    {"name": "env-read", "tool": "read", "permission": "read", "path": "/workspace/test.env", "expected": "ask"},
    {"name": "env-suffix-read", "tool": "read", "permission": "read", "path": "/workspace/test.env.production", "expected": "ask"},
    {"name": "example-read", "tool": "read", "permission": "read", "path": "/workspace/test.env.example", "expected": "allow"},
    {"name": "env-write", "tool": "write", "permission": "edit", "path": "/workspace/new.env", "expected": "ask"},
    {"name": "external-read", "tool": "read", "permission": "external_directory", "path": "/tmp/box-policy-outside.fixture", "permission_resource": "/tmp/*", "expected": "ask"},
]


class Handler(BaseHTTPRequestHandler):
    operation = None

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""
        try:
            data = json.loads(body) if body else {}
        except Exception:
            self.send_response(400)
            self.end_headers()
            return
        msgs = data.get("messages", [])
        done = not data.get("tools") or any(m.get("role") == "tool" for m in msgs)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        op = Handler.operation or {}
        if not done:
            params = {"path": op.get("path", "/workspace/test.env")}
            if op.get("tool") == "write":
                params["content"] = "synthetic non-secret fixture\n"
            delta = {"tool_calls": [{"index": 0, "id": "call_fixture", "type": "function",
                                    "function": {"name": op.get("tool", "read"),
                                                 "arguments": json.dumps(params)}}]}
        else:
            delta = {"content": "fixture complete"}
        for choice in [
            {"index": 0, "delta": {"role": "assistant", **delta}, "finish_reason": None},
            {"index": 0, "delta": {}, "finish_reason": "stop" if done else "tool_calls"},
        ]:
            chunk = {"id": "chatcmpl-fixture", "object": "chat.completion.chunk",
                     "created": 1, "model": "fixture", "choices": [choice]}
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
        self.wfile.write(b"data: [DONE]\n\n")

    def log_message(self, *args):
        pass


def run_opencode(args, env):
    try:
        proc = subprocess.run(
            ["opencode", *args],
            env=env, capture_output=True, text=True, timeout=25,
        )
        return {"code": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr, "bounded": True}
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        err = exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        return {"code": -1, "stdout": out, "stderr": err, "bounded": False}


def classify(result, op):
    """Only matched native evidence is authoritative; silence is never denial."""
    if not result.get("bounded"):
        return "unavailable"
    try:
        events = [json.loads(line) for line in result.get("stdout", "").splitlines() if line.strip()]
        if not events or any(not isinstance(event, dict) for event in events):
            return "unavailable"
        parts = [event.get("part", {}) for event in events if event.get("type") == "tool_use"]
        matched = [part["state"] for part in parts
                   if part.get("tool") == op["tool"]
                   and part.get("state", {}).get("input", {}).get("path") == op["path"]]
        if not matched:
            return "unavailable"
        state = matched[-1]
        resource = op.get("permission_resource", pathlib.Path(op["path"]).name)
        request = "permission requested: " + op["permission"] + " (" + resource + "); auto-rejecting"
        asks = [line for line in result.get("stderr", "").splitlines() if request in line]
        if "permission requested:" in result.get("stderr", "") and not asks:
            return "unavailable"
        # CLI ask auto-rejection emits an aborted shutdown as well as its tool error.
        errors = [event.get("error", {}) for event in events if event.get("type") == "error"]
        if any(error.get("type") != "aborted" or not asks for error in errors):
            return "unavailable"
        if asks and state.get("status") == "error" and state.get("error") == "The user declined this tool call":
            return "ask"
        if state.get("status") == "completed" and result.get("code") == 0 and not errors and not asks:
            return "allow"
        if (state.get("status") == "error" and result.get("code") == 0 and not asks and not errors
                and state.get("error") == "Permission denied: " + op["permission"]):
            return "deny"
    except (ValueError, TypeError, KeyError, AttributeError):
        pass
    return "unavailable"


def save_approval():
    """Use the pinned server API to approve and persist an actual native request."""
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    proc = subprocess.Popen(["opencode", "serve", "--hostname", "127.0.0.1", "--port", str(port)],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        # Read bounded startup lines without printing the generated server password.
        lines = []
        deadline = time.monotonic() + 10
        buffer = b""
        while len(lines) < 2 and time.monotonic() < deadline:
            if select.select([proc.stdout], [], [], 0.2)[0]:
                chunk = os.read(proc.stdout.fileno(), 4096)
                if not chunk:
                    raise RuntimeError("Native server failed at startup")
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    lines.append(line.decode())
        password = next(line.split("server password ", 1)[1] for line in lines if line.startswith("server password "))
        headers = {"Authorization": "Basic " + base64.b64encode(("opencode:" + password).encode()).decode(),
                   "Content-Type": "application/json"}
        def api(path, body=None):
            request = urllib.request.Request(f"http://127.0.0.1:{port}" + path,
                        data=None if body is None else json.dumps(body).encode(), headers=headers)
            with urllib.request.urlopen(request, timeout=10) as response:
                payload = response.read()
                return json.loads(payload) if payload else None
        # Initialize the native agent service before its experimental permission API.
        # Without this route, a fresh serve process can resolve the fallback deny agent.
        if not isinstance(api("/api/agent").get("data"), list):
            raise RuntimeError("Native agent inspection unavailable")
        session = api("/api/session", {"location": {"directory": "/workspace"}, "agent": "build"})["data"]["id"]
        path = f"/api/session/{session}/permission"
        request = {"action": "read", "resources": ["test.env"], "save": ["*.env"], "agent": "build"}
        created = api(path, request)["data"]
        if created["effect"] != "ask":
            raise RuntimeError("Native saved approval seed did not request approval")
        pending = api(path)["data"]
        if (len(pending) != 1 or pending[0]["id"] != created["id"]
                or pending[0]["action"] != "read" or pending[0]["resources"] != ["test.env"]):
            raise RuntimeError("Missing matched native approval request")
        api(path + "/" + created["id"] + "/reply", {"decision": "always"})
        if api(path, request)["data"]["effect"] != "allow":
            raise RuntimeError("Native saved approval did not allow")
        saved = api("/api/permission/saved")["data"]
        if not any(item["action"] == "read" and item["resource"] == "*.env" for item in saved):
            raise RuntimeError("Native approval was not durably saved")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def main():
    if not (WORKSPACE / ".box-native-disposable").exists():
        raise RuntimeError("Native probe requires a disposable acceptance project")
    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        OUTSIDE.write_text("synthetic non-secret fixture\n")
    except OSError:
        pass
    provider = {"box_fixture": {
        "name": "Local fixture",
        "package": "@opencode/ai/providers/openai-compatible",
        "settings": {"baseURL": f"http://127.0.0.1:{port}/v1", "apiKey": "{env:SYNTHETIC_FIXTURE_KEY}"},
        "models": {"fixture": {"name": "fixture",
                               "capabilities": {"tools": True, "input": ["text"], "output": ["text"]},
                               "limit": {"context": 200000, "output": 1024}}},
    }}
    base_env = dict(os.environ, SYNTHETIC_FIXTURE_KEY="synthetic-fixture")
    failures = 0
    try:
        phase = sys.argv[1] if len(sys.argv) == 2 else "matrix"
        if phase not in ("matrix", "saved-seed", "saved-restart", "saved-isolation"):
            raise RuntimeError("Unknown native probe phase")
        if phase != "matrix":
            (WORKSPACE / "opencode.json").write_text(json.dumps({"providers": provider}))
            Handler.operation = OPERATIONS[0]
            pathlib.Path(OPERATIONS[0]["path"]).write_text("synthetic non-secret fixture\n")
            args = ["run", "--standalone", "--format", "json", "--agent", "build",
                    "--model", "box_fixture/fixture", "Use the fixture tool"]
            if phase == "saved-seed":
                # A native turn resolves current agent rules after the override matrix.
                # The experimental permission API reads the stored resolved agent.
                before = run_opencode(args, base_env)
                if classify(before, OPERATIONS[0]) != "ask":
                    raise RuntimeError("Saved approval seed lacks initial matched native ask")
                save_approval()
            result = run_opencode(args, base_env)
            expected = "ask" if phase == "saved-isolation" else "allow"
            if classify(result, OPERATIONS[0]) != expected:
                raise RuntimeError("Saved approval inspection failed: " + phase)
            print("PASS: " + phase + ": matched native read " + expected, flush=True)
        for scenario in SCENARIOS if phase == "matrix" else []:
            project_cfg = {"providers": provider}
            if scenario.get("agentConfig"):
                project_cfg["agents"] = scenario["agentConfig"]
            if scenario.get("projectPermissions"):
                project_cfg["permissions"] = scenario["projectPermissions"]
            (WORKSPACE / "opencode.json").write_text(json.dumps(project_cfg))
            for op in OPERATIONS:
                Handler.operation = op
                if op["tool"] == "write":
                    try:
                        pathlib.Path(op["path"]).unlink()
                    except OSError:
                        pass
                else:
                    pathlib.Path(op["path"]).write_text("synthetic non-secret fixture\n")
                result = run_opencode(
                    ["run", "--standalone", "--format", "json", "--agent", scenario["agent"],
                     "--model", "box_fixture/fixture", *(scenario.get("flags") or []),
                     "Use the fixture tool"],
                    base_env,
                )
                actual = classify(result, op)
                expected = "allow" if scenario["name"] in ("custom-agent", "project-override", "session-auto") else op["expected"]
                status = "PASS" if actual == expected else "FAIL"
                if actual != expected:
                    failures += 1
                print(f"{status}: {scenario['name']}/{op['name']}: native {actual}, expected {expected}", flush=True)
                if not result["bounded"]:
                    print("FAIL: native OpenCode inspection timed out", file=sys.stderr)
                    failures += 1
        # Separate --auto hard-deny coverage; durable approvals are tested via native API.
        deny_cfg = {"providers": provider,
                    "permissions": [
                        {"action": "*", "resource": "*", "effect": "allow"},
                        {"action": "read", "resource": "*.env", "effect": "deny"},
                    ]}
        (WORKSPACE / "opencode.json").write_text(json.dumps(deny_cfg))
        Handler.operation = OPERATIONS[0]
        pathlib.Path(OPERATIONS[0]["path"]).write_text("synthetic non-secret fixture\n")
        result = run_opencode(
            ["run", "--standalone", "--format", "json", "--agent", "build",
             "--model", "box_fixture/fixture", *( ["--auto"] if phase == "matrix" else []), "Use the fixture tool"],
            base_env,
        )
        denied = classify(result, OPERATIONS[0]) == "deny"
        if denied:
            print("PASS: deny/ask-matrix: configured deny survives " + ("--auto" if phase == "matrix" else "saved approval"), flush=True)
        else:
            print("FAIL: deny/ask-matrix: configured deny lacks explicit native rejection", flush=True)
            failures += 1
    finally:
        server.shutdown()
        try:
            (WORKSPACE / "opencode.json").unlink()
        except OSError:
            pass
    if failures:
        print("FAIL: OpenCode native approval-default/override inspection", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL: native OpenCode inspection unavailable: {exc}", file=sys.stderr)
        sys.exit(1)
