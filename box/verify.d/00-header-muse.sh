#!/usr/bin/env bash
# verify-muse.sh — in-container readiness harness for box-m.
# GENERATED NOTE: do not edit by hand — edit verify.d/ partials and run
# gen-verify.sh. This file and verify-opencode.sh stay self-contained
# (delivered via stdin under --shell, cannot source a shared file). Shared
# §§1-2/5 (workspace, toolchain, containment) live once in verify.d/
# (10-workspace.sh, 20-toolchain.sh, 50-containment.sh); §4 is
# tool-specific and §6 documents the differing inner-sandbox probes.
set -euo pipefail
export LC_ALL=C
# N1: root gate FIRST — before any mktemp/touch probes (§1/§4) or user `bash -c`
# (§5, deferred). Running as root would otherwise execute project code as root.
test "$(id -u)" -ne 0 || { echo 'FAIL: running as root' >&2; exit 1; }
# Warning counter for the warning-aware footer (§99): every WARNING site below
# increments box_warnings so the final banner reports tolerated warnings
# instead of an unconditional ALL PASSED.
box_warnings=0
# Fail closed on attacker-set or typo'd harness env: BOX_RUNTIME must be
# runc|runsc when set (unset = manual run, grades like runsc with WARNING);
# BOX_ALLOW_PROXY must be 0|1 when set.
case "${BOX_RUNTIME:-}" in ''|runc|runsc) : ;; *) echo 'FAIL: BOX_RUNTIME must be runc|runsc' >&2; exit 1 ;; esac
case "${BOX_ALLOW_PROXY:-0}" in 0|1) : ;; *) echo 'FAIL: BOX_ALLOW_PROXY must be 0|1' >&2; exit 1 ;; esac
if [[ -z "${BOX_RUNTIME:-}" ]]; then echo 'WARNING: BOX_RUNTIME unset (manual run; grading CapBnd like runsc)'; box_warnings=$((box_warnings+1)); fi
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo 'Usage: box-m --shell -s -- <existing-project-file> [test-command] < verify-muse.sh'
  exit 0
fi
[[ "$PWD" == /workspace ]] || { echo 'Run through box-m --shell.' >&2; exit 1; }
[[ -n "${1:-}" && -f "$1" ]] || { echo 'Usage: pass an existing project file, then optionally a test command.' >&2; exit 1; }
# Single EXIT cleanup for the whole harness: every section below shares these
# temp vars and only assigns them, never re-arms the trap, so the chain
# cannot rot when a section is added or renamed.
write_test=""
scratch=""
build_scratch=""
_muse_probe=""
_opencode_probe=""
box_cleanup() { rm -f -- "${write_test:-}" "${_muse_probe:-}" "${_opencode_probe:-}"; rm -rf -- "${scratch:-}" "${build_scratch:-}"; }
trap box_cleanup EXIT

