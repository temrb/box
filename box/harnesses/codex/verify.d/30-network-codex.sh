echo '=== 3. Codex transport (separate from authentication) ==='
command -v timeout >/dev/null || { echo 'FAIL: timeout not on PATH' >&2; exit 1; }
command -v getent >/dev/null || { echo 'FAIL: getent not on PATH' >&2; exit 1; }
for _host in auth.openai.com api.openai.com chatgpt.com; do
  timeout 15 getent hosts "$_host" >/dev/null || { echo "FAIL: Codex DNS transport for $_host" >&2; exit 1; }
done
# TLS egress proof (shared helper): a TLS-blocking proxy must not pass
# DNS-only checks here and fail opaquely later at `login status`.
box_verify_egress https://auth.openai.com auth.openai.com
