echo "=== 3. Network Egress Check ==="
command -v curl >/dev/null || { echo 'FAIL: curl not on PATH' >&2; exit 1; }
# Provider API root (matches settings.json api.base_url): any HTTP response
# code — including 4xx without credentials — proves TCP+TLS egress. Record
# both the curl exit and the HTTP code: FAIL on transport failure (rc != 0)
# or empty/000 code.
provider_code=$(curl --silent --location --max-time 15 --output /dev/null --write-out '%{http_code}' https://api.meta.ai/v1 2>/dev/null); provider_rc=$?
[[ "$provider_rc" -eq 0 && -n "${provider_code:-}" && "$provider_code" != "000" ]] \
  || { echo "FAIL: outbound HTTPS to api.meta.ai/v1 unreachable (curl rc=$provider_rc http=${provider_code:-none})" >&2; exit 1; }
echo "Outbound HTTPS to api.meta.ai/v1 (HTTP $provider_code): PASS"

# Device-flow endpoint (muse login): same transport-failure rule. Regression
# for runsc + Docker embedded DNS (127.0.0.11) failures that present as
# `login failed: device flow transport error` while api.meta.ai/v1 may
# already be covered above.
auth_code=$(curl --silent --location --max-time 15 --output /dev/null --write-out '%{http_code}' https://auth.meta.com/ 2>/dev/null); auth_rc=$?
[[ "$auth_rc" -eq 0 && -n "${auth_code:-}" && "$auth_code" != "000" ]] \
  || { echo "FAIL: outbound HTTPS to auth.meta.com unreachable (curl rc=$auth_rc http=${auth_code:-none}; muse login device flow will fail)" >&2; exit 1; }
echo "Outbound HTTPS to auth.meta.com (HTTP $auth_code): PASS"
