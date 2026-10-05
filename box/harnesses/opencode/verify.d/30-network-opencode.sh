echo "=== 3. Network Egress Check ==="
# Generic HTTPS egress (opencode ships no provider endpoint under pure
# /connect, so any stable public HTTPS URL proves TCP+TLS): shared proof.
box_verify_egress https://opencode.ai opencode.ai
