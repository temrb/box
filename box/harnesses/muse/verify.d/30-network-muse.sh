echo "=== 3. Network Egress Check ==="
# Provider API root (matches settings.json endpoint_transport.base_url) and
# device-flow endpoint (muse login): shared egress proof (see §2 helper).
# Regression cover for runsc + Docker embedded DNS (127.0.0.11) failures that
# present as `login failed: device flow transport error`.
box_verify_egress https://api.meta.ai/v1 api.meta.ai/v1
box_verify_egress https://auth.meta.com/ auth.meta.com '; muse login device flow will fail'
