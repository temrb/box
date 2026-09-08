# shellcheck shell=bash
# shellcheck disable=SC2034 # readonly constants are consumed cross-file (see Consumers below).
# box/lib/config.sh — single constants home for genuinely shared values.
# All cross-file constants live here as readonly values so the credential
# allowlist, timeouts, and resource limits cannot drift apart. Per-tool
# identity lives in the registry (lib/tools.sh) — nothing per-tool remains
# here. Sourced after lib/preflight.sh (uses die). Never executed directly.
# Consumers: lib/run.sh (resources), lib/launcher.sh (probe timeout),
# both launchers + setup.sh (allowlist). Value parity with
# settings.json/opencode.json and the stdin-deliverable verify.d/ partials
# is pinned by tests/bats/config-linkage.bats.

# Guard against double-sourcing (setup.sh sources several libs that chain here).
[[ -n "${_BOX_CONFIG_LOADED:-}" ]] && return 0
_BOX_CONFIG_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# --- Credential allowlist (shared providers.env) ---
# Single key: muse forwards MUSE_CODE_API_KEY (least privilege); opencode
# forwards nothing (pure /connect via auth.json). Both launchers parse the
# shared file with this allowlist; unknown keys hard-FAIL.
readonly BOX_CRED_KEYS='MUSE_CODE_API_KEY'

# --- Timeouts / resources (single home; was copied per launcher) ---
readonly BOX_DNS_PROBE_TIMEOUT=30
readonly BOX_CONTAINER_MEMORY='8g'
readonly BOX_CONTAINER_CPUS='4'
readonly BOX_CONTAINER_PIDS='512'
