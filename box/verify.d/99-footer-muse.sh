echo "================================================================="
if ((box_warnings > 0)); then
  echo "ALL CONTAINER & MUSE CODE READINESS ASSERTIONS PASSED WITH $box_warnings WARNING(S) (see WARNING lines above; tolerated: CapBnd under runsc, bwrap/unshare success, BOX_ALLOW_PROXY=1, ~/.docker presence, unset BOX_RUNTIME)"
else
  echo "ALL CONTAINER & MUSE CODE READINESS ASSERTIONS PASSED"
fi
echo "================================================================="
