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
