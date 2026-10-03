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

