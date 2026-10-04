#!/usr/bin/env bash
# verify-codex.sh — in-container readiness harness for box-c.
# GENERATED NOTE: do not edit by hand — edit shared/package verify.d/ partials and run
# gen-verify.sh. All generated verifiers stay self-contained
# (delivered via stdin under --shell, cannot source a shared file). Shared
# §§1-2/5 (workspace, toolchain, containment) live once in verify.d/
# (10-workspace.sh, 20-toolchain.sh, 50-containment.sh); §4 is
# tool-specific (image requirements + native app-server policy) and §6
# documents the unshare-only outer-runtime probe (no inner bwrap).
set -euo pipefail
export LC_ALL=C
# N1: root gate FIRST — before any mktemp/touch probes (§1/§4) or user `bash -c`
# (§5, deferred). Running as root would otherwise execute project code as root.
test "$(id -u)" -ne 0 || { echo 'FAIL: running as root' >&2; exit 1; }
# Warning counter for the warning-aware footer (§99): every WARNING site below
# increments box_warnings so the final banner reports tolerated warnings
# instead of an unconditional ALL PASSED.
box_warnings=0
# Fail closed on attacker-set or typo'd harness env: BOX_RUNTIME must be
# runc|runsc when set (unset = manual run, grades like runsc with WARNING);
# BOX_ALLOW_PROXY must be 0|1 when set.
case "${BOX_RUNTIME:-}" in ''|runc|runsc) : ;; *) echo 'FAIL: BOX_RUNTIME must be runc|runsc' >&2; exit 1 ;; esac
case "${BOX_ALLOW_PROXY:-0}" in 0|1) : ;; *) echo 'FAIL: BOX_ALLOW_PROXY must be 0|1' >&2; exit 1 ;; esac
if [[ -z "${BOX_RUNTIME:-}" ]]; then echo 'WARNING: BOX_RUNTIME unset (manual run; grading CapBnd like runsc)'; box_warnings=$((box_warnings+1)); fi
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo 'Usage: box-o --shell -s -- <existing-project-file> [test-command] < verify-codex.sh'
  exit 0
fi
[[ "$PWD" == /workspace ]] || { echo 'Run through box-o --shell.' >&2; exit 1; }
[[ -n "${1:-}" && -f "$1" ]] || { echo 'Usage: pass an existing project file, then optionally a test command.' >&2; exit 1; }
# Single EXIT cleanup for the whole harness: every section below shares these
# temp vars and only assigns them, never re-arms the trap, so the chain
# cannot rot when a section is added or renamed.
write_test=""
scratch=""
build_scratch=""
_muse_probe=""
_codex_probe=""
box_cleanup() { rm -f -- "${write_test:-}" "${_muse_probe:-}" "${_codex_probe:-}"; rm -rf -- "${scratch:-}" "${build_scratch:-}"; }
trap box_cleanup EXIT

echo "=== 1. Workspace Read/Write Verifications ==="
printf 'Workspace file read: '
# Empty project files pass `head -c 1` vacuously (exit 0, no output): require
# non-empty so the read probe is meaningful.
# No `--` separator: POSIX test(1) has no `--` (it errors `unexpected
# operator`, exit 2). The operand position after -s is unambiguous, so a
# leading-dash filename cannot be misparsed as an option here.
test -s "$1" || { echo 'FAIL: project file is empty or missing' >&2; exit 1; }
head -c 1 -- "$1" >/dev/null || { echo 'FAIL: cannot read project file' >&2; exit 1; }
echo PASS

# Secure write-test file (mktemp is atomic; no rm+recreate TOCTOU — the mktemp
# file itself is the write target). Removed by the single EXIT cleanup in
# 00-header (shared vars, never re-armed here).
write_test=$(mktemp /workspace/.box-write-test.XXXXXX) || { echo 'FAIL: cannot create workspace write-test file' >&2; exit 1; }
printf 'created\n' > "$write_test"
printf 'edited\n' >> "$write_test"
grep -q -- edited "$write_test"
rm -f -- "$write_test"
echo 'Workspace create/edit/delete: PASS'

echo "=== 2. Discovery & Toolchain Checks ==="
# Discovery outputs are asserted by exit code with explicit FAIL (never bare:
# `set -e` alone aborts with no FAIL line). Non-git projects fail closed here
# by design (git ls-files requires a repo) — run the harness from a git checkout.
command -v git >/dev/null || { echo 'FAIL: git not on PATH' >&2; exit 1; }
command -v rg >/dev/null || { echo 'FAIL: rg not on PATH' >&2; exit 1; }
command -v fd >/dev/null || { echo 'FAIL: fd not on PATH' >&2; exit 1; }
command -v find >/dev/null || { echo 'FAIL: find not on PATH' >&2; exit 1; }
rg --files . >/dev/null || { echo 'FAIL: rg --files failed' >&2; exit 1; }
find . -maxdepth 3 -type f >/dev/null || { echo 'FAIL: find failed' >&2; exit 1; }
fd --version >/dev/null || { echo 'FAIL: fd --version failed' >&2; exit 1; }
git ls-files >/dev/null || { echo 'FAIL: git ls-files failed (run from a git checkout)' >&2; exit 1; }
if git grep -q -I -e .; then
  echo 'git grep: matched tracked text'
else
  status=$?
  if [[ "$status" -eq 1 ]]; then
    echo 'git grep: ran successfully, no tracked text matched'
  else
    echo "FAIL: git grep failed (status $status)" >&2; exit "$status"
  fi
fi
git status --short || { echo 'FAIL: git status failed' >&2; exit 1; }
git diff --stat || { echo 'FAIL: git diff failed' >&2; exit 1; }
git log -1 --oneline || { echo 'FAIL: git log failed' >&2; exit 1; }
echo 'Discovery & Git tools: PASS'

# Ephemeral build scratch on container /tmp (tmpfs under --read-only):
# never on /workspace, so host binds and git status stay clean.
# Removed by the single EXIT cleanup in 00-header (never re-armed here).
build_scratch=$(mktemp -d /tmp/box-build.XXXXXX) || { echo 'FAIL: cannot create build scratch dir' >&2; exit 1; }
[[ -n "${build_scratch:-}" ]] || { echo 'FAIL: empty scratch dir' >&2; exit 1; }
printf '#include <stdio.h>\nint main(void) { puts("C build/run: PASS"); return 0; }\n' > "$build_scratch/main.c" || { echo 'FAIL: cannot write build scratch' >&2; exit 1; }
cc -Wall -Wextra -Werror "$build_scratch/main.c" -o "$build_scratch/check" || { echo 'FAIL: cc build failed' >&2; exit 1; }
"$build_scratch/check" || { echo 'FAIL: built check binary failed' >&2; exit 1; }

if [[ -n "${2:-}" ]]; then
  echo 'Project build/test command: DEFERRED (runs after §5 containment gates)'
else
  echo 'Project build/test: SKIPPED (pass command as argument 2)'
fi

echo '=== 3. Codex transport (separate from authentication) ==='
for _host in auth.openai.com api.openai.com chatgpt.com; do
  timeout 15 getent hosts "$_host" >/dev/null || { echo "FAIL: Codex DNS transport for $_host" >&2; exit 1; }
done
echo '=== 4. Codex native startup and policy ==='
codex_version_out=$(timeout 30 codex --version 2>&1) || { echo 'FAIL: codex --version failed' >&2; exit 1; }
[[ "$codex_version_out" == 'codex-cli 0.160.0' ]] || { echo 'FAIL: exact Codex binary version mismatch' >&2; exit 1; }
[[ "$CODEX_HOME" == /home/box/.codex && -w "$CODEX_HOME" && -w /persist/state/codex ]] || { echo 'FAIL: Codex state paths' >&2; exit 1; }
[[ "$(stat -c '%u:%a' /etc/codex/requirements.toml)" == 0:644 ]] || { echo 'FAIL: Codex managed policy owner/mode' >&2; exit 1; }
_codex_expected=\{\"allowed_approval_policies\":\[\"on-request\"\]\,\"allowed_approvals_reviewers\":\[\"user\"\]\,\"default_permissions\":\":danger-full-access\"\,\"cli_auth_credentials_store\":\"file\"\,\"check_for_update_on_startup\":false\,\"sqlite_home\":\"/persist/state/codex\"\,\"allowed_permission_profiles\":\{\":danger-full-access\":true\}\}
_codex_seed=\{\"model\":\"gpt-6.1-sol\"\,\"model_context_window\":1050000\,\"model_auto_compact_token_limit\":700000\,\"model_auto_compact_token_limit_scope\":\"total\"\,\"tool_output_token_limit\":8000\,\"project_doc_max_bytes\":65536\,\"model_reasoning_effort\":\"low\"\,\"plan_mode_reasoning_effort\":\"high\"\,\"model_reasoning_summary\":\"concise\"\,\"personality\":\"pragmatic\"\,\"default_permissions\":\":danger-full-access\"\,\"approval_policy\":\"on-request\"\,\"approvals_reviewer\":\"user\"\,\"cli_auth_credentials_store\":\"file\"\,\"check_for_update_on_startup\":false\,\"sqlite_home\":\"/persist/state/codex\"\,\"web_search\":\"live\"\,\"agents\":\{\"enabled\":true\,\"max_concurrent_threads_per_session\":6\,\"default_subagent_model\":\"gpt-6-luna\"\,\"default_subagent_reasoning_effort\":\"max\"\}\,\"skills\":\{\"max_context_tokens\":8000\}\,\"tools\":\{\"web_search\":\{\"context_size\":\"medium\"\}\}\,\"tui\":\{\"status_line\":\[\"model\"\,\"reasoning\"\,\"used-tokens\"\,\"total-input-tokens\"\,\"total-output-tokens\"\,\"five-hour-limit\"\,\"weekly-limit\"\,\"context-remaining\"\,\"task-progress\"\,\"fast-mode\"\]\}\}
python3 - "$_codex_expected" <<'PYPOLICY'
import json, sys, tomllib
with open("/etc/codex/requirements.toml", "rb") as f:
    actual = tomllib.load(f)
if actual != json.loads(sys.argv[1]):
    sys.exit("FAIL: Codex managed policy differs")
with open("/etc/codex/config.toml", "rb") as f:
    tomllib.load(f)
PYPOLICY
python3 - --policy-json "$_codex_expected" <<'PYNATIVE'
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

PYNATIVE
if [[ -e "$CODEX_HOME/auth.json" || -L "$CODEX_HOME/auth.json" ]]; then
  [[ ! -L "$CODEX_HOME/auth.json" && -f "$CODEX_HOME/auth.json" && "$(stat -c %u "$CODEX_HOME/auth.json")" == "$(id -u)" && "$(stat -c %a "$CODEX_HOME/auth.json")" == 600 && -w "$CODEX_HOME/auth.json" ]] || { echo 'FAIL: unsafe native Codex auth cache' >&2; exit 1; }
fi
timeout 30 codex login status >/dev/null 2>&1 || { echo 'FAIL: Codex authentication unavailable (native policy tested separately)' >&2; exit 1; }
echo 'PASS: Codex authentication status (values withheld)'
echo "=== 5. Hardening & Host Containment Assertions ==="
export LC_ALL=C
# Defense-in-depth: the primary root gate lives in 00-header (N1, before any
# user code); repeat here so a hand-assembled harness cannot skip it.
test "$(id -u)" -ne 0 || { echo 'FAIL: running as root' >&2; exit 1; }
command -v capsh >/dev/null || { echo 'FAIL: capsh not on PATH' >&2; exit 1; }
id || { echo 'FAIL: id failed' >&2; exit 1; }
uname -r || { echo 'FAIL: uname failed' >&2; exit 1; }
grep -E -- '^(Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs):' /proc/self/status || { echo 'FAIL: cannot read capability status' >&2; exit 1; }
# Parser: /proc/self/status via awk '$2 !~ /^0+$/'. CapInh/Prm/Eff/Amb must be
# all-zero (FAIL otherwise). CapBnd is graded by the launcher-provided
# BOX_RUNTIME (see §7): FAIL on runc (the kernel reports bounding caps
# honestly there), WARNING on runsc (runsc/kernels may retain bounding bits
# while still dropping effective caps, so a nonzero CapBnd alone does not
# prove containment failure). Unset (manual runs, old images) grades like
# runsc. Record kernel (uname -r above) and runsc version from the host when
# triaging.
awk '
  /^Cap(Inh|Prm|Eff|Amb):/ {
    if ($2 !~ /^0+$/) { printf "FAIL: nonzero %s\n", $1 > "/dev/stderr"; exit 1 }
  }
  /^NoNewPrivs:/ {
    nnp_seen++
    if ($2 != 1) { printf "FAIL: NoNewPrivs=%s\n", $2 > "/dev/stderr"; exit 1 }
  }
  END {
    if (nnp_seen == 0) { printf "FAIL: NoNewPrivs field absent\n" > "/dev/stderr"; exit 1 }
  }
' /proc/self/status || { echo 'FAIL: capability/NoNewPrivs assertion failed' >&2; exit 1; }
# Single-grep (no pipe): avoids pipefail/SIGPIPE skew from grep|grep.
if ! grep -qE -- '^CapBnd:[[:space:]]*0+[[:space:]]*$' /proc/self/status; then
  if [[ "${BOX_RUNTIME:-runsc}" == runc ]]; then
    echo 'FAIL: nonzero CapBnd under runc (bounding caps must be empty here)' >&2
    exit 1
  fi
  echo 'WARNING: nonzero CapBnd (tolerance-graded under runsc; check CapEff==0 + NoNewPrivs==1 above)'
  box_warnings=$((box_warnings+1))
fi
# Current caps must be empty (always FAIL); the Bounding set is graded like
# CapBnd above (FAIL on runc, WARNING on runsc/unset) so the runsc tolerance
# can actually tolerate. NOTE: `Current:` has a colon while `Bounding set`
# has none — the patterns must match both spellings.
# Pipefail-safe: capture capsh output first so a SIGPIPE from
# `capsh | grep` cannot fail open; grep reads a herestring (no pipe).
capsh_out=$(capsh --print 2>/dev/null) || { echo 'FAIL: capsh unavailable' >&2; exit 1; }
if grep -E -- '^Current: .*cap_[a-z_]+' <<<"$capsh_out" >/dev/null; then
  echo 'FAIL: capsh reports effective capabilities' >&2
  exit 1
fi
if grep -E -- '^Bounding set .*cap_[a-z_]+' <<<"$capsh_out" >/dev/null; then
  if [[ "${BOX_RUNTIME:-runsc}" == runc ]]; then
    echo 'FAIL: capsh reports bounding capabilities under runc' >&2
    exit 1
  fi
  echo 'WARNING: capsh reports bounding capabilities (tolerance-graded under runsc; check Current above)'
  box_warnings=$((box_warnings+1))
fi
echo 'Capability stripping (CapEff==0, NoNewPrivs==1): PASS'
# Prove /etc/passwd is the container file, not the host file.
grep -q -- '^box:' /etc/passwd || { echo 'FAIL: container /etc/passwd lacks box user' >&2; exit 1; }
echo 'Container /etc/passwd isolation: PASS'

test ! -S /var/run/docker.sock || { echo 'FAIL: docker.sock mounted' >&2; exit 1; }
test ! -S /run/docker.sock || { echo 'FAIL: docker.sock mounted' >&2; exit 1; }
test ! -S /run/podman/podman.sock || { echo 'FAIL: podman socket mounted' >&2; exit 1; }
command -v timeout >/dev/null || { echo 'FAIL: timeout not on PATH (daemon probes must be bounded)' >&2; exit 1; }
if command -v docker >/dev/null; then
  if timeout 10 docker ps >/dev/null 2>&1; then echo 'FAIL: Docker daemon reachable' >&2; exit 1; fi
fi
if command -v podman >/dev/null; then
  if timeout 10 podman ps >/dev/null 2>&1; then echo 'FAIL: Podman daemon reachable' >&2; exit 1; fi
fi
# Daemon reachability must not be reintroduced via env: these must be unset
# inside the container (launcher strips them on the host and pins --host).
for leaked in DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH DOCKER_CONFIG; do
  [[ -z "${!leaked:-}" ]] || { echo "FAIL: $leaked is set in container" >&2; exit 1; }
done
# Proxy envs would let egress or registry auth leak around the isolated
# docker-cli config: FAIL by default. If your toolchain legitimately needs a
# proxy, export BOX_ALLOW_PROXY=1 in the container before running this
# harness to downgrade to WARNING (then allowlist the proxy explicitly).
# Messages print the variable name only — never the value (it may embed
# proxy credentials as user:pass@host).
for proxy_var in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy; do
  if [[ -n "${!proxy_var:-}" ]]; then
    if [[ "${BOX_ALLOW_PROXY:-0}" == 1 ]]; then
      echo "WARNING: $proxy_var is set in container"
      box_warnings=$((box_warnings+1))
    else
      echo "FAIL: $proxy_var is set in container (export BOX_ALLOW_PROXY=1 to allowlist)" >&2
      exit 1
    fi
  fi
done
# Dangling-symlink-safe absence checks: a symlink pointing at a host
# credential path must FAIL even when its target is unreadable (`test ! -e`
# alone is true for a dangling link, so require both ! -e and ! -L).
# Native writable config/state parents are asserted separately in §4.
for _cred in /home/box/.ssh /home/box/.gnupg /home/box/.aws /home/box/.docker /home/box/.git-credentials /home/box/.netrc /home/box/.config/gcloud; do
  if [[ -e "$_cred" || -L "$_cred" ]]; then echo "FAIL: host credential path present: $_cred" >&2; exit 1; fi
done
unset _cred
echo 'Credential-path absence: PASS'
[[ "$(stat -c %u /persist)" == "$(id -u)" && "$(stat -c %a /persist)" == 700 ]] \
  || { echo 'FAIL: project state volume must be user-owned mode 700' >&2; exit 1; }
echo 'Project state volume ownership/mode: PASS'

# Deferred project command: runs here, after all containment gates above.
# Plain `bash -c` (never `-l`: login profiles would source untrusted project
# dotfiles before the test command runs).
if [[ -n "${2:-}" ]]; then
  bash -c "$2" || { echo 'FAIL: project build/test command failed' >&2; exit 1; }
  echo 'Project build/test command: PASS'
fi
echo '=== 6. Codex outer boundary ==='
echo 'Codex uses dangerFullAccess inside the separately graded Docker/runtime boundary.'
echo "================================================================="
if ((box_warnings > 0)); then
  echo "ALL CONTAINER & CODEX READINESS ASSERTIONS PASSED WITH $box_warnings WARNING(S) (see WARNING lines above; tolerated: CapBnd/Bounding set under runsc, unshare success, BOX_ALLOW_PROXY=1, unset BOX_RUNTIME)"
else
  echo "ALL CONTAINER & CODEX READINESS ASSERTIONS PASSED"
fi
echo "================================================================="
