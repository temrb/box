echo "=== 4. Muse Code Operational Readiness ==="
command -v muse >/dev/null || { echo 'FAIL: muse binary not on PATH' >&2; exit 1; }
command -v timeout >/dev/null || { echo 'FAIL: timeout not on PATH' >&2; exit 1; }
command -v jq >/dev/null || { echo 'FAIL: jq not on PATH' >&2; exit 1; }
printf 'Muse binary version: '
muse_version_out=$(timeout 30 muse --version 2>&1) || { echo 'FAIL: muse --version failed' >&2; exit 1; }
printf '%s\n' "$muse_version_out"
_muse_pin='@@MUSE_VERSION@@'
[[ "$muse_version_out" == "Muse Code ${_muse_pin%%-*} ($_muse_pin)" ]] || { echo 'FAIL: muse exact binary version mismatch' >&2; exit 1; }
test "${MUSE_NO_AUTO_UPDATE:-0}" = "1" || { echo 'FAIL: MUSE_NO_AUTO_UPDATE is not set to 1' >&2; exit 1; }

# shellcheck disable=SC2043 # one declared native cache today
for _cache in /home/box/.config/muse/auth.json; do
  box_verify_cache "$_cache"
done
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

# Enforced-keys presence (filter home: harnesses/muse/native.sh, baked in below).
jq -e '@@ENFORCED_JQ@@' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: Muse settings lack enforced keys' >&2; exit 1; }
# Generated expectations come from the native source artifact.
_muse_expected=@@ARTIFACT_SETTINGS@@
jq -e --argjson expected "$_muse_expected" '
  .telemetry.enabled == $expected.telemetry.enabled and
  .endpoint_transport.base_url == $expected.endpoint_transport.base_url and .schema_version == $expected.schema_version and
  (.model|type == "string" and length > 0) and .reasoning_effort == $expected.reasoning_effort
' /home/box/.config/muse/settings.json >/dev/null || { echo 'FAIL: Muse startup settings differ' >&2; exit 1; }
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
if touch /home/box/.config/muse/settings.json 2>/dev/null; then
  echo 'FAIL: settings snapshot must be read-only' >&2; exit 1
fi
echo 'Muse persistent auth/trust parent writable; settings snapshot read-only: PASS'
