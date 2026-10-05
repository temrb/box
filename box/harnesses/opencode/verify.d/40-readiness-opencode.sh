echo "=== 4. OpenCode Operational Readiness ==="
command -v opencode >/dev/null || { echo 'FAIL: opencode binary not on PATH' >&2; exit 1; }
command -v timeout >/dev/null || { echo 'FAIL: timeout not on PATH' >&2; exit 1; }
command -v jq >/dev/null || { echo 'FAIL: jq not on PATH' >&2; exit 1; }
printf 'OpenCode binary version: '
opencode_version_out=$(opencode --version 2>&1) || { echo 'FAIL: opencode --version failed' >&2; exit 1; }
printf '%s\n' "$opencode_version_out"
[[ "$opencode_version_out" == 'opencode v@@OPENCODE_VERSION@@' ]] || { echo 'FAIL: opencode exact binary version mismatch' >&2; exit 1; }
test "${OPENCODE_DISABLE_AUTOUPDATE:-0}" = "1" || { echo 'FAIL: OPENCODE_DISABLE_AUTOUPDATE is not set to 1' >&2; exit 1; }

for _parent in /persist/data /persist/data/opencode /persist/data/opencode/opencode; do
  [[ ! -L "$_parent" ]] || { echo 'FAIL: redirected native OpenCode cache parent' >&2; exit 1; }
done
for _cache in /persist/data/opencode/opencode/opencode.db /persist/data/opencode/opencode/opencode.db-wal /persist/data/opencode/opencode/opencode.db-shm; do
  box_verify_cache "$_cache"
done
# The pinned v2 native credential store is SQLite, not the retired auth.json cache.
# Inspect natively without printing account metadata or keys. Missing inspection fails.
_native_auth=$(timeout 30 opencode auth list --standalone --format json 2>/dev/null) || { echo 'FAIL: native authentication inspection unavailable' >&2; exit 1; }
printf '%s' "$_native_auth" | jq -e 'type == "array" and length > 0' >/dev/null || {
  echo 'FAIL: no provider auth: connect natively via /connect' >&2
  exit 1
}
unset _native_auth
echo 'Native OpenCode credentials present: PASS (real model/resume acceptance separate)'

_opencode_expected=@@ARTIFACT_CONFIG@@
jq -e --argjson expected "$_opencode_expected" '.permissions == $expected.permissions and .default_agent == "plan" and .update == "disable" and (has("lsp") | not) and (has("permission") | not)' /persist/config/opencode/opencode.json >/dev/null || { echo 'FAIL: OpenCode live v2 permissions differ' >&2; exit 1; }
# Client preferences must be writable while the shipped configuration stays read-only.
_opencode_probe=$(mktemp /persist/config/opencode/.box-write-test.XXXXXX) || { echo 'FAIL: cannot write to /persist/config/opencode (needs persistent volume)' >&2; exit 1; }
rm -f -- "$_opencode_probe"
unset _opencode_probe
if touch /persist/config/opencode/opencode.json 2>/dev/null; then echo 'FAIL: opencode.json is writable (must stay readonly)' >&2; exit 1; fi
echo 'OpenCode config-dir writability (persistent volume) + opencode.json readonly: PASS'

# Missing policy inspection is an acceptance failure. v2 debug config lists
# sources with {path, info}; the shipped file must resolve with ordered
# permissions, default_agent plan, and update disable.
effective_json=$(timeout 30 opencode debug config 2>/dev/null) || { echo 'FAIL: native OpenCode policy inspection unavailable' >&2; exit 1; }
printf '%s' "$effective_json" | jq -e --argjson expected "$_opencode_expected" '
  [.[] | select(.path == "/persist/config/opencode/opencode.json") | .info]
  | length == 1 and all(
    .permissions == $expected.permissions and .default_agent == "plan" and .update == "disable"
  )
' >/dev/null || { echo 'FAIL: effective OpenCode v2 permissions differ' >&2; exit 1; }
echo 'OpenCode native source inspection: PASS (permission enforcement and account model/resume evidence are separate)'
