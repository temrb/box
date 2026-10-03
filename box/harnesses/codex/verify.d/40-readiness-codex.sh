echo '=== 4. Codex native startup and policy ==='
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
with open("/home/box/.codex/config.toml", "rb") as f:
    tomllib.load(f)
PYPOLICY
python3 - --policy-json "$_codex_expected" <<'PYNATIVE'
@@NATIVE_PROBE@@
PYNATIVE
if [[ -e "$CODEX_HOME/auth.json" || -L "$CODEX_HOME/auth.json" ]]; then
  [[ ! -L "$CODEX_HOME/auth.json" && -f "$CODEX_HOME/auth.json" && "$(stat -c %u "$CODEX_HOME/auth.json")" == "$(id -u)" && "$(stat -c %a "$CODEX_HOME/auth.json")" == 600 && -w "$CODEX_HOME/auth.json" ]] || { echo 'FAIL: unsafe native Codex auth cache' >&2; exit 1; }
fi
timeout 30 codex login status >/dev/null 2>&1 || { echo 'FAIL: Codex authentication unavailable (native policy tested separately)' >&2; exit 1; }
echo 'PASS: Codex authentication status (values withheld)'
