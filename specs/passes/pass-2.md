# plan.md uncommitted implementation check

**Session ID:** ses_ee84de0f4ffeHU2PE5QxpQSTwi
**Created:** 10/7/2026, 6:48:31 PM
**Updated:** 10/7/2026, 6:48:58 PM

---

## User

double check if @specs/plan.md has been implemented correctly and cleanly (uncomitted changes)

first pass context: @specs/pass-1.md

---

## Assistant

_Thinking:_

Synthesizing subagent findings to assess implementation correctness and cleanliness against the plan and uncommitted changes.

_Thinking:_

Condensing subagent findings into a concise verdict with file:line citations and severity-ranked gaps.

Core model is in place but DoD isn't met — compiling the full gap list with evidence.

**Tool: shell**

**Input:**

```json
{
	"command": "bash box/gen-verify.sh --check 2>&1 | tail -n 5; echo \"---BATS-AUTH-POLICY---\"; bats box/tests/bats/auth-policy.bats 2>&1 | tail -n 20",
	"workdir": "/workspace"
}
```

gen-verify.sh: PASS (verify-\*.sh match verify.d/ output)
---BATS-AUTH-POLICY---
/bin/bash: line 1: bats: command not found

Command exited with code 0.

---

## Assistant

_Thinking:_

No — happy-path present, `specs/plan.md` DoD not met.

Correct:

- Registry: `box/lib/tools.sh:217,220,223` one `auth` record/harness, `class=auth,scope=auth-policy,kind=bind,runtime=/run/box-auth,mode=700,schema=1`, fallbacks `global/project/project`. Validated `box/lib/tools.sh:388-421`.
- Precedence `box/lib/auth.sh:174-178` matches §3. `BOX_C_AUTH` independent (`box/harnesses/codex/launch.sh:73` only).
- Layout `box/lib/auth.sh:249-256`, `box/lib/state.sh:114-130`: `R/H/uU/global`, `R/H/uU/projects/P`, UID-keyed, `700/600`, object-dir-only mount (`box/harnesses/codex/launch.sh:115`, `box/harnesses/muse/launch.sh:141`, `box/harnesses/opencode/launch.sh:91`).
- Envelope `{schema,revision,tombstone,payload}`; Codex `tmp+mv` + tombstone `box/harnesses/codex/auth.sh:24-48`; OpenCode explicit columns + `?` binds `box/harnesses/opencode/auth-state.py:28-37,83-90,226-238`, single-active selection `box/harnesses/opencode/auth-state.py:314-320`.
- Capture fresh ns `box/harnesses/opencode/capture-validation.sh:61-80`; `gen-verify.sh --check` PASS.

Must-fix:

1. Phase-1 gate violated: live `ensure_object+transition+reserve+install` unconditional `box/harnesses/muse/launch.sh:97-101`, `box/harnesses/codex/launch.sh:92-96`, `box/harnesses/opencode/launch.sh:59-65`. Muse backend unresolved.
2. OpenCode live missing `box_auth_migration_gate` (`box/harnesses/opencode/launch.sh:59-65` comment only).
3. Legacy quarantine missing; OpenCode `retire` no-op `box/harnesses/opencode/auth.sh:52-59`.
4. Muse qualification comment-only `box/harnesses/muse/auth.sh:16-24`; no keychain/MCP detection. MCP hash/account-table unverified (`box/harnesses/opencode/auth-state.py` passes `integration` opaquely).
5. Shared-lib harness branch violates §2: `box/lib/auth-ops.sh:95-112` `case $id`.
6. Old test contradicts new model: `box/tests/bats/live-defaults.bats:66-107` treats `$BOX_M_PERSIST_DIR/auth.json` as durable, now projection + gate target.
7. Dry-run omits migration/transition + legacy coordinates required §6/§9 (`box/harnesses/muse/launch.sh:64-68`, `box/harnesses/codex/launch.sh:51-55`, `box/harnesses/opencode/launch.sh:37-42`).
8. `state-remove` only effective scope `box/lib/auth-ops.sh:372-404` (global dies `:383-384`); no inactive-scope/custom-root/projection sweep.
9. §10.10/11 missing: no old-image/supervisor rejection; `box_ops_migrate:163-223` no stopped-container check.
10. Validation: `__unset__` accepted as unset `box/lib/auth.sh:140-174`; `BOX_STATE_CONFIG=""`/`BOX_AUTH_ROOT=""` silently default `:40,:210`; `policy_source:190-191` skips config validation; `jq`-absent fail-open `box/lib/auth.sh:345,414`, `box/lib/auth-ops.sh:430`.

Cleanliness:

- Triplicated auth-dir formula `box/lib/test-state.sh:258`, `box/lib/auth.sh:232`, `box/lib/state.sh:114-130`; old `box_project_identity` still live `box/lib/launcher.sh:92,458`.
- Dead: `box_config_get_optional` (`box/lib/config-file.sh:138-172` zero callers), `box/lib/test-state.sh:199-208` no-op, `box/lib/auth-ops.sh:129-141` `if False`.
- Fragile: `box/lib/state.sh:239-246` `grep -q` empty-pattern bypass; `box/lib/auth.sh:333-342` fd leak on `die`; docs retain inline hash `box/docs/operations.md:253-270`; `.dockerignore` `!harnesses/muse/` over-broad.
