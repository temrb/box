#!/usr/bin/env bash
# verify-muse.sh — in-container readiness harness for box-m.
# GENERATED NOTE: do not edit by hand — edit verify.d/ partials and run
# gen-verify.sh. This file and verify-opencode.sh stay self-contained
# (delivered via stdin under --shell, cannot source a shared file). Shared
# §§1-2/5 (workspace, toolchain, containment) live once in verify.d/
# (10-workspace.sh, 20-toolchain.sh, 50-containment.sh); §4 is
# tool-specific and §6 documents the differing inner-sandbox probes.
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
  echo 'Usage: box-m --shell -s -- <existing-project-file> [test-command] < verify-muse.sh'
  exit 0
fi
[[ "$PWD" == /workspace ]] || { echo 'Run through box-m --shell.' >&2; exit 1; }
[[ -n "${1:-}" && -f "$1" ]] || { echo 'Usage: pass an existing project file, then optionally a test command.' >&2; exit 1; }
# Single EXIT cleanup for the whole harness: every section below shares these
# temp vars and only assigns them, never re-arms the trap, so the chain
# cannot rot when a section is added or renamed.
write_test=""
scratch=""
build_scratch=""
_muse_probe=""
_opencode_probe=""
box_cleanup() { rm -f -- "${write_test:-}" "${_muse_probe:-}" "${_opencode_probe:-}"; rm -rf -- "${scratch:-}" "${build_scratch:-}"; }
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

echo "=== 3. Network Egress Check ==="
command -v curl >/dev/null || { echo 'FAIL: curl not on PATH' >&2; exit 1; }
# Provider API root (matches settings.json api.base_url): any HTTP response
# code — including 4xx without credentials — proves TCP+TLS egress. Record
# both the curl exit and the HTTP code: FAIL on transport failure (rc != 0)
# or empty/000 code.
provider_code=$(curl --silent --show-error --location --max-time 15 --output /dev/null --write-out '%{http_code}' https://api.meta.ai/v1 2>/dev/null); provider_rc=$?
[[ "$provider_rc" -eq 0 && -n "${provider_code:-}" && "$provider_code" != "000" ]] \
  || { echo "FAIL: outbound HTTPS to api.meta.ai/v1 unreachable (curl rc=$provider_rc http=${provider_code:-none})" >&2; exit 1; }
echo "Outbound HTTPS to api.meta.ai/v1 (HTTP $provider_code): PASS"

# Device-flow endpoint (muse login): same transport-failure rule. Regression
# for runsc + Docker embedded DNS (127.0.0.11) failures that present as
# `login failed: device flow transport error` while api.meta.ai/v1 may
# already be covered above.
auth_code=$(curl --silent --show-error --location --max-time 15 --output /dev/null --write-out '%{http_code}' https://auth.meta.com/ 2>/dev/null); auth_rc=$?
[[ "$auth_rc" -eq 0 && -n "${auth_code:-}" && "$auth_code" != "000" ]] \
  || { echo "FAIL: outbound HTTPS to auth.meta.com unreachable (curl rc=$auth_rc http=${auth_code:-none}; muse login device flow will fail)" >&2; exit 1; }
echo "Outbound HTTPS to auth.meta.com (HTTP $auth_code): PASS"
echo "=== 4. Muse Code Operational Readiness ==="
command -v muse >/dev/null || { echo 'FAIL: muse binary not on PATH' >&2; exit 1; }
printf 'Muse binary version: '
muse_version_out=$(muse --version 2>&1) || { echo 'FAIL: muse --version failed' >&2; exit 1; }
printf '%s\n' "$muse_version_out"
printf '%s' "$muse_version_out" | grep -Fq '1.0.3-R2198.1' \
  || { echo 'FAIL: muse binary version mismatch (want 1.0.3-R2198.1)' >&2; exit 1; }
test "${MUSE_NO_AUTO_UPDATE:-0}" = "1" || { echo 'FAIL: MUSE_NO_AUTO_UPDATE is not set to 1' >&2; exit 1; }

# Muse auth: provider key OR device-login auth, without printing values.
# Key path: MUSE_CODE_API_KEY in the environment (forwarded by name).
# Device path (`muse login`): auth.json persists non-empty in the global
# persistent config dir. One of the two paths must hold.
if [[ -n "${MUSE_CODE_API_KEY:-}" ]]; then
  echo 'MUSE_CODE_API_KEY environment injection: PASS (value withheld)'
elif [[ -s /home/box/.config/muse/auth.json ]]; then
  echo 'Native muse auth (auth.json via device login): PASS'
else
  echo 'FAIL: no muse auth: set MUSE_CODE_API_KEY or log in via device flow (auth.json)' >&2
  exit 1
fi

# Assert configuration file validity (model, approvals, telemetry, endpoint).
# Every jq path has a has() pre-assert so a missing key fails closed instead
# of comparing null (jq -e returns 0 on null without it).
test -f /home/box/.config/muse/settings.json || { echo 'FAIL: settings.json missing' >&2; exit 1; }
jq -e 'has("schema_version") and .schema_version == 1' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json schema_version != 1' >&2; exit 1; }
jq -e 'has("api") and (.api|has("base_url")) and .api.base_url == "https://api.meta.ai/v1"' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: invalid API base URL' >&2; exit 1; }
jq -e 'has("model") and (.model|type == "string") and (.model|length > 0)' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json model missing or empty (user-mutable; must be a non-empty string)' >&2; exit 1; }
jq -e 'has("reasoning_effort") and .reasoning_effort == "max"' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json reasoning_effort != max' >&2; exit 1; }
jq -e 'has("approval_mode") and .approval_mode == "on-request"' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json approval_mode != on-request' >&2; exit 1; }
jq -e 'has("approval_judge") and .approval_judge == true' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json approval_judge != true' >&2; exit 1; }
jq -e 'has("telemetry") and (.telemetry|has("enabled")) and .telemetry.enabled == false' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json telemetry.enabled != false' >&2; exit 1; }
echo 'Muse Code settings.json validation: PASS'

# Regression: config dir must be a writable persistent global bind
# (~/.config/box-m/muse-config/ holding settings.json, auth.json,
# .trust.json; see docs/operations.md §9). Without the writable parent,
# `muse` fails with `failed to save trust decision: ... Read-only file system`;
# without persistence, `muse login` succeeds but the next run prompts again.
# Removed by the single EXIT cleanup in 00-header, so an early abort cannot
# leak the probe into the persistent bind.
_muse_probe=$(mktemp /home/box/.config/muse/.box-write-test.XXXXXX) || { echo 'FAIL: cannot write to /home/box/.config/muse (needs writable persistent bind)' >&2; exit 1; }
rm -f -- "$_muse_probe"
unset _muse_probe
touch /home/box/.config/muse/settings.json 2>/dev/null || { echo 'FAIL: settings.json is not writable (in-container model changes must persist)' >&2; exit 1; }
echo 'Muse Code config-dir writability (persistent bind) + settings.json writable: PASS'

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
# Effective caps must be empty: fail if capsh reports any named capability
# in the Current or Bounding set. NOTE: `Current:` has a colon while
# `Bounding set` has none — the alternation must match both spellings.
# Pipefail-safe: capture capsh output first so a SIGPIPE from
# `capsh | grep` cannot fail open; grep reads a herestring (no pipe).
capsh_out=$(capsh --print 2>/dev/null) || { echo 'FAIL: capsh unavailable' >&2; exit 1; }
if grep -E -- '^(Current:|Bounding set) .*cap_[a-z_]+' <<<"$capsh_out" >/dev/null; then
  echo 'FAIL: capsh reports effective/bounding capabilities' >&2
  exit 1
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
# Note: /home/box/.config/muse (muse persistent bind) and
# /home/box/.config/opencode (opencode tmpfs) intentionally not listed:
# they are the legitimate writable config parents asserted in §4.
for _cred in /home/box/.ssh /home/box/.gnupg /home/box/.aws /home/box/.docker /home/box/.git-credentials /home/box/.netrc /home/box/.config/gcloud; do
  if [[ -e "$_cred" || -L "$_cred" ]]; then echo "FAIL: host credential path present: $_cred" >&2; exit 1; fi
done
unset _cred
echo 'Credential-path absence: PASS'

# Deferred project command: runs here, after all containment gates above.
# Plain `bash -c` (never `-l`: login profiles would source untrusted project
# dotfiles before the test command runs).
if [[ -n "${2:-}" ]]; then
  bash -c "$2" || { echo 'FAIL: project build/test command failed' >&2; exit 1; }
  echo 'Project build/test command: PASS'
fi

echo "=== 6. Inner Sandbox Probe Verification ==="
# Do not assert causation: unprivileged `unshare -Ur` needs no capabilities, so
# the observed block is gVisor seccomp/runsc behavior, not
# `--cap-drop=ALL`+`no-new-privileges` alone. Record probe evidence (exit
# codes) and treat outer Docker/gVisor as the sole containment layer.
if command -v bwrap >/dev/null; then
  set +e
  bwrap --ro-bind / / true >/dev/null 2>&1
  bwrap_status=$?
  set -e
  if ((bwrap_status == 0)); then
    echo 'WARNING: inner bwrap unexpectedly succeeded (exit 0)'
    box_warnings=$((box_warnings+1))
  else
    echo "Inner bwrap probe blocked by outer runsc/seccomp (exit $bwrap_status, expected nonzero): PASS"
  fi
else
  echo 'Inner bwrap probe: SKIPPED (bwrap not installed)'
fi
if command -v unshare >/dev/null; then
  set +e
  unshare -Ur true >/dev/null 2>&1
  unshare_status=$?
  set -e
  if ((unshare_status == 0)); then
    echo 'WARNING: inner unshare -Ur unexpectedly succeeded (exit 0)'
    box_warnings=$((box_warnings+1))
  else
    echo "Inner unshare -Ur probe blocked by outer runsc/seccomp (exit $unshare_status, expected nonzero): PASS"
  fi
else
  echo 'Inner unshare probe: SKIPPED (unshare not installed)'
fi

echo "================================================================="
if ((box_warnings > 0)); then
  echo "ALL CONTAINER & MUSE CODE READINESS ASSERTIONS PASSED WITH $box_warnings WARNING(S) (see WARNING lines above; tolerated: CapBnd under runsc, bwrap/unshare success, BOX_ALLOW_PROXY=1, ~/.docker presence, unset BOX_RUNTIME)"
else
  echo "ALL CONTAINER & MUSE CODE READINESS ASSERTIONS PASSED"
fi
echo "================================================================="
