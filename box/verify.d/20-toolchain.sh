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

# Shared verify helpers (defined once here, available to §§3-4/6 below).
# Outputs stay self-contained: no sourcing, just concatenation order.
# Egress proof: any HTTP response code — including 4xx — proves TCP+TLS.
# FAIL on transport failure (rc != 0) or empty/000 code. Optional $3 hint
# appends context to the FAIL line only.
box_verify_egress() {
  local url=${1:-} label=${2:-} hint=${3:-} rc=0 code
  [[ -n "$url" && -n "$label" ]] || { echo 'FAIL: internal egress arguments' >&2; exit 1; }
  command -v curl >/dev/null || { echo 'FAIL: curl not on PATH' >&2; exit 1; }
  code=$(curl --silent --location --max-time 15 --output /dev/null --write-out '%{http_code}' "$url" 2>/dev/null) || rc=$?
  [[ "$rc" -eq 0 && -n "${code:-}" && "$code" != "000" ]] \
    || { echo "FAIL: outbound HTTPS to $label unreachable (curl rc=$rc http=${code:-none}$hint)" >&2; exit 1; }
  echo "Outbound HTTPS to $label (HTTP $code): PASS"
}
# Auth-cache hygiene: existing caches must be user-owned regular files with
# mode 600 and writable (refresh). Missing caches are fine (keyless login).
box_verify_cache() {
  local cache=${1:-} label=${2:-unsafe native authentication cache owner/mode/writability}
  [[ -n "$cache" ]] || { echo 'FAIL: internal cache arguments' >&2; exit 1; }
  if [[ -e "$cache" || -L "$cache" ]]; then
    [[ ! -L "$cache" && -f "$cache" && "$(stat -c %u "$cache")" == "$(id -u)" && "$(stat -c %a "$cache")" == 600 && -w "$cache" ]] \
      || { echo "FAIL: $label" >&2; exit 1; }
  fi
}
# Outer-runtime unshare probe: unprivileged `unshare -Ur` needs no
# capabilities, so an observed block is gVisor seccomp/runsc behavior, not
# `--cap-drop=ALL`+`no-new-privileges` alone. Record evidence (exit codes).
box_verify_unshare() {
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
}

