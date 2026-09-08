echo "=== 3. Network Egress Check ==="
command -v curl >/dev/null || { echo 'FAIL: curl not on PATH' >&2; exit 1; }
# Generic HTTPS egress (opencode ships no provider endpoint under pure
# /connect, so any stable public HTTPS URL proves TCP+TLS). Any HTTP
# response code — including 4xx — proves egress. FAIL on transport failure
# (rc != 0) or empty/000 code.
egress_code=$(curl --silent --location --max-time 15 --output /dev/null --write-out '%{http_code}' https://registry.npmjs.org/opencode-ai 2>/dev/null); egress_rc=$?
[[ "$egress_rc" -eq 0 && -n "${egress_code:-}" && "$egress_code" != "000" ]] \
  || { echo "FAIL: outbound HTTPS to registry.npmjs.org/opencode-ai unreachable (curl rc=$egress_rc http=${egress_code:-none})" >&2; exit 1; }
echo "Outbound HTTPS to registry.npmjs.org/opencode-ai (HTTP $egress_code): PASS"
