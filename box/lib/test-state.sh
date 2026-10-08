# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # registry globals (box_tool_ids, HOME,
# host_uid) are set/consumed across lib files; standalone analysis is partial.
# box/lib/test-state.sh — authoritative disposable test-state namespace.
#
# Phase S implementation of specs/plan.md §0 B0. This is the ONLY code
# permitted to map (namespace, harness, uid, gid) to a volume/home identity
# in test runs. Launchers, box/tests/native/acceptance.sh,
# box/tests/native/lifecycle-audit.py and
# box/harnesses/opencode/capture-validation.sh must resolve every test
# volume/home through these functions — never reconstruct names inline and
# never shell out to `docker volume rm` on a non-namespaced name.
#
# Contract (normative, see specs/plan.md §0 B0):
# - BOX_TEST_STATE_NS is required in every test process that can derive
#   persistence identity. Charset ^[a-z0-9]([a-z0-9-]{0,31})$ (max 32).
# - Test volumes are exactly box-test-<ns>-<state-prefix>-u<uid>-g<gid>
#   (state_prefix from the registry, so codex -> box-c, opencode ->
#   box-o-v2, muse -> box-m). Production box-c-u*-g* / box-o-v2-u*-g*
#   names are never valid test targets.
# - Test Codex homes are exactly <BOX_TEST_TASK_ROOT>/<ns>/codex-home.
# - Missing or malformed namespace fails closed (die) before launch, native
#   inspection, or destructive cleanup — never falls back to production.
# - Every set registry state override in a test run must resolve inside
#   BOX_TEST_TASK_ROOT (tests clear production BOX_C_STATE_ROOT /
#   BOX_C_STATE_DIR / BOX_M_PERSIST_DIR); the test Codex root is the only
#   sanctioned exception and it also lives under the task root.
# - Cleanup may remove only test-namespaced volumes owned by the current
#   test run: each candidate must exactly equal the resolver identity for
#   its recorded (harness, namespace, uid, gid) coordinates. Production
#   global names never match; neither do other namespaces (a parent NS never
#   authorizes `<ns>-cap-<hex>` capture volumes and vice versa). Owned-
#   cleanup failure is a hard failure, not a leftover warning.
#
# Read-only boundary: everything here is pure string/path validation plus
# read-only existence checks ([[ -d ]], realpath -m). Nothing here inspects
# Docker, creates namespaces/volumes, acquires locks, or reads auth.
#
# Phase-S note: test drivers assign one namespace per disposable project
# (plus <ns>-cap-<8hex> capture sub-namespaces) so pre-existing
# per-project isolation assertions keep passing. Phases 5/7 collapse
# multi-project flows onto the shared run namespace with sharing
# expectations. Production launchers never consult these vars (test mode
# engages only when BOX_TEST_STATE_NS or BOX_TEST_TASK_ROOT is set).
[[ "${BASH_SOURCE[0]:-}" != "${0:-}" && -n "${_BOX_TEST_STATE_LOADED:-}" ]] && return 0
_BOX_TEST_STATE_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Canonical self-dir bootstrap (same form as lib/tools.sh; realpath
# preferred, readlink fallback).
_test_state_src=${BASH_SOURCE[0]}
if command -v realpath >/dev/null 2>&1; then
  _test_state_src=$(realpath -- "$_test_state_src" 2>/dev/null || printf '%s' "$_test_state_src")
elif command -v readlink >/dev/null 2>&1; then
  _test_state_src=$(readlink -f -- "$_test_state_src" 2>/dev/null || printf '%s' "$_test_state_src")
fi
_test_state_dir=$(dirname -- "$_test_state_src")
unset _test_state_src
# shellcheck source=lib/tools.sh
source "$_test_state_dir/tools.sh"
unset _test_state_dir

# Validate a test namespace and print it. Dies on missing/malformed input
# with no production fallback. Pure string check: no Docker, no locks.
# Usage: box_test_validate_ns [ns]  (defaults to $BOX_TEST_STATE_NS)
box_test_validate_ns() {
  local ns=${1:-${BOX_TEST_STATE_NS:-}}
  [[ -n "$ns" ]] || die 'BOX_TEST_STATE_NS is required for test-state identity (never fall back to production).'
  [[ "$ns" =~ ^[a-z0-9]([a-z0-9-]{0,31})$ ]] || die "Invalid BOX_TEST_STATE_NS: '$ns' (lowercase alnum/dash, leading alnum, max 32 chars)."
  printf '%s' "$ns"
}

# Test mode engages when either test variable is set. Partial setup (only
# one of the two) is a hard failure via box_test_require_vars, never a
# silent production run.
box_test_in_test_mode() {
  [[ -n "${BOX_TEST_STATE_NS+x}" || -n "${BOX_TEST_TASK_ROOT+x}" || -n "${BOX_TEST_PROJECT_HASH+x}" ]]
}

# Print the validated task root. The root must already exist (drivers create
# it with mktemp -d); this check never creates anything.
box_test_task_root() {
  local task_root=${1:-${BOX_TEST_TASK_ROOT:-}}
  [[ -n "$task_root" ]] || die 'BOX_TEST_TASK_ROOT is required alongside BOX_TEST_STATE_NS (partial test setup must fail closed).'
  [[ -d "$task_root" ]] || die 'BOX_TEST_TASK_ROOT must be an existing disposable directory.'
  printf '%s' "$task_root"
}

# Fail closed on missing/malformed test setup. Silent on success.
box_test_require_vars() {
  box_test_validate_ns >/dev/null
  box_test_task_root >/dev/null
}

# Mint a fresh run/project namespace: t-<12hex> (14 chars, capture-safe).
# An explicit hex makes bats coverage deterministic.
# Usage: box_test_new_ns [12hex]
box_test_new_ns() {
  local hex=${1:-}
  if [[ -z "$hex" ]]; then
    hex=$(od -An -tx1 -N6 /dev/urandom 2>/dev/null | tr -d ' \n' || true)
    [[ "$hex" =~ ^[0-9a-f]{12}$ ]] || hex=$(printf '%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM")
  fi
  [[ "$hex" =~ ^[0-9a-f]{12}$ ]] || die 'Internal error: test namespace hex must be 12 lowercase hex chars.'
  printf 't-%s' "$hex"
}

# Reverse-map a registry state_prefix to its harness id. The launcher knows
# only the prefix; the lookup stays registry-driven (no harness branches).
# Usage: box_test_id_for_prefix <state-prefix>
box_test_id_for_prefix() {
  local prefix=${1:-} id match=
  [[ -n "$prefix" ]] || die 'Internal error: missing state prefix.'
  for id in $box_tool_ids; do
    if [[ "$(box_tool_field "$id" state_prefix)" == "$prefix" ]]; then
      [[ -z "$match" ]] || die 'Internal error: ambiguous state prefix.'
      match=$id
    fi
  done
  [[ -n "$match" ]] || die "Internal error: unknown state prefix: $prefix"
  printf '%s' "$match"
}

# The single volume-identity resolver. Only the canonical registry
# state_prefix feeds the name; config-parent never names a separate volume.
# Usage: box_test_volume <harness-id> <ns> <uid> <gid>
box_test_volume() {
  local id=${1:-} ns=${2:-} uid=${3:-} gid=${4:-} prefix
  box_require_tool "$id"
  [[ -n "$ns" ]] || die 'BOX_TEST_STATE_NS is required for test volume identity.'
  box_test_validate_ns "$ns" >/dev/null
  [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] \
    || die 'Internal error: test volume UID/GID must be non-zero numbers.'
  ((10#$uid != 0 && 10#$gid != 0)) \
    || die 'Internal error: test volume UID/GID must be non-zero numbers.'
  prefix=$(box_tool_field "$id" state_prefix)
  [[ "$prefix" =~ ^[a-z][a-z0-9-]*$ ]] || die "Internal error: invalid state prefix: $id"
  if [[ -n "${BOX_TEST_PROJECT_HASH+x}" ]]; then
    [[ "$BOX_TEST_PROJECT_HASH" =~ ^[0-9a-f]{20}$ ]] || die 'Invalid test fixture project hash.'
    printf 'box-test-%s-%s-u%s-g%s-p%s' "$ns" "$prefix" "$uid" "$gid" "$BOX_TEST_PROJECT_HASH"
  else
    printf 'box-test-%s-%s-u%s-g%s' "$ns" "$prefix" "$uid" "$gid"
  fi
}

# The single Codex-home resolver: exactly <task-root>/<ns>/codex-home.
# Usage: box_test_codex_home [task-root] [ns]
box_test_native_home() {
  local leaf=$1 task_root=${2:-${BOX_TEST_TASK_ROOT:-}} ns=${3:-${BOX_TEST_STATE_NS:-}}
  [[ "$leaf" =~ ^[a-z][a-z0-9-]*$ ]] || die 'Invalid native fixture leaf.'
  box_test_task_root "$task_root" >/dev/null
  box_test_validate_ns "$ns" >/dev/null
  if [[ -n "${BOX_TEST_PROJECT_HASH+x}" ]]; then
    BOX_TEST_TASK_ROOT=$task_root box_test_fixture_dir "$ns" "$BOX_TEST_PROJECT_HASH" "$leaf"
  else
    printf '%s/%s/%s' "$task_root" "$ns" "$leaf"
  fi
}

box_test_codex_home() {
  box_test_native_home "$(box_state_field codex home leaf)" "$@"
}

# Derive an independent capture sub-namespace: <parent>-cap-<8hex>.
# The parent must fit so the sub stays within 32 chars; longer parents fail
# closed (drivers mint short run namespaces).
# Usage: box_test_capture_ns [parent-ns] [8hex]
box_test_capture_ns() {
  local parent=${1:-${BOX_TEST_STATE_NS:-}} hex=${2:-} sub
  parent=$(box_test_validate_ns "$parent") || die 'Invalid parent test namespace for capture derivation.'
  ((${#parent} <= 19)) || die 'Parent test namespace too long for capture sub-namespace (max 19 chars).'
  if [[ -z "$hex" ]]; then
    hex=$(od -An -tx1 -N4 /dev/urandom 2>/dev/null | tr -d ' \n' || true)
    [[ "$hex" =~ ^[0-9a-f]{8}$ ]] || hex=$(printf '%04x%04x' "$RANDOM" "$RANDOM")
  fi
  [[ "$hex" =~ ^[0-9a-f]{8}$ ]] || die 'Internal error: capture hex suffix must be 8 lowercase hex chars.'
  sub="$parent-cap-$hex"
  ((${#sub} <= 32)) || die 'Internal error: capture sub-namespace exceeds 32 chars.'
  printf '%s' "$sub"
}

# Every set registry state override in a test run must resolve inside the
# disposable task root. Generic over the registry (no harness branches): the
# test Codex root passes because drivers point it under the task root, while
# any leftover production BOX_C_STATE_ROOT / BOX_C_STATE_DIR /
# BOX_M_PERSIST_DIR / BOX_AUTH_ROOT fails closed here. BOX_STATE_CONFIG, when
# set, must also live inside the task root and never select production state.
box_test_state_overrides_location_check() {
  local id state override raw resolved task_resolved
  box_test_task_root >/dev/null
  task_resolved=$(realpath -m -- "$BOX_TEST_TASK_ROOT") || die 'Cannot resolve BOX_TEST_TASK_ROOT.'
  for id in $box_tool_ids; do
    for state in $(box_tool_field "$id" states); do
      for override in $(box_state_field "$id" "$state" override); do
        [[ -n "${!override+x}" ]] || continue
        raw=${!override}
        [[ -n "$raw" && "$raw" == /* ]] || die 'Test state overrides must be nonempty absolute paths.'
        resolved=$(realpath -m -- "$raw") || die "Cannot resolve $override."
        case "$resolved" in
          "$task_resolved"/*) ;;
          *) die "$override must point inside BOX_TEST_TASK_ROOT in test runs (got: $raw)." ;;
        esac
        box_plan_directory "$raw" >/dev/null || return 1
      done
    done
  done
  if [[ -n "${BOX_STATE_CONFIG:-}" ]]; then
    resolved=$(realpath -m -- "$BOX_STATE_CONFIG") || die 'Cannot resolve BOX_STATE_CONFIG.'
    case "$resolved" in
      "$task_resolved"/*) ;;
      *) die 'BOX_STATE_CONFIG must point inside BOX_TEST_TASK_ROOT in test runs.' ;;
    esac
  fi
  # Scope overrides (BOX_AUTH_SCOPE, <PREFIX>_AUTH_SCOPE) are value-only;
  # they carry no filesystem location and need no containment check here.
  # Values themselves are validated by box_auth_policy_resolve before any
  # state access.
}

# Authorize a test bind root: it must live under the disposable task root
# and must never equal (or sit under) a production default root. Pure path
# logic; creates nothing, contacts nothing. Production roots derive from the
# registry (all bind roots plus the shared auth root and state index),
# never a second hardcoded list.
# Usage: box_test_guard_bind_root <candidate-path>
box_test_guard_bind_root() {
  local path=${1:-} task_resolved path_resolved real_home prod prod_resolved
  local id state root override raw
  [[ -n "$path" ]] || die 'Internal error: missing test bind-root candidate.'
  [[ -n "${BOX_TEST_TASK_ROOT:-}" ]] || die 'BOX_TEST_TASK_ROOT is required to authorize test bind roots.'
  task_resolved=$(realpath -m -- "$BOX_TEST_TASK_ROOT") || die 'Cannot resolve BOX_TEST_TASK_ROOT.'
  path_resolved=$(realpath -m -- "$path") || die 'Cannot resolve test bind-root candidate.'
  case "$path_resolved" in
    "$task_resolved"/*) ;;
    *) die "Test state root must live under BOX_TEST_TASK_ROOT (got: $path)." ;;
  esac
  real_home=${BOX_TEST_REAL_HOME:-$HOME}
  [[ -n "$real_home" ]] || die 'Cannot determine home for production-root comparison.'
  local -a prods=("$real_home/.config/box")
  for id in $box_tool_ids; do
    for state in $(box_tool_field "$id" states); do
      [[ "$(box_state_field "$id" "$state" kind)" == bind ]] || continue
      root=$(box_state_field "$id" "$state" root)
      prods+=("$real_home/$root")
      for override in $(box_state_field "$id" "$state" override); do
        # Only production defaults participate here; test runs must leave
        # overrides unset or inside the task root (checked separately).
        case "$override" in BOX_AUTH_ROOT|BOX_STATE_CONFIG) continue ;; esac
        raw=${!override:-}
        [[ -n "$raw" ]] || continue
        # Overrides inside the disposable task root are test coordinates,
        # not production roots. Defaults above still reject collisions.
        prod_resolved=$(realpath -m -- "$raw") || die 'Cannot resolve state override.'
        case "$prod_resolved" in "$task_resolved"/*) continue ;; esac
        prods+=("$raw")
      done
    done
  done
  for prod in "${prods[@]}"; do
    prod_resolved=$(realpath -m -- "$prod") || die 'Cannot resolve production root.'
    [[ "$path_resolved" != "$prod_resolved" && "$path_resolved" != "$prod_resolved"/* ]] \
      || die "Test state root must never equal a production root (got: $path)."
    [[ "$task_resolved" != "$prod_resolved" && "$task_resolved" != "$prod_resolved"/* ]] \
      || die 'BOX_TEST_TASK_ROOT must not live inside a production state root.'
  done
}

# Test auth directory: namespace-local canonical auth.
# Usage: box_test_auth_dir <harness> <ns> <uid> <global|project> [project-hash]
box_test_auth_dir() {
  local id=${1:-} ns=${2:-} uid=${3:-} scope=${4:-} hash=${5:-}
  local troot
  box_require_tool "$id"
  box_test_validate_ns "$ns" >/dev/null
  [[ "$uid" =~ ^[0-9]+$ ]] || die 'Invalid test auth UID.'
  ((10#$uid != 0)) || die 'Invalid test auth UID.'
  case "$scope" in global|project) ;; *) die 'Invalid test auth scope.';; esac
  troot=$(box_test_task_root "${BOX_TEST_TASK_ROOT:-}") || return 1
  if [[ "$scope" == global ]]; then
    printf '%s/%s/auth/%s/u%s/global' "$troot" "$ns" "$id" "$uid"
  else
    [[ "$hash" =~ ^[0-9a-f]{20}$ ]] || die 'Invalid project hash for test project auth.'
    printf '%s/%s/auth/%s/u%s/projects/%s' "$troot" "$ns" "$id" "$uid" "$hash"
  fi
}

# Project-qualified fixture identity for two-project scope tests: an
# independent non-auth store inside one namespace without inlining a new
# naming formula in callers.
# Usage: box_test_fixture_dir <ns> <project-hash> <leaf>
box_test_fixture_dir() {
  local ns=${1:-} hash=${2:-} leaf=${3:-fixture} troot
  box_test_validate_ns "$ns" >/dev/null
  [[ "$hash" =~ ^[0-9a-f]{20}$ ]] || die 'Invalid fixture project hash.'
  [[ "$leaf" =~ ^[A-Za-z0-9_.-]+$ ]] || die 'Invalid fixture leaf.'
  troot=$(box_test_task_root "${BOX_TEST_TASK_ROOT:-}") || return 1
  printf '%s/%s/fixtures/%s/%s' "$troot" "$ns" "$hash" "$leaf"
}

# Authorize one test auth cleanup candidate: exact resolver identity only.
# Usage: box_test_guard_auth_cleanup <candidate> <harness> <ns> <uid> <global|project> [hash]
box_test_guard_auth_cleanup() {
  local candidate=${1:-} id=${2:-} ns=${3:-} uid=${4:-} scope=${5:-} hash=${6:-} expected
  [[ -n "$candidate" ]] || die 'Refusing cleanup of an empty auth path.'
  case "$candidate" in *'*'*|*'?'*|*'['*) die 'Refusing wildcard auth cleanup.';; esac
  if [[ "$scope" == global ]]; then
    expected=$(box_test_auth_dir "$id" "$ns" "$uid" "$scope") || die 'Refusing auth cleanup: cannot resolve owned identity.'
  else
    [[ $# -eq 6 ]] || die 'Internal error: project auth cleanup needs a project hash.'
    expected=$(box_test_auth_dir "$id" "$ns" "$uid" "$scope" "$hash") || die 'Refusing auth cleanup: cannot resolve owned identity.'
  fi
  [[ "$candidate" == "$expected" ]] || die "Refusing auth cleanup outside owned test identity (got: $candidate)."
}

# Authorize one cleanup candidate: it must exactly equal the resolver
# identity for its recorded (harness, namespace, uid, gid) coordinates.
# Dies WITHOUT touching Docker otherwise — production global names never
# match, and neither do foreign namespaces (a parent NS never authorizes a
# `<ns>-cap-<hex>` capture volume). Callers track coordinates alongside
# every resolver-built volume and iterate explicit volume lists only —
# never `docker volume ls` globs.
# Usage: box_test_guard_cleanup <candidate> <harness-id> <ns> <uid> <gid>
box_test_guard_cleanup() {
  local candidate=${1:-} id=${2:-} ns=${3:-} uid=${4:-} gid=${5:-} expected
  [[ $# -eq 5 ]] || die 'Internal error: cleanup guard takes candidate, harness, namespace, uid, gid.'
  [[ -n "$candidate" ]] || die 'Refusing cleanup of an empty volume name.'
  [[ "$candidate" == box-test-* ]] || die "Refusing cleanup of non-test volume: $candidate"
  expected=$(box_test_volume "$id" "$ns" "$uid" "$gid") || die 'Refusing cleanup: cannot resolve owned test identity.'
  [[ "$candidate" == "$expected" ]] || die "Refusing cleanup outside owned test identity (got: $candidate)."
}

# Minimal CLI for non-bash consumers (lifecycle-audit.py). Stdout carries
# the result; any failure dies on stderr with exit 1 before Docker exists.
box_test_cli() {
  local sub=${1:-}
  [[ -n "$sub" ]] || die 'Usage: test-state.sh <new-ns|volume|id-for-prefix|codex-home|capture-ns|guard-bind-root|guard-cleanup|validate-ns|task-root|auth-dir|fixture-dir|guard-auth-cleanup> ...'
  shift
  case "$sub" in
    new-ns) [[ $# -le 1 ]] || die 'Usage: test-state.sh new-ns [12hex]'; box_test_new_ns "${1:-}" ;;
    volume) [[ $# -eq 4 ]] || die 'Usage: test-state.sh volume <harness-id> <ns> <uid> <gid>'; box_test_volume "$@" ;;
    id-for-prefix) [[ $# -eq 1 ]] || die 'Usage: test-state.sh id-for-prefix <state-prefix>'; box_test_id_for_prefix "$1" ;;
    codex-home) [[ $# -le 2 ]] || die 'Usage: test-state.sh codex-home [task-root] [ns]'; box_test_codex_home "${1:-}" "${2:-}" ;;
    capture-ns) [[ $# -le 2 ]] || die 'Usage: test-state.sh capture-ns [parent-ns] [8hex]'; box_test_capture_ns "${1:-}" "${2:-}" ;;
    guard-bind-root) [[ $# -eq 1 ]] || die 'Usage: test-state.sh guard-bind-root <path>'; box_test_guard_bind_root "$1" ;;
    guard-cleanup) [[ $# -eq 5 ]] || die 'Usage: test-state.sh guard-cleanup <candidate> <harness-id> <ns> <uid> <gid>'; box_test_guard_cleanup "$@" ;;
    validate-ns) [[ $# -le 1 ]] || die 'Usage: test-state.sh validate-ns [ns]'; box_test_validate_ns "${1:-}" ;;
    task-root) [[ $# -le 1 ]] || die 'Usage: test-state.sh task-root [path]'; box_test_task_root "${1:-}" ;;
    auth-dir) [[ $# -eq 4 || $# -eq 5 ]] || die 'Usage: test-state.sh auth-dir <harness> <ns> <uid> <scope> [hash]'; box_test_auth_dir "$@" ;;
    fixture-dir) [[ $# -eq 3 ]] || die 'Usage: test-state.sh fixture-dir <ns> <hash> <leaf>'; box_test_fixture_dir "$@" ;;
    guard-auth-cleanup) [[ $# -eq 5 || $# -eq 6 ]] || die 'Usage: test-state.sh guard-auth-cleanup <candidate> <harness> <ns> <uid> <scope> [hash]'; box_test_guard_auth_cleanup "$@" ;;
    *) die "Unknown test-state command: $sub" ;;
  esac
}

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  box_test_cli "$@"
fi
