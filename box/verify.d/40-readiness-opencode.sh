echo "=== 4. OpenCode Operational Readiness ==="
command -v opencode >/dev/null || { echo 'FAIL: opencode binary not on PATH' >&2; exit 1; }
printf 'OpenCode binary version: '
opencode_version_out=$(opencode --version 2>&1) || { echo 'FAIL: opencode --version failed' >&2; exit 1; }
printf '%s\n' "$opencode_version_out"
printf '%s' "$opencode_version_out" | grep -Fq '1.18.29' \
  || { echo 'FAIL: opencode binary version mismatch (want 1.18.29)' >&2; exit 1; }
test "${OPENCODE_DISABLE_AUTOUPDATE:-0}" = "1" || { echo 'FAIL: OPENCODE_DISABLE_AUTOUPDATE is not set to 1' >&2; exit 1; }

# Provider auth: native opencode auth only (pure /connect — the launcher
# forwards zero manual keys). `/connect` / `opencode auth login` in the TUI
# persists auth.json under XDG_DATA_HOME on the per-project volume; the
# XDG-app-suffixed layout is accepted too since upstream may resolve either
# one.
if [[ -s /persist/data/opencode/auth.json || -s /persist/data/opencode/opencode/auth.json ]]; then
  echo 'Native opencode auth (auth.json via /connect): PASS'
else
  echo 'FAIL: no provider auth: connect natively via /connect (auth.json)' >&2
  exit 1
fi

# Assert configuration file validity with has() pre-asserts on every path
# (a missing key must fail closed, not compare null).
test -f /home/box/.config/opencode/opencode.json || { echo 'FAIL: opencode.json missing' >&2; exit 1; }
jq -e '.permission.read["*.env"] == "ask"' /home/box/.config/opencode/opencode.json >/dev/null \
  || { echo 'FAIL: opencode.json permission.read["*.env"] != ask' >&2; exit 1; }
jq -e '.permission.edit["*.env"] == "ask"' /home/box/.config/opencode/opencode.json >/dev/null \
  || { echo 'FAIL: opencode.json permission.edit["*.env"] != ask' >&2; exit 1; }
jq -e '.permission.read["*.env.*"] == "ask"' /home/box/.config/opencode/opencode.json >/dev/null \
  || { echo 'FAIL: opencode.json permission.read["*.env.*"] != ask' >&2; exit 1; }
jq -e '.permission.edit["*.env.*"] == "ask"' /home/box/.config/opencode/opencode.json >/dev/null \
  || { echo 'FAIL: opencode.json permission.edit["*.env.*"] != ask' >&2; exit 1; }
jq -e 'has("permission") and (.permission.read|has("*.env.example")) and .permission.read["*.env.example"] == "allow"' /home/box/.config/opencode/opencode.json >/dev/null \
  || { echo 'FAIL: opencode.json permission.read["*.env.example"] != allow' >&2; exit 1; }
jq -e 'has("permission") and (.permission.edit|has("*.env.example")) and .permission.edit["*.env.example"] == "allow"' /home/box/.config/opencode/opencode.json >/dev/null \
  || { echo 'FAIL: opencode.json permission.edit["*.env.example"] != allow' >&2; exit 1; }
jq -e 'has("permission") and (.permission|has("external_directory")) and .permission.external_directory == "ask"' /home/box/.config/opencode/opencode.json >/dev/null \
  || { echo 'FAIL: opencode.json permission.external_directory != ask' >&2; exit 1; }
echo 'OpenCode opencode.json validation: PASS'

# Regression: config dir must be writable tmpfs for server/auth sibling
# state while the pinned file stays readonly (see docs/operations.md §9).
# Without the tmpfs, `opencode` fails with `Unexpected server error`.
# Removed by the single EXIT cleanup in 00-header, so an early abort cannot
# leak the probe into the config dir.
_opencode_probe=$(mktemp /home/box/.config/opencode/.box-write-test.XXXXXX) || { echo 'FAIL: cannot write to /home/box/.config/opencode (needs writable tmpfs)' >&2; exit 1; }
rm -f -- "$_opencode_probe"
unset _opencode_probe
if touch /home/box/.config/opencode/opencode.json 2>/dev/null; then echo 'FAIL: opencode.json is writable (must stay readonly)' >&2; exit 1; fi
echo 'OpenCode config-dir writability (tmpfs) + opencode.json readonly: PASS'

# Assert the effective merged config agrees with the shipped permission pins:
# a user-global or default merge must not silently relax the ask policy.
# `opencode debug config` prints the merged JSON; if the subcommand is
# unavailable or fails offline, warn instead of failing. There is no model
# or provider pin to check (pure /connect: model/auth are user-chosen).
if effective_json=$(opencode debug config 2>/dev/null); then
  printf '%s' "$effective_json" | jq -e '.permission.read["*.env"] == "ask"' >/dev/null \
    || { echo 'FAIL: effective opencode debug config permission.read["*.env"] != ask' >&2; exit 1; }
  printf '%s' "$effective_json" | jq -e '.permission.edit["*.env"] == "ask"' >/dev/null \
    || { echo 'FAIL: effective opencode debug config permission.edit["*.env"] != ask' >&2; exit 1; }
  printf '%s' "$effective_json" | jq -e '.permission.read["*.env.*"] == "ask"' >/dev/null \
    || { echo 'FAIL: effective opencode debug config permission.read["*.env.*"] != ask' >&2; exit 1; }
  printf '%s' "$effective_json" | jq -e '.permission.edit["*.env.*"] == "ask"' >/dev/null \
    || { echo 'FAIL: effective opencode debug config permission.edit["*.env.*"] != ask' >&2; exit 1; }
  printf '%s' "$effective_json" | jq -e '.permission.external_directory == "ask"' >/dev/null \
    || { echo 'FAIL: effective opencode debug config permission.external_directory != ask' >&2; exit 1; }
  echo 'OpenCode effective-config (permissions): PASS'
else
  # shellcheck disable=SC2016 # backticks are an intentional literal in this message.
  echo 'WARNING: `opencode debug config` unavailable; effective-config check skipped'
  box_warnings=$((box_warnings+1))
fi

