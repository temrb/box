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

