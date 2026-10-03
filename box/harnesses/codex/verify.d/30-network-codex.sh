echo '=== 3. Codex transport (separate from authentication) ==='
for _host in auth.openai.com api.openai.com chatgpt.com; do
  timeout 15 getent hosts "$_host" >/dev/null || { echo "FAIL: Codex DNS transport for $_host" >&2; exit 1; }
done
