# tests/bats/helpers.bash — shared setup for the Phase 1 safety-net suite.
# No behavior change to the bundle: these helpers only isolate $HOME/$project
# per test so the strict parsers run against throwaway dirs.
#
# NOTE: scratch *projects* live under the real $HOME (mktemp template below).
# They cannot live under /tmp: /tmp/* is on the closed project denylist, so a
# /tmp project dies at the denylist before any deeper check runs. The fake
# $HOME itself stays under /tmp (it is resolved, never used as a project).
# PROJ_ROOT therefore stays under $HOME (not BATS_TMPDIR, which is /tmp on
# most hosts and would denylist every test project); TEST_TMP under
# BATS_TMPDIR holds only non-project scratch. Kill -9 leaks PROJ_ROOT by
# design (documented here, not moved: correctness over tidiness).
#
# Load with: load helpers (from within tests/bats/).

# BUNDLE_DIR resolves to box/ regardless of the bats invocation CWD.
BUNDLE_DIR=$(dirname -- "$(realpath -- "${BATS_TEST_FILENAME:-$0}" 2>/dev/null || readlink -f -- "${BATS_TEST_FILENAME:-$0}")")
BUNDLE_DIR=$(dirname -- "$BUNDLE_DIR")
BUNDLE_DIR=$(dirname -- "$BUNDLE_DIR")

setup() {
  BOX_TOOL=test
  export BOX_TOOL
  # shellcheck source=../../lib/preflight.sh
  source "$BUNDLE_DIR/lib/preflight.sh"
  # shellcheck source=../../lib/tools.sh
  source "$BUNDLE_DIR/lib/tools.sh"
  # shellcheck source=../../lib/config.sh
  source "$BUNDLE_DIR/lib/config.sh"
  # shellcheck source=../../lib/docker.sh
  source "$BUNDLE_DIR/lib/docker.sh"
  # shellcheck source=../../lib/launcher.sh
  source "$BUNDLE_DIR/lib/launcher.sh"
  # shellcheck source=../../lib/run.sh
  source "$BUNDLE_DIR/lib/run.sh"
  # shellcheck source=../../lib/pins.sh
  source "$BUNDLE_DIR/lib/pins.sh"
  # shellcheck source=../../lib/build.sh
  source "$BUNDLE_DIR/lib/build.sh"

  TEST_TMP=$(mktemp -d "${BATS_TMPDIR:-/tmp}/box-bats.XXXXXX")
  # shellcheck disable=SC2155
  export REAL_HOME="$HOME"
  SAVED_HOME="$HOME"
  export SAVED_HOME
  PROJ_ROOT=$(mktemp -d "$HOME/.box-bats.XXXXXX")
  # Fake $HOME lives under PROJ_ROOT (real home), not /tmp: several guards
  # compare $project against $HOME, and any /tmp/* project dies at the
  # denylist before those guards run.
  TEST_HOME="$PROJ_ROOT/home"
  mkdir -p -- "$TEST_HOME"
  TEST_PROJ="$PROJ_ROOT/proj"
  mkdir -p -- "$TEST_PROJ"
  HOME="$TEST_HOME"
  export HOME
  host_uid=$(id -u)
  host_gid=$(id -g)
  project="$TEST_PROJ"

  # Minimal git identity for launcher dry-run tests.
  BOX_M_GIT_NAME='Test User'
  BOX_M_GIT_EMAIL='test@example.com'
  BOX_O_GIT_NAME='Test User'
  BOX_O_GIT_EMAIL='test@example.com'
  export BOX_M_GIT_NAME BOX_M_GIT_EMAIL BOX_O_GIT_NAME BOX_O_GIT_EMAIL
}

teardown() {
  HOME="${SAVED_HOME:-$HOME}"
  export HOME
  rm -rf -- "${TEST_TMP:-/tmp/box-bats-nonexistent}" "${PROJ_ROOT:-$HOME/.box-bats-nonexistent}"
}

# Write a minimal valid muse pin file at path $1 (pins derived from the
# bundle so upgrades never rot the helpers).
make_muse_version_file() {
  local dest=${1:-}
  {
    printf 'MUSE_VERSION=%s\n' "$(box_print_pin "$BUNDLE_DIR" MUSE_VERSION)"
    printf 'MUSE_SHA256_AMD64=%s\n' "$(box_print_pin "$BUNDLE_DIR" MUSE_SHA256_AMD64)"
    printf 'MUSE_SHA256_ARM64=%s\n' "$(box_print_pin "$BUNDLE_DIR" MUSE_SHA256_ARM64)"
  } >"$dest"
  chmod 600 -- "$dest"
}

# Write a minimal valid opencode pin file at path $1 (derived from bundle).
make_opencode_version_file() {
  local dest=${1:-}
  {
    printf 'OPENCODE_VERSION=%s\n' "$(box_print_pin "$BUNDLE_DIR" OPENCODE_VERSION)"
    printf 'OPENCODE_NPM_INTEGRITY=%s\n' "$(box_print_pin "$BUNDLE_DIR" OPENCODE_NPM_INTEGRITY)"
    printf 'OPENCODE_NPM_INTEGRITY_LINUX_X64=%s\n' "$(box_print_pin "$BUNDLE_DIR" OPENCODE_NPM_INTEGRITY_LINUX_X64)"
    printf 'OPENCODE_NPM_INTEGRITY_LINUX_ARM64=%s\n' "$(box_print_pin "$BUNDLE_DIR" OPENCODE_NPM_INTEGRITY_LINUX_ARM64)"
    printf 'NODE_VERSION=%s\n' "$(box_print_pin "$BUNDLE_DIR" NODE_VERSION)"
    printf 'NODESOURCE_FINGERPRINT=%s\n' "$(box_print_pin "$BUNDLE_DIR" NODESOURCE_FINGERPRINT)"
  } >"$dest"
  chmod 600 -- "$dest"
}

# Write a credentials file with the given literal lines at path $1.
make_creds_file() {
  local dest=${1:-}
  shift
  : >"$dest"
  chmod 600 -- "$dest"
  local line
  for line in "$@"; do
    printf '%s\n' "$line" >>"$dest"
  done
}
