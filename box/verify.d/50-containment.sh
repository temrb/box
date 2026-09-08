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

