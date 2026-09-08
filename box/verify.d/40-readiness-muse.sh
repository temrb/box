echo "=== 4. Muse Code Operational Readiness ==="
command -v muse >/dev/null || { echo 'FAIL: muse binary not on PATH' >&2; exit 1; }
printf 'Muse binary version: '
muse_version_out=$(muse --version 2>&1) || { echo 'FAIL: muse --version failed' >&2; exit 1; }
printf '%s\n' "$muse_version_out"
printf '%s' "$muse_version_out" | grep -Fq '1.0.3-R2198.1' \
  || { echo 'FAIL: muse binary version mismatch (want 1.0.3-R2198.1)' >&2; exit 1; }
test "${MUSE_NO_AUTO_UPDATE:-0}" = "1" || { echo 'FAIL: MUSE_NO_AUTO_UPDATE is not set to 1' >&2; exit 1; }

# Muse auth: provider key OR device-login auth, without printing values.
# Key path: MUSE_CODE_API_KEY in the environment (forwarded by name).
# Device path (`muse login`): auth.json persists non-empty in the global
# persistent config dir. One of the two paths must hold.
if [[ -n "${MUSE_CODE_API_KEY:-}" ]]; then
  echo 'MUSE_CODE_API_KEY environment injection: PASS (value withheld)'
elif [[ -s /home/box/.config/muse/auth.json ]]; then
  echo 'Native muse auth (auth.json via device login): PASS'
else
  echo 'FAIL: no muse auth: set MUSE_CODE_API_KEY or log in via device flow (auth.json)' >&2
  exit 1
fi

# Assert configuration file validity (model, approvals, telemetry, endpoint).
# Every jq path has a has() pre-assert as defense-in-depth: `jq -e` already
# exits 1 on a missing-key compare against a non-null literal (and on bare
# null), so the guards are redundant-but-harmless here — but `jq -e` exits 0
# on `.x == null` when the key is missing (null==null is true), so the guards
# are not universally redundant. Keep them.
test -f /home/box/.config/muse/settings.json || { echo 'FAIL: settings.json missing' >&2; exit 1; }
jq -e 'has("schema_version") and .schema_version == 1' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json schema_version != 1' >&2; exit 1; }
jq -e 'has("api") and (.api|has("base_url")) and .api.base_url == "https://api.meta.ai/v1"' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: invalid API base URL' >&2; exit 1; }
jq -e 'has("model") and (.model|type == "string") and (.model|length > 0)' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json model missing or empty (user-mutable; must be a non-empty string)' >&2; exit 1; }
jq -e 'has("reasoning_effort") and .reasoning_effort == "max"' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json reasoning_effort != max' >&2; exit 1; }
jq -e 'has("approval_mode") and .approval_mode == "on-request"' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json approval_mode != on-request' >&2; exit 1; }
jq -e 'has("approval_judge") and .approval_judge == true' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json approval_judge != true' >&2; exit 1; }
jq -e 'has("telemetry") and (.telemetry|has("enabled")) and .telemetry.enabled == false' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: settings.json telemetry.enabled != false' >&2; exit 1; }
echo 'Muse Code settings.json validation: PASS'

# Regression: config dir must be a writable persistent global bind
# (~/.config/box-m/muse-config/ holding settings.json, auth.json,
# .trust.json; see docs/operations.md §9). Without the writable parent,
# `muse` fails with `failed to save trust decision: ... Read-only file system`;
# without persistence, `muse login` succeeds but the next run prompts again.
# Removed by the single EXIT cleanup in 00-header, so an early abort cannot
# leak the probe into the persistent bind.
_muse_probe=$(mktemp /home/box/.config/muse/.box-write-test.XXXXXX) || { echo 'FAIL: cannot write to /home/box/.config/muse (needs writable persistent bind)' >&2; exit 1; }
rm -f -- "$_muse_probe"
unset _muse_probe
touch /home/box/.config/muse/settings.json 2>/dev/null || { echo 'FAIL: settings.json is not writable (in-container model changes must persist)' >&2; exit 1; }
echo 'Muse Code config-dir writability (persistent bind) + settings.json writable: PASS'

