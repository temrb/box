echo "================================================================="
if ((box_warnings > 0)); then
  echo "ALL CONTAINER & @@DISPLAY@@ READINESS ASSERTIONS PASSED WITH $box_warnings WARNING(S) (see WARNING lines above; tolerated: CapBnd/Bounding set under runsc, unshare success, BOX_ALLOW_PROXY=1, unset BOX_RUNTIME)"
else
  echo "ALL CONTAINER & @@DISPLAY@@ READINESS ASSERTIONS PASSED"
fi
echo "================================================================="
