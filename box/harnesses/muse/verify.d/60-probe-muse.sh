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
box_verify_unshare

