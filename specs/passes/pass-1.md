# Verifying plan.md uncommitted changes

**Session ID:** ses_ee867ee6bffeZodApp29BAoD3V
**Created:** 10/7/2026, 6:20:04 PM
**Updated:** 10/7/2026, 6:20:12 PM

---

## User

double check if @specs/plan.md has been implemented correctly and cleanly (uncomitted changes)

---

## Assistant

_Thinking:_

Checking your uncommitted changes against the plan — inventorying the workspace first.

**Tool: read**

**Input:**

```json
{
	"path": "/workspace"
}
```

Read directory /workspace, entries 1-20
.agents/
.bats-home/
.bats-run-base/
.bats-run-c1/
.bats-run-c2/
.bats-run-c3/
.bats-run-c4/
.bats-run-parent/
.bats-run/
.git/
.github/
.vscode/
box/
specs/
.gitignore
AGENTS.md
LICENSE
meta-api-key
README.md
skills-lock.json

---

## Assistant

_Thinking:_

**Tool: shell**

**Input:**

```json
{
	"command": "git status --porcelain=v1; echo \"---BRANCH---\"; git branch --show-current; echo \"---LOG---\"; git log --oneline -5; echo \"---DIFF STAT---\"; git diff --stat; echo \"---DIFF NAME---\"; git diff --name-only; echo \"---STAGED STAT---\"; git diff --cached --stat",
	"workdir": "/workspace"
}
```

M .gitignore
M box/.dockerignore
M box/Dockerfile
M box/Makefile
M box/README.md
M box/box-c
M box/box-m
M box/box-m-login
M box/box-o
M box/check-pins.sh
M box/docs/acceptance.md
M box/docs/adding-a-tool.md
M box/docs/architecture.md
M box/docs/harnesses.md
M box/docs/operations.md
M box/docs/security-resource-audit.md
M box/docs/troubleshooting.md
M box/docs/upgrades.md
M box/harnesses/codex/README.md
M box/harnesses/codex/launch.sh
M box/harnesses/codex/verify.d/40-readiness-codex.sh
M box/harnesses/muse/README.md
M box/harnesses/muse/install.sh
M box/harnesses/muse/launch.sh
M box/harnesses/muse/verify.d/40-readiness-muse.sh
M box/harnesses/opencode/README.md
M box/harnesses/opencode/capture-validation.sh
M box/harnesses/opencode/entrypoint.sh
M box/harnesses/opencode/launch.sh
M box/harnesses/opencode/verify.d/40-readiness-opencode.sh
M box/lib/config-file.sh
M box/lib/install.sh
M box/lib/test-state.sh
M box/lib/tools.sh
M box/setup.sh
M box/tests/bats/helpers.bash
M box/tests/bats/opencode-capture.bats
M box/tests/bats/setup.bats
M box/tests/bats/tools.bats
M box/tests/native/acceptance.sh
M box/tests/native/lifecycle-audit.py
M box/verify-codex.sh
M box/verify-muse.sh
M box/verify-opencode.sh
?? .agents/
?? box/harnesses/codex/auth.sh
?? box/harnesses/muse/auth.sh
?? box/harnesses/opencode/auth-state.py
?? box/harnesses/opencode/auth.sh
?? box/lib/auth-ops.sh
?? box/lib/auth.sh
?? box/lib/state.sh
?? box/lib/supervisor.sh
?? box/tests/bats/auth-adapters.bats
?? box/tests/bats/auth-lifecycle.bats
?? box/tests/bats/auth-migration.bats
?? box/tests/bats/auth-policy.bats
?? box/tests/bats/state.bats
?? specs/
---BRANCH---
dev
---LOG---
c85d13c Isolate test state in disposable box-test namespaces
ef808f0 fix gi
b9303c4 Merge pull request #1 from temrb/dev
5f41d33 Fixed the shared cause of both CI failures in box/lib/preflight.sh:201: early pipe closure caused `find` to report “Broken pipe.”
5751d1b Suppress shellcheck nameref false positives in lib/tools.sh
---DIFF STAT---
.gitignore | 9 +-
box/.dockerignore | 10 +++
box/Dockerfile | 13 ++-
box/Makefile | 47 ++++++++++-
box/README.md | 4 +
box/box-c | 6 ++
box/box-m | 6 ++
box/box-m-login | 4 +-
box/box-o | 6 ++
box/check-pins.sh | 11 ++-
box/docs/acceptance.md | 1 +
box/docs/adding-a-tool.md | 12 ++-
box/docs/architecture.md | 47 ++++++++++-
box/docs/harnesses.md | 6 +-
box/docs/operations.md | 70 +++++++++++++---
box/docs/security-resource-audit.md | 7 +-
box/docs/troubleshooting.md | 3 +
box/docs/upgrades.md | 16 ++++
box/harnesses/codex/README.md | 29 ++++---
box/harnesses/codex/launch.sh | 35 ++++++++
box/harnesses/codex/verify.d/40-readiness-codex.sh | 13 +++
box/harnesses/muse/README.md | 31 ++++---
box/harnesses/muse/install.sh | 16 +++-
box/harnesses/muse/launch.sh | 52 ++++++++++--
box/harnesses/muse/verify.d/40-readiness-muse.sh | 14 ++++
box/harnesses/opencode/README.md | 17 +++-
box/harnesses/opencode/capture-validation.sh | 45 ++++++----
box/harnesses/opencode/entrypoint.sh | 44 ++++++++++
box/harnesses/opencode/launch.sh | 48 +++++++++++
.../opencode/verify.d/40-readiness-opencode.sh | 14 ++++
box/lib/config-file.sh | 40 +++++++++
box/lib/install.sh | 20 +++++
box/lib/test-state.sh | 96 +++++++++++++++++++++-
box/lib/tools.sh | 58 ++++++++++---
box/setup.sh | 13 +++
box/tests/bats/helpers.bash | 9 ++
box/tests/bats/opencode-capture.bats | 25 ++++++
box/tests/bats/setup.bats | 25 ++++++
box/tests/bats/tools.bats | 38 +++++++++
box/tests/native/acceptance.sh | 21 +++++
box/tests/native/lifecycle-audit.py | 26 ++++++
box/verify-codex.sh | 13 +++
box/verify-muse.sh | 14 ++++
box/verify-opencode.sh | 14 ++++
44 files changed, 947 insertions(+), 101 deletions(-)
---DIFF NAME---
.gitignore
box/.dockerignore
box/Dockerfile
box/Makefile
box/README.md
box/box-c
box/box-m
box/box-m-login
box/box-o
box/check-pins.sh
box/docs/acceptance.md
box/docs/adding-a-tool.md
box/docs/architecture.md
box/docs/harnesses.md
box/docs/operations.md
box/docs/security-resource-audit.md
box/docs/troubleshooting.md
box/docs/upgrades.md
box/harnesses/codex/README.md
box/harnesses/codex/launch.sh
box/harnesses/codex/verify.d/40-readiness-codex.sh
box/harnesses/muse/README.md
box/harnesses/muse/install.sh
box/harnesses/muse/launch.sh
box/harnesses/muse/verify.d/40-readiness-muse.sh
box/harnesses/opencode/README.md
box/harnesses/opencode/capture-validation.sh
box/harnesses/opencode/entrypoint.sh
box/harnesses/opencode/launch.sh
box/harnesses/opencode/verify.d/40-readiness-opencode.sh
box/lib/config-file.sh
box/lib/install.sh
box/lib/test-state.sh
box/lib/tools.sh
box/setup.sh
box/tests/bats/helpers.bash
box/tests/bats/opencode-capture.bats
box/tests/bats/setup.bats
box/tests/bats/tools.bats
box/tests/native/acceptance.sh
box/tests/native/lifecycle-audit.py
box/verify-codex.sh
box/verify-muse.sh
box/verify-opencode.sh
---STAGED STAT---

Command exited with code 0.

---

## Assistant

_Thinking:_

**Tool: read**

**Input:**

```json
{
	"path": "/workspace/specs"
}
```

Read directory /workspace/specs, entries 1-1
plan.md

---

## Assistant

_Thinking:_

Seen the scope — 44 modified plus 14 new files. Now doing a deep check against all 12 plan sections.

**Tool: subagent**

**Input:**

```json
{
	"agent": "general",
	"description": "Review state resolver impl",
	"prompt": "In /workspace, review uncommitted changes (git diff + untracked files) against specs/plan.md sections 2 (Declarative state model, Resolver boundaries) and 4 (State-layout design).\n\nRead these files fully:\n- specs/plan.md sections 2 and 4\n- box/lib/tools.sh (git diff + full file for auth records)\n- box/lib/state.sh (untracked, full)\n- box/lib/test-state.sh (diff + full)\n- box/lib/auth.sh and box/lib/auth-ops.sh (untracked, full)\n- box/lib/config-file.sh diff\n\nReport:\n1. Does _BOX_STATES have exactly one auth record per harness with class=auth, scope=auth-policy, kind=bind, mode 700, runtime /run/box-auth? Quote evidence.\n2. Are box_state_context/resolve/validate/guard/cli and box_auth_* functions present with correct signatures?\n3. Do identities match R/H/uU/global and R/H/uU/projects/P layout? Is UID (not GID) the key? Are modes 700/600 enforced? Is /run/box-auth mount only object dir?\n4. Any harness-name conditionals in shared lib (violates plan)?\n5. Cleanliness issues (duplicated identity logic left, dead code, shellcheck risks).\n\nBe factual, cite file:line. Do not fix, only report."
}
```

<subagent sessionID="ses_ee867b17affe62Wv5XP0lHqGdU" state="completed">
Review of uncommitted changes vs `specs/plan.md` §§2,4. All `bash -n` pass; `shellcheck` binary absent in this env.

## 1. `_BOX_STATES` auth records — YES, exactly one per harness

`box/lib/tools.sh:91,102,113` — each harness `states` list now ends in `auth`:

- `muse,states='home volume auth'`, `opencode,states='volume config-parent auth'`, `codex,states='home volume auth'`

`box/lib/tools.sh:217,220,223`:

- `muse auth auth-policy bind .config/box/auth BOX_AUTH_ROOT /run/box-auth 700 'auth-canonical-only' auth global harnesses/muse/auth.sh 1`
- `opencode auth ... auth project harnesses/opencode/auth.sh 1`
- `codex auth ... auth project harnesses/codex/auth.sh 1`

So per record: `class=auth`, `scope=auth-policy`, `kind=bind`, `mode=700`, `runtime=/run/box-auth`, shared root `.config/box/auth`, override `BOX_AUTH_ROOT`. Fallbacks (`global`/`project`/`project`) match plan §3 table.

Enforcement in `box/lib/tools.sh:388-399,421`: auth branch checks name==`auth`, scope, kind, root, override, runtime, `default_scope ∈ {global,project}`, `adapter=="harnesses/$id/auth.sh"` + file exists, `schema==1`; non-auth branch rejects orphan auth fields (`:403`); `:421` `[[ "$auth_count" == 1 ]]` dies otherwise. Non-auth resets rewritten to `*-non-auth` (`:215-222`), auth reset is `auth-canonical-only`.

## 2. Resolver / auth functions — all present, signatures match

`box/lib/state.sh`:

- `box_state_context` `:54` — `(harness, uid, gid, project-path, production|test, [ns], [task-root])`; sets `BOX_STATE_HARNESS/UID/GID/PROJECT/HASH/DOMAIN/NS/TASK_ROOT`. Matches spec.
- `box_state_resolve` `:94` — `<state-name>` via context globals, prints `KEY=value` descriptor (`domain,harness,state,class,scope,uid,gid,project_hash,project,path,runtime,adapter,schema_version,volume`). Matches.
- `box_state_validate_descriptor` `:183` — `<descriptor-file>`, no mutation. Matches.
- `box_state_guard_operation` `:227` — `<op> <descriptor…>`, ops `migrate|copy|init|recover|reset|remove|plan`. Matches.
- `box_state_cli` `:254` — `context|resolve|validate|guard|project-hash|volume`. Spec's "machine-readable descriptor output for Python/native consumers" is satisfied; extra `project-hash|volume` subcommands are additive pure primitives (allowed by §2 test-boundary).

`box/lib/auth.sh` — all seven spec functions present:

- `box_auth_policy_resolve <harness>` `:132`, `box_auth_plan <harness> <uid> <project-hash>` `:423`, `box_auth_prepare <harness> <uid> <hash> <proj-lock> [native] [bundle] [desc]` `:612`, `box_auth_transition_plan <harness> <uid> <hash> [project-path]` `:541`, `box_auth_lease_reserve <auth-dir> <proj-lock> [proj-data]` `:325`, `box_auth_recover <auth-dir>` `:388`, `box_auth_guard_remove <auth-dir>` `:408`.
- Plus supporting extras (not spec-violating): `box_auth_valid_scope`, `config_file`, `parse_config`, `policy_source`, `root`, `index_dir`, `object_dir`, `ensure_object`, `sorted_locks`, `lease_release`, `install/collect_projection`, `migration_gate`, `binding_file`.

## 3. Layout / UID key / modes / mount

- Production layout matches §4 (`R/H/uU/global`, `R/H/uU/projects/P`): `box/lib/auth.sh:249-256` → `$rroot/$id/u$uid/global` and `$rroot/$id/u$uid/projects/$hash`; same in `box_state_resolve` `:123-130` via `box_auth_root()`.
- Test layout matches (`T/N/auth/H/uU/...`): `box/lib/test-state.sh:258-273` (`box_test_auth_dir`), mirrored by `auth.sh:239-247` test branch and `state.sh:114-121`. Three implementations of one formula — see §5 duplication.
- UID is the key: auth paths take `uid` only, never `gid` (zero `gid` refs in `auth.sh`); `box_state_resolve` auth branch uses only `BOX_STATE_UID` (`:118,120,126,128`). GID retained only in descriptor/volume names (`:175-178`, `box_state_volume_name :79`). Per §4 ("changing primary group must not create another login").
- Modes: `box_auth_ensure_object` (`auth.sh:260-310`) creates dir via `box_prepare_directory … 700` (`:269`), `chmod 600` on `identity.json/credentials.json/lease.json/lock` (`:284,294,298,302`), then `box_assert_owner_mode … dir700` + per-file `creds` checks (`:305-309`). Leaves created are exactly the §4 set (`identity.json`, `credentials.json`, `lease.json`, `lock`); journal/staging/rollback leaves live in `auth-ops.sh`. `state.sh` itself resolves only, enforces nothing — correct.
- `/run/box-auth` object-dir-only: registry declares `runtime=/run/box-auth` (`tools.sh:217,220,223,395`); no shared-lib code mounts anything (mounting is harness `launch.sh`, outside requested scope). For reference the harness adapters do mount the resolved object dir only: `box/harnesses/codex/launch.sh:115`, `muse/launch.sh:141`, `opencode/launch.sh:91` (`src=$*_auth_dir,dst=/run/box-auth,bind-recursive=disabled,bind-propagation=rprivate`). No shared-lib code mounts the shared root.

## 4. Harness-name conditionals in shared lib — one violation

- **Violation:** `box/lib/auth-ops.sh:95-112` `box_ops_legacy_source` does `case "$id" in muse) …BOX_M_PERSIST_DIR… ;; codex) …BOX_C_STATE_ROOT… ;; opencode) … ;;`. This is exactly what §2 forbids ("shared code … never branches on harness names"; legacy-source discovery should be registry/adapter-driven).
- Compliant-by-construction: `state.sh:160-170` dispatches on `root` suffix (`*/projects → …/codex-home`), not on harness name (comment at `:158-160` says so); adapter install/collect/validate/export/retire go through `box_state_field … adapter` (`auth.sh:446,469; auth-ops.sh:192`) — compliant.
- Pre-existing / out-of-scope: `box_test_codex_home` (`test-state.sh:144-149`) and `codex-home` leaf literals (`state.sh:161,169`) predate this change and are explicitly retained by §2 ("Retain PR #2's … Codex-home resolver"); `box/harnesses/*/launch.sh` per-harness files are adapters, not shared lib.

## 5. Cleanliness

- **Old identity logic not yet replaced** (§2 lists `box_project_identity`, Codex-home, Muse-home, OpenCode capture derivation as replaced): `box/lib/launcher.sh:92` still defines `box_project_identity` (hash/volume/container inline, `:119-131`) and it is still called (`:458`); `state.sh`/`auth-ops.sh` reuse only `box_state_project_hash`/`box_state_volume_name`/`box_test_volume`. New resolver coexists with old — migration incomplete.
- **Triplicated auth-dir formula:** `box_test_auth_dir` (`test-state.sh:258`), `box_auth_object_dir` (`auth.sh:232`), auth branch of `box_state_resolve` (`state.sh:114-130`), plus `box_ops_auth_dir` (`auth-ops.sh:65`) re-resolving policy+object dir a fourth way.
- **Dead / no-op code:**
  - `box_config_get_optional` (`config-file.sh:138-172`) has zero callers (`grep` finds only the definition; `box_auth_parse_config` inlines its own TOML parsing instead).
  - `test-state.sh:199-208` scope-override loop is a no-op (`[[ -z … ]] || :`, then `unset`).
  - `test-state.sh:239` `case … in BOX_AUTH_ROOT|BOX_STATE_CONFIG)` — `BOX_STATE_CONFIG` can never appear as a state `override` (state overrides are `BOX_AUTH_ROOT`/`BOX_M_PERSIST_DIR`/etc.), dead arm.
  - `auth-ops.sh:129-141` flush helper contains `os.fsync(f.fileno()) if False else None` — dead expression; only the dir `fsync` runs.
- **Fragile patterns (no shellcheck available; `bash -n` clean):**
  - `state.sh:239-246` guard uses `grep -qx/ -q` + `cut`/`grep '^path='`; line 241 `grep -q -- "$BOX_TEST_TASK_ROOT"` matches everything when the var is unset (empty pattern), silently `continue`-ing past the containment check for `domain=test` descriptors.
  - `auth.sh:333-342,378-379` `exec {BOX_AUTH_FD}>…`/`flock -n` inside a loop that only acts on one member; fds leak on mid-function `die` (no trap), and `lease_release` is the only closer.
  - `auth.sh:197,200` `grep -qx "$id\\.scope=…"` relies on BRE `\|` under `-x`; works in GNU grep but brittle and `$id` is unescaped (safe today only because ids are registry-constrained).
  - `auth.sh:567-568` `sed -n '1p/2p'` binding read; `mktemp` (`auth.sh:477`), indirect `${!var}` (`state.sh:149`, `test-state.sh:182,204`, `auth.sh:140`) — all standard for this codebase but untested by shellcheck here.
    </subagent>

**Tool: subagent**

**Input:**

```json
{
	"agent": "general",
	"description": "Review config policy impl",
	"prompt": "In /workspace, review uncommitted changes against specs/plan.md section 3 (Effective configuration matrix).\n\nRead:\n- specs/plan.md section 3\n- box/lib/auth.sh, box/lib/auth-ops.sh (full)\n- box/lib/config-file.sh (full + git diff)\n- box/lib/tools.sh auth-related parts\n- box/setup.sh diff, box/lib/install.sh diff\n- box/tests/bats/auth-policy.bats (untracked, full)\n\nReport:\n1. Are defaults muse=global, opencode=project, codex=project preserved as registry fallbacks?\n2. Is precedence exactly: harness runtime > common runtime > harness config > common config > registry fallback? Is BOX_AUTH_SCOPE, BOX_M/O/C_AUTH_SCOPE, BOX_STATE_CONFIG, BOX_AUTH_ROOT supported? Does BOX_C_AUTH remain independent?\n3. Is validation correct: accepted scopes exactly global/project, set-but-empty errors, unknown keys/harnesses error, duplicate TOML error, explicit-missing-config errors, implicit-missing ok, unsafe root errors, no sourcing as shell, validate-all-supplied-before-resolution including shadowed values?\n4. Does setup seed versioned file with no explicit scopes and preserve byte-for-byte on rerun?\n5. Cleanliness/correctness bugs with evidence file:line.\n\nBe factual, cite file:line. Do not fix."
}
```

<subagent sessionID="ses_ee867b17affdIGnHiC707671RZ" state="completed">
Review of uncommitted changes vs `specs/plan.md` §3. All citations are post-change working-tree lines.

## 1. Registry fallbacks preserved — YES

`box/lib/tools.sh:217,220,223`:

- `muse auth … auth global harnesses/muse/auth.sh 1`
- `opencode auth … auth project harnesses/opencode/auth.sh 1`
- `codex auth … auth project harnesses/codex/auth.sh 1`

Validation enforces it: `box/lib/tools.sh:388-399` (auth must be `scope=auth-policy`, `kind=bind`, `root=.config/box/auth`, `override=BOX_AUTH_ROOT`, `runtime=/run/box-auth`, `default_scope in global|project`, `adapter=harnesses/$id/auth.sh`, `schema=1`), `box/lib/tools.sh:421` (exactly one auth record), `box/lib/tools.sh:403` (non-auth must not carry orphan auth fields).

Resolver consumes it as final fallback: `box/lib/auth.sh:170-172`, `box/lib/auth.sh:178`.
Tests assert it: `box/tests/bats/auth-policy.bats:11-20`, `box/tests/bats/tools.bats:145-180`.

## 2. Precedence and runtime interface — YES, with two deviations noted in §5

Precedence in `box/lib/auth.sh:174-178` is exactly spec order:

1. harness runtime, 2. `BOX_AUTH_SCOPE`, 3. harness config, 4. common config, 5. registry fallback.

Env names derived from registry, no harness literals: `box/lib/auth.sh:136-137` (`gpfx=$(box_tool_field "$id" git_prefix); harness_var="${gpfx}_AUTH_SCOPE"`), same pattern in `box/lib/auth.sh:187-188` and `box/lib/test-state.sh:199-206`. Registry prefixes at `box/lib/tools.sh:64,81,131` (`BOX_M`, `BOX_O`, `BOX_C`) yield `BOX_M/O/C_AUTH_SCOPE`. `BOX_AUTH_SCOPE` read at `box/lib/auth.sh:141`. Config selection at `box/lib/auth.sh:39-63`: explicit `BOX_STATE_CONFIG` else implicit `~/.config/box/state.toml`. Root at `box/lib/auth.sh:209-216` (`BOX_AUTH_ROOT` else `$HOME/.config/box/auth`, absolute + comma/newline reject + `box_plan_directory` + `box_assert_project_disjoint`).

`BOX_C_AUTH` independent: nothing in `box/lib/auth.sh` or `box/lib/config-file.sh` reads `BOX_C_AUTH`; only `box/harnesses/codex/launch.sh:73` validates it as `chatgpt|api` credential-forwarding flag. Covered by `box/tests/bats/auth-policy.bats:104-110`.

Precedence combinations empirically verified (fallback, common>fallback, harness>common, harness-cfg>default, env>cfg in both layers).

Deviations: `box_auth_policy_source` returns env without validating config (`box/lib/auth.sh:190-191`), and `BOX_STATE_CONFIG=""` / `BOX_AUTH_ROOT=""` are masked by `:-` (`box/lib/auth.sh:40,210`) instead of erroring — details in §5.

## 3. Validation

- Accepted scopes exactly `global|project`: YES. `box/lib/auth.sh:32-34`, parser `box/lib/auth.sh:100-101,117`, fallback `box/lib/auth.sh:172`.
- Set-but-empty errors (scope vars): YES. `box/lib/auth.sh:164-168`; tested `box/tests/bats/auth-policy.bats:50-61`. Empirically `BOX_AUTH_SCOPE=""`, `BOX_M_AUTH_SCOPE=""`, `=everywhere` all die.
- Unknown keys/harnesses error: YES. `box/lib/auth.sh:81-84` (top), `92-95` (auth keys), `106-108` (harness id), `111-113` (per-harness keys). Tested `box/tests/bats/auth-policy.bats:75-92`.
- Wrong type / empty string error: YES. `box/lib/auth.sh:100,117` reject non-string and `""`; `default_scope=1`, `default_scope=""` tested.
- Unsupported schema error: YES. `box/lib/auth.sh:85-87` (`schema != 1` dies); tested with `schema_version = 2`.
- Duplicate TOML error: YES by implementation, NO test. Python `tomllib.load` raises `ValueError` subclass on duplicate keys, caught in `box/lib/config-file.sh:44-51` and `box/lib/auth.sh:73-80`. Empirically duplicate `default_scope` dies via `Invalid TOML configuration`. No `auth-policy.bats` case covers duplicates — coverage gap.
- Explicit-missing errors / implicit-missing ok: YES. `box/lib/auth.sh:41-54` vs `55-62`. Tested `box/tests/bats/auth-policy.bats:94-102`; empirically explicit missing dies, implicit absent resolves to fallback.
- Unsafe root errors: YES. Relative/comma rejected `box/lib/auth.sh:211`; in-project rejected via `box_plan_directory`→`box_assert_project_disjoint` (`box/lib/preflight.sh:169-175,478-504`); empirically relative, comma, in-project all die. Ancestor symlink/unwritable-owner enforced by `box_plan_directory` (`box/lib/preflight.sh:486-502`).
- Present unsafe config errors: YES for symlink/unreadable/group-writable/in-project. `box/lib/auth.sh:43,56,46-51,58-61`. Empirically symlink and `666` die, in-project `BOX_STATE_CONFIG` dies. Note `644` resolves successfully — correct by design since policy is `nowrite` (`box/lib/preflight.sh:311-327`), not `creds`; scope config is non-secret.
- No sourcing as shell: YES. Grep finds no `source`/`eval` of config values; parsing is `box_config_validate` + isolated `python3 -I tomllib` in `box/lib/auth.sh:69-124`, `box/lib/config-file.sh:138-172`.
- Validate-all-supplied-before-resolution incl. shadowed: YES for resolve path. Env loop validates both layers even when overridden (`box/lib/auth.sh:164-168`); config loop validates selected default+harness even when env overrides (`box/lib/auth.sh:155-158`); parser validates _every_ harness table eagerly (`box/lib/auth.sh:106-119`). Tested `box/tests/bats/auth-policy.bats:63-73`; empirically shadowed-bogus env, shadowed-bogus config, and other-harness-bogus all die.
  - Exception: `box_auth_policy_source` does NOT validate when env is set (returns `env:…` at `box/lib/auth.sh:190-191` without parsing config). Empirically invalid config + `BOX_AUTH_SCOPE=project` → `resolve` dies but `source` prints `env:BOX_AUTH_SCOPE rc=0`.
- No native project config sets scope: YES (vacuously). Scope comes only from env/config/registry; no reader consults `.codex/config.toml`, `settings.json`, etc.
- Resolve-before-mutation: YES for the shared path. `box_auth_prepare` (`box/lib/auth.sh:612-633`) resolves (`617`), then ensures object, transition plan, migration gate, lease reserve, projection install — no Docker/credential/lock contact before `617`.

Strictness note: `[auth.harnesses.muse]` with no `scope` key dies (`box/lib/auth.sh:115-116`). Spec says “omitted key: inherit.” If “omitted” includes empty tables, this is stricter than spec; if it means omitted table/default, behavior is correct. No bats case pins it.

## 4. Setup seeding — YES

`box/lib/install.sh:104-119` seeds `schema_version = 1\n`, mode `600`, via stage+`mv`; rerun path (`113-117`) only checks `-f` and prints `kept` with no write — byte-for-byte preservation. `box/setup.sh:249-256` calls it after `_setup_dirs` (which already includes `$HOME/.config/box` at `box/setup.sh:146` and creates it before first write), so the `Missing state-policy parent` die is unreachable in normal setup. Empirically: `created`+`600`+`box_config_validate toml` passes; rerun `sha256` identical; custom `[auth] default_scope` content preserved; symlink and missing-parent die. Tests: `box/tests/bats/setup.bats:250-273`.

## 5. Cleanliness / correctness bugs (evidence, no fix)

1. Sentinel collision `__unset__`: `box/lib/auth.sh:140-141,164-168,174-175`. `BOX_AUTH_SCOPE=__unset__` is treated as unset, skips validation, falls to fallback. Empirically `BOX_AUTH_SCOPE=__unset__ box_auth_policy_resolve muse` → `global rc=0`, should die as unknown scope.
2. `BOX_STATE_CONFIG=""` / `BOX_AUTH_ROOT=""` silently default: `box/lib/auth.sh:40` (`${BOX_STATE_CONFIG:-}`), `box/lib/auth.sh:210` (`${BOX_AUTH_ROOT:-…}`). Empirically both `rc=0` (empty config → implicit; empty root → default). Inconsistent with strict empty handling for scope vars at `box/lib/auth.sh:166`.
3. `box_auth_policy_source` skips validation when env set: `box/lib/auth.sh:190-191`. See §3 exception.
4. `jq`-absent fail-open on lease checks: `box/lib/auth.sh:345` (reserve busy check), `box/lib/auth.sh:414` (guard remove), `box/lib/auth-ops.sh:430` (reset active check) all gate on `command -v jq … && jq -e …`, so missing `jq` silently proceeds with overwrite/removal/reset. Contrast `box_auth_recover` (`box/lib/auth.sh:392`), `box_auth_collect_projection` (`box/lib/auth.sh:480`), `box_ops_publish_envelope` (`box/lib/auth-ops.sh:122`) which hard-require `jq`.
5. Dead shared validator: `box_config_get_optional` defined `box/lib/config-file.sh:138-172`, zero callers (grep finds only the definition). `box_auth_parse_config` inlines its own TOML schema instead of using it.
6. Test-harness env leak: `box/tests/bats/helpers.bash:30` unsets scope/config/root vars but not `BOX_C_AUTH` or `BOX_AUTH_TRANSITION` (read at `box/lib/auth.sh:574`). Former is harmless (independent); latter can flip transition-plan outcomes if exported in the outer environment.
7. Predictable non-atomic stage without trap: `box/lib/install.sh:110-113` uses `>"$dest.tmp.$$"` instead of `mktemp`+trap/`box_atomic_install` idiom used elsewhere in the same file; concurrent runs can interleave and failures leave stale `$dest.tmp.<pid>`.
8. Misleading lock-order helper: `box/lib/auth.sh:312-316,336-343`. Comment claims sorted deterministic acquisition, but auth lock is always taken first regardless of lexicographic order. Deadlock-free (all contenders share the order) but `box_auth_sorted_locks` is vestigial.
   </subagent>

**Tool: subagent**

**Input:**

```json
{
	"agent": "general",
	"description": "Review harness adapters",
	"prompt": "In /workspace, review uncommitted changes against specs/plan.md section 5 (Harness adaptation) and section 6 (Migration design).\n\nRead fully:\n- box/harnesses/muse/auth.sh, box/harnesses/codex/auth.sh, box/harnesses/opencode/auth.sh, box/harnesses/opencode/auth-state.py (all untracked)\n- box/harnesses/muse/launch.sh diff, box/harnesses/codex/launch.sh diff, box/harnesses/opencode/launch.sh + entrypoint.sh diffs\n- box/lib/supervisor.sh (untracked)\n- box/Makefile diff (for auth-migrate/copy/init/recover, state-plan/remove targets)\n- box/tests/bats/auth-adapters.bats, auth-migration.bats, auth-lifecycle.bats (untracked)\n\nReport:\n1. Does each adapter support validate/export/export-selection/install/collect/scrub/recover per plan? Is envelope credentials.json with harness/adapter schema, revision, payload, tombstone, no prefs/trust/approvals/sessions? Is selection stored separately (e.g. box-auth-selection.json)?\n2. Muse: is persistent-home auth-scope assertion removed? Are trust/settings excluded? Is backend qualification explicit or silently assumed?\n3. Codex: is auth.json regular-file projection (not bind/symlink)? Is logout->tombstone? Is CODEX_HOME still project-scoped?\n4. OpenCode: explicit column lists + parameterized SQL? Sessions/approvals/config excluded? Selection restore only if credential exists? No timestamp-based choice? Service stopped before collect? WAL hygiene? Legacy auth.json import disabled/quarantined? MCP endpoint identity (hash name+URL) preserved?\n5. Migration: setup performs no migration? First-live-launch refuses without migration record? Dry-run reads no credentials? Transaction journal planned->staged->committed->verified->retired->complete? Source retained until verified? No merge, no auto-populate, explicit source choice, acknowledgment fresh/use-existing/copy?\n6. Supervisor: 9-step lifecycle present? Shell runs wrapped? No docker socket?\nBe factual, cite file:line. Do not fix."
}
```

<subagent sessionID="ses_ee867b17affcNu7CXis5kuCsZI" state="completed">
Review of uncommitted changes vs `specs/plan.md` §5–§6. No fixes applied.

## 1. Adapter contract (plan §5 intro, §2 envelope)

Files: `box/harnesses/muse/auth.sh`, `box/harnesses/codex/auth.sh`, `box/harnesses/opencode/auth.sh`, `box/harnesses/opencode/auth-state.py`.

Implemented per adapter: `box_adapter_validate` / `export` / `install` / `collect` (=`export`) / `scrub` / `retire`:

- muse/auth.sh:16,26,42,57,61,70; codex/auth.sh:11,20,36,51,55,64; opencode/auth.sh:21,29,36,42,46,56.
- Missing as adapter verbs: **no `export-selection` and no `recover`** in any `auth.sh`. Selection is a separate verb only for OpenCode (`save-selection`/`restore-selection` subcommands, auth-state.py:305,338; front-end `auth.sh` does not expose them — only called from `entrypoint.sh:71,76`). Muse/Codex have no selection export at all (single-file payload assumed inseparable; not stated in code).
- Envelope shape matches plan: `{schema_version:1, harness, adapter_schema:1, revision, tombstone:bool, payload}` — muse/auth.sh:31-32,37-38; codex/auth.sh:25-26,31-32; auth-state.py:111-118,145-152; `lib/auth.sh:287-294` (fresh tombstone `revision:0`), `lib/auth-ops.sh:126,154`.
- "No prefs/trust/approvals/sessions" holds by construction, not by filtering for file harnesses: adapters copy the whole native `auth.json` verbatim (`--slurpfile p`, muse/auth.sh:37-38; codex/auth.sh:31-32). Exclusion relies on trust/settings living in sibling files the adapter never opens (muse `settings.json`/`.trust.json`, codex `config.toml`/history/SQLite — comments muse/auth.sh:2-5, codex/auth.sh:2-5). No field-level strip inside `auth.json` itself.
- Selection stored separately: only OpenCode sidecar `/persist/state/opencode/box-auth-selection.json`, keyed by auth identity — entrypoint.sh:64-67, auth-state.py:276-335. Muse/Codex: no sidecar.

## 2. Muse (plan §5 Muse)

- Persistent-home scope assertion removed: yes. `launch.sh:34-43` resolves `muse_auth_scope/dir` via `box_auth_policy_resolve`; usage text rewritten (launch.sh:15-18); `install.sh:10` drops `box_assert_native_cache "$home/auth.json"` with comment "Setup never inspects native auth."
- Trust/settings excluded: adapter never reads them; launch keeps snapshot/backup flow (launch.sh:71-94,103-123) and mounts home writable + settings snapshot read-only (launch.sh:137-139). `auth-adapters.bats:29-32` asserts sibling untouched.
- Backend qualification: **comment-only, not enforced**. muse/auth.sh:4-5 claims "file backend only; keychain-only behaviour fails explicitly," but `box_adapter_validate` (auth.sh:16-24) only checks absent-or-regular-JSON-object + `jq`. No keychain/backend detection, no pinned fixture probing, no MCP store handling. Whole-file export silently assumes file content is auth.

## 3. Codex (plan §5 Codex)

- Regular-file projection (not bind/symlink): yes. Install writes `tmp.$$` + `chmod 600` + `mv` (codex/auth.sh:46-48); validate/export reject symlinks/non-regular (codex/auth.sh:15,30); launch mounts the whole home dir (launch.sh:112), never a file bind of `auth.json`.
- Logout→tombstone: yes. Absent native exports `{tombstone:true,payload:null}` (codex/auth.sh:24-29); `collect=export` (codex/auth.sh:51-53); host collect path `lib/auth.sh:461-493` commits it with bumped revision then scrubs.
- `CODEX_HOME` still project-scoped: yes. `launch.sh:40-47` (`$state_root/$project_hash/codex-home`, test `<task-root>/<ns>/codex-home`), mounted at `/home/box/.codex`, `CODEX_HOME=/home/box/.codex` (launch.sh:112,116). Canonical auth is the separate `$codex_auth_dir` mounted at `/run/box-auth` (launch.sh:19-28,115).
- Trust/transcripts preserved: `config.toml` trust-subtree rewrite kept (launch.sh:81-87) with comment "regardless of scope."

## 4. OpenCode (plan §5 OpenCode)

- Explicit column lists + parameterized SQL: yes. `CREDENTIAL_COLUMNS` allowlist (auth-state.py:28-37); SELECT builds from allowlist∩live cols with quoted identifiers (auth-state.py:83-90); INSERT uses `?` placeholders (auth-state.py:226-234); `UPDATE ... WHERE "id"=?` (auth-state.py:238,356). Column names are interpolated (unavoidable), values are bound.
- Sessions/approvals/config excluded: yes. Only `credential` table is SELECT/DELETE/INSERT (auth-state.py:82-104,223,262); `session`/`approval` fixtures asserted unchanged in `auth-adapters.bats:64-83`.
- Selection restore only if credential exists: yes. `restore-selection` updates `active=1 WHERE id=?` and warns/leaves unselected on `rowcount==0` (auth-state.py:354-359); install forces `active=0` (auth-state.py:235-238).
- No timestamp choice: yes. `save-selection` records active only when exactly one `active=1` row (auth-state.py:314-320, comment "never by timestamps"); else key removed.
- Service stopped before collect: partial. Container entrypoint `pkill -f 'opencode.*serve'` before install (entrypoint.sh:60) and again in EXIT trap before `save-selection`+`collect` (entrypoint.sh:75). Host `launch.sh:54-73` does not stop anything — collect is container-side; host `opencode_cleanup` trap is an intentional no-op comment.
- WAL hygiene: partial. Helper sets `journal_mode=WAL` + `busy_timeout` (auth-state.py:40-44), consistent `BEGIN IMMEDIATE/COMMIT/ROLLBACK` (auth-state.py:129-141,220-246,260-270); entrypoint guards `.db/-wal/-shm` owner/mode/writability (entrypoint.sh:14-21). No explicit checkpoint; no concurrent-edit guard beyond lease + pkill.
- Legacy `auth.json` import disabled/quarantined: **not implemented**. No reference to legacy `auth.json`/quarantine in `entrypoint.sh`, `auth.sh`, `auth-state.py` (grep finds only `.box-legacy` preference backups, entrypoint.sh:34-39). `box_adapter_retire` for OpenCode is unconditional no-op success (opencode/auth.sh:52-59) with rationale "never the live importer path."
- MCP endpoint identity (hash name+URL): **not verified**. `integration` column is passed through opaquely (auth-state.py:28-37,73,179,194); no name+URL hash check or MCP-specific branch.

## 5. Migration (plan §6)

- Setup performs no migration: yes. `harnesses/muse/install.sh:10-24` only plans home + seeds `state.toml`; `setup.sh:250-251` comment "setup never migrates login material."
- First-live-launch refuses without migration record: **partial**. Muse (`launch.sh:97-99`) and Codex (`launch.sh:94`) call `box_auth_migration_gate` (non-reading presence check + refuse, `lib/auth.sh:499-517`). **OpenCode `launch.sh:54-73` never calls `box_auth_migration_gate`** — only `ensure_object` + `transition_plan` + `lease_reserve`; comment says "Volume-backed legacy gate uses non-secret metadata only" but no gate call.
- Dry-run reads no credentials: yes for auth planning. `box_auth_plan` (lib/auth.sh:423-436) and all three launch dry-run blocks (muse/launch.sh:64-68, codex/launch.sh:51-55, opencode/launch.sh:37-41) print scope/source/dir/projection only. Note: OpenCode still runs `box_load_credentials` for `providers.env` (launch.sh:51) — unrelated external key file, not the SQLite DB; DB is never opened on dry-run.
- Journal `planned→staged→destination-committed→verified→source-retired→complete`: exact strings match plan §6 (auth-ops.sh:8,36-37,199-221 for migrate; 252-264 for copy which skips retire stages and ends at `complete`).
- Source retained until verified: yes for migrate — export→stage→publish→re-`validate`→`verified`→`retire` (auth-ops.sh:199-211); rollback copy kept at `$dir/rollback-credentials.json` (auth-ops.sh:204) and legacy moved to `$dir/legacy-auth-rollback.json` (via `box_adapter_retire`). Copy preserves source, refuses differing destination (auth-ops.sh:142-152,260-264).
- No merge / no auto-populate / explicit source / ack `fresh|use-existing|copy`: yes. No project enumeration; `box_ops_copy` requires explicit src/dst identities and rejects identical or differing-occupied dst (auth-ops.sh:228-248,260); `box_ops_guard_test_domain` blocks test↔prod mixing (auth-ops.sh:50-60); `box_auth_transition_plan` auto-records first binding then requires `BOX_AUTH_TRANSITION=fresh|use-existing` or explicit copy (lib/auth.sh:541-599). `auth-migrate/copy/init/recover`, `state-plan/remove`, `project-reset` targets exist (Makefile diff `+47`).
- Gap: copy journal omits `source-retired` (correct — source preserved) but also `publish` conflict path silently returns 0 on identical payload (auth-ops.sh:147-151).

## 6. Supervisor (plan §5 Shared wrapper)

`box/lib/supervisor.sh` (untracked, 109 lines):

- Steps present in-code: (1) validate reservation+identity (`box_supervisor_validate`, :28-36, harness+schema+`active`); (4) install (:41-48); (5) run+reap (`box_supervisor_run` runs `$@`, :96-109 — "reap" is caller-trap obligation per comment :92-94); (6) export incl. logout (:57-74); (7) atomic commit w/ revision bump (:69-74); (8) scrub (:75); (9) mark idle (:76-88). No Docker socket references anywhere in supervisor or mounts (grep empty).
- Steps (2) deterministic lock acquisition and (3) "record preparation before modifying native auth" are **host-side, not in supervisor**: `box_auth_lease_reserve` + sorted locks (lib/auth.sh:325-359), `box_auth_prepare` (lib/auth.sh:612-633). Supervisor comment (:9-15) acknowledges this split (host file harnesses via launcher EXIT trap; OpenCode via entrypoint).
- Shell runs wrapped: yes by placement. Muse/Codex install/reserve/collect traps are installed for all live runs before `box_launch_epilogue`, and tail functions only switch entrypoint for `shell_mode` (muse/launch.sh:95-118,147-175; codex/launch.sh:91-110,124-135). OpenCode shell goes through the same entrypoint trap (`BOX_OPENCODE_SHELL=1` branch after trap, entrypoint.sh:72-89).
  </subagent>

**Tool: subagent**

**Input:**

```json
{
	"agent": "general",
	"description": "Review tests docs lifecycle",
	"prompt": "In /workspace, review uncommitted changes against specs/plan.md sections 7,8,9,10,12 (sequence, test plan, docs/UX, compat, DoD).\n\nRead:\n- specs/plan.md sections 7-10,12\n- git diff for box/Dockerfile, box/lib/run.sh (if changed), box/lib/docker.sh (if changed), box/harnesses/opencode/capture-validation.sh, box/harnesses/*/verify.d/*, box/tests/native/acceptance.sh, box/tests/native/lifecycle-audit.py, box/verify-*.sh, box/Makefile, box/docs/*, box/box-m box/box-o box/box-c box/box-m-login\n- box/tests/bats/state.bats, auth-*.bats, tools.bats/setup.bats/opencode-capture.bats diffs\n- box/.dockerignore, box/check-pins.sh diffs\n\nReport:\n1. Phase ordering violations? Is migration enabled before adapters qualified (plan requires checkpoint)?\n2. Do existing tests still equate home/volume scope with auth scope (plan forbids)?\n3. Capture always in fresh disposable namespace? Verification fragments adapter-aware? gen-verify consistency?\n4. Dry-run reports domain/scope/source/identity/canonical/projection/non-auth/migration-requirement without secrets, no Docker/auth inspection/side-effects?\n5. Lifecycle contract: reset default removes project auth only, --keep-auth retains, global never removed, refuse on active lease, full removal inventories inactive scopes/custom roots/rollbacks? Code-only uninstall preserves?\n6. Backward-compat items 1-12 preserved? Old images rejected? Rollback copies outside importer paths?\n7. Cleanliness: generated files hand-edited vs regenerated? .dockerignore/Makefile/pins consistency? Docs consistency?\nBe factual, cite file:line. Do not fix."
}
```

<subagent sessionID="ses_ee867b175ffe8ayMl4FWWJypzn" state="completed">
Review of uncommitted changes vs `specs/plan.md` §§7,8,9,10,12. All citations are current-worktree paths.

## 1. Phase ordering (plan §7) — migration enabled in the same changeset as adapters, no checkpoint gate

- The single uncommitted changeset simultaneously adds: adapters (`box/harnesses/muse/auth.sh`, `box/harnesses/codex/auth.sh`, `box/harnesses/opencode/auth.sh`, `box/harnesses/opencode/auth-state.py`), registry/config (`box/lib/tools.sh`, `box/lib/config-file.sh`, `box/lib/auth.sh`), descriptors (`box/lib/state.sh`), lease/supervisor (`box/lib/supervisor.sh`), launch integration (all three `harnesses/*/launch.sh` + `harnesses/opencode/entrypoint.sh`), migration/lifecycle ops (`box/lib/auth-ops.sh`, `box/Makefile` `auth-migrate/auth-copy/auth-init/auth-recover/state-plan/state-remove/project-reset`), capture/verify/native (`capture-validation.sh`, `verify.d/40-readiness-*`, `tests/native/acceptance.sh`, `lifecycle-audit.py`), and docs. Phases 1–7 of §7 land atomically; there is no staged checkpoint.
- Live migration enforcement is active now, not gated: `box/harnesses/muse/launch.sh:97-101`, `box/harnesses/codex/launch.sh:92-96`, `box/harnesses/opencode/launch.sh:59-65` call `box_auth_ensure_object` + `box_auth_transition_plan` + (`box_auth_migration_gate` for file harnesses) + `box_auth_lease_reserve` + projection install on every live run. Plan §7 Phase 1 checkpoint requires "no production migration or scope support is enabled until pinned adapters pass synthetic native import/export/logout tests" and Muse backend uncertainties resolved first — this tree enables it unconditionally.
- Adapter qualification itself is synthetic-only so far: `box/docs/acceptance.md:65` records the new `auth-*`/`state` Bats as "synthetic credentials prove storage mechanics only; real login/refresh/logout/model/resume need dedicated test accounts". Account-dependent gates remain UNMET per the same file, consistent with plan §11 risk 9, but the code does not enforce the Phase 1 gate (nothing blocks live migration on unqualified backends).

## 2. Existing tests still equate home/volume scope with auth scope (plan §8 forbids)

- Plan §8: "Do not retain tests that equate 'Muse home is global' with 'auth must be global,' or 'OpenCode volume is project-scoped' with 'auth must be project-scoped.'"
- `box/tests/bats/live-defaults.bats:66-107` is unmodified and now contradicts the new model: it writes `{"synthetic":"auth"}` to `$BOX_M_PERSIST_DIR/auth.json` (`:76`) and asserts byte-preservation after launch (`:107`), treating the home `auth.json` as durable auth. Under the new launcher the same path is a temporary projection (`box/harnesses/muse/launch.sh:53-54`, `:97-101` install/collect/scrub), and the live path with a non-empty legacy `auth.json` and no `migration.json` now hits `box_auth_migration_gate` (`box/lib/auth.sh:499-517`) and dies — the test's stubbed `box_docker_cli/box_docker_exec` harness (`live-defaults.bats:89-94`) was written before the gate existed and is not updated.
- No diff touches `live-defaults.bats`, `launchers.bats` dry-run shape tests, `opencode-v2.bats`, or `config.bats` for the §8 rewrites (workspace-vs-resolver identity, supervised entrypoint, mixed-DB-remains-project-scoped + projection lifecycle). New coverage was added alongside (`auth-policy/auth-lifecycle/auth-migration/auth-adapters/state.bats`), but the old assertions were retained as-is.

## 3. Capture, verification fragments, gen-verify (plan §7 Phase 7)

- Capture: PASS (with one note). `box/harnesses/opencode/capture-validation.sh:61-80` now mints a fresh disposable task root + namespace (`mktemp -d $HOME/.box-capture.*`, `box_test_new_ns`) outside test mode, forces `BOX_TEST_REAL_HOME/BOX_TEST_TASK_ROOT/BOX_TEST_STATE_NS` (`:140`), resolves the volume only through the disposable resolver (`:81`), and the EXIT trap removes only the capture's own sub-namespace volume via `box_test_guard_cleanup` (`:92-100`, now `|| return 1`) plus the owned task root (`:119-121`). New `box/tests/bats/opencode-capture.bats` test asserts a fresh `t-[12hex]` namespace, root under `$HOME/.box-capture.*`, `BOX_TEST_REAL_HOME=$HOME`, and no `$HOME/.config/box/auth` creation. Note: the non-test scratch parent changed from `$HOME` to the disposable root — intended per §7 ("must not consume global auth merely to inspect configuration").
- Verification fragments are adapter-aware: each `harnesses/*/verify.d/40-readiness-*.sh` appends a `/run/box-auth` object-dir-only mount check plus `identity.json` (harness + schema 1), `lease.json` active, and `credentials.json` envelope shape via `jq`, values withheld. OpenCode's comment correctly notes the DB stays project-scoped with only credential rows projected.
- `gen-verify` consistency: PASS. `bash box/gen-verify.sh --check` returns `PASS (verify-*.sh match verify.d/ output)`; the `verify-*.sh` diffs are exactly the new partial blocks, i.e. regenerated, not hand-diverged.

## 4. Dry-run (plan §§6,9 + §12 DoD)

What dry-run does right:

- All three launchers print `Execution domain / Auth scope / Auth policy source / Canonical auth directory / Native projection / Non-auth home|volume` with no secret values (`box/harnesses/muse/launch.sh:64-68`, `box/harnesses/codex/launch.sh:51-55`, `box/harnesses/opencode/launch.sh:37-42`). `box_load_credentials` early-returns on dry-run (`box/lib/preflight.sh:463`), `box_docker_cli` returns before mutation/contact on dry-run (`box/lib/docker.sh:70`), and auth/health asserts are live-only (`muse:70`, `codex:57`). `box_auth_policy_resolve/object_dir` use `box_plan_directory` (no creation), no locks/writes/DB opens on the dry-run path.
- `box_auth_policy_source` (`box/lib/auth.sh:183-205`) and UID-keyed, harness-separated object dirs (`box/lib/auth.sh:232-258`) match the §9 metadata list.

Gaps vs §9/§6:

- Dry-run does **not** report the migration/transition requirement. Plan §9 requires dry-run to report "migration/transition requirement based on non-secret metadata", and §6 requires "dry-run reports the prospective new location and legacy candidate coordinates without reading credential files". The migration gate (`box_auth_migration_gate`, `box_auth_transition_plan`) runs only inside `if (( ! dry_run ))` (`muse:82ff`, `codex:74ff`, `opencode:54ff`); the dry-run output has no legacy-coordinate or transition-required line, and `box_ops_plan` (`box/lib/auth-ops.sh:350-366`) likewise omits it.
- OpenCode live path has no `box_auth_migration_gate` call at all (only a comment at `opencode/launch.sh:61-62` that the DB "is opened only by explicit migration"); file harnesses gate on `auth.json` presence (`box/lib/auth.sh:504-514`), but the volume-backed legacy gate is metadata-only by design and never surfaces in dry-run.

## 5. Lifecycle contract (plan §9 table + reset/full-removal rules)

Correct:

- Reset default removes project auth only; `--keep-auth` retains; global never removed; refuses on active lease: `box/lib/auth-ops.sh:429-438` (active-lease refusal when `!keep_auth && scope==project`), `box_ops_remove_auth:383-384` refuses global-as-project removal, `box_auth_guard_remove:408-418` requires exact identity files, rejects globs, refuses active leases. Reset inventory prints exact descriptors and only deletes with `--execute` (`:440-447`).
- Rollback copies are inventoried alongside the identity (`:391-398` lists `migration.json`, `migration-journal.json`, `rollback-credentials.json`, `legacy-auth-rollback.json`).

Gaps:

- "Full removal must include inactive scopes, custom roots, rollback copies, and recovery projections — not merely the currently effective auth identity." `state-remove` (`box_ops_remove_auth:372-404`) inventories **only the currently effective scope's single directory**; there is no inactive-scope sweep, no `BOX_AUTH_ROOT`/custom-root enumeration, no `state-index`/`bindings`/lease-projection sweep, and no explicit global-identity removal path (global effective scope hard-dies at `:383-384`). Recovery projections outside the one `lease.json` coordinate are not inventoried.
- "Refuse reset when an active/unrecovered projection depends on the target": enforced for the file-harness project-auth case (`:429-433`), but when `scope==global` reset silently retains (`:438`) without checking whether the global lease is active — correct to never remove, but the "refuse" vs "retain-and-proceed" distinction for a busy global identity is undocumented in code.
- Code-only uninstall preserves: `box/setup.sh` preserves the state policy byte-for-byte (`box/lib/install.sh:box_install_state_policy`, `setup.sh:249-256`) and the package install only refreshes code (`setup.sh:219-244`); docs (`box/docs/operations.md:294-304`) state code-only uninstall retains stores. There is no `uninstall` Make target to audit (grep finds none), so the "full removal inventories…" operator path is docs-only plus the partial `state-remove`/`project-reset`.

## 6. Backward-compat items 1–12 (plan §10)

- (1) Fallback scopes preserved: `box/lib/tools.sh:211-219` (`muse auth default_scope=global`, `opencode/codex=project`); asserted in `tools.bats` and `auth-policy.bats:12-14`. PASS.
- (2) Production volume names preserved: `box/lib/state.sh:79-87` keeps `<prefix>-u<uid>-g<gid>-<hash>`; `state.bats` asserts `box-m/box-o-v2/box-c` formulas. PASS.
- (3) Codex home formulas + root aliases preserved: `box/harnesses/codex/launch.sh:22-42` keeps `BOX_C_STATE_ROOT`/`BOX_C_STATE_DIR` agreement check and `$root/$hash/codex-home`. PASS.
- (4) Muse non-auth global home + trust lifecycle: home record stays `global bind` (`tools.sh:215`), trust rewrite path retained in launch; reset wording changed to `global-settings-trust-non-auth`. PASS (modulo item 2's test lag).
- (5) OpenCode v2 DB + preference lifecycle: entrypoint still guards WAL/SHM/modes before projection (`entrypoint.sh` pre-existing block untouched); credential rows only via adapter. PASS.
- (6) "Introduce auth configuration/descriptors before enabling migration": VIOLATED in ordering terms — config/descriptors and migration enablement ship in one changeset (see §1); no sequencing enforcement.
- (7) Explicit migration required: PASS for file harnesses via gate (`box/lib/auth.sh:513-515`); OpenCode requires explicit `--db-path` export (`auth-ops.sh:107`), never auto-opens a volume. PASS.
- (8) Rollback copies outside importer paths: PASS. `rollback="$dir/rollback-credentials.json"` (`auth-ops.sh:203-204,258-259`) and `box_adapter_retire … "$dir/legacy-auth-rollback.json"` (`:210`) live in the auth object; OpenCode `retire` is a documented no-op since the source is an explicit export copy (`harnesses/opencode/auth.sh:box_adapter_retire`).
- (9) Migration + tombstone records: PASS. `migration.json` (`auth-ops.sh:212-220,283-290`), journal stages `planned→…→complete` (`:36-37`), tombstone envelopes in all three adapters.
- (10) "Reject older images lacking the supervisor/adapter contract, including explicit image overrides": MISSING. No launcher-side image label/digest or supervisor-presence check was added; `box_launch_prologue` still resolves tags from version files only. The `/run/box-auth` + supervisor checks run **inside** the new image (`verify.d` fragments, `entrypoint.sh:48-56`); an old image or `BOX_*_IMAGE` override bypasses them silently. `box/docs/upgrades.md:54` only says "use no image override for acceptance".
- (11) "Require stopped old clients before migration; old launchers must not continue writing legacy auth": MISSING in code. `box_ops_migrate` (`auth-ops.sh:163-223`) validates descriptors, lease idleness, schema, destination conflict, and journals — but never checks for running/stopped containers or old-client writes. `docs/upgrades.md` auth-rollout paragraph describes the policy without an enforcement hook.
- (12) Code-only uninstall state-preserving: PASS per setup/policy-preservation (see §5).

## 7. Cleanliness

- Generated vs hand-edited: CLEAN. `gen-verify.sh --check` passes; `verify-*.sh` diffs equal the `verify.d` partial additions. Per plan, partials were hand-edited and outputs regenerated.
- `.dockerignore` / `Makefile` / pins: CONSISTENT with one breadth note. `box/.dockerignore` adds `!harnesses/opencode/auth.sh`, `!harnesses/opencode/auth-state.py`, `!harnesses/muse/`, `!harnesses/codex/auth.sh`, `!lib/` + `!lib/supervisor.sh`, matching the new `COPY` lines in `box/Dockerfile` (supervisor + per-harness adapter + `auth-state.py`, plus `python3` for Muse). `box/check-pins.sh` now enforces the `lib/` exception is exactly those two lines. Note `!harnesses/muse/` allowlists the whole Muse harness dir (broader than the single `auth.sh` COPY), whereas the opencode/codex exceptions are file-scoped — works but is looser than the stated "only entrypoint/archive/policy/supervisor inputs" intent.
- `Makefile` targets (`auth-migrate/auth-copy/auth-init/auth-recover/state-plan/state-remove/project-reset`) all route through the single `lib/auth-ops.sh` entrypoint with required-arg guards — matches §6's "one shared operational entrypoint".
- Docs consistency: mostly consistent (architecture §3a, operations §9a, upgrades auth-rollout, troubleshooting lease/migration rows, all three harness READMEs, harnesses index, acceptance synthetic row, `box-m-login` help). One leftover vs §7 Phase 6 ("replace inline hash/name reconstruction with resolver output"): `box/docs/operations.md:253-270` retains the old inline `sha256sum`/volume/home reconstruction snippet and merely appends "Prefer the resolver-backed inventory (`state-plan`)" — old authority not removed.

</subagent>

---

## Assistant

_Thinking:_

Synthesizing final answer by checking implementation against specs, weighing verification options like static checks vs tests, and citing evidence with gaps.

Reviews are in — now verifying the critical gaps directly before reporting.

**Tool: shell**

**Input:**

```json
{
	"command": "git diff -- box/harnesses/opencode/launch.sh | head -n 120; echo \"===AUTH-SH-GREP===\"; grep -n \"migration_gate\\|ensure_object\\|transition_plan\" box/harnesses/*/launch.sh box/lib/auth.sh | head -n 30",
	"workdir": "/workspace"
}
```

diff --git a/box/harnesses/opencode/launch.sh b/box/harnesses/opencode/launch.sh
index f067368..29b8789 100644
--- a/box/harnesses/opencode/launch.sh
+++ b/box/harnesses/opencode/launch.sh
@@ -24,6 +24,22 @@ set -- "${launcher_rest[@]}"

box_launch_prologue opencode

+# Auth scope is declarative (registry + policy). The mixed SQLite database
+# stays project-scoped on /persist; canonical auth lives in the resolved
+# object and is projected via the SQLite adapter (container-side).
+opencode_auth_scope=$(box_auth_policy_resolve opencode)
+opencode_auth_source=$(box_auth_policy_source opencode)
+if [["$opencode_auth_scope" == global]]; then

- opencode_auth_dir=$(box_auth_object_dir opencode global "$host_uid")
  +else
- opencode_auth_dir=$(box_auth_object_dir opencode project "$host_uid" "$project_hash")
  +fi
  +if ((dry_run)); then
- printf 'Execution domain: %s\n' "$([ -n "${BOX_TEST_STATE_NS:-}" ] && printf 'test' || printf 'production')"
- printf 'Auth scope: %s\nAuth policy source: %s\nCanonical auth directory: %s\nNative projection: volume %s (/persist/data/opencode/opencode/opencode.db)\nNon-auth volume: %s\n' \
- "$opencode_auth_scope" "$opencode_auth_source" "$opencode_auth_dir" "$volume" "$volume"
  +fi
- # Parse literal KEY=value entries; never source the credentials file.
  # Duplicate keys are rejected before any credentials are exported.
  # Shared providers file (see setup.sh); fail-closed except --dry-run.
  @@ -35,12 +51,44 @@ credentials=${BOX_O_ENV_FILE:-$HOME/.config/box/providers.env}
  box_load_credentials "$credentials" "$dry_run" $BOX_CRED_KEYS
  # Prepare the isolated CLI only after read-only credential validation.
  box_docker_cli "$HOME/.config/$(box_tool_field opencode config_dir)/docker-cli"
  +if (( ! dry_run )); then
- # Canonical auth object + lease. The SQLite projection itself is installed
- # and collected inside the container (entrypoint) where /persist is
- # available; the host only reserves the identity and mounts it at
- # /run/box-auth. Selection sidecars stay in project state.
- box_auth_ensure_object "$opencode_auth_dir" opencode "$opencode_auth_scope" "$host_uid" "$project_hash"
- box_auth_transition_plan opencode "$host_uid" "$project_hash" "$project"
- # Volume-backed legacy gate uses non-secret metadata only; the database is
- # opened only by explicit migration, never by ordinary launch planning.
- \_opencode_index=$(box_auth_index_dir) || die 'Cannot resolve auth index.'
- box_prepare_directory "$\_opencode_index/locks" 700 >/dev/null
- box_auth_lease_reserve "$opencode_auth_dir" "$\_opencode_index/locks/$volume.lock" "volume:$volume"
- unset \_opencode_index
- opencode_cleanup() {
- local rc=$?
- if [[-n "${opencode_auth_dir:-}" && -f "$opencode_auth_dir/lease.json"]] && grep -q '"state":"active"' -- "$opencode_auth_dir/lease.json" 2>/dev/null; then
-      # Container collected and scrubbed; host marks idle. If the container
-      # died before collection the lease stays active for recovery.
-      # Best-effort: a missing projection during recovery is an error, never
-      # permission to restore stale credentials (checked in recover).
-      :
- fi
- return "$rc"
- }
- # NOTE: the entrypoint owns collection/scrub inside the container; the host
- # trap below only preserves the lease on interrupt. Idle marking happens
- # after successful container collection (see entrypoint).
- trap 'exit 130' INT
- trap 'exit 143' TERM
- trap 'exit 129' HUP
  +fi

launch_mounts=(--env XDG_CONFIG_HOME=/persist/config
--mount "type=bind,src=$project,dst=/workspace,bind-recursive=disabled,bind-propagation=rprivate"

# Client preferences are writable siblings in the per-project v2 volume.

--mount "type=volume,src=$volume,dst=/persist"
   --mount "type=bind,src=$config,dst=/persist/config/opencode/opencode.json,readonly"

- --mount "type=bind,src=$opencode_auth_dir,dst=/run/box-auth,bind-recursive=disabled,bind-propagation=rprivate"
   --env "GIT_AUTHOR_NAME=$identity_name" --env "GIT_COMMITTER_NAME=$identity_name"
   --env "GIT_AUTHOR_EMAIL=$identity_email" --env "GIT_COMMITTER_EMAIL=$identity_email"
   --env GIT_CONFIG_GLOBAL=/dev/null --env GIT_CONFIG_NOSYSTEM=1
===AUTH-SH-GREP===
box/harnesses/codex/launch.sh:92:  box_auth_ensure_object "$codex_auth_dir" codex "$codex_auth_scope" "$host_uid" "$project_hash"
box/harnesses/codex/launch.sh:93:  box_auth_transition_plan codex "$host_uid" "$project_hash" "$project"
  box/harnesses/codex/launch.sh:94: box_auth_migration_gate codex "$codex_auth_dir" "$codex_home/auth.json" "$codex_auth_dir/migration.json"
box/harnesses/muse/launch.sh:97:box_auth_ensure_object "$muse_auth_dir" muse "$muse_auth_scope" "$host_uid" "$project_hash"
box/harnesses/muse/launch.sh:98:box_auth_transition_plan muse "$host_uid" "$project_hash" "$project"
  box/harnesses/muse/launch.sh:99:box_auth_migration_gate muse "$muse_auth_dir" "$muse_persist_dir/auth.json" "$muse_auth_dir/migration.json"
box/harnesses/opencode/launch.sh:59:  box_auth_ensure_object "$opencode_auth_dir" opencode "$opencode_auth_scope" "$host_uid" "$project_hash"
box/harnesses/opencode/launch.sh:60:  box_auth_transition_plan opencode "$host_uid" "$project_hash" "$project"
  box/lib/auth.sh:263:# Usage: box_auth_ensure_object <dir> <harness> <scope> <uid> [hash]
  box/lib/auth.sh:264:box_auth_ensure_object() {
  box/lib/auth.sh:498:# Usage: box_auth_migration_gate <harness> <auth-dir> <legacy-native-path> <migration-record>
  box/lib/auth.sh:499:box_auth_migration_gate() {
  box/lib/auth.sh:540:# Usage: box_auth_transition_plan <harness> <uid> <project-hash> [project-path]
  box/lib/auth.sh:541:box_auth_transition_plan() {
  box/lib/auth.sh:623: box_auth_ensure_object "$dir" "$id" "$scope" "$uid" "$hash" || return 1
box/lib/auth.sh:624:  box_auth_transition_plan "$id" "$uid" "$hash" || return 1
  box/lib/auth.sh:626: box_auth_migration_gate "$id" "$dir" "$native" "$dir/migration.json" || return 1

Command exited with code 0.

---

## Assistant

_Thinking:_

**Tool: shell**

**Input:**

```json
{
	"command": "grep -n \"__unset__\\|BOX_STATE_CONFIG:-\\|BOX_AUTH_ROOT:-\\|command -v jq\" box/lib/auth.sh box/lib/auth-ops.sh | head -n 20\necho \"---LEGACY-SOURCE---\"\nsed -n '95,112p' box/lib/auth-ops.sh\necho \"---LIVE-DEFAULTS---\"\nsed -n '66,107p' box/tests/bats/live-defaults.bats",
	"workdir": "/workspace"
}
```

box/lib/auth.sh:40: local explicit=${BOX_STATE_CONFIG:-} implicit="$HOME/.config/box/state.toml"
box/lib/auth.sh:140: if [[-n "${!harness_var+x}"]]; then harness*val=${!harness_var}; else harness_val=__unset__; fi
box/lib/auth.sh:141:  if [[ -n "${BOX_AUTH_SCOPE+x}" ]]; then common_val=$BOX_AUTH_SCOPE; else common_val=__unset__; fi
box/lib/auth.sh:143:  local cfg_default=__unset__ cfg_harness=__unset__
box/lib/auth.sh:156:      [[ "$val" == **unset** || -z "$val" ]] && continue
box/lib/auth.sh:165:    [[ "$val" == **unset** ]] && continue
box/lib/auth.sh:174: if [["$harness_val" != __unset__]]; then printf '%s' "$harness_val"; return 0; fi
box/lib/auth.sh:175:  if [[ "$common_val" != **unset** ]]; then printf '%s' "$common_val"; return 0; fi
box/lib/auth.sh:176:  if [[ "$cfg_harness" != **unset** && -n "$cfg_harness" ]]; then printf '%s' "$cfg_harness"; return 0; fi
box/lib/auth.sh:177: if [["$cfg_default" != __unset__ && -n "$cfg_default"]]; then printf '%s' "$cfg_default"; return 0; fi
box/lib/auth.sh:210:  local raw=${BOX_AUTH_ROOT:-$HOME/.config/box/auth}
box/lib/auth.sh:345:  if command -v jq >/dev/null 2>&1 && jq -e '.state == "active"' -- "$auth_dir/lease.json" >/dev/null 2>&1; then
box/lib/auth.sh:392: command -v jq >/dev/null 2>&1 || die 'jq is required for auth recovery.'
box/lib/auth.sh:414: if command -v jq >/dev/null 2>&1 && jq -e '.state == "active"' -- "$auth_dir/lease.json" >/dev/null 2>&1; then
box/lib/auth.sh:480:  command -v jq >/dev/null 2>&1 || die 'jq is required for auth collection.'
box/lib/auth.sh:510:  if [[ -f "$auth_dir/credentials.json" ]] && command -v jq >/dev/null 2>&1; then
box/lib/auth.sh:585: if [[-f "$dir/credentials.json"]] && command -v jq >/dev/null 2>&1; then
box/lib/auth-ops.sh:122: command -v jq >/dev/null 2>&1 || die 'jq is required for auth migration.'
box/lib/auth-ops.sh:188: if command -v jq >/dev/null 2>&1 && jq -e '.state == "active"' -- "$dir/lease.json" >/dev/null 2>&1; then
box/lib/auth-ops.sh:245:  if command -v jq >/dev/null 2>&1; then
---LEGACY-SOURCE---
  case "$id" in
muse)
home=${BOX_M_PERSIST_DIR:-$HOME/.config/box-m/muse-config}
[["$home" == /*]] || die 'Invalid Muse persist dir.'
printf '%s/auth.json' "$(box_plan_directory "$home")"
return 0 ;;
codex)
root=${BOX_C_STATE_ROOT:-${BOX_C_STATE_DIR:-$HOME/.config/box-c/projects}}
      [[ "$root" == /* ]] || die 'Invalid Codex state root.'
printf '%s/%s/codex-home/auth.json' "$(box_plan_directory "$root")" "$hash"
      return 0 ;;
    opencode)
      [[ -n "$db" ]] || die 'OpenCode migration needs an explicit --db-path export of the v2 project database (never auto-opens a live volume).'
[["$db" == /_]] || die 'OpenCode --db-path must be absolute.'
printf '%s' "$db"
      return 0 ;;
    *) die 'Internal error: unknown harness.' ;;
  esac
---LIVE-DEFAULTS---
@test "Muse launch snapshots refresh defaults preserve auth and clean up independently" {
  export BOX_M_CONFIG="$TEST_TMP/defaults.json"
export BOX_M_VERSION_FILE="$BUNDLE_DIR/harnesses/muse/version-muse.env"
  export BOX_M_ENV_FILE="$TEST_TMP/providers.env"
export BOX_M_PERSIST_DIR="$TEST_TMP/muse-home"
  cp "$BUNDLE_DIR/harnesses/muse/config/settings.json" "$BOX_M_CONFIG"
  : > "$BOX_M_ENV_FILE"
chmod 600 "$BOX_M_ENV_FILE"
  mkdir -m 700 "$BOX_M_PERSIST_DIR"
printf '{"model":"legacy"}' > "$BOX_M_PERSIST_DIR/settings.json"
  printf '{"synthetic":"auth"}' > "$BOX_M_PERSIST_DIR/auth.json"
chmod 600 "$BOX_M_PERSIST_DIR/auth.json"
  printf 'trust fixture' > "$BOX_M_PERSIST_DIR/.trust.json"
mkdir -p "$TEST_PROJ/.muse"
  printf '{"endpoint_transport":{"base_url":"https://evil.example"},"tui":{"theme":"project"}}' > "$TEST_PROJ/.muse/settings.json"
cat > "$TEST_TMP/launch.sh" <<'SCRIPT'
set -euo pipefail
BOX_TOOL=box-m
script_dir=$1
for library in preflight tools config docker launcher run pins build config-file; do
  source "$script_dir/lib/$library.sh"
done
source "$script_dir/harnesses/muse/native.sh"
box_docker_cli() { docker_cmd=(true); }
box_docker_exec() {
cp "$settings_snapshot" "$snapshot_result"
printf "%s" "$settings_snapshot_dir" > "$snapshot_result.path"
}
source "$script_dir/harnesses/muse/launch.sh" --project-root "$PWD" --shell -c true
SCRIPT
export snapshot_result="$TEST_TMP/result.json"
  cd "$TEST_PROJ"
run bash "$TEST_TMP/launch.sh" "$BUNDLE_DIR"
[ "$status" -eq 0 ]
[ "$(jq -r '.tui.theme' "$snapshot_result")" = project ]
[ "$(jq -r '.endpoint_transport.base_url' "$snapshot_result")" = "$(jq -r '.endpoint_transport.base_url' "$BOX_M_CONFIG")" ]
jq '.model = "new-default"' "$BOX_M_CONFIG" > "$TEST_TMP/new.json"
mv "$TEST_TMP/new.json" "$BOX_M_CONFIG"
run bash "$TEST_TMP/launch.sh" "$BUNDLE_DIR"
[ "$status" -eq 0 ]
[ "$(jq -r '.model' "$snapshot_result")" = new-default ]
[ "$(cat "$BOX_M_PERSIST_DIR/auth.json")" = '{"synthetic":"auth"}' ]

Command exited with code 0.

---

## Assistant

_Thinking:_

Analyzing code review findings and categorizing implementation status, gaps, and required fixes with file references.

No — core happy-path is present, but `specs/plan.md` DoD is not met. Uncommitted work lands Phases 1-7 atomically with gaps.

Implemented correctly:

- Registry: `box/lib/tools.sh:217,220,223` one `auth` record/harness (`class=auth,scope=auth-policy,kind=bind,runtime=/run/box-auth,mode=700,schema=1`), fallbacks `global/project/project`; validated at `box/lib/tools.sh:388-421`.
- Policy precedence `box/lib/auth.sh:174-178` matches §3; `BOX_C_AUTH` independent (`box/harnesses/codex/launch.sh:73` only).
- Layout `box/lib/auth.sh:249-256`, `box/lib/state.sh:114-130`: `R/H/uU/global`, `R/H/uU/projects/P`, UID-keyed, `700/600`, object-dir-only mount.
- Envelope `{schema_version,harness,adapter_schema,revision,tombstone,payload}`; Codex regular-file `tmp+mv` + `tombstone` (`box/harnesses/codex/auth.sh:24-48`); OpenCode explicit columns + `?` binds + `active=0` on install + single-active selection (`box/harnesses/opencode/auth-state.py:28-37,83-90,226-238,314-320`).
- Capture fresh disposable ns (`box/harnesses/opencode/capture-validation.sh:61-80`); `gen-verify.sh --check` passes; `Makefile` routes via single `box/lib/auth-ops.sh`.

Must-fix gaps:

1. Phase-1 gate violated: live `ensure_object+transition+reserve+install` runs unconditionally (`box/harnesses/muse/launch.sh:97-101`, `codex/launch.sh:92-96`, `opencode/launch.sh:59-65`); Muse backend still unresolved.
2. OpenCode live has no `box_auth_migration_gate` (comment only at `box/harnesses/opencode/launch.sh:61-62`).
3. Legacy `auth.json` quarantine missing; OpenCode `retire` is no-op (`box/harnesses/opencode/auth.sh:52-59`).
4. Muse qualification comment-only (`box/harnesses/muse/auth.sh:16-24` checks regular-JSON only, no keychain/MCP detection); MCP hash + account-table use unverified (`auth-state.py` passes `integration` opaquely).
5. Shared-lib harness branch violates §2: `box/lib/auth-ops.sh:95-112` `case $id`.
6. Old tests retained vs §8 ban: `box/tests/bats/live-defaults.bats:66-107` treats `$BOX_M_PERSIST_DIR/auth.json` as durable (now a projection + gate target); `launchers/config/opencode-v2.bats` not rewritten.
7. Dry-run omits migration/transition + legacy coordinates required by §6/§9 (`muse/launch.sh:64-68`, `codex:51-55`, `opencode:37-42`; gate only in `!dry_run`).
8. `state-remove` inventories only effective scope (`box/lib/auth-ops.sh:372-404`, global dies at `:383-384`); no inactive-scope/custom-root/projection sweep.
9. §10.10/11 missing: no old-image/supervisor rejection; `box_ops_migrate:163-223` never checks stopped containers.
10. Validation: `__unset__` accepted as unset (`box/lib/auth.sh:140-174`); `BOX_STATE_CONFIG=""`/`BOX_AUTH_ROOT=""` silently default (`:40,:210`); `policy_source:190-191` skips config validation; `jq`-absent fail-open (`box/lib/auth.sh:345,414`, `box/lib/auth-ops.sh:430`).

Cleanliness:

- Triplicated auth-dir formula (`box/lib/test-state.sh:258`, `box/lib/auth.sh:232`, `box/lib/state.sh:114-130`); old `box_project_identity` still live (`box/lib/launcher.sh:92,458`).
- Dead: `box_config_get_optional`, `test-state.sh:199-208` no-op, `auth-ops.sh:129-141` `if False`.
- Docs retain inline hash reconstruction (`box/docs/operations.md:253-270`); `.dockerignore` `!harnesses/muse/` over-broad.
