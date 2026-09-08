echo "=== 6. Outer-Runtime Probe (no inner bwrap in OpenCode) ==="
# OpenCode has no inner bubblewrap sandbox, so there is no bwrap probe and no
# --disable-sandbox-style bypass flag to verify here. The unshare probe below
# records outer Docker/gVisor behavior only: unprivileged `unshare -Ur` needs
# no capabilities, so an observed block is gVisor seccomp/runsc behavior, not
# `--cap-drop=ALL`+`no-new-privileges` alone. Treat outer Docker/gVisor as the
# sole containment layer.
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

