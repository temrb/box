echo '=== 4. Codex native startup and policy ==='
command -v timeout >/dev/null || { echo 'FAIL: timeout not on PATH' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'FAIL: python3 not on PATH' >&2; exit 1; }
codex_version_out=$(timeout 30 codex --version 2>&1) || { echo 'FAIL: codex --version failed' >&2; exit 1; }
[[ "$codex_version_out" == 'codex-cli @@CODEX_VERSION@@' ]] || { echo 'FAIL: exact Codex binary version mismatch' >&2; exit 1; }
[[ "$CODEX_HOME" == /home/box/.codex && -w "$CODEX_HOME" && -w /persist/state/codex ]] || { echo 'FAIL: Codex state paths' >&2; exit 1; }
[[ "$(stat -c '%u:%a' /etc/codex/requirements.toml)" == 0:644 ]] || { echo 'FAIL: Codex managed policy owner/mode' >&2; exit 1; }
_codex_expected=@@ARTIFACT_POLICY@@
_codex_seed=@@ARTIFACT_CONFIG@@
python3 - "$_codex_expected" <<'PYPOLICY'
import json, sys, tomllib
with open("/etc/codex/requirements.toml", "rb") as f:
    actual = tomllib.load(f)
if actual != json.loads(sys.argv[1]):
    sys.exit("FAIL: Codex managed policy differs")
with open("/etc/codex/config.toml", "rb") as f:
    tomllib.load(f)
PYPOLICY
python3 - --policy-json "$_codex_expected" <<'PYNATIVE'
@@NATIVE_PROBE@@
PYNATIVE
box_verify_cache "$CODEX_HOME/auth.json" 'unsafe native Codex auth cache'
timeout 30 codex login status >/dev/null 2>&1 || { echo 'FAIL: Codex authentication unavailable (native policy tested separately)' >&2; exit 1; }
echo 'PASS: Codex authentication status (values withheld)'

# Auth-managed run: the selected canonical object is mounted read-write at
# /run/box-auth (object dir only, never the shared auth root). The native
# auth.json above is a temporary projection collected on host exit.
[[ -d /run/box-auth ]] || { echo 'FAIL: /run/box-auth is not mounted (auth-managed runs only)' >&2; exit 1; }
jq -e --arg h codex '.harness == $h and .schema_version == 1' -- /run/box-auth/identity.json >/dev/null 2>&1 \
  || { echo 'FAIL: auth identity mismatch (expected codex schema 1)' >&2; exit 1; }
jq -e '.state == "active"' -- /run/box-auth/lease.json >/dev/null 2>&1 \
  || { echo 'FAIL: auth lease is not active' >&2; exit 1; }
jq -e 'type == "object" and .schema_version == 1 and .harness == "codex" and (.tombstone | type == "boolean")' \
  -- /run/box-auth/credentials.json >/dev/null 2>&1 \
  || { echo 'FAIL: auth envelope is not a valid codex envelope' >&2; exit 1; }
echo 'PASS: Codex canonical auth mount + lease + envelope (values withheld)'
