echo "================================================================="
if ((box_warnings > 0)); then
  echo "ALL CONTAINER & OPENCODE READINESS ASSERTIONS PASSED WITH $box_warnings WARNING(S) (see WARNING lines above; tolerated: CapBnd/Bounding set under runsc, unshare success, BOX_ALLOW_PROXY=1, effective-config/model omission, unset BOX_RUNTIME)"
else
  echo "ALL CONTAINER & OPENCODE READINESS ASSERTIONS PASSED"
fi
echo "================================================================="
