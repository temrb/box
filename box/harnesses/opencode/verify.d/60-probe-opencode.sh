echo "=== 6. Outer-Runtime Probe (no inner bwrap in OpenCode) ==="
# OpenCode has no inner bubblewrap sandbox, so there is no bwrap probe and no
# --disable-sandbox-style bypass flag to verify here. The unshare probe below
# records outer Docker/gVisor behavior only: unprivileged `unshare -Ur` needs
# no capabilities, so an observed block is gVisor seccomp/runsc behavior, not
# `--cap-drop=ALL`+`no-new-privileges` alone. Treat outer Docker/gVisor as the
# sole containment layer.
box_verify_unshare

