# Verifying plan.md uncommitted implementation

**Session ID:** ses_ee836e3a5ffe67ExDDbBcK3oBF
**Created:** 10/7/2026, 7:13:38 PM
**Updated:** 10/7/2026, 7:14:00 PM

---

## User

double check if @specs/plan.md has been implemented correctly and cleanly (uncomitted changes)

previous passes context: @specs/passes/

---

## Assistant

_Thinking:_

Checking your plan against the uncommitted work — inventorying changes and previous passes.

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

**Tool: read**

**Input:**

```json
{
	"path": "/workspace/specs"
}
```

Read directory /workspace/specs, entries 1-2
passes/
plan.md

---

## Assistant

**Tool: read**

**Input:**

```json
{
	"path": "/workspace/specs/passes"
}
```

Read directory /workspace/specs/passes, entries 1-2
pass-1.md
pass-2.md

---

## Assistant

_Thinking:_

**Tool: shell**

**Input:**

```json
{
	"command": "git status --porcelain=v1; echo \"---BRANCH---\"; git branch --show-current; echo \"---LOG---\"; git log --oneline -5; echo \"---DIFFSTAT---\"; git diff --stat; echo \"---DIFFSTAT-CACHED---\"; git diff --cached --stat",
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
---DIFFSTAT---
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
---DIFFSTAT-CACHED---

Command exited with code 0.

---

## Assistant

_Thinking:_

**Tool: read**

**Input:**

```json
{
	"path": "/workspace/specs/passes/pass-1.md"
}
```

Read file /workspace/specs/passes/pass-1.md, lines 1-550
1: # Verifying plan.md uncommitted changes
2:
3: **Session ID:** ses*ee867ee6bffeZodApp29BAoD3V
4: **Created:** 10/7/2026, 6:20:04 PM
5: **Updated:** 10/7/2026, 6:20:12 PM
6:
7: ---
8:
9: ## User
10:
11: double check if @specs/plan.md has been implemented correctly and cleanly (uncomitted changes)
12:
13: ---
14:
15: ## Assistant
16:
17: \_Thinking:*
18:
19: Checking your uncommitted changes against the plan — inventorying the workspace first.
20:
21: **Tool: read**
22:
23: **Input:**
24:
25: `json
26: {
27: 	"path": "/workspace"
28: }
29: `
30:
31: Read directory /workspace, entries 1-20
32: .agents/
33: .bats-home/
34: .bats-run-base/
35: .bats-run-c1/
36: .bats-run-c2/
37: .bats-run-c3/
38: .bats-run-c4/
39: .bats-run-parent/
40: .bats-run/
41: .git/
42: .github/
43: .vscode/
44: box/
45: specs/
46: .gitignore
47: AGENTS.md
48: LICENSE
49: meta-api-key
50: README.md
51: skills-lock.json
52:
53: ---
54:
55: ## Assistant
56:
57: _Thinking:_
58:
59: **Tool: shell**
60:
61: **Input:**
62:
63: `json
64: {
65: 	"command": "git status --porcelain=v1; echo \"---BRANCH---\"; git branch --show-current; echo \"---LOG---\"; git log --oneline -5; echo \"---DIFF STAT---\"; git diff --stat; echo \"---DIFF NAME---\"; git diff --name-only; echo \"---STAGED STAT---\"; git diff --cached --stat",
66: 	"workdir": "/workspace"
67: }
68: `
69:
70: M .gitignore
71: M box/.dockerignore
72: M box/Dockerfile
73: M box/Makefile
74: M box/README.md
75: M box/box-c
76: M box/box-m
77: M box/box-m-login
78: M box/box-o
79: M box/check-pins.sh
80: M box/docs/acceptance.md
81: M box/docs/adding-a-tool.md
82: M box/docs/architecture.md
83: M box/docs/harnesses.md
84: M box/docs/operations.md
85: M box/docs/security-resource-audit.md
86: M box/docs/troubleshooting.md
87: M box/docs/upgrades.md
88: M box/harnesses/codex/README.md
89: M box/harnesses/codex/launch.sh
90: M box/harnesses/codex/verify.d/40-readiness-codex.sh
91: M box/harnesses/muse/README.md
92: M box/harnesses/muse/install.sh
93: M box/harnesses/muse/launch.sh
94: M box/harnesses/muse/verify.d/40-readiness-muse.sh
95: M box/harnesses/opencode/README.md
96: M box/harnesses/opencode/capture-validation.sh
97: M box/harnesses/opencode/entrypoint.sh
98: M box/harnesses/opencode/launch.sh
99: M box/harnesses/opencode/verify.d/40-readiness-opencode.sh
100: M box/lib/config-file.sh
101: M box/lib/install.sh
102: M box/lib/test-state.sh
103: M box/lib/tools.sh
104: M box/setup.sh
105: M box/tests/bats/helpers.bash
106: M box/tests/bats/opencode-capture.bats
107: M box/tests/bats/setup.bats
108: M box/tests/bats/tools.bats
109: M box/tests/native/acceptance.sh
110: M box/tests/native/lifecycle-audit.py
111: M box/verify-codex.sh
112: M box/verify-muse.sh
113: M box/verify-opencode.sh
114: ?? .agents/
115: ?? box/harnesses/codex/auth.sh
116: ?? box/harnesses/muse/auth.sh
117: ?? box/harnesses/opencode/auth-state.py
118: ?? box/harnesses/opencode/auth.sh
119: ?? box/lib/auth-ops.sh
120: ?? box/lib/auth.sh
121: ?? box/lib/state.sh
122: ?? box/lib/supervisor.sh
123: ?? box/tests/bats/auth-adapters.bats
124: ?? box/tests/bats/auth-lifecycle.bats
125: ?? box/tests/bats/auth-migration.bats
126: ?? box/tests/bats/auth-policy.bats
127: ?? box/tests/bats/state.bats
128: ?? specs/
129: ---BRANCH---
130: dev
131: ---LOG---
132: c85d13c Isolate test state in disposable box-test namespaces
133: ef808f0 fix gi
134: b9303c4 Merge pull request #1 from temrb/dev
135: 5f41d33 Fixed the shared cause of both CI failures in box/lib/preflight.sh:201: early pipe closure caused `find` to report “Broken pipe.”
136: 5751d1b Suppress shellcheck nameref false positives in lib/tools.sh
137: ---DIFF STAT---
138: .gitignore | 9 +-
139: box/.dockerignore | 10 +++
140: box/Dockerfile | 13 ++-
141: box/Makefile | 47 ++++++++++-
142: box/README.md | 4 +
143: box/box-c | 6 ++
144: box/box-m | 6 ++
145: box/box-m-login | 4 +-
146: box/box-o | 6 ++
147: box/check-pins.sh | 11 ++-
148: box/docs/acceptance.md | 1 +
149: box/docs/adding-a-tool.md | 12 ++-
150: box/docs/architecture.md | 47 ++++++++++-
151: box/docs/harnesses.md | 6 +-
152: box/docs/operations.md | 70 +++++++++++++---
153: box/docs/security-resource-audit.md | 7 +-
154: box/docs/troubleshooting.md | 3 +
155: box/docs/upgrades.md | 16 ++++
156: box/harnesses/codex/README.md | 29 ++++---
157: box/harnesses/codex/launch.sh | 35 ++++++++
158: box/harnesses/codex/verify.d/40-readiness-codex.sh | 13 +++
159: box/harnesses/muse/README.md | 31 ++++---
160: box/harnesses/muse/install.sh | 16 +++-
161: box/harnesses/muse/launch.sh | 52 ++++++++++--
162: box/harnesses/muse/verify.d/40-readiness-muse.sh | 14 ++++
163: box/harnesses/opencode/README.md | 17 +++-
164: box/harnesses/opencode/capture-validation.sh | 45 ++++++----
165: box/harnesses/opencode/entrypoint.sh | 44 ++++++++++
166: box/harnesses/opencode/launch.sh | 48 +++++++++++
167: .../opencode/verify.d/40-readiness-opencode.sh | 14 ++++
168: box/lib/config-file.sh | 40 +++++++++
169: box/lib/install.sh | 20 +++++
170: box/lib/test-state.sh | 96 +++++++++++++++++++++-
171: box/lib/tools.sh | 58 ++++++++++---
172: box/setup.sh | 13 +++
173: box/tests/bats/helpers.bash | 9 ++
174: box/tests/bats/opencode-capture.bats | 25 ++++++
175: box/tests/bats/setup.bats | 25 ++++++
176: box/tests/bats/tools.bats | 38 +++++++++
177: box/tests/native/acceptance.sh | 21 +++++
178: box/tests/native/lifecycle-audit.py | 26 ++++++
179: box/verify-codex.sh | 13 +++
180: box/verify-muse.sh | 14 ++++
181: box/verify-opencode.sh | 14 ++++
182: 44 files changed, 947 insertions(+), 101 deletions(-)
183: ---DIFF NAME---
184: .gitignore
185: box/.dockerignore
186: box/Dockerfile
187: box/Makefile
188: box/README.md
189: box/box-c
190: box/box-m
191: box/box-m-login
192: box/box-o
193: box/check-pins.sh
194: box/docs/acceptance.md
195: box/docs/adding-a-tool.md
196: box/docs/architecture.md
197: box/docs/harnesses.md
198: box/docs/operations.md
199: box/docs/security-resource-audit.md
200: box/docs/troubleshooting.md
201: box/docs/upgrades.md
202: box/harnesses/codex/README.md
203: box/harnesses/codex/launch.sh
204: box/harnesses/codex/verify.d/40-readiness-codex.sh
205: box/harnesses/muse/README.md
206: box/harnesses/muse/install.sh
207: box/harnesses/muse/launch.sh
208: box/harnesses/muse/verify.d/40-readiness-muse.sh
209: box/harnesses/opencode/README.md
210: box/harnesses/opencode/capture-validation.sh
211: box/harnesses/opencode/entrypoint.sh
212: box/harnesses/opencode/launch.sh
213: box/harnesses/opencode/verify.d/40-readiness-opencode.sh
214: box/lib/config-file.sh
215: box/lib/install.sh
216: box/lib/test-state.sh
217: box/lib/tools.sh
218: box/setup.sh
219: box/tests/bats/helpers.bash
220: box/tests/bats/opencode-capture.bats
221: box/tests/bats/setup.bats
222: box/tests/bats/tools.bats
223: box/tests/native/acceptance.sh
224: box/tests/native/lifecycle-audit.py
225: box/verify-codex.sh
226: box/verify-muse.sh
227: box/verify-opencode.sh
228: ---STAGED STAT---
229:
230: Command exited with code 0.
231:
232: ---
233:
234: ## Assistant
235:
236: _Thinking:_
237:
238: **Tool: read**
239:
240: **Input:**
241:
242: `json
243: {
244: 	"path": "/workspace/specs"
245: }
246: `
247:
248: Read directory /workspace/specs, entries 1-1
249: plan.md
250:
251: ---
252:
253: ## Assistant
254:
255: _Thinking:_
256:
257: Seen the scope — 44 modified plus 14 new files. Now doing a deep check against all 12 plan sections.
258:
259: **Tool: subagent**
260:
261: **Input:**
262:
263: `json
264: {
265: 	"agent": "general",
266: 	"description": "Review state resolver impl",
267: 	"prompt": "In /workspace, review uncommitted changes (git diff + untracked files) against specs/plan.md sections 2 (Declarative state model, Resolver boundaries) and 4 (State-layout design).\n\nRead these files fully:\n- specs/plan.md sections 2 and 4\n- box/lib/tools.sh (git diff + full file for auth records)\n- box/lib/state.sh (untracked, full)\n- box/lib/test-state.sh (diff + full)\n- box/lib/auth.sh and box/lib/auth-ops.sh (untracked, full)\n- box/lib/config-file.sh diff\n\nReport:\n1. Does _BOX_STATES have exactly one auth record per harness with class=auth, scope=auth-policy, kind=bind, mode 700, runtime /run/box-auth? Quote evidence.\n2. Are box_state_context/resolve/validate/guard/cli and box_auth_* functions present with correct signatures?\n3. Do identities match R/H/uU/global and R/H/uU/projects/P layout? Is UID (not GID) the key? Are modes 700/600 enforced? Is /run/box-auth mount only object dir?\n4. Any harness-name conditionals in shared lib (violates plan)?\n5. Cleanliness issues (duplicated identity logic left, dead code, shellcheck risks).\n\nBe factual, cite file:line. Do not fix, only report."
268: }
269: `
270:
271: <subagent sessionID="ses_ee867b17affe62Wv5XP0lHqGdU" state="completed">
272: Review of uncommitted changes vs `specs/plan.md` §§2,4. All `bash -n` pass; `shellcheck` binary absent in this env.
273:
274: ## 1. `_BOX_STATES` auth records — YES, exactly one per harness
275:
276: `box/lib/tools.sh:91,102,113` — each harness `states` list now ends in `auth`:
277:
278: - `muse,states='home volume auth'`, `opencode,states='volume config-parent auth'`, `codex,states='home volume auth'`
279:
280: `box/lib/tools.sh:217,220,223`:
281:
282: - `muse auth auth-policy bind .config/box/auth BOX_AUTH_ROOT /run/box-auth 700 'auth-canonical-only' auth global harnesses/muse/auth.sh 1`
283: - `opencode auth ... auth project harnesses/opencode/auth.sh 1`
284: - `codex auth ... auth project harnesses/codex/auth.sh 1`
285:
286: So per record: `class=auth`, `scope=auth-policy`, `kind=bind`, `mode=700`, `runtime=/run/box-auth`, shared root `.config/box/auth`, override `BOX_AUTH_ROOT`. Fallbacks (`global`/`project`/`project`) match plan §3 table.
287:
288: Enforcement in `box/lib/tools.sh:388-399,421`: auth branch checks name==`auth`, scope, kind, root, override, runtime, `default_scope ∈ {global,project}`, `adapter=="harnesses/$id/auth.sh"` + file exists, `schema==1`; non-auth branch rejects orphan auth fields (`:403`); `:421` `[[ "$auth_count" == 1 ]]` dies otherwise. Non-auth resets rewritten to `*-non-auth` (`:215-222`), auth reset is `auth-canonical-only`.
289:
290: ## 2. Resolver / auth functions — all present, signatures match
291:
292: `box/lib/state.sh`:
293:
294: - `box_state_context` `:54` — `(harness, uid, gid, project-path, production|test, [ns], [task-root])`; sets `BOX_STATE_HARNESS/UID/GID/PROJECT/HASH/DOMAIN/NS/TASK_ROOT`. Matches spec.
295: - `box_state_resolve` `:94` — `<state-name>` via context globals, prints `KEY=value` descriptor (`domain,harness,state,class,scope,uid,gid,project_hash,project,path,runtime,adapter,schema_version,volume`). Matches.
296: - `box_state_validate_descriptor` `:183` — `<descriptor-file>`, no mutation. Matches.
297: - `box_state_guard_operation` `:227` — `<op> <descriptor…>`, ops `migrate|copy|init|recover|reset|remove|plan`. Matches.
298: - `box_state_cli` `:254` — `context|resolve|validate|guard|project-hash|volume`. Spec's "machine-readable descriptor output for Python/native consumers" is satisfied; extra `project-hash|volume` subcommands are additive pure primitives (allowed by §2 test-boundary).
299:
300: `box/lib/auth.sh` — all seven spec functions present:
301:
302: - `box_auth_policy_resolve <harness>` `:132`, `box_auth_plan <harness> <uid> <project-hash>` `:423`, `box_auth_prepare <harness> <uid> <hash> <proj-lock> [native] [bundle] [desc]` `:612`, `box_auth_transition_plan <harness> <uid> <hash> [project-path]` `:541`, `box_auth_lease_reserve <auth-dir> <proj-lock> [proj-data]` `:325`, `box_auth_recover <auth-dir>` `:388`, `box_auth_guard_remove <auth-dir>` `:408`.
303: - Plus supporting extras (not spec-violating): `box_auth_valid_scope`, `config_file`, `parse_config`, `policy_source`, `root`, `index_dir`, `object_dir`, `ensure_object`, `sorted_locks`, `lease_release`, `install/collect_projection`, `migration_gate`, `binding_file`.
304:
305: ## 3. Layout / UID key / modes / mount
306:
307: - Production layout matches §4 (`R/H/uU/global`, `R/H/uU/projects/P`): `box/lib/auth.sh:249-256` → `$rroot/$id/u$uid/global` and `$rroot/$id/u$uid/projects/$hash`; same in `box_state_resolve` `:123-130` via `box_auth_root()`.
308: - Test layout matches (`T/N/auth/H/uU/...`): `box/lib/test-state.sh:258-273` (`box_test_auth_dir`), mirrored by `auth.sh:239-247` test branch and `state.sh:114-121`. Three implementations of one formula — see §5 duplication.
309: - UID is the key: auth paths take `uid` only, never `gid` (zero `gid` refs in `auth.sh`); `box_state_resolve` auth branch uses only `BOX_STATE_UID` (`:118,120,126,128`). GID retained only in descriptor/volume names (`:175-178`, `box_state_volume_name :79`). Per §4 ("changing primary group must not create another login").
310: - Modes: `box_auth_ensure_object` (`auth.sh:260-310`) creates dir via `box_prepare_directory … 700` (`:269`), `chmod 600` on `identity.json/credentials.json/lease.json/lock` (`:284,294,298,302`), then `box_assert_owner_mode … dir700` + per-file `creds` checks (`:305-309`). Leaves created are exactly the §4 set (`identity.json`, `credentials.json`, `lease.json`, `lock`); journal/staging/rollback leaves live in `auth-ops.sh`. `state.sh` itself resolves only, enforces nothing — correct.
311: - `/run/box-auth` object-dir-only: registry declares `runtime=/run/box-auth` (`tools.sh:217,220,223,395`); no shared-lib code mounts anything (mounting is harness `launch.sh`, outside requested scope). For reference the harness adapters do mount the resolved object dir only: `box/harnesses/codex/launch.sh:115`, `muse/launch.sh:141`, `opencode/launch.sh:91` (`src=$*_auth_dir,dst=/run/box-auth,bind-recursive=disabled,bind-propagation=rprivate`). No shared-lib code mounts the shared root.
312:
313: ## 4. Harness-name conditionals in shared lib — one violation
314:
315: - **Violation:** `box/lib/auth-ops.sh:95-112` `box_ops_legacy_source` does `case "$id" in muse) …BOX_M_PERSIST_DIR… ;; codex) …BOX_C_STATE_ROOT… ;; opencode) … ;;`. This is exactly what §2 forbids ("shared code … never branches on harness names"; legacy-source discovery should be registry/adapter-driven).
316: - Compliant-by-construction: `state.sh:160-170` dispatches on `root` suffix (`*/projects → …/codex-home`), not on harness name (comment at `:158-160` says so); adapter install/collect/validate/export/retire go through `box_state_field … adapter` (`auth.sh:446,469; auth-ops.sh:192`) — compliant.
317: - Pre-existing / out-of-scope: `box_test_codex_home` (`test-state.sh:144-149`) and `codex-home` leaf literals (`state.sh:161,169`) predate this change and are explicitly retained by §2 ("Retain PR #2's … Codex-home resolver"); `box/harnesses/*/launch.sh` per-harness files are adapters, not shared lib.
318:
319: ## 5. Cleanliness
320:
321: - **Old identity logic not yet replaced** (§2 lists `box_project_identity`, Codex-home, Muse-home, OpenCode capture derivation as replaced): `box/lib/launcher.sh:92` still defines `box_project_identity` (hash/volume/container inline, `:119-131`) and it is still called (`:458`); `state.sh`/`auth-ops.sh` reuse only `box_state_project_hash`/`box_state_volume_name`/`box_test_volume`. New resolver coexists with old — migration incomplete.
322: - **Triplicated auth-dir formula:** `box_test_auth_dir` (`test-state.sh:258`), `box_auth_object_dir` (`auth.sh:232`), auth branch of `box_state_resolve` (`state.sh:114-130`), plus `box_ops_auth_dir` (`auth-ops.sh:65`) re-resolving policy+object dir a fourth way.
323: - **Dead / no-op code:**
324: - `box_config_get_optional` (`config-file.sh:138-172`) has zero callers (`grep` finds only the definition; `box_auth_parse_config` inlines its own TOML parsing instead).
325: - `test-state.sh:199-208` scope-override loop is a no-op (`[[ -z … ]] || :`, then `unset`).
326: - `test-state.sh:239` `case … in BOX_AUTH_ROOT|BOX_STATE_CONFIG)` — `BOX_STATE_CONFIG` can never appear as a state `override` (state overrides are `BOX_AUTH_ROOT`/`BOX_M_PERSIST_DIR`/etc.), dead arm.
327: - `auth-ops.sh:129-141` flush helper contains `os.fsync(f.fileno()) if False else None` — dead expression; only the dir `fsync` runs.
328: - **Fragile patterns (no shellcheck available; `bash -n` clean):**
329: - `state.sh:239-246` guard uses `grep -qx/ -q` + `cut`/`grep '^path='`; line 241 `grep -q -- "$BOX_TEST_TASK_ROOT"` matches everything when the var is unset (empty pattern), silently `continue`-ing past the containment check for `domain=test` descriptors.
330: - `auth.sh:333-342,378-379` `exec {BOX_AUTH_FD}>…`/`flock -n` inside a loop that only acts on one member; fds leak on mid-function `die` (no trap), and `lease_release` is the only closer.
331: - `auth.sh:197,200` `grep -qx "$id\\.scope=…"` relies on BRE `\|` under `-x`; works in GNU grep but brittle and `$id` is unescaped (safe today only because ids are registry-constrained).
332: - `auth.sh:567-568` `sed -n '1p/2p'` binding read; `mktemp` (`auth.sh:477`), indirect `${!var}` (`state.sh:149`, `test-state.sh:182,204`, `auth.sh:140`) — all standard for this codebase but untested by shellcheck here.
333: </subagent>
334:
335: **Tool: subagent**
336:
337: **Input:**
338:
339: `json
340: {
341: 	"agent": "general",
342: 	"description": "Review config policy impl",
343: 	"prompt": "In /workspace, review uncommitted changes against specs/plan.md section 3 (Effective configuration matrix).\n\nRead:\n- specs/plan.md section 3\n- box/lib/auth.sh, box/lib/auth-ops.sh (full)\n- box/lib/config-file.sh (full + git diff)\n- box/lib/tools.sh auth-related parts\n- box/setup.sh diff, box/lib/install.sh diff\n- box/tests/bats/auth-policy.bats (untracked, full)\n\nReport:\n1. Are defaults muse=global, opencode=project, codex=project preserved as registry fallbacks?\n2. Is precedence exactly: harness runtime > common runtime > harness config > common config > registry fallback? Is BOX_AUTH_SCOPE, BOX_M/O/C_AUTH_SCOPE, BOX_STATE_CONFIG, BOX_AUTH_ROOT supported? Does BOX_C_AUTH remain independent?\n3. Is validation correct: accepted scopes exactly global/project, set-but-empty errors, unknown keys/harnesses error, duplicate TOML error, explicit-missing-config errors, implicit-missing ok, unsafe root errors, no sourcing as shell, validate-all-supplied-before-resolution including shadowed values?\n4. Does setup seed versioned file with no explicit scopes and preserve byte-for-byte on rerun?\n5. Cleanliness/correctness bugs with evidence file:line.\n\nBe factual, cite file:line. Do not fix."
344: }
345: `
346:
347: <subagent sessionID="ses_ee867b17affdIGnHiC707671RZ" state="completed">
348: Review of uncommitted changes vs `specs/plan.md` §3. All citations are post-change working-tree lines.
349:
350: ## 1. Registry fallbacks preserved — YES
351:
352: `box/lib/tools.sh:217,220,223`:
353:
354: - `muse auth … auth global harnesses/muse/auth.sh 1`
355: - `opencode auth … auth project harnesses/opencode/auth.sh 1`
356: - `codex auth … auth project harnesses/codex/auth.sh 1`
357:
358: Validation enforces it: `box/lib/tools.sh:388-399` (auth must be `scope=auth-policy`, `kind=bind`, `root=.config/box/auth`, `override=BOX_AUTH_ROOT`, `runtime=/run/box-auth`, `default_scope in global|project`, `adapter=harnesses/$id/auth.sh`, `schema=1`), `box/lib/tools.sh:421` (exactly one auth record), `box/lib/tools.sh:403` (non-auth must not carry orphan auth fields).
359:
360: Resolver consumes it as final fallback: `box/lib/auth.sh:170-172`, `box/lib/auth.sh:178`.
361: Tests assert it: `box/tests/bats/auth-policy.bats:11-20`, `box/tests/bats/tools.bats:145-180`.
362:
363: ## 2. Precedence and runtime interface — YES, with two deviations noted in §5
364:
365: Precedence in `box/lib/auth.sh:174-178` is exactly spec order:
366:
367: 1. harness runtime, 2. `BOX_AUTH_SCOPE`, 3. harness config, 4. common config, 5. registry fallback.
368:
369: Env names derived from registry, no harness literals: `box/lib/auth.sh:136-137` (`gpfx=$(box_tool_field "$id" git_prefix); harness_var="${gpfx}_AUTH_SCOPE"`), same pattern in `box/lib/auth.sh:187-188` and `box/lib/test-state.sh:199-206`. Registry prefixes at `box/lib/tools.sh:64,81,131` (`BOX_M`, `BOX_O`, `BOX_C`) yield `BOX_M/O/C_AUTH_SCOPE`. `BOX_AUTH_SCOPE` read at `box/lib/auth.sh:141`. Config selection at `box/lib/auth.sh:39-63`: explicit `BOX_STATE_CONFIG` else implicit `~/.config/box/state.toml`. Root at `box/lib/auth.sh:209-216` (`BOX_AUTH_ROOT` else `$HOME/.config/box/auth`, absolute + comma/newline reject + `box_plan_directory` + `box_assert_project_disjoint`).
370:
371: `BOX_C_AUTH` independent: nothing in `box/lib/auth.sh` or `box/lib/config-file.sh` reads `BOX_C_AUTH`; only `box/harnesses/codex/launch.sh:73` validates it as `chatgpt|api` credential-forwarding flag. Covered by `box/tests/bats/auth-policy.bats:104-110`.
372:
373: Precedence combinations empirically verified (fallback, common>fallback, harness>common, harness-cfg>default, env>cfg in both layers).
374:
375: Deviations: `box_auth_policy_source` returns env without validating config (`box/lib/auth.sh:190-191`), and `BOX_STATE_CONFIG=""` / `BOX_AUTH_ROOT=""` are masked by `:-` (`box/lib/auth.sh:40,210`) instead of erroring — details in §5.
376:
377: ## 3. Validation
378:
379: - Accepted scopes exactly `global|project`: YES. `box/lib/auth.sh:32-34`, parser `box/lib/auth.sh:100-101,117`, fallback `box/lib/auth.sh:172`.
380: - Set-but-empty errors (scope vars): YES. `box/lib/auth.sh:164-168`; tested `box/tests/bats/auth-policy.bats:50-61`. Empirically `BOX_AUTH_SCOPE=""`, `BOX_M_AUTH_SCOPE=""`, `=everywhere` all die.
381: - Unknown keys/harnesses error: YES. `box/lib/auth.sh:81-84` (top), `92-95` (auth keys), `106-108` (harness id), `111-113` (per-harness keys). Tested `box/tests/bats/auth-policy.bats:75-92`.
382: - Wrong type / empty string error: YES. `box/lib/auth.sh:100,117` reject non-string and `""`; `default_scope=1`, `default_scope=""` tested.
383: - Unsupported schema error: YES. `box/lib/auth.sh:85-87` (`schema != 1` dies); tested with `schema_version = 2`.
384: - Duplicate TOML error: YES by implementation, NO test. Python `tomllib.load` raises `ValueError` subclass on duplicate keys, caught in `box/lib/config-file.sh:44-51` and `box/lib/auth.sh:73-80`. Empirically duplicate `default_scope` dies via `Invalid TOML configuration`. No `auth-policy.bats` case covers duplicates — coverage gap.
385: - Explicit-missing errors / implicit-missing ok: YES. `box/lib/auth.sh:41-54` vs `55-62`. Tested `box/tests/bats/auth-policy.bats:94-102`; empirically explicit missing dies, implicit absent resolves to fallback.
386: - Unsafe root errors: YES. Relative/comma rejected `box/lib/auth.sh:211`; in-project rejected via `box_plan_directory`→`box_assert_project_disjoint` (`box/lib/preflight.sh:169-175,478-504`); empirically relative, comma, in-project all die. Ancestor symlink/unwritable-owner enforced by `box_plan_directory` (`box/lib/preflight.sh:486-502`).
387: - Present unsafe config errors: YES for symlink/unreadable/group-writable/in-project. `box/lib/auth.sh:43,56,46-51,58-61`. Empirically symlink and `666` die, in-project `BOX_STATE_CONFIG` dies. Note `644` resolves successfully — correct by design since policy is `nowrite` (`box/lib/preflight.sh:311-327`), not `creds`; scope config is non-secret.
388: - No sourcing as shell: YES. Grep finds no `source`/`eval` of config values; parsing is `box_config_validate` + isolated `python3 -I tomllib` in `box/lib/auth.sh:69-124`, `box/lib/config-file.sh:138-172`.
389: - Validate-all-supplied-before-resolution incl. shadowed: YES for resolve path. Env loop validates both layers even when overridden (`box/lib/auth.sh:164-168`); config loop validates selected default+harness even when env overrides (`box/lib/auth.sh:155-158`); parser validates _every_ harness table eagerly (`box/lib/auth.sh:106-119`). Tested `box/tests/bats/auth-policy.bats:63-73`; empirically shadowed-bogus env, shadowed-bogus config, and other-harness-bogus all die.
390: - Exception: `box_auth_policy_source` does NOT validate when env is set (returns `env:…` at `box/lib/auth.sh:190-191` without parsing config). Empirically invalid config + `BOX_AUTH_SCOPE=project` → `resolve` dies but `source` prints `env:BOX_AUTH_SCOPE rc=0`.
391: - No native project config sets scope: YES (vacuously). Scope comes only from env/config/registry; no reader consults `.codex/config.toml`, `settings.json`, etc.
392: - Resolve-before-mutation: YES for the shared path. `box_auth_prepare` (`box/lib/auth.sh:612-633`) resolves (`617`), then ensures object, transition plan, migration gate, lease reserve, projection install — no Docker/credential/lock contact before `617`.
393:
394: Strictness note: `[auth.harnesses.muse]` with no `scope` key dies (`box/lib/auth.sh:115-116`). Spec says “omitted key: inherit.” If “omitted” includes empty tables, this is stricter than spec; if it means omitted table/default, behavior is correct. No bats case pins it.
395:
396: ## 4. Setup seeding — YES
397:
398: `box/lib/install.sh:104-119` seeds `schema_version = 1\n`, mode `600`, via stage+`mv`; rerun path (`113-117`) only checks `-f` and prints `kept` with no write — byte-for-byte preservation. `box/setup.sh:249-256` calls it after `_setup_dirs` (which already includes `$HOME/.config/box` at `box/setup.sh:146` and creates it before first write), so the `Missing state-policy parent` die is unreachable in normal setup. Empirically: `created`+`600`+`box_config_validate toml` passes; rerun `sha256` identical; custom `[auth] default_scope` content preserved; symlink and missing-parent die. Tests: `box/tests/bats/setup.bats:250-273`.
399:
400: ## 5. Cleanliness / correctness bugs (evidence, no fix)
401:
402: 1. Sentinel collision `__unset__`: `box/lib/auth.sh:140-141,164-168,174-175`. `BOX_AUTH_SCOPE=__unset__` is treated as unset, skips validation, falls to fallback. Empirically `BOX_AUTH_SCOPE=__unset__ box_auth_policy_resolve muse` → `global rc=0`, should die as unknown scope.
403: 2. `BOX_STATE_CONFIG=""` / `BOX_AUTH_ROOT=""` silently default: `box/lib/auth.sh:40` (`${BOX_STATE_CONFIG:-}`), `box/lib/auth.sh:210` (`${BOX_AUTH_ROOT:-…}`). Empirically both `rc=0` (empty config → implicit; empty root → default). Inconsistent with strict empty handling for scope vars at `box/lib/auth.sh:166`.
404: 3. `box_auth_policy_source` skips validation when env set: `box/lib/auth.sh:190-191`. See §3 exception.
405: 4. `jq`-absent fail-open on lease checks: `box/lib/auth.sh:345` (reserve busy check), `box/lib/auth.sh:414` (guard remove), `box/lib/auth-ops.sh:430` (reset active check) all gate on `command -v jq … && jq -e …`, so missing `jq` silently proceeds with overwrite/removal/reset. Contrast `box_auth_recover` (`box/lib/auth.sh:392`), `box_auth_collect_projection` (`box/lib/auth.sh:480`), `box_ops_publish_envelope` (`box/lib/auth-ops.sh:122`) which hard-require `jq`.
406: 5. Dead shared validator: `box_config_get_optional` defined `box/lib/config-file.sh:138-172`, zero callers (grep finds only the definition). `box_auth_parse_config` inlines its own TOML schema instead of using it.
407: 6. Test-harness env leak: `box/tests/bats/helpers.bash:30` unsets scope/config/root vars but not `BOX_C_AUTH` or `BOX_AUTH_TRANSITION` (read at `box/lib/auth.sh:574`). Former is harmless (independent); latter can flip transition-plan outcomes if exported in the outer environment.
408: 7. Predictable non-atomic stage without trap: `box/lib/install.sh:110-113` uses `>"$dest.tmp.$$"` instead of `mktemp`+trap/`box_atomic_install` idiom used elsewhere in the same file; concurrent runs can interleave and failures leave stale `$dest.tmp.<pid>`.
409: 8. Misleading lock-order helper: `box/lib/auth.sh:312-316,336-343`. Comment claims sorted deterministic acquisition, but auth lock is always taken first regardless of lexicographic order. Deadlock-free (all contenders share the order) but `box_auth_sorted_locks` is vestigial.
410: </subagent>
411:
412: **Tool: subagent**
413:
414: **Input:**
415:
416: `json
417: {
418: 	"agent": "general",
419: 	"description": "Review harness adapters",
420: 	"prompt": "In /workspace, review uncommitted changes against specs/plan.md section 5 (Harness adaptation) and section 6 (Migration design).\n\nRead fully:\n- box/harnesses/muse/auth.sh, box/harnesses/codex/auth.sh, box/harnesses/opencode/auth.sh, box/harnesses/opencode/auth-state.py (all untracked)\n- box/harnesses/muse/launch.sh diff, box/harnesses/codex/launch.sh diff, box/harnesses/opencode/launch.sh + entrypoint.sh diffs\n- box/lib/supervisor.sh (untracked)\n- box/Makefile diff (for auth-migrate/copy/init/recover, state-plan/remove targets)\n- box/tests/bats/auth-adapters.bats, auth-migration.bats, auth-lifecycle.bats (untracked)\n\nReport:\n1. Does each adapter support validate/export/export-selection/install/collect/scrub/recover per plan? Is envelope credentials.json with harness/adapter schema, revision, payload, tombstone, no prefs/trust/approvals/sessions? Is selection stored separately (e.g. box-auth-selection.json)?\n2. Muse: is persistent-home auth-scope assertion removed? Are trust/settings excluded? Is backend qualification explicit or silently assumed?\n3. Codex: is auth.json regular-file projection (not bind/symlink)? Is logout->tombstone? Is CODEX_HOME still project-scoped?\n4. OpenCode: explicit column lists + parameterized SQL? Sessions/approvals/config excluded? Selection restore only if credential exists? No timestamp-based choice? Service stopped before collect? WAL hygiene? Legacy auth.json import disabled/quarantined? MCP endpoint identity (hash name+URL) preserved?\n5. Migration: setup performs no migration? First-live-launch refuses without migration record? Dry-run reads no credentials? Transaction journal planned->staged->committed->verified->retired->complete? Source retained until verified? No merge, no auto-populate, explicit source choice, acknowledgment fresh/use-existing/copy?\n6. Supervisor: 9-step lifecycle present? Shell runs wrapped? No docker socket?\nBe factual, cite file:line. Do not fix."
421: }
422: `
423:
424: <subagent sessionID="ses_ee867b17affcNu7CXis5kuCsZI" state="completed">
425: Review of uncommitted changes vs `specs/plan.md` §5–§6. No fixes applied.
426:
427: ## 1. Adapter contract (plan §5 intro, §2 envelope)
428:
429: Files: `box/harnesses/muse/auth.sh`, `box/harnesses/codex/auth.sh`, `box/harnesses/opencode/auth.sh`, `box/harnesses/opencode/auth-state.py`.
430:
431: Implemented per adapter: `box_adapter_validate` / `export` / `install` / `collect` (=`export`) / `scrub` / `retire`:
432:
433: - muse/auth.sh:16,26,42,57,61,70; codex/auth.sh:11,20,36,51,55,64; opencode/auth.sh:21,29,36,42,46,56.
434: - Missing as adapter verbs: **no `export-selection` and no `recover`** in any `auth.sh`. Selection is a separate verb only for OpenCode (`save-selection`/`restore-selection` subcommands, auth-state.py:305,338; front-end `auth.sh` does not expose them — only called from `entrypoint.sh:71,76`). Muse/Codex have no selection export at all (single-file payload assumed inseparable; not stated in code).
435: - Envelope shape matches plan: `{schema_version:1, harness, adapter_schema:1, revision, tombstone:bool, payload}` — muse/auth.sh:31-32,37-38; codex/auth.sh:25-26,31-32; auth-state.py:111-118,145-152; `lib/auth.sh:287-294` (fresh tombstone `revision:0`), `lib/auth-ops.sh:126,154`.
436: - "No prefs/trust/approvals/sessions" holds by construction, not by filtering for file harnesses: adapters copy the whole native `auth.json` verbatim (`--slurpfile p`, muse/auth.sh:37-38; codex/auth.sh:31-32). Exclusion relies on trust/settings living in sibling files the adapter never opens (muse `settings.json`/`.trust.json`, codex `config.toml`/history/SQLite — comments muse/auth.sh:2-5, codex/auth.sh:2-5). No field-level strip inside `auth.json` itself.
437: - Selection stored separately: only OpenCode sidecar `/persist/state/opencode/box-auth-selection.json`, keyed by auth identity — entrypoint.sh:64-67, auth-state.py:276-335. Muse/Codex: no sidecar.
438:
439: ## 2. Muse (plan §5 Muse)
440:
441: - Persistent-home scope assertion removed: yes. `launch.sh:34-43` resolves `muse_auth_scope/dir` via `box_auth_policy_resolve`; usage text rewritten (launch.sh:15-18); `install.sh:10` drops `box_assert_native_cache "$home/auth.json"` with comment "Setup never inspects native auth."
442: - Trust/settings excluded: adapter never reads them; launch keeps snapshot/backup flow (launch.sh:71-94,103-123) and mounts home writable + settings snapshot read-only (launch.sh:137-139). `auth-adapters.bats:29-32` asserts sibling untouched.
443: - Backend qualification: **comment-only, not enforced**. muse/auth.sh:4-5 claims "file backend only; keychain-only behaviour fails explicitly," but `box_adapter_validate` (auth.sh:16-24) only checks absent-or-regular-JSON-object + `jq`. No keychain/backend detection, no pinned fixture probing, no MCP store handling. Whole-file export silently assumes file content is auth.
444:
445: ## 3. Codex (plan §5 Codex)
446:
447: - Regular-file projection (not bind/symlink): yes. Install writes `tmp.$$` + `chmod 600` + `mv` (codex/auth.sh:46-48); validate/export reject symlinks/non-regular (codex/auth.sh:15,30); launch mounts the whole home dir (launch.sh:112), never a file bind of `auth.json`.
448: - Logout→tombstone: yes. Absent native exports `{tombstone:true,payload:null}` (codex/auth.sh:24-29); `collect=export` (codex/auth.sh:51-53); host collect path `lib/auth.sh:461-493` commits it with bumped revision then scrubs.
449: - `CODEX_HOME` still project-scoped: yes. `launch.sh:40-47` (`$state_root/$project_hash/codex-home`, test `<task-root>/<ns>/codex-home`), mounted at `/home/box/.codex`, `CODEX_HOME=/home/box/.codex` (launch.sh:112,116). Canonical auth is the separate `$codex_auth_dir` mounted at `/run/box-auth` (launch.sh:19-28,115).
450: - Trust/transcripts preserved: `config.toml` trust-subtree rewrite kept (launch.sh:81-87) with comment "regardless of scope."
451:
452: ## 4. OpenCode (plan §5 OpenCode)
453:
454: - Explicit column lists + parameterized SQL: yes. `CREDENTIAL_COLUMNS` allowlist (auth-state.py:28-37); SELECT builds from allowlist∩live cols with quoted identifiers (auth-state.py:83-90); INSERT uses `?` placeholders (auth-state.py:226-234); `UPDATE ... WHERE "id"=?` (auth-state.py:238,356). Column names are interpolated (unavoidable), values are bound.
455: - Sessions/approvals/config excluded: yes. Only `credential` table is SELECT/DELETE/INSERT (auth-state.py:82-104,223,262); `session`/`approval` fixtures asserted unchanged in `auth-adapters.bats:64-83`.
456: - Selection restore only if credential exists: yes. `restore-selection` updates `active=1 WHERE id=?` and warns/leaves unselected on `rowcount==0` (auth-state.py:354-359); install forces `active=0` (auth-state.py:235-238).
457: - No timestamp choice: yes. `save-selection` records active only when exactly one `active=1` row (auth-state.py:314-320, comment "never by timestamps"); else key removed.
458: - Service stopped before collect: partial. Container entrypoint `pkill -f 'opencode.*serve'` before install (entrypoint.sh:60) and again in EXIT trap before `save-selection`+`collect` (entrypoint.sh:75). Host `launch.sh:54-73` does not stop anything — collect is container-side; host `opencode_cleanup` trap is an intentional no-op comment.
459: - WAL hygiene: partial. Helper sets `journal_mode=WAL` + `busy_timeout` (auth-state.py:40-44), consistent `BEGIN IMMEDIATE/COMMIT/ROLLBACK` (auth-state.py:129-141,220-246,260-270); entrypoint guards `.db/-wal/-shm` owner/mode/writability (entrypoint.sh:14-21). No explicit checkpoint; no concurrent-edit guard beyond lease + pkill.
460: - Legacy `auth.json` import disabled/quarantined: **not implemented**. No reference to legacy `auth.json`/quarantine in `entrypoint.sh`, `auth.sh`, `auth-state.py` (grep finds only `.box-legacy` preference backups, entrypoint.sh:34-39). `box_adapter_retire` for OpenCode is unconditional no-op success (opencode/auth.sh:52-59) with rationale "never the live importer path."
461: - MCP endpoint identity (hash name+URL): **not verified**. `integration` column is passed through opaquely (auth-state.py:28-37,73,179,194); no name+URL hash check or MCP-specific branch.
462:
463: ## 5. Migration (plan §6)
464:
465: - Setup performs no migration: yes. `harnesses/muse/install.sh:10-24` only plans home + seeds `state.toml`; `setup.sh:250-251` comment "setup never migrates login material."
466: - First-live-launch refuses without migration record: **partial**. Muse (`launch.sh:97-99`) and Codex (`launch.sh:94`) call `box_auth_migration_gate` (non-reading presence check + refuse, `lib/auth.sh:499-517`). **OpenCode `launch.sh:54-73` never calls `box_auth_migration_gate`** — only `ensure_object` + `transition_plan` + `lease_reserve`; comment says "Volume-backed legacy gate uses non-secret metadata only" but no gate call.
467: - Dry-run reads no credentials: yes for auth planning. `box_auth_plan` (lib/auth.sh:423-436) and all three launch dry-run blocks (muse/launch.sh:64-68, codex/launch.sh:51-55, opencode/launch.sh:37-41) print scope/source/dir/projection only. Note: OpenCode still runs `box_load_credentials` for `providers.env` (launch.sh:51) — unrelated external key file, not the SQLite DB; DB is never opened on dry-run.
468: - Journal `planned→staged→destination-committed→verified→source-retired→complete`: exact strings match plan §6 (auth-ops.sh:8,36-37,199-221 for migrate; 252-264 for copy which skips retire stages and ends at `complete`).
469: - Source retained until verified: yes for migrate — export→stage→publish→re-`validate`→`verified`→`retire` (auth-ops.sh:199-211); rollback copy kept at `$dir/rollback-credentials.json` (auth-ops.sh:204) and legacy moved to `$dir/legacy-auth-rollback.json` (via `box_adapter_retire`). Copy preserves source, refuses differing destination (auth-ops.sh:142-152,260-264).
470: - No merge / no auto-populate / explicit source / ack `fresh|use-existing|copy`: yes. No project enumeration; `box_ops_copy` requires explicit src/dst identities and rejects identical or differing-occupied dst (auth-ops.sh:228-248,260); `box_ops_guard_test_domain` blocks test↔prod mixing (auth-ops.sh:50-60); `box_auth_transition_plan` auto-records first binding then requires `BOX_AUTH_TRANSITION=fresh|use-existing` or explicit copy (lib/auth.sh:541-599). `auth-migrate/copy/init/recover`, `state-plan/remove`, `project-reset` targets exist (Makefile diff `+47`).
471: - Gap: copy journal omits `source-retired` (correct — source preserved) but also `publish` conflict path silently returns 0 on identical payload (auth-ops.sh:147-151).
472:
473: ## 6. Supervisor (plan §5 Shared wrapper)
474:
475: `box/lib/supervisor.sh` (untracked, 109 lines):
476:
477: - Steps present in-code: (1) validate reservation+identity (`box_supervisor_validate`, :28-36, harness+schema+`active`); (4) install (:41-48); (5) run+reap (`box_supervisor_run` runs `$@`, :96-109 — "reap" is caller-trap obligation per comment :92-94); (6) export incl. logout (:57-74); (7) atomic commit w/ revision bump (:69-74); (8) scrub (:75); (9) mark idle (:76-88). No Docker socket references anywhere in supervisor or mounts (grep empty).
478: - Steps (2) deterministic lock acquisition and (3) "record preparation before modifying native auth" are **host-side, not in supervisor**: `box_auth_lease_reserve` + sorted locks (lib/auth.sh:325-359), `box_auth_prepare` (lib/auth.sh:612-633). Supervisor comment (:9-15) acknowledges this split (host file harnesses via launcher EXIT trap; OpenCode via entrypoint).
479: - Shell runs wrapped: yes by placement. Muse/Codex install/reserve/collect traps are installed for all live runs before `box_launch_epilogue`, and tail functions only switch entrypoint for `shell_mode` (muse/launch.sh:95-118,147-175; codex/launch.sh:91-110,124-135). OpenCode shell goes through the same entrypoint trap (`BOX_OPENCODE_SHELL=1` branch after trap, entrypoint.sh:72-89).
480: </subagent>
481:
482: **Tool: subagent**
483:
484: **Input:**
485:
486: `json
487: {
488: 	"agent": "general",
489: 	"description": "Review tests docs lifecycle",
490: 	"prompt": "In /workspace, review uncommitted changes against specs/plan.md sections 7,8,9,10,12 (sequence, test plan, docs/UX, compat, DoD).\n\nRead:\n- specs/plan.md sections 7-10,12\n- git diff for box/Dockerfile, box/lib/run.sh (if changed), box/lib/docker.sh (if changed), box/harnesses/opencode/capture-validation.sh, box/harnesses/*/verify.d/*, box/tests/native/acceptance.sh, box/tests/native/lifecycle-audit.py, box/verify-*.sh, box/Makefile, box/docs/*, box/box-m box/box-o box/box-c box/box-m-login\n- box/tests/bats/state.bats, auth-*.bats, tools.bats/setup.bats/opencode-capture.bats diffs\n- box/.dockerignore, box/check-pins.sh diffs\n\nReport:\n1. Phase ordering violations? Is migration enabled before adapters qualified (plan requires checkpoint)?\n2. Do existing tests still equate home/volume scope with auth scope (plan forbids)?\n3. Capture always in fresh disposable namespace? Verification fragments adapter-aware? gen-verify consistency?\n4. Dry-run reports domain/scope/source/identity/canonical/projection/non-auth/migration-requirement without secrets, no Docker/auth inspection/side-effects?\n5. Lifecycle contract: reset default removes project auth only, --keep-auth retains, global never removed, refuse on active lease, full removal inventories inactive scopes/custom roots/rollbacks? Code-only uninstall preserves?\n6. Backward-compat items 1-12 preserved? Old images rejected? Rollback copies outside importer paths?\n7. Cleanliness: generated files hand-edited vs regenerated? .dockerignore/Makefile/pins consistency? Docs consistency?\nBe factual, cite file:line. Do not fix."
491: }
492: `
493:
494: <subagent sessionID="ses_ee867b175ffe8ayMl4FWWJypzn" state="completed">
495: Review of uncommitted changes vs `specs/plan.md` §§7,8,9,10,12. All citations are current-worktree paths.
496:
497: ## 1. Phase ordering (plan §7) — migration enabled in the same changeset as adapters, no checkpoint gate
498:
499: - The single uncommitted changeset simultaneously adds: adapters (`box/harnesses/muse/auth.sh`, `box/harnesses/codex/auth.sh`, `box/harnesses/opencode/auth.sh`, `box/harnesses/opencode/auth-state.py`), registry/config (`box/lib/tools.sh`, `box/lib/config-file.sh`, `box/lib/auth.sh`), descriptors (`box/lib/state.sh`), lease/supervisor (`box/lib/supervisor.sh`), launch integration (all three `harnesses/*/launch.sh` + `harnesses/opencode/entrypoint.sh`), migration/lifecycle ops (`box/lib/auth-ops.sh`, `box/Makefile` `auth-migrate/auth-copy/auth-init/auth-recover/state-plan/state-remove/project-reset`), capture/verify/native (`capture-validation.sh`, `verify.d/40-readiness-*`, `tests/native/acceptance.sh`, `lifecycle-audit.py`), and docs. Phases 1–7 of §7 land atomically; there is no staged checkpoint.
500: - Live migration enforcement is active now, not gated: `box/harnesses/muse/launch.sh:97-101`, `box/harnesses/codex/launch.sh:92-96`, `box/harnesses/opencode/launch.sh:59-65` call `box_auth_ensure_object` + `box_auth_transition_plan` + (`box_auth_migration_gate` for file harnesses) + `box_auth_lease_reserve` + projection install on every live run. Plan §7 Phase 1 checkpoint requires "no production migration or scope support is enabled until pinned adapters pass synthetic native import/export/logout tests" and Muse backend uncertainties resolved first — this tree enables it unconditionally.
501: - Adapter qualification itself is synthetic-only so far: `box/docs/acceptance.md:65` records the new `auth-*`/`state` Bats as "synthetic credentials prove storage mechanics only; real login/refresh/logout/model/resume need dedicated test accounts". Account-dependent gates remain UNMET per the same file, consistent with plan §11 risk 9, but the code does not enforce the Phase 1 gate (nothing blocks live migration on unqualified backends).
502:
503: ## 2. Existing tests still equate home/volume scope with auth scope (plan §8 forbids)
504:
505: - Plan §8: "Do not retain tests that equate 'Muse home is global' with 'auth must be global,' or 'OpenCode volume is project-scoped' with 'auth must be project-scoped.'"
506: - `box/tests/bats/live-defaults.bats:66-107` is unmodified and now contradicts the new model: it writes `{"synthetic":"auth"}` to `$BOX_M_PERSIST_DIR/auth.json` (`:76`) and asserts byte-preservation after launch (`:107`), treating the home `auth.json` as durable auth. Under the new launcher the same path is a temporary projection (`box/harnesses/muse/launch.sh:53-54`, `:97-101` install/collect/scrub), and the live path with a non-empty legacy `auth.json` and no `migration.json` now hits `box_auth_migration_gate` (`box/lib/auth.sh:499-517`) and dies — the test's stubbed `box_docker_cli/box_docker_exec` harness (`live-defaults.bats:89-94`) was written before the gate existed and is not updated.
507: - No diff touches `live-defaults.bats`, `launchers.bats` dry-run shape tests, `opencode-v2.bats`, or `config.bats` for the §8 rewrites (workspace-vs-resolver identity, supervised entrypoint, mixed-DB-remains-project-scoped + projection lifecycle). New coverage was added alongside (`auth-policy/auth-lifecycle/auth-migration/auth-adapters/state.bats`), but the old assertions were retained as-is.
508:
509: ## 3. Capture, verification fragments, gen-verify (plan §7 Phase 7)
510:
511: - Capture: PASS (with one note). `box/harnesses/opencode/capture-validation.sh:61-80` now mints a fresh disposable task root + namespace (`mktemp -d $HOME/.box-capture.*`, `box_test_new_ns`) outside test mode, forces `BOX_TEST_REAL_HOME/BOX_TEST_TASK_ROOT/BOX_TEST_STATE_NS` (`:140`), resolves the volume only through the disposable resolver (`:81`), and the EXIT trap removes only the capture's own sub-namespace volume via `box_test_guard_cleanup` (`:92-100`, now `|| return 1`) plus the owned task root (`:119-121`). New `box/tests/bats/opencode-capture.bats` test asserts a fresh `t-[12hex]` namespace, root under `$HOME/.box-capture.*`, `BOX_TEST_REAL_HOME=$HOME`, and no `$HOME/.config/box/auth` creation. Note: the non-test scratch parent changed from `$HOME` to the disposable root — intended per §7 ("must not consume global auth merely to inspect configuration").
512: - Verification fragments are adapter-aware: each `harnesses/*/verify.d/40-readiness-*.sh` appends a `/run/box-auth` object-dir-only mount check plus `identity.json` (harness + schema 1), `lease.json` active, and `credentials.json` envelope shape via `jq`, values withheld. OpenCode's comment correctly notes the DB stays project-scoped with only credential rows projected.
513: - `gen-verify` consistency: PASS. `bash box/gen-verify.sh --check` returns `PASS (verify-*.sh match verify.d/ output)`; the `verify-*.sh` diffs are exactly the new partial blocks, i.e. regenerated, not hand-diverged.
514:
515: ## 4. Dry-run (plan §§6,9 + §12 DoD)
516:
517: What dry-run does right:
518:
519: - All three launchers print `Execution domain / Auth scope / Auth policy source / Canonical auth directory / Native projection / Non-auth home|volume` with no secret values (`box/harnesses/muse/launch.sh:64-68`, `box/harnesses/codex/launch.sh:51-55`, `box/harnesses/opencode/launch.sh:37-42`). `box_load_credentials` early-returns on dry-run (`box/lib/preflight.sh:463`), `box_docker_cli` returns before mutation/contact on dry-run (`box/lib/docker.sh:70`), and auth/health asserts are live-only (`muse:70`, `codex:57`). `box_auth_policy_resolve/object_dir` use `box_plan_directory` (no creation), no locks/writes/DB opens on the dry-run path.
520: - `box_auth_policy_source` (`box/lib/auth.sh:183-205`) and UID-keyed, harness-separated object dirs (`box/lib/auth.sh:232-258`) match the §9 metadata list.
521:
522: Gaps vs §9/§6:
523:
524: - Dry-run does **not** report the migration/transition requirement. Plan §9 requires dry-run to report "migration/transition requirement based on non-secret metadata", and §6 requires "dry-run reports the prospective new location and legacy candidate coordinates without reading credential files". The migration gate (`box_auth_migration_gate`, `box_auth_transition_plan`) runs only inside `if (( ! dry_run ))` (`muse:82ff`, `codex:74ff`, `opencode:54ff`); the dry-run output has no legacy-coordinate or transition-required line, and `box_ops_plan` (`box/lib/auth-ops.sh:350-366`) likewise omits it.
525: - OpenCode live path has no `box_auth_migration_gate` call at all (only a comment at `opencode/launch.sh:61-62` that the DB "is opened only by explicit migration"); file harnesses gate on `auth.json` presence (`box/lib/auth.sh:504-514`), but the volume-backed legacy gate is metadata-only by design and never surfaces in dry-run.
526:
527: ## 5. Lifecycle contract (plan §9 table + reset/full-removal rules)
528:
529: Correct:
530:
531: - Reset default removes project auth only; `--keep-auth` retains; global never removed; refuses on active lease: `box/lib/auth-ops.sh:429-438` (active-lease refusal when `!keep_auth && scope==project`), `box_ops_remove_auth:383-384` refuses global-as-project removal, `box_auth_guard_remove:408-418` requires exact identity files, rejects globs, refuses active leases. Reset inventory prints exact descriptors and only deletes with `--execute` (`:440-447`).
532: - Rollback copies are inventoried alongside the identity (`:391-398` lists `migration.json`, `migration-journal.json`, `rollback-credentials.json`, `legacy-auth-rollback.json`).
533:
534: Gaps:
535:
536: - "Full removal must include inactive scopes, custom roots, rollback copies, and recovery projections — not merely the currently effective auth identity." `state-remove` (`box_ops_remove_auth:372-404`) inventories **only the currently effective scope's single directory**; there is no inactive-scope sweep, no `BOX_AUTH_ROOT`/custom-root enumeration, no `state-index`/`bindings`/lease-projection sweep, and no explicit global-identity removal path (global effective scope hard-dies at `:383-384`). Recovery projections outside the one `lease.json` coordinate are not inventoried.
537: - "Refuse reset when an active/unrecovered projection depends on the target": enforced for the file-harness project-auth case (`:429-433`), but when `scope==global` reset silently retains (`:438`) without checking whether the global lease is active — correct to never remove, but the "refuse" vs "retain-and-proceed" distinction for a busy global identity is undocumented in code.
538: - Code-only uninstall preserves: `box/setup.sh` preserves the state policy byte-for-byte (`box/lib/install.sh:box_install_state_policy`, `setup.sh:249-256`) and the package install only refreshes code (`setup.sh:219-244`); docs (`box/docs/operations.md:294-304`) state code-only uninstall retains stores. There is no `uninstall` Make target to audit (grep finds none), so the "full removal inventories…" operator path is docs-only plus the partial `state-remove`/`project-reset`.
539:
540: ## 6. Backward-compat items 1–12 (plan §10)
541:
542: - (1) Fallback scopes preserved: `box/lib/tools.sh:211-219` (`muse auth default_scope=global`, `opencode/codex=project`); asserted in `tools.bats` and `auth-policy.bats:12-14`. PASS.
543: - (2) Production volume names preserved: `box/lib/state.sh:79-87` keeps `<prefix>-u<uid>-g<gid>-<hash>`; `state.bats` asserts `box-m/box-o-v2/box-c` formulas. PASS.
544: - (3) Codex home formulas + root aliases preserved: `box/harnesses/codex/launch.sh:22-42` keeps `BOX_C_STATE_ROOT`/`BOX_C_STATE_DIR` agreement check and `$root/$hash/codex-home`. PASS.
545: - (4) Muse non-auth global home + trust lifecycle: home record stays `global bind` (`tools.sh:215`), trust rewrite path retained in launch; reset wording changed to `global-settings-trust-non-auth`. PASS (modulo item 2's test lag).
546: - (5) OpenCode v2 DB + preference lifecycle: entrypoint still guards WAL/SHM/modes before projection (`entrypoint.sh` pre-existing block untouched); credential rows only via adapter. PASS.
547: - (6) "Introduce auth configuration/descriptors before enabling migration": VIOLATED in ordering terms — config/descriptors and migration enablement ship in one changeset (see §1); no sequencing enforcement.
548: - (7) Explicit migration required: PASS for file harnesses via gate (`box/lib/auth.sh:513-515`); OpenCode requires explicit `--db-path` export (`auth-ops.sh:107`), never auto-opens a volume. PASS.
549: - (8) Rollback copies outside importer paths: PASS. `rollback="$dir/rollback-credentials.json"` (`auth-ops.sh:203-204,258-259`) and `box_adapter_retire … "$dir/legacy-auth-rollback.json"` (`:210`) live in the auth object; OpenCode `retire` is a documented no-op since the source is an explicit export copy (`harnesses/opencode/auth.sh:box_adapter_retire`).
550: - (9) Migration + tombstone records: PASS. `migration.json` (`auth-ops.sh:212-220,283-290`), journal stages `planned→…→complete` (`:36-37`), tombstone envelopes in all three adapters.
[Output truncated. Continue reading with offset: 551]

**Tool: read**

**Input:**

```json
{
	"path": "/workspace/specs/passes/pass-2.md"
}
```

Read file /workspace/specs/passes/pass-2.md, lines 1-79
1: # plan.md uncommitted implementation check
2:
3: **Session ID:** ses*ee84de0f4ffeHU2PE5QxpQSTwi
4: **Created:** 10/7/2026, 6:48:31 PM
5: **Updated:** 10/7/2026, 6:48:58 PM
6:
7: ---
8:
9: ## User
10:
11: double check if @specs/plan.md has been implemented correctly and cleanly (uncomitted changes)
12:
13: first pass context: @specs/pass-1.md
14:
15: ---
16:
17: ## Assistant
18:
19: \_Thinking:*
20:
21: Synthesizing subagent findings to assess implementation correctness and cleanliness against the plan and uncommitted changes.
22:
23: _Thinking:_
24:
25: Condensing subagent findings into a concise verdict with file:line citations and severity-ranked gaps.
26:
27: Core model is in place but DoD isn't met — compiling the full gap list with evidence.
28:
29: **Tool: shell**
30:
31: **Input:**
32:
33: `json
34: {
35: 	"command": "bash box/gen-verify.sh --check 2>&1 | tail -n 5; echo \"---BATS-AUTH-POLICY---\"; bats box/tests/bats/auth-policy.bats 2>&1 | tail -n 20",
36: 	"workdir": "/workspace"
37: }
38: `
39:
40: gen-verify.sh: PASS (verify-\*.sh match verify.d/ output)
41: ---BATS-AUTH-POLICY---
42: /bin/bash: line 1: bats: command not found
43:
44: Command exited with code 0.
45:
46: ---
47:
48: ## Assistant
49:
50: _Thinking:_
51:
52: No — happy-path present, `specs/plan.md` DoD not met.
53:
54: Correct:
55:
56: - Registry: `box/lib/tools.sh:217,220,223` one `auth` record/harness, `class=auth,scope=auth-policy,kind=bind,runtime=/run/box-auth,mode=700,schema=1`, fallbacks `global/project/project`. Validated `box/lib/tools.sh:388-421`.
57: - Precedence `box/lib/auth.sh:174-178` matches §3. `BOX_C_AUTH` independent (`box/harnesses/codex/launch.sh:73` only).
58: - Layout `box/lib/auth.sh:249-256`, `box/lib/state.sh:114-130`: `R/H/uU/global`, `R/H/uU/projects/P`, UID-keyed, `700/600`, object-dir-only mount (`box/harnesses/codex/launch.sh:115`, `box/harnesses/muse/launch.sh:141`, `box/harnesses/opencode/launch.sh:91`).
59: - Envelope `{schema,revision,tombstone,payload}`; Codex `tmp+mv` + tombstone `box/harnesses/codex/auth.sh:24-48`; OpenCode explicit columns + `?` binds `box/harnesses/opencode/auth-state.py:28-37,83-90,226-238`, single-active selection `box/harnesses/opencode/auth-state.py:314-320`.
60: - Capture fresh ns `box/harnesses/opencode/capture-validation.sh:61-80`; `gen-verify.sh --check` PASS.
61:
62: Must-fix:
63:
64: 1. Phase-1 gate violated: live `ensure_object+transition+reserve+install` unconditional `box/harnesses/muse/launch.sh:97-101`, `box/harnesses/codex/launch.sh:92-96`, `box/harnesses/opencode/launch.sh:59-65`. Muse backend unresolved.
65: 2. OpenCode live missing `box_auth_migration_gate` (`box/harnesses/opencode/launch.sh:59-65` comment only).
66: 3. Legacy quarantine missing; OpenCode `retire` no-op `box/harnesses/opencode/auth.sh:52-59`.
67: 4. Muse qualification comment-only `box/harnesses/muse/auth.sh:16-24`; no keychain/MCP detection. MCP hash/account-table unverified (`box/harnesses/opencode/auth-state.py` passes `integration` opaquely).
68: 5. Shared-lib harness branch violates §2: `box/lib/auth-ops.sh:95-112` `case $id`.
69: 6. Old test contradicts new model: `box/tests/bats/live-defaults.bats:66-107` treats `$BOX_M_PERSIST_DIR/auth.json` as durable, now projection + gate target.
70: 7. Dry-run omits migration/transition + legacy coordinates required §6/§9 (`box/harnesses/muse/launch.sh:64-68`, `box/harnesses/codex/launch.sh:51-55`, `box/harnesses/opencode/launch.sh:37-42`).
71: 8. `state-remove` only effective scope `box/lib/auth-ops.sh:372-404` (global dies `:383-384`); no inactive-scope/custom-root/projection sweep.
72: 9. §10.10/11 missing: no old-image/supervisor rejection; `box_ops_migrate:163-223` no stopped-container check.
73: 10. Validation: `__unset__` accepted as unset `box/lib/auth.sh:140-174`; `BOX_STATE_CONFIG=""`/`BOX_AUTH_ROOT=""` silently default `:40,:210`; `policy_source:190-191` skips config validation; `jq`-absent fail-open `box/lib/auth.sh:345,414`, `box/lib/auth-ops.sh:430`.
74:
75: Cleanliness:
76:
77: - Triplicated auth-dir formula `box/lib/test-state.sh:258`, `box/lib/auth.sh:232`, `box/lib/state.sh:114-130`; old `box_project_identity` still live `box/lib/launcher.sh:92,458`.
78: - Dead: `box_config_get_optional` (`box/lib/config-file.sh:138-172` zero callers), `box/lib/test-state.sh:199-208` no-op, `box/lib/auth-ops.sh:129-141` `if False`.
79: - Fragile: `box/lib/state.sh:239-246` `grep -q` empty-pattern bypass; `box/lib/auth.sh:333-342` fd leak on `die`; docs retain inline hash `box/docs/operations.md:253-270`; `.dockerignore` `!harnesses/muse/` over-broad.

**Tool: read**

**Input:**

```json
{
	"path": "/workspace/specs/plan.md"
}
```

Read file /workspace/specs/plan.md, lines 1-839
1: # 1. Current-state inventory
2:
3: **Recommendation:** add a declarative `auth` state to the existing registry, backed by a shared scope resolver and guarded lifecycle operations. Use an auth-only canonical store and client-specific projections into native storage. For the currently pinned clients, serialize access to each auth identity and preserve interrupted projections for recovery.
4:
5: This avoids moving mixed homes or databases into global scope. It also avoids relying on file mounts or symlinks that break when a client replaces or deletes its credential file.
6:
7: No repository files were modified.
8:
9: ## Investigation baseline
10:
11: Inspected:
12:
13: - Repository-local `AGENTS.md` and `box/README.md`.
14: - Production base: `b9303c487838b0bee4c7111829aa1c5b6d905a25`.
15: - PR #2 head and local checkout: `c85d13ca5706ba865bdede73b8aa8021df8a28ff`.
16: - All materially relevant PR changes, registry and launcher helpers, setup/install/preflight/configuration paths, harness adapters, capture, verification, Bats, native acceptance, lifecycle audit, and operational documentation.
17: - Pinned OpenCode `v2.0.6` source, commit `b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad`.
18: - Pinned Codex `rust-v0.160.0` source, commit `a956835d020762cb2b570053af06f643a11c0ecc`.
19: - Official client documentation where available.
20:
21: The production base already has declarative `_BOX_STATES` records. PR #2 adds test identity resolution, stronger registry validation, and disposable cleanup authorization; it does not separate production authentication from mixed native stores. Its isolation contract must remain intact. [PR #2](https://github.com/temrb/box/pull/2)
22:
23: The pinned releases are Muse `1.4.0-R4161.1`, OpenCode `2.0.6`, and Codex `0.160.0`. Native clients and Docker were not available for exercising Muse/OpenCode here; repository runtime evidence is historical evidence, not a fresh validation of authenticated behavior.
24:
25: ## Existing identities and ownership
26:
27: Production project identity is:
28:
29: - Physical workspace root selected by sanitized Git discovery or `--project-root`.
30: - `P = first 20 hexadecimal characters of SHA256(physical workspace-root path)`.
31: - Canonical project volume: `<state_prefix>-u<UID>-g<GID>-<P>`.
32:
33: Current prefixes are `box-m`, `box-o-v2`, and `box-c`.
34:
35: Physical aliases and symlinks resolve to the same identity. Moving or renaming the physical workspace changes `P`; old state remains.
36:
37: Host persistent directories must be outside the project, user-owned, symlink-free, and protected from writable ancestors. Native credential caches require regular files, accepted credential modes, and writability for refresh. Docker images run as the invoking UID/GID. `/persist` starts with user-owned image seed directories.
38:
39: ## Muse
40:
41: | Category | Verified storage/boundary | Classification and existing lifecycle |
42: | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
43: | Provider login credentials | Host `~/.config/box-m/muse-config/auth.json`; parent overridden by `BOX_M_PERSIST_DIR`; mounted under `/home/box/.config/muse` | Auth; shared across projects |
44: | External API key | Protected shared `providers.env`; only `MUSE_CODE_API_KEY` forwarded | External credential source; separately managed |
45: | Trust | Repository describes `.trust.json` beside settings/auth | Auth-adjacent security state; presently global |
46: | Preferences/settings | Installed host `settings.json`, directory overrides, private launch snapshot mounted read-only | Unrelated; live configuration, not durable UI saves |
47: | Legacy preferences | `settings.json.box-legacy` in persistent Muse home | Unrelated protected backup |
48: | Sessions/history/transcripts | Persistent native data/state roots; `/home/box/.muse` points to `/persist/data/muse` | Unrelated project state |
49: | Native data/state | `XDG_DATA_HOME=/persist/data/muse`, `XDG_STATE_HOME=/persist/state/muse` | Project volume lifecycle |
50: | Cache | Base image `XDG_CACHE_HOME=/home/box/.cache` | Container-lifetime unless written inside workspace/persist |
51: | Approvals | Native prompting/session behavior; no separate durable approval store established by repository evidence | Retain native/session lifecycle |
52: | Account/provider selection | May be embedded in auth or settings; exact pinned representation is not established | Must distinguish intrinsic credential identity from selection before adapter promotion |
53:
54: The full Muse config parent is writable, with a read-only settings overlay. Setup prepares the default global home; launch validates `auth.json` only on live runs. Project-volume reset currently preserves global auth/trust.
55:
56: Official Muse documentation establishes settings discovery through `XDG_CONFIG_HOME`, but documents `trust.json`, whereas the repository names `.trust.json`. Resolve that difference against the pinned binary before changing trust handling. [Muse extension locations](https://meta-models.github.io/muse-code-sdk/next/guides/extend/)
57:
58: Muse also supports MCP OAuth credentials. Official documentation describes credential refresh and local removal on MCP logout, but the exact pinned credential filename/backend was not established. Do not silently include an unidentified MCP store in migration. [Muse MCP authentication](https://meta-models.github.io/muse-code-sdk/next/guides/extend/mcp-servers/)
59:
60: Exact session/transcript leaf names are not proven by current repository evidence. The known containment boundary is the project volume and native data/state roots; retain that boundary.
61:
62: ## OpenCode
63:
64: | Category | Verified storage/boundary | Classification and existing lifecycle |
65: | ---------------------------- | ------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
66: | Provider/MCP credentials | `/persist/data/opencode/opencode/opencode.db`, `credential` table | Auth; currently project-scoped |
67: | Credential values | `credential.value`: typed key or OAuth value, including refresh/access/expiry and metadata | Auth |
68: | Saved account inventory | `credential.id`, integration, label, method/connection metadata | Auth identity metadata |
69: | Active credential selection | `credential.active` | Auth-adjacent selection; currently project-scoped |
70: | Account tokens | Schema contains `account` and legacy `control_account`, including access/refresh tokens | Auth-bearing schema; active use requires pinned adapter verification |
71: | Active account/org | `account_state`; legacy `control_account.active` | Auth-adjacent selection |
72: | Sessions/history/transcripts | Same mixed SQLite database | Unrelated project state |
73: | Saved approvals | Same database, exercised by native permission probe | Unrelated project security state |
74: | Preferences | `/persist/config/opencode`; `cli.json`, `tui.json`, `opencode.jsonc` backed up and removed before client execution | Unrelated; existing reset-on-launch policy |
75: | Host defaults | `~/.config/box-o/opencode.json`, mounted read-only | Unrelated installed configuration |
76: | Data/logs/repos | App-suffixed paths under `/persist/data/opencode` | Unrelated project state |
77: | Service state | App-suffixed paths under `/persist/state/opencode`; service configuration under config parent | Unrelated project state |
78: | Cache | App-suffixed cache beneath `/home/box/.cache` | Container-lifetime |
79: | Legacy `auth.json` | Legacy importer, not native v2 login store | Legacy auth; must prevent uncontrolled re-import |
80:
81: The entrypoint guards the database and its WAL/SHM files: regular, user-owned, writable, mode `600`, with non-symlink parents. It serializes preference reset, then releases that lock before execution.
82:
83: Pinned source confirms:
84:
85: - `Credential.Service` uses `Database.Service`.
86: - Credential creation, activation, update, and removal operate on the mixed database.
87: - Removing an active credential may activate another saved credential.
88: - Database initialization uses WAL, a busy timeout, and an in-process bootstrap semaphore. Those mechanisms do not establish safe cross-process OAuth refresh coordination.
89: - MCP integration identity includes a hash of server name and URL, rather than name alone.
90:
91: Relevant source: [credential service](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/credential.ts), [credential schema](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/credential/sql.ts), [account schema](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/account/sql.ts), [database service](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/database/database.ts).
92:
93: `OPENCODE_DB` redirects the database as a whole. It does not independently redirect auth. Moving that database globally would also share sessions and approvals. [OpenCode database location](https://opencode.ai/v2/docs/troubleshooting/)
94:
95: Native logout removes a selected saved account; it does not necessarily remove every account for the provider. Preserve that distinction in UX. [OpenCode auth commands](https://opencode.ai/v2/docs/cli/commands/)
96:
97: ## Codex
98:
99: | Category | Verified storage/boundary | Classification and existing lifecycle |
100: | ------------------------------ | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
101: | Cached login | `<state_root>/<P>/codex-home/auth.json` | Auth; currently project-scoped |
102: | Host home root | Default `~/.config/box-c/projects`; `BOX_C_STATE_ROOT`, legacy `BOX_C_STATE_DIR` | Mixed project home |
103: | Container home | `/home/box/.codex`, `CODEX_HOME=/home/box/.codex` | Project bind |
104: | Credential identity/mode | Fields in `auth.json`, including API key or token/account material and refresh metadata | Auth |
105: | Provider selection/preferences | Installed/system configuration, home configuration, allowed native directory configuration | Unrelated or auth-adjacent selection |
106: | Trust | `[projects.…].trust_level` retained in home `config.toml` | Auth-adjacent security state; project home lifecycle |
107: | Sessions/transcripts/history | Native home, including documented `history.jsonl`; other native session/log/cache files | Unrelated project-home lifecycle |
108: | SQLite runtime state | `/persist/state/codex`, constrained by configuration and image requirements | Unrelated project-volume lifecycle |
109: | Approval defaults | Installed config and image-owned requirements | Unrelated policy |
110: | Approval/session facts | Native runtime/session stores | Unrelated project lifecycle |
111: | External API key | Protected provider file, explicitly imported or forwarded through `BOX_C_AUTH=api` | Separately managed external credential |
112: | MCP OAuth | Separate native OAuth credential machinery | Auth, distinct from provider `auth.json`; exact supported store must be included in adapter qualification |
113:
114: The launcher backs up home preferences, retains trust records, and releases its preference lock before container startup. Removing only the volume retains home auth/transcripts; removing only the home retains SQLite state.
115:
116: Official documentation confirms file auth under `CODEX_HOME`, automatic refresh, and separate keyring modes. The repository enforces file credentials. [Codex authentication](https://learn.chatgpt.com/docs/auth)
117:
118: Pinned file-storage source opens/truncates `auth.json` when saving and unlinks it when deleting. It does not supply a cross-process file lock in that backend. Therefore:
119:
120: - A bind-mounted credential file cannot reliably support native unlink.
121: - A symlink alone cannot implement logout: deleting the symlink leaves the canonical target.
122: - Changing all of `CODEX_HOME` would change unrelated state scope.
123:
124: [Codex 0.160.0 file-storage implementation](https://github.com/openai/codex/blob/a956835d020762cb2b570053af06f643a11c0ecc/codex-rs/login/src/auth/storage.rs)
125:
126: ## PR #2 test state
127:
128: Verified current formulas:
129:
130: - Volume: `box-test-<namespace>-<state_prefix>-u<UID>-g<GID>`.
131: - Codex home: `<BOX_TEST_TASK_ROOT>/<namespace>/codex-home`.
132: - Capture namespace: `<parent>-cap-<8hex>`.
133: - Partial or malformed test configuration fails closed.
134: - Overrides must remain inside the disposable task root.
135: - Cleanup checks exact resolver identity and recorded coordinates.
136: - Capture owns an independent namespace.
137: - Native drivers currently allocate different namespaces to different projects.
138:
139: The last point means current native tests do not yet demonstrate two physical projects sharing one test-global auth identity. That coverage must be added without allowing production fallback.
140:
141: # 2. Target architecture
142:
143: ## Declarative state model
144:
145: Extend `_BOX_STATES`; do not replace it.
146:
147: Add exactly one selectable `auth` state per harness. Add narrowly scoped state fields:
148:
149: | Field | Purpose |
150: | ---------------- | --------------------------------------------------------------- |
151: | `class` | `auth` or existing non-auth class |
152: | `scope` | Fixed scope or `auth-policy` |
153: | `default_scope` | Harness fallback: `global` or `project`; empty for fixed states |
154: | `adapter` | Declared native storage adapter path |
155: | `schema_version` | Box auth envelope/adapter contract version |
156:
157: Existing `kind`, `root`, `override`, `runtime`, `mode`, and `reset` remain. Auth records use:
158:
159: - `class=auth`
160: - `scope=auth-policy`
161: - `kind=bind`
162: - Shared protected auth root
163: - `runtime=/run/box-auth`
164: - `mode=700`
165: - Explicit auth reset semantics
166:
167: Retain existing home and volume records, but rewrite reset descriptions to distinguish non-auth contents from temporary native auth projections.
168:
169: Validate that every harness has exactly one auth record, a supported adapter, a valid fallback scope, and its canonical `/persist` volume.
170:
171: ## Resolver boundaries
172:
173: Add `box/lib/state.sh` as the authoritative state identity/location resolver.
174:
175: Proposed functions:
176:
177: - `box_state_context`: validated harness, UID/GID, physical project, execution domain.
178: - `box_state_resolve`: produces a descriptor for an explicitly requested state.
179: - `box_state_validate_descriptor`: validates a descriptor without mutation.
180: - `box_state_guard_operation`: authorizes an explicit operation against exact descriptors.
181: - `box_state_cli`: machine-readable descriptor output for Python/native consumers.
182:
183: Add `box/lib/auth.sh` for:
184:
185: - `box_auth_policy_resolve`
186: - `box_auth_plan`
187: - `box_auth_prepare`
188: - `box_auth_transition_plan`
189: - `box_auth_lease_reserve`
190: - `box_auth_recover`
191: - `box_auth_guard_remove`
192:
193: The resolver returns structured metadata, including domain, harness, class, scope, UID, project hash where applicable, paths, mount target, adapter, and schema. Callers must not rebuild names.
194:
195: This replaces duplicated identity logic in:
196:
197: - `box_project_identity`
198: - Codex home derivation
199: - Muse persistent-home handling
200: - OpenCode capture volume derivation
201: - Operational reset examples
202: - Native acceptance/lifecycle inventories
203:
204: Keep workspace discovery in `launcher.sh`; pass its existing physical-root result into the state resolver.
205:
206: ## Canonical auth and native projections
207:
208: The canonical auth object contains **auth material only**. Native homes/databases remain their existing scopes.
209:
210: Each adapter supports:
211:
212: 1. Validate supported native storage/schema.
213: 2. Export auth without unrelated records.
214: 3. Export selection separately.
215: 4. Install a canonical auth projection.
216: 5. Collect changes, including logout and refresh.
217: 6. Scrub only the projection.
218: 7. Recover an interrupted projection.
219:
220: Use a versioned, mode-`600` `credentials.json` envelope:
221:
222: - Harness and adapter schema.
223: - Auth revision.
224: - Native auth payload.
225: - Explicit absence/tombstone state.
226: - No project preferences, trust, approvals, sessions, or transcripts.
227: - No active account/provider selection unless inseparable from the credential’s intrinsic identity.
228:
229: A canonical store is authoritative while idle. During an active lease, the recorded native projection is authoritative for uncommitted auth updates. Recovery must collect it before another launch can import the previous canonical revision.
230:
231: This is a managed import/export layer, **not best-effort synchronization**. There are no periodic “last writer wins” copies.
232:
233: ## Why adapters are necessary
234:
235: Shared code branches on declared storage mechanics or invokes the declared adapter; it never branches on harness names.
236:
237: - Muse adapter: native file/backend semantics and unresolved pinned storage details.
238: - Codex adapter: file save/unlink behavior and native credential schema.
239: - OpenCode adapter: auth rows embedded in a mixed SQLite database, foreign keys, and selection fields.
240:
241: These cannot reasonably be represented by path strings alone.
242:
243: A future client-supported auth path can replace projection mechanics within its adapter. Scope configuration, identities, migration authorization, and launcher consumption remain unchanged.
244:
245: ## Concurrency contract
246:
247: Initial implementation permits **one active writer per auth identity**.
248:
249: Also lock each native projection store:
250:
251: - Codex: project home.
252: - OpenCode: project database/volume.
253: - Muse: existing global native config home.
254:
255: Consequences:
256:
257: - Global auth serializes projects sharing that harness/user identity.
258: - Project auth permits independent projects, except Muse’s existing shared config parent still requires serialization.
259: - Busy launches fail promptly with non-secret identity metadata.
260: - Do not silently wait indefinitely.
261: - Login, logout, shell execution, refresh-capable runs, migration, reset, and recovery obey the same locks.
262:
263: This restriction is required because SQLite writer locking does not coordinate remote token rotation, and Codex file storage does not provide the required inter-process serialization.
264:
265: ## Test-specific boundary
266:
267: Keep in `test-state.sh`:
268:
269: - Test activation/partial-configuration rejection.
270: - Namespace validation and generation.
271: - Task-root validation.
272: - Capture subnamespace ownership.
273: - Explicit test cleanup authorization.
274:
275: Reuse only pure primitives: physical-project hashing, descriptor construction, numeric identity validation, and containment checks.
276:
277: The dispatcher selects the test domain **before** evaluating production roots or legacy discovery. Tests never call production migration/import/recovery. A test descriptor cannot be converted into a production descriptor.
278:
279: Extend test root exclusion using registry-declared protected roots, including the new auth root. Do not preserve its current hardcoded production-root list as a second authority.
280:
281: # 3. Effective configuration matrix
282:
283: ## Defaults and user configuration
284:
285: Preserve existing auth scope as registry fallbacks:
286:
287: | Harness | Registry fallback | Reason |
288: | -------- | ----------------- | ------------------------------ |
289: | Muse | `global` | Preserve current login sharing |
290: | OpenCode | `project` | Preserve current isolation |
291: | Codex | `project` | Preserve current isolation |
292:
293: Use optional, protected host configuration:
294:
295: `~/.config/box/state.toml`
296:
297: Proposed configuration:
298:
299: `toml
300: schema_version = 1
301:
302: [auth]
303: default_scope = "project"
304:
305: [auth.harnesses.muse]
306: scope = "global"
307: `
308:
309: Omitting `default_scope` means use harness registry fallbacks. Omitting a harness override means inherit the common policy, then its registry fallback.
310:
311: For a new installation, seed a versioned file with no explicit scope settings. Setup reruns preserve it byte-for-byte.
312:
313: ## Runtime interface
314:
315: - `BOX_AUTH_SCOPE`: common runtime policy.
316: - `BOX_M_AUTH_SCOPE`, `BOX_O_AUTH_SCOPE`, `BOX_C_AUTH_SCOPE`: harness runtime overrides, derived through existing registry `git_prefix`.
317: - `BOX_STATE_CONFIG`: optional absolute path to an existing protected state configuration.
318: - `BOX_AUTH_ROOT`: optional absolute protected root for canonical auth objects.
319:
320: `BOX_C_AUTH` remains the independent authentication-mode/key-forwarding setting. It must never select persistence scope.
321:
322: ## Exact precedence
323:
324: Highest first:
325:
326: 1. Selected harness runtime scope.
327: 2. Common runtime `BOX_AUTH_SCOPE`.
328: 3. Selected harness scope in installed/user configuration.
329: 4. Common `auth.default_scope` in that configuration.
330: 5. Selected harness registry fallback.
331:
332: Configuration file selection:
333:
334: 1. Explicit `BOX_STATE_CONFIG`.
335: 2. Optional default `~/.config/box/state.toml`.
336:
337: Validate **all supplied values before resolution**, including shadowed values. An invalid lower-precedence value must not be hidden by a valid override.
338:
339: ## Validation and inheritance
340:
341: - Accepted scope strings: exactly `global` or `project`.
342: - Unset environment variable: inherit.
343: - Set-but-empty variable: error.
344: - Omitted configuration key: inherit.
345: - Empty string, wrong type, unknown harness/key, unsupported schema, duplicate TOML declaration: error.
346: - Explicit missing config file: error.
347: - Missing implicit default config file: valid pre-upgrade absence.
348: - Present unreadable/unsafe config file: error.
349: - Unsafe root or conflicting legacy root aliases: error.
350: - No native project configuration may set Box auth scope.
351: - Never source configuration as shell code.
352: - Use `config-file.sh` for TOML parsing and a shared schema validator for optional fields.
353:
354: Resolve and validate policy before creating directories, contacting Docker, inspecting native credentials, acquiring auth locks, or preparing projections.
355:
356: Scope is configurable at runtime and durably through user configuration. Setup installs the interface; it does not migrate login material.
357:
358: Changing policy selects a different identity. It does not implicitly copy or merge credentials.
359:
360: # 4. State-layout design
361:
362: The following are **proposed new paths**. Existing native paths remain as inventoried above.
363:
364: Define:
365:
366: - `H`: registered harness ID.
367: - `U`: validated nonzero host UID.
368: - `G`: host GID used for ownership/runtime compatibility.
369: - `P`: existing 20-hex physical-project hash.
370: - `R`: `BOX_AUTH_ROOT`, otherwise `$HOME/.config/box/auth`.
371: - `N`: validated disposable namespace.
372: - `T`: validated disposable task root.
373:
374: ## Production auth identities
375:
376: | Scope | Logical identity | Auth object directory |
377: | ------- | -------------------------------------- | --------------------- |
378: | Global | `(production, H, auth, U, global)` | `R/H/uU/global/` |
379: | Project | `(production, H, auth, U, project, P)` | `R/H/uU/projects/P/` |
380:
381: Use UID, not GID, as the auth identity key: changing a user’s primary group must not silently create another login identity. Record and validate ownership; group ownership is operational metadata.
382:
383: Existing non-auth volumes retain UID/GID naming.
384:
385: Each auth object contains explicit leaves:
386:
387: - `identity.json`: non-secret identity/schema metadata.
388: - `credentials.json`: auth envelope.
389: - `lease.json`: non-secret active/recovery record.
390: - `lock`: stable lock inode, never replaced.
391: - Explicitly recorded transaction/staging leaves during migration.
392:
393: Mount only the selected object directory at `/run/box-auth`, writable, with existing non-recursive/private bind flags. Do not mount the shared auth root or all harness/user objects.
394:
395: Directories: user-owned `700`. Files: user-owned `600`. Credential state must be writable. Reject unsafe existing metadata rather than silently repairing it.
396:
397: ## Test auth identities
398:
399: | Scope | Logical identity | Directory |
400: | ------------ | ----------------------------------- | --------------------------- |
401: | Test-global | `(test, N, H, auth, U, global)` | `T/N/auth/H/uU/global/` |
402: | Test-project | `(test, N, H, auth, U, project, P)` | `T/N/auth/H/uU/projects/P/` |
403:
404: “Global” in tests means shared only inside one disposable namespace. Another namespace gets another auth identity.
405:
406: Retain PR #2’s current non-auth volume formula and Codex-home resolver for existing tests. Add dedicated scope tests with two projects in one namespace. Where those tests require independent non-auth stores, extend the test resolver with an explicit project-qualified fixture identity; never inline a new naming formula in callers.
407:
408: No auth Docker volumes are required. Canonical auth is a protected bind; project `/persist` volumes remain unchanged.
409:
410: ## Auxiliary lifecycle metadata
411:
412: Add a protected, non-secret index beneath `$HOME/.config/box/state-index/`:
413:
414: - Known exact descriptors.
415: - Explicit custom roots.
416: - Project-to-auth binding acknowledgments.
417: - Native projection coordinates.
418: - Migration/recovery transaction identifiers.
419:
420: Test indexes live under `T/N/`.
421:
422: The index is discovery metadata, not deletion authority. Every operation re-resolves and validates each candidate. Missing entries never authorize prefix/glob cleanup.
423:
424: Retain full physical paths in project descriptors for collision checking. If two paths produce the same truncated hash, fail; do not share state.
425:
426: Moves change project auth identity but retain global auth identity. Physical aliases retain both identities.
427:
428: # 5. Harness adaptation
429:
430: ## Muse
431:
432: Modify `harnesses/muse/launch.sh` and `install.sh`:
433:
434: - Remove the assertion that the persistent home itself defines auth scope.
435: - Continue resolving `BOX_M_PERSIST_DIR` as the non-auth native config home.
436: - Preserve existing trust, settings snapshot, preference backup, and project `/persist` behavior.
437: - Project the selected auth envelope into native `auth.json` while holding both auth and native-home leases.
438: - Collect refresh/login/logout changes before releasing the lease.
439: - Remove projected auth after successful collection.
440: - Keep auth backups outside the live native-home bind.
441: - Stop setup from inspecting native auth as part of ordinary installation.
442:
443: Add `harnesses/muse/auth.sh` and bounded native qualification fixtures.
444:
445: Before promotion, establish the pinned file backend, supported empty/no-login representation, logout behavior, and all additional credential stores. Unsupported/keychain-only behavior must fail explicitly; do not reinterpret an auth pointer as a plaintext token store.
446:
447: Trust filenames and contents are excluded from auth export.
448:
449: ## Codex
450:
451: Modify `harnesses/codex/launch.sh`:
452:
453: - Keep existing project-home resolution and root alias agreement.
454: - Keep `CODEX_HOME` project-scoped.
455: - Keep `/persist/state/codex` project-scoped.
456: - Replace direct auth-home lifecycle assumptions with the resolved auth descriptor.
457: - Project the canonical provider login into the native home as a regular `auth.json`.
458: - Treat native removal as logged-out state; export a tombstone.
459: - Preserve trust rewrite, transcripts, history, logs, preferences, and SQLite state.
460:
461: Add `harnesses/codex/auth.sh` with native schema validation and auth-only import/export.
462:
463: Do not use file bind mounts or permanent credential symlinks. Do not change credential-store requirements to keyring/auto.
464:
465: Preserve explicit API-key import and NAME-only forwarding. Provider-file credentials remain independently managed.
466:
467: Qualify MCP OAuth storage separately; include discovered credential leaves as declared adapter members, with their corresponding selection/security state excluded. If a supported feature cannot be safely separated, reject its use under the new managed mode until qualified.
468:
469: ## OpenCode
470:
471: Add `harnesses/opencode/auth-state.py` and `auth.sh`; update `entrypoint.sh`.
472:
473: Implement schema-bound SQLite projection:
474:
475: - Verify the pinned schema before operating.
476: - Use explicit column lists and parameterized statements.
477: - Export supported `credential` auth records.
478: - Preserve IDs, integration IDs, labels, values, method/connection metadata, and timestamps.
479: - Store `active` selections separately in project state.
480: - Handle supported `account`/legacy auth records only through a verified adapter schema.
481: - Preserve `account_state` and equivalent selections in project state.
482: - Do not export sessions, messages, events, saved approvals, workspace/project rows, configuration, caches, or logs.
483: - Restore selection only when its credential still exists.
484: - If multiple credentials exist and a new project has no selection, require explicit native selection; do not choose by timestamps.
485: - Allow an auth-selection operation without executing a model turn.
486:
487: Place selection sidecar metadata under the existing project state root, for example `/persist/state/opencode/box-auth-selection.json`. Key selections by auth identity so switching scopes does not overwrite another scope’s remembered selection.
488:
489: Use SQLite transactions and retain WAL/SHM hygiene. Stop and reap the native background service before collecting/scrubbing. Never edit the database concurrently with the client.
490:
491: For a fresh native database, perform bounded native schema initialization before projection, then stop the service. Do not reconstruct the entire upstream schema in Box.
492:
493: Scrubbing removes only supported auth rows and adjusts unavoidable credential foreign-key references. Saved selection is retained separately for restoration. Check unrelated tables remain unchanged.
494:
495: Disable uncontrolled legacy `auth.json` import after migration. Detect and quarantine explicitly authorized legacy files outside normal native importer paths.
496:
497: Include MCP credentials in the same scope only where integration identity is stable and endpoint-bound. The pinned MCP implementation hashes name and URL; preserve those IDs. Unknown credential payload/schema versions fail closed. [Pinned MCP integration identity](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/mcp/index.ts)
498:
499: ## Shared execution wrapper
500:
501: Add an image-installed supervisor around ordinary, auth, and shell runs.
502:
503: It must:
504:
505: 1. Validate the reserved lease and adapter version.
506: 2. Acquire auth and projection locks in deterministic order.
507: 3. Record projection preparation before modifying native auth.
508: 4. Install auth.
509: 5. Run and reap the client and supported background service.
510: 6. Export valid resulting auth, including logout.
511: 7. Atomically commit the canonical revision.
512: 8. Scrub the native projection.
513: 9. Mark the lease idle.
514:
515: A shell run also needs the wrapper: it can execute native login/logout or alter credential storage.
516:
517: Do not give the container Docker socket access.
518:
519: # 6. Migration design
520:
521: ## Installation migration
522:
523: Setup performs no credential migration.
524:
525: On the first live launch after upgrade:
526:
527: - Resolve policy and new auth identity.
528: - Inspect only explicitly resolved legacy stores for that harness/project.
529: - If legacy credentials exist without a completed migration record, refuse launch with an actionable migration requirement.
530: - Dry-run reports the prospective new location and legacy candidate coordinates without reading credential files/databases.
531:
532: Provide explicit Make targets backed by the same resolver:
533:
534: - `auth-migrate`: legacy native auth → selected canonical identity.
535: - `auth-copy`: explicitly selected canonical source → destination.
536: - `auth-init`: acknowledge a fresh identity without importing.
537: - `auth-recover`: resolve interrupted lease/transaction.
538: - `state-plan` and `state-remove`: lifecycle operations.
539:
540: These are operational actions; inspection remains available through launcher dry-run.
541:
542: ## Source discovery
543:
544: - Muse: exact resolved legacy `auth.json` and qualified credential members.
545: - Codex: exact selected project home and qualified credential members.
546: - OpenCode: exact selected v2 project volume/database, opened through a contained helper.
547: - Older root/subdirectory identities: explicit user-supplied descriptor.
548: - OpenCode v1 volumes: retain current no-auto-import policy; explicit unsupported migration unless separately qualified.
549:
550: Do not search host-native credential homes or unrelated projects automatically.
551:
552: ## Preconditions
553:
554: Before reading/exporting:
555:
556: - Validate source and destination descriptors.
557: - Require stopped dependent clients and services.
558: - Acquire source, destination, and projection locks in sorted identity order.
559: - Validate ownership, modes, file types, symlink-free ancestry, and containment.
560: - Validate native schema.
561: - Require destination absent/empty or demonstrably identical.
562: - Reject destination conflict without mutation.
563: - Never allow a test transaction to name a production source or destination.
564:
565: ## Atomic transaction
566:
567: Use a durable non-secret transaction journal with explicit source/destination coordinates and stages:
568:
569: `planned → staged → destination-committed → verified → source-retired → complete`
570:
571: Process:
572:
573: 1. Export source auth into a protected staging file beside the destination.
574: 2. Validate exported native payload and selection separation.
575: 3. Flush file and containing directory.
576: 4. Publish destination without overwriting an existing winner.
577: 5. Reopen and verify the committed payload privately.
578: 6. Record committed destination revision.
579: 7. Retire legacy auth from its active importer path only after verification.
580: 8. Preserve an explicit protected rollback copy.
581: 9. Complete the journal.
582:
583: For SQLite, export through a consistent transaction/backup boundary; do not copy a live database file without its WAL state.
584:
585: Rollback restores only explicitly recorded targets. Never merge stores.
586:
587: ## Project → global
588:
589: - Configuration change alone does not copy credentials.
590: - If global auth exists, use it only after acknowledging the identity change.
591: - If absent, choose fresh login or explicitly copy one selected project identity.
592: - Do not enumerate projects and select the newest, first, or last.
593: - Multiple differing candidates produce a conflict requiring an explicit source choice or fresh login.
594: - Preserve every unselected source.
595: - A nonempty destination is never overwritten by default.
596: - Initial implementation does not merge account sets across sources.
597:
598: ## Global → project
599:
600: - Each project starts with an independently selected identity.
601: - Require explicit acknowledgment: fresh login or explicit copy from global.
602: - Copy only into the selected project.
603: - Preserve the global source.
604: - Never populate all known projects automatically.
605: - Existing project credentials conflict with a copy unless identical.
606:
607: Copied OAuth refresh tokens may not remain independently usable after either copy rotates or is revoked. Prefer fresh login for separate long-lived accounts; document this as provider behavior, not a guarantee of independent token validity.
608:
609: ## Scope-change acknowledgment
610:
611: Record the last acknowledged auth identity for each physical project/harness.
612:
613: When it changes, a live launch requires an explicit transition choice:
614:
615: - `fresh`: initialize/use an empty destination without import.
616: - `use-existing`: acknowledge the selected existing destination.
617: - Explicit `auth-copy`: import from named source.
618:
619: Do not infer acknowledgment from elapsed time or from an empty store.
620:
621: ## Interrupted operation/recovery
622:
623: - Before destination commit: source remains authoritative.
624: - After commit but before retirement: journal identifies the committed destination; resume verification/retirement.
625: - After interrupted native execution: projection remains authoritative until collected.
626: - Failed validation leaves source, destination, and projection intact.
627: - Missing projection during required recovery is an error, never permission to restore stale credentials.
628: - Completed logout is a tombstone, preventing legacy re-import.
629:
630: # 7. Implementation sequence
631:
632: ## Phase 1 — Freeze native adapter contracts
633:
634: Files:
635:
636: - New harness auth adapters and fixtures.
637: - `harnesses/opencode/auth-state.py`.
638: - Bounded native adapter verification scripts.
639: - Acceptance documentation.
640:
641: Establish file/schema members, selection fields, logout, writable refresh behavior, service shutdown, and mixed-store exclusions.
642:
643: **Checkpoint:** no production migration or scope support is enabled until pinned adapters pass synthetic native import/export/logout tests. Muse backend uncertainties must be resolved here.
644:
645: ## Phase 2 — Registry and configuration
646:
647: Change:
648:
649: - `lib/tools.sh`: state fields, auth records, validation.
650: - `lib/config-file.sh`: optional-key/schema parsing support.
651: - New `lib/auth.sh`: shared policy resolution.
652: - `setup.sh`, `lib/install.sh`: optional policy file installation/preservation.
653:
654: Retain mandatory `BOX_TOOL` contracts.
655:
656: **Checkpoint:** registry/config Bats cover every precedence and invalid-value case; setup failures leave files and metadata unchanged.
657:
658: ## Phase 3 — Authoritative state descriptors
659:
660: Add `lib/state.sh`.
661:
662: Change:
663:
664: - `lib/launcher.sh`: separate workspace discovery from persistent state resolution.
665: - `lib/preflight.sh`: enumerate new protected roots from registry.
666: - `lib/test-state.sh`: test-domain dispatch, registry-backed production exclusions, auth test descriptors.
667: - Native Python consumers: call descriptor CLI.
668:
669: Preserve existing production volume names and existing non-auth home formulas.
670:
671: **Checkpoint:** read-only resolver tests prove physical aliases, moves, UID separation, harness separation, hash collisions, and test-domain isolation.
672:
673: ## Phase 4 — Lease and supervised container lifecycle
674:
675: Change:
676:
677: - `lib/run.sh`: attach resolved auth/projection descriptors.
678: - `lib/docker.sh`: durable auth-managed lifecycle.
679: - Dockerfile: install supervisor/adapters and required Python support.
680: - Wrapper sourcing/install discovery.
681:
682: For auth-managed runs, replace anonymous `docker run --rm` lifecycle with:
683:
684: 1. Validate Engine/runtime/image/network.
685: 2. Reserve under locks.
686: 3. `docker create` with exact labels, mounts, and lease token.
687: 4. Record immutable container ID before start.
688: 5. Release reservation locks; start/attach.
689: 6. Supervisor validates reservation and owns runtime locks.
690: 7. Remove the exact container only after completed collection or recorded recovery state.
691:
692: A reserved container blocks competing launches even before it starts. Host failure between creation/start leaves a recoverable reservation. Container failure leaves the persistent projection and lease.
693:
694: Never infer container ownership from a loose name prefix.
695:
696: **Checkpoint:** fault injection covers every reserve/create/start/import/commit/scrub boundary, host-client death, container death, daemon failure, and cleanup failure.
697:
698: ## Phase 5 — Harness launch integration
699:
700: Change all three `launch.sh` adapters and OpenCode `entrypoint.sh`.
701:
702: - Remove hardcoded production auth-scope policy.
703: - Retain native non-auth locations and existing preference behavior.
704: - Route ordinary/auth/shell execution through supervisor.
705: - Move auth validation into the shared live preparation/adapter path.
706: - Keep dry-run free of auth inspection.
707: - Preserve existing credential forwarding and approval rules.
708:
709: **Checkpoint:** installed-launcher tests pass without checkout access; mount and entrypoint assertions reflect the supervisor.
710:
711: ## Phase 6 — Migration and lifecycle tools
712:
713: Add resolver-backed Make targets and one shared operational entrypoint.
714:
715: Implement exact descriptors for:
716:
717: - Migration/copy/init/recovery.
718: - Project reset.
719: - Explicit auth removal.
720: - Code-only uninstall inventory.
721: - Full state removal inventory.
722:
723: Replace documentation’s inline hash/name reconstruction with resolver output.
724:
725: **Checkpoint:** conflict, interruption, rollback, and deletion-authorization tests pass; foreign targets remain unchanged.
726:
727: ## Phase 7 — Capture, verification, and native coverage
728:
729: Change:
730:
731: - `harnesses/opencode/capture-validation.sh`
732: - Harness `verify.d/40-readiness-*`
733: - Relevant shared verification fragments
734: - `tests/native/acceptance.sh`
735: - `tests/native/lifecycle-audit.py`
736: - `tests/native/opencode-state.py`
737: - `tests/native/probe-races.py` where container lifecycle expectations change
738:
739: Capture always runs in a fresh disposable namespace, including when invoked from a normal production shell. It must not consume global auth merely to inspect configuration.
740:
741: Regenerate `verify-*.sh` using `gen-verify.sh`; never edit generated scripts directly.
742:
743: **Checkpoint:** `make -C box verify-static`, `pins`, and generated consistency pass. Build through Make, then run both explicit runtimes.
744:
745: ## Phase 8 — Documentation and controlled rollout
746:
747: Update all surfaces listed below, record adapter/runtime/account evidence, and preserve legacy support until removal criteria are met.
748:
749: # 8. Test plan
750:
751: ## Existing tests to rewrite
752:
753: | Existing surface | Required conceptual change |
754: | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
755: | `tools.bats` registry completeness/state validation | Auth records, dynamic scope, adapters, schema and lifecycle validation |
756: | `config.bats`: “project-identity derives stable volume and container names” | Workspace identity versus resolver-produced state identities |
757: | `launchers.bats` dry-run/mount/shell tests | Effective auth metadata and supervised entrypoint |
758: | `live-defaults.bats`: “Muse launch snapshots refresh defaults preserve auth…” | Preserve non-auth home behavior; canonical auth and projections are separate |
759: | `live-defaults.bats`: interruption/lock test | Preference lock release remains; auth lease remains until collection/recovery |
760: | `live-defaults.bats`: Codex trust migration | Trust/history unaffected by either auth scope |
761: | `opencode-v2.bats`: config siblings and SQLite guard | Mixed database remains project-scoped; auth projection lifecycle added |
762: | `test-state.bats` exact identity/cleanup tests | Add auth descriptors without weakening existing namespace guards |
763: | `opencode-capture.bats` | Every capture owns disposable auth/non-auth state, including normal invocation |
764: | `setup.bats` | Preserve policy, canonical auth, migration journals, and indexes |
765: | `preflight.bats` | Registry-declared auth roots, custom roots, escapes |
766: | `split.bats`, `config-linkage.bats`, `gen-verify.bats` | New installed package/helpers and generated adapter-aware checks |
767: | `cancellation.bats`, `run.bats`, `auto-runtime.bats` | Reserved/create/start lifecycle and exact cancellation ownership |
768:
769: Do not retain tests that equate “Muse home is global” with “auth must be global,” or “OpenCode volume is project-scoped” with “auth must be project-scoped.”
770:
771: ## New Bats classes
772:
773: Add:
774:
775: - `auth-policy.bats`
776: - `state.bats`
777: - `auth-lifecycle.bats`
778: - `auth-migration.bats`
779: - `auth-adapters.bats`
780:
781: Cover:
782:
783: | Class | Assertions |
784: | --------------------- | --------------------------------------------------------------------------------------------------------------------- |
785: | Registry/schema | Missing/duplicate auth record; bad adapter; bad scope/schema; orphan fields; canonical `/persist` still required |
786: | Policy | Registry fallbacks, common default, per-harness overrides, every precedence combination |
787: | Invalid configuration | Empty/unknown/malformed values, wrong types, unknown keys/harnesses, shadowed invalid values, missing explicit config |
788: | Identity | Global project independence; project isolation; aliases; moves; UID separation; GID stability; harness separation |
789: | Paths | Unsafe owner/mode, relative root, ancestor symlink, escape, project overlap, comma/newline, non-file credential/lock |
790: | Migration | Empty destination, identical destination, differing accounts, explicit source choice, no automatic merge |
791: | Switching | Both directions; fresh/use-existing acknowledgment; unrelated project not populated |
792: | Transactions | Interruption at every journal stage, atomic publication, source retained until verified |
793: | Logout | Tombstone, no legacy resurrection, partial-account logout semantics |
794: | Lease | Busy failure, deterministic lock order, dead reservation, live-container recovery refusal |
795: | Cleanup | Exact identity required; wrong class/domain/harness/UID/project rejected; no wildcard/prefix authority |
796: | Dry-run | No credential reads, DB opens, locks, writes, migration, Docker contact, or secret output |
797: | Setup/uninstall | Rerun preservation; code-only preservation; exact full-state removal |
798: | Legacy | Root aliases, older project identities, unsupported v1 state, protected rollback copies |
799:
800: Use fault-injection clients and fake Docker responses to test actual interruption boundaries. Do not test merely that functions echo expected implementation strings.
801:
802: ## Adapter verification
803:
804: **Codex:**
805:
806: - Synthetic valid native auth import.
807: - Native login status where account-independent.
808: - Native logout/unlink → canonical tombstone.
809: - File mutation/refresh-shaped write collected.
810: - Malformed/truncated auth preserves prior canonical revision and requires recovery.
811: - Trust, history, sessions and SQLite markers unchanged.
812:
813: **OpenCode:**
814:
815: - Fixture database created by the pinned client.
816: - Multiple key/OAuth credentials.
817: - Selection stored per project.
818: - Native account switching/logout.
819: - Auth-only export/import/scrub.
820: - Session/approval/project/config rows unchanged.
821: - WAL recovery and interrupted commit.
822: - Unknown schema/payload rejected.
823: - Native service stopped before collection.
824: - MCP endpoint identity retained.
825:
826: **Muse:**
827:
828: - Qualified file backend.
829: - Native empty/logout behavior.
830: - Auth mutation and recovery.
831: - Trust/settings/session markers unchanged.
832: - Backend/schema mismatch fails explicitly.
833:
834: ## Native acceptance and lifecycle audit
835:
836: Expand both existing drivers to the Cartesian coverage:
837:
838: - Three harnesses.
839: - Global and project auth.
[Output truncated. Continue reading with offset: 840]

---

## Assistant

_Thinking:_

Verifying current uncommitted changes against prior passes to check if earlier gaps remain or were fixed.

Seen the prior passes — now re-checking the current tree to see what still holds.

**Tool: shell**

**Input:**

```json
{
	"command": "git diff --stat; echo \"===UNTRACKED===\"; git status --porcelain=v1 | grep '??'; echo \"===DIFF-CHECK===\"; git diff -- box/lib/auth.sh | head -n 20\necho \"===CURRENT-HEAD===\"; git log --oneline -3; git diff --name-only | tr '\\n' ' '",
	"workdir": "/workspace"
}
```

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
===UNTRACKED===
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
===DIFF-CHECK===
===CURRENT-HEAD===
c85d13c Isolate test state in disposable box-test namespaces
ef808f0 fix gi
b9303c4 Merge pull request #1 from temrb/dev
.gitignore box/.dockerignore box/Dockerfile box/Makefile box/README.md box/box-c box/box-m box/box-m-login box/box-o box/check-pins.sh box/docs/acceptance.md box/docs/adding-a-tool.md box/docs/architecture.md box/docs/harnesses.md box/docs/operations.md box/docs/security-resource-audit.md box/docs/troubleshooting.md box/docs/upgrades.md box/harnesses/codex/README.md box/harnesses/codex/launch.sh box/harnesses/codex/verify.d/40-readiness-codex.sh box/harnesses/muse/README.md box/harnesses/muse/install.sh box/harnesses/muse/launch.sh box/harnesses/muse/verify.d/40-readiness-muse.sh box/harnesses/opencode/README.md box/harnesses/opencode/capture-validation.sh box/harnesses/opencode/entrypoint.sh box/harnesses/opencode/launch.sh box/harnesses/opencode/verify.d/40-readiness-opencode.sh box/lib/config-file.sh box/lib/install.sh box/lib/test-state.sh box/lib/tools.sh box/setup.sh box/tests/bats/helpers.bash box/tests/bats/opencode-capture.bats box/tests/bats/setup.bats box/tests/bats/tools.bats box/tests/native/acceptance.sh box/tests/native/lifecycle-audit.py box/verify-codex.sh box/verify-muse.sh box/verify-opencode.sh
Command exited with code 0.

---

## Assistant

_Thinking:_

**Tool: shell**

**Input:**

```json
{
	"command": "echo \"===1 OpenCode gate===\"; grep -n \"migration_gate\\|ensure_object\\|transition_plan\\|lease_reserve\" box/harnesses/opencode/launch.sh; echo \"===2 Muse/Codex gate===\"; grep -n \"migration_gate\" box/harnesses/muse/launch.sh box/harnesses/codex/launch.sh; echo \"===3 shared case id ===\"; grep -n 'case \"$id\"' box/lib/auth-ops.sh; sed -n '95,115p' box/lib/auth-ops.sh; echo \"===4 live-defaults ===\"; git diff --name-only | grep -c live-defaults; grep -n \"synthetic.*auth\\|migration\" box/tests/bats/live-defaults.bats | head; echo \"===5 dry-run ===\"; grep -n \"dry_run\\|migration\\|transition\\|legacy\" box/harnesses/muse/launch.sh | head -n 20; grep -n \"dry_run\\|migration\\|transition\\|legacy\" box/harnesses/opencode/launch.sh | head -n 20",
	"workdir": "/workspace"
}
```

===1 OpenCode gate===
59: box*auth_ensure_object "$opencode_auth_dir" opencode "$opencode_auth_scope" "$host_uid" "$project_hash"
60: box_auth_transition_plan opencode "$host_uid" "$project_hash" "$project"
65:  box_auth_lease_reserve "$opencode_auth_dir" "$_opencode_index/locks/$volume.lock" "volume:$volume"
===2 Muse/Codex gate===
box/harnesses/muse/launch.sh:99:box_auth_migration_gate muse "$muse_auth_dir" "$muse_persist_dir/auth.json" "$muse_auth_dir/migration.json"
box/harnesses/codex/launch.sh:94: box_auth_migration_gate codex "$codex_auth_dir" "$codex_home/auth.json" "$codex_auth_dir/migration.json"
===3 shared case id ===
95:  case "$id" in
case "$id" in
    muse)
      home=${BOX_M_PERSIST_DIR:-$HOME/.config/box-m/muse-config}
      [[ "$home" == /* ]] || die 'Invalid Muse persist dir.'
printf '%s/auth.json' "$(box_plan_directory "$home")"
return 0 ;;
codex)
root=${BOX_C_STATE_ROOT:-${BOX*C_STATE_DIR:-$HOME/.config/box-c/projects}}
      [[ "$root" == /* ]] || die 'Invalid Codex state root.'
printf '%s/%s/codex-home/auth.json' "$(box_plan_directory "$root")" "$hash"
      return 0 ;;
    opencode)
      [[ -n "$db" ]] || die 'OpenCode migration needs an explicit --db-path export of the v2 project database (never auto-opens a live volume).'
[["$db" == /*]] || die 'OpenCode --db-path must be absolute.'
printf '%s' "$db"
return 0 ;;
\*) die 'Internal error: unknown harness.' ;;
esac
}

# Atomic publish: stage file beside the destination, flush, publish without

===4 live-defaults ===
0
76: printf '{"synthetic":"auth"}' > "$BOX_M_PERSIST_DIR/auth.json"
107:  [ "$(cat "$BOX_M_PERSIST_DIR/auth.json")" = '{"synthetic":"auth"}' ]
200:@test "Codex launch and trust migration ignore project Python modules and import settings" {
===5 dry-run ===
64:if ((dry_run)); then
70:if (( ! dry_run )); then box_assert_native_cache "$muse_persist_dir/auth.json"; fi
80:box_load_credentials "$credentials" "$dry_run" $BOX_CRED_KEYS
82:if (( ! dry_run )); then
84:[[ ! -L "$muse_persist_dir/.box-migration.lock" ]] || die 'Redirected Muse migration lock.'
85:exec {migration_lock}>"$muse_persist_dir/.box-migration.lock"
86:flock -x "$migration_lock"
93:flock -u "$migration_lock"
94:exec {migration_lock}>&-
98:box_auth_transition_plan muse "$host_uid" "$project_hash" "$project"
99:box_auth_migration_gate muse "$muse_auth_dir" "$muse_persist_dir/auth.json" "$muse_auth_dir/migration.json"
37:if ((dry_run)); then
51:box_load_credentials "$credentials" "$dry_run" $BOX_CRED_KEYS
54:if (( ! dry_run )); then
60:  box_auth_transition_plan opencode "$host_uid" "$project_hash" "$project"
61: # Volume-backed legacy gate uses non-secret metadata only; the database is
62: # opened only by explicit migration, never by ordinary launch planning.

Command exited with code 0.

---

## Assistant

**Tool: shell**

**Input:**

```json
{
	"command": "echo \"===6 sentinel/empty/jq===\"; grep -n \"__unset__\\|BOX_STATE_CONFIG:-\\|BOX_AUTH_ROOT:-\\|command -v jq\" box/lib/auth.sh box/lib/auth-ops.sh; echo \"===7 retire/quarantine===\"; grep -n \"retire\\|quarantine\\|legacy\" box/harnesses/opencode/auth.sh box/harnesses/opencode/auth-state.py box/harnesses/opencode/entrypoint.sh | head -n 20; echo \"===8 muse validate===\"; sed -n '1,30p' box/harnesses/muse/auth.sh; echo \"===9 state-remove===\"; sed -n '372,405p' box/lib/auth-ops.sh; echo \"===10 run/docker ===\"; git diff --name-only | grep -E \"lib/run|lib/docker|lib/launcher|lib/preflight\"; echo \"(empty means Phase4 lifecycle untouched)\"",
	"workdir": "/workspace"
}
```

===6 sentinel/empty/jq===
box/lib/auth.sh:40: local explicit=${BOX_STATE_CONFIG:-} implicit="$HOME/.config/box/state.toml"
box/lib/auth.sh:140: if [[-n "${!harness_var+x}"]]; then harness_val=${!harness_var}; else harness_val=__unset__; fi
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
box/lib/auth-ops.sh:249:  command -v jq >/dev/null 2>&1 || die 'jq is required for auth copy.'
box/lib/auth-ops.sh:321:  command -v jq >/dev/null 2>&1 || die 'jq is required for auth recovery.'
box/lib/auth-ops.sh:430:    if [[ -f "$dir/lease.json" ]] && command -v jq >/dev/null 2>&1 && jq -e '.state == "active"' -- "$dir/lease.json" >/dev/null 2>&1; then
===7 retire/quarantine===
box/harnesses/opencode/auth.sh:52:# Retire legacy auth: the migration source for SQLite is an explicit
box/harnesses/opencode/auth.sh:54:# nothing to retire after verification. Always succeeds.
box/harnesses/opencode/auth.sh:55:# Usage: box_adapter_retire <legacy-export-path> <rollback-path>
box/harnesses/opencode/auth.sh:56:box_adapter_retire() {
box/harnesses/opencode/entrypoint.sh:34:    [[ ! -L "$file.box-legacy" ]] || { echo "FAIL: redirected preference backup: $file" >&2; exit 1; }
box/harnesses/opencode/entrypoint.sh:35:    if [[ ! -e "$file.box-legacy" ]]; then
box/harnesses/opencode/entrypoint.sh:36: cp -- "$file" "$file.box-legacy"
box/harnesses/opencode/entrypoint.sh:37: chmod 600 "$file.box-legacy"
box/harnesses/opencode/entrypoint.sh:39:      [[ -f "$file.box-legacy" && "$(stat -c %u "$file.box-legacy")" == "$(id -u)" && "$(stat -c %a "$file.box-legacy")" =~ ^(600|400)$ ]] || { echo "FAIL: unsafe preference backup: $file" >&2; exit 1; }
===8 muse validate===

# shellcheck shell=bash

# harnesses/muse/auth.sh — Muse file-adapter for managed auth projections.

# Canonical envelope <-> native auth.json projection. Trust, settings,

# sessions and MCP stores are never exported. Backend qualification:

# file backend only; keychain-only behaviour fails explicitly.

# Adapter contract (generic names; sourced alone, never with siblings):

# box_adapter_validate <native-auth-path>

# box_adapter_export <native-auth-path> <envelope-out>

# box_adapter_install <envelope> <native-auth-path>

# box_adapter_collect <native-auth-path> <envelope-out>

# box_adapter_scrub <native-auth-path>

# box_adapter_retire <legacy-native-path> <rollback-path>

[[-n "${_BOX_ADAPTER_MUSE_LOADED:-}"]] && return 0
\_BOX_ADAPTER_MUSE_LOADED=1

box_adapter_validate() {
local native=${1:-}
  [[ -n "$native" ]] || return 1

# Supported: absent (fresh login) or regular JSON object file.

if [[! -e "$native" && ! -L "$native"]]; then return 0; fi
[[! -L "$native" && -f "$native"]] || return 1
command -v jq >/dev/null 2>&1 || return 1
jq -e 'type == "object"' -- "$native" >/dev/null 2>&1
}

box_adapter_export() {
local native=${1:-} out=${2:-}
[[-n "$native" && -n "$out"]] || return 1
command -v jq >/dev/null 2>&1 || return 1
if [[! -e "$native" && ! -L "$native"]]; then
===9 state-remove===
box_ops_remove_auth() {
local id=${1:-} proj=${2:-} execute=0
box_require_tool "$id"
  [[ -n "$proj" ]] || die 'Usage: state-remove HARNESS=<id> PROJECT=<path> [--execute]'
shift 2
while (($#)); do case "$1" in --execute) execute=1; shift ;; *) die "Unknown remove argument: $1" ;; esac; done
  local uid hash scope dir
  uid=$(id -u) || die 'Cannot determine UID.'
proj=$(box_realpath -e -- "$proj") || die 'Cannot resolve project path.'
hash=$(box_state_project_hash "$proj") || return 1
scope=$(box_auth_policy_resolve "$id") || return 1
if [["$scope" == global]]; then
die 'Refusing to remove global auth as part of a project removal (remove the exact global identity explicitly if intended).'
fi
dir=$(box_auth_object_dir "$id" "$scope" "$uid" "$hash") || return 1
  box_ops_guard_test_domain "$dir"
local inv
inv=$(box_auth_guard_remove "$dir") || return 1
printf '%s\n' "$inv"
  for extra in migration.json migration-journal.json rollback-credentials.json legacy-auth-rollback.json; do
    [[ -e "$dir/$extra" ]] && printf '%s\n' "$dir/$extra"
  done
  if ((execute)); then
    while IFS= read -r p; do [[ -n "$p" ]] || continue; rm -f -- "$p" || die "Cannot remove $p"; done <<<"$inv"
for extra in migration.json migration-journal.json rollback-credentials.json legacy-auth-rollback.json; do
rm -f -- "$dir/$extra" || die "Cannot remove $dir/$extra"
done
rmdir -- "$dir" 2>/dev/null || true
    printf 'Removed project auth %s\n' "$dir"
else
printf 'Dry run: pass --execute to remove the inventoried paths above.\n'
fi
}

===10 run/docker ===
(empty means Phase4 lifecycle untouched)

Command exited with code 0.

---

## Assistant

**Tool: shell**

**Input:**

```json
{
	"command": "echo \"=== verify-static ===\"; make -C box verify-static 2>&1 | tail -n 30; echo \"EXIT:$?\"; echo \"=== gen-verify ===\"; bash box/gen-verify.sh --check 2>&1 | tail -n 5; echo \"=== bash -n new files ===\"; for f in box/lib/state.sh box/lib/auth.sh box/lib/auth-ops.sh box/lib/supervisor.sh box/harnesses/muse/auth.sh box/harnesses/codex/auth.sh box/harnesses/opencode/auth.sh; do bash -n \"$f\" && echo \"OK $f\" || echo \"FAIL $f\"; done; python3 -m py_compile box/harnesses/opencode/auth-state.py && echo \"OK auth-state.py\" || echo \"FAIL auth-state.py\"",
	"workdir": "/workspace"
}
```

=== verify-static ===
make: Entering directory '/workspace/box'
make verify-shell
make[1]: Entering directory '/workspace/box'
for f in box-c box-m box-m-login box-o check-pins.sh gen-pins.sh gen-verify.sh harnesses/codex/auth.sh harnesses/codex/launch.sh harnesses/codex/update.sh harnesses/codex/validate.sh harnesses/muse/auth.sh harnesses/muse/install.sh harnesses/muse/launch.sh harnesses/muse/native.sh harnesses/muse/update.sh harnesses/muse/validate.sh harnesses/opencode/auth.sh harnesses/opencode/capture-validation.sh harnesses/opencode/entrypoint.sh harnesses/opencode/launch.sh harnesses/opencode/update.sh harnesses/opencode/validate.sh lib/auth-ops.sh lib/auth.sh lib/build.sh lib/config-file.sh lib/config.sh lib/docker.sh lib/install.sh lib/launcher.sh lib/pins.sh lib/preflight.sh lib/run.sh lib/state.sh lib/supervisor.sh lib/test-state.sh lib/tools.sh regen-validation.sh setup.sh sync-pins.sh tests/native/acceptance.sh update-pins.sh verify-codex.sh verify-muse.sh verify-opencode.sh; do bash -n "/workspace/box/$f" || exit 1; done
for f in harnesses/codex/verify.d/00-header-codex.sh harnesses/codex/verify.d/60-probe-codex.sh harnesses/codex/verify.d/40-readiness-codex.sh harnesses/codex/verify.d/99-footer-codex.sh harnesses/codex/verify.d/30-network-codex.sh harnesses/opencode/verify.d/40-readiness-opencode.sh harnesses/opencode/verify.d/60-probe-opencode.sh harnesses/opencode/verify.d/00-header-opencode.sh harnesses/opencode/verify.d/99-footer-opencode.sh harnesses/opencode/verify.d/30-network-opencode.sh harnesses/muse/verify.d/00-header-muse.sh harnesses/muse/verify.d/30-network-muse.sh harnesses/muse/verify.d/99-footer-muse.sh harnesses/muse/verify.d/60-probe-muse.sh harnesses/muse/verify.d/40-readiness-muse.sh verify.d/10-workspace.sh verify.d/20-toolchain.sh verify.d/50-containment.sh; do bash -n "/workspace/box/$f" || exit 1; done
make[1]: Leaving directory '/workspace/box'
make verify-python
make[1]: Entering directory '/workspace/box'
python3 -m py*compile "/workspace/box/"harnesses/codex/native-probe.py "/workspace/box/"harnesses/opencode/archive.py "/workspace/box/"harnesses/opencode/auth-state.py "/workspace/box/"harnesses/opencode/native-probe.py "/workspace/box/"tests/native/lifecycle-audit.py "/workspace/box/"tests/native/opencode-state.py "/workspace/box/"tests/native/probe-races.py "/workspace/box/"tests/native/resource-audit-test.py "/workspace/box/"tests/native/resource-audit.py "/workspace/box/"tests/native/scratch-workloads.py
make[1]: Leaving directory '/workspace/box'
make verify-config
make[1]: Entering directory '/workspace/box'
BOX_TOOL=make bash -c 'source "/workspace/box/lib/preflight.sh" && source "/workspace/box/lib/config-file.sh" && source "/workspace/box/lib/tools.sh" && box_validate_registry "/workspace/box" && for f in "$@"; do box_config_validate "/workspace/box/$f" || exit 1; done' * harnesses/codex/config/config.toml harnesses/codex/policy/requirements.toml harnesses/muse/config/settings.json harnesses/opencode/config/opencode.json
make[1]: Leaving directory '/workspace/box'
bash "/workspace/box/gen-verify.sh" --check
gen-verify.sh: PASS (verify-\*.sh match verify.d/ output)
bash "/workspace/box/gen-pins.sh" --check
gen-pins.sh: PASS (docs/architecture.md §4 matches version files/Dockerfile)
bash "/workspace/box/check-pins.sh"
check-pins.sh: PASS (muse 1.4.0-R4161.1, opencode 2.0.6, codex 0.160.0, base sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132)
shellcheck "/workspace/box/"box-c "/workspace/box/"box-m "/workspace/box/"box-m-login "/workspace/box/"box-o "/workspace/box/"check-pins.sh "/workspace/box/"gen-pins.sh "/workspace/box/"gen-verify.sh "/workspace/box/"harnesses/codex/auth.sh "/workspace/box/"harnesses/codex/launch.sh "/workspace/box/"harnesses/codex/update.sh "/workspace/box/"harnesses/codex/validate.sh "/workspace/box/"harnesses/muse/auth.sh "/workspace/box/"harnesses/muse/install.sh "/workspace/box/"harnesses/muse/launch.sh "/workspace/box/"harnesses/muse/native.sh "/workspace/box/"harnesses/muse/update.sh "/workspace/box/"harnesses/muse/validate.sh "/workspace/box/"harnesses/opencode/auth.sh "/workspace/box/"harnesses/opencode/capture-validation.sh "/workspace/box/"harnesses/opencode/entrypoint.sh "/workspace/box/"harnesses/opencode/launch.sh "/workspace/box/"harnesses/opencode/update.sh "/workspace/box/"harnesses/opencode/validate.sh "/workspace/box/"lib/auth-ops.sh "/workspace/box/"lib/auth.sh "/workspace/box/"lib/build.sh "/workspace/box/"lib/config-file.sh "/workspace/box/"lib/config.sh "/workspace/box/"lib/docker.sh "/workspace/box/"lib/install.sh "/workspace/box/"lib/launcher.sh "/workspace/box/"lib/pins.sh "/workspace/box/"lib/preflight.sh "/workspace/box/"lib/run.sh "/workspace/box/"lib/state.sh "/workspace/box/"lib/supervisor.sh "/workspace/box/"lib/test-state.sh "/workspace/box/"lib/tools.sh "/workspace/box/"regen-validation.sh "/workspace/box/"setup.sh "/workspace/box/"sync-pins.sh "/workspace/box/"tests/native/acceptance.sh "/workspace/box/"update-pins.sh "/workspace/box/"verify-codex.sh "/workspace/box/"verify-muse.sh "/workspace/box/"verify-opencode.sh
/bin/sh: 1: shellcheck: not found
make: _\*\* [Makefile:147: verify-static] Error 127
make: Leaving directory '/workspace/box'
EXIT:0
=== gen-verify ===
gen-verify.sh: PASS (verify-_.sh match verify.d/ output)
=== bash -n new files ===
OK box/lib/state.sh
OK box/lib/auth.sh
OK box/lib/auth-ops.sh
OK box/lib/supervisor.sh
OK box/harnesses/muse/auth.sh
OK box/harnesses/codex/auth.sh
OK box/harnesses/opencode/auth.sh
OK auth-state.py

Command exited with code 0.

---

## Assistant

_Thinking:_

Evaluating static verification without shellcheck, bats availability, code cleanliness, and concluding DoD is not met with must-fix items.

Re-verified the key gaps — pulling the last cleanliness details.

**Tool: shell**

**Input:**

```json
{
	"command": "git diff -- .gitignore | head -n 30; echo \"===\"; grep -n \"agents\\|specs\" .gitignore || echo \"no agents/specs ignore\"",
	"workdir": "/workspace"
}
```

diff --git a/.gitignore b/.gitignore
index 9d5dfae..3439fae 100644
--- a/.gitignore
+++ b/.gitignore
@@ -22,10 +22,6 @@ providers.env

# Local test scratch (bats HOME override used by validation runs).

.bats\*

## -/.agents/

## -/specs/

skills-lock.json

# Python bytecode / caches (native-probe.py, archive.py, tests/native/\*.py).

@@ -48,4 +44,7 @@ coverage.xml

# OS junk.

.DS_Store
-Thumbs.db
\ No newline at end of file
+Thumbs.db

- +# /.agents/
  +# /specs/
  \ No newline at end of file
  ===
  49:# /.agents/
  50:# /specs/

Command exited with code 0.

---

## Assistant

_Thinking:_

**Tool: shell**

**Input:**

```json
{
	"command": "grep -n \"box_project_identity\" box/lib/launcher.sh | head; echo \"===\"; grep -rn \"box_config_get_optional\" box/lib/ | head; echo \"===\"; grep -n \"if False\" box/lib/auth-ops.sh",
	"workdir": "/workspace"
}
```

90:# Usage: box_project_identity <tool-prefix> (e.g. box_project_identity box-m)
92:box_project_identity() {
458: box_project_identity "$(box_tool_field "$id" state_prefix)"
===
box/lib/config-file.sh:137:# Usage: val=$(box_config_get_optional <file> <dotted-path> <kind> [allow-empty:0|1])
box/lib/config-file.sh:138:box_config_get_optional() {
===
134:os.fsync(f.fileno()) if False else None

Command exited with code 0.

---

## Assistant

_Thinking:_

No — core model present, `specs/plan.md` DoD not met. Diffstat identical to passes (`44M + 14 untracked, 947 insertions`): pass-2 gaps reconfirmed fresh today.

Correct:

- Registry: `box/lib/tools.sh:217,220,223` one `auth`/harness, `class=auth,scope=auth-policy,kind=bind,runtime=/run/box-auth,mode=700,schema=1`, fallbacks `global/project/project`.
- Precedence `box/lib/auth.sh:174-178` matches §3; `BOX_C_AUTH` independent (`box/harnesses/codex/launch.sh:73` only).
- Layout `box/lib/auth.sh:249-256`, `box/lib/state.sh:114-130`: `R/H/uU/global`, `R/H/uU/projects/P`, UID-keyed, `700/600`, object-dir-only mount.
- Envelope `{schema,revision,tombstone,payload}`; OpenCode explicit columns + `?` binds `box/harnesses/opencode/auth-state.py:28-37,83-90,226-238`.
- Capture fresh ns `box/harnesses/opencode/capture-validation.sh:61-80`; `gen-verify.sh --check` PASS.

Must-fix (reverified):

1. Phase-1 gate violated: live `ensure+transition+reserve+install` unconditional `box/harnesses/muse/launch.sh:97-101`, `box/harnesses/codex/launch.sh:92-96`, `box/harnesses/opencode/launch.sh:59-65`.
2. OpenCode live missing `box_auth_migration_gate` (`box/harnesses/opencode/launch.sh:59-65` comment only); file harnesses have it `:99`/`:94`.
3. Legacy quarantine missing; OpenCode `retire` no-op `box/harnesses/opencode/auth.sh:52-59`.
4. Muse qualification comment-only `box/harnesses/muse/auth.sh:16-24`; no keychain/MCP detection; MCP hash/account-table unverified.
5. Shared-lib harness branch violates §2: `box/lib/auth-ops.sh:95-112` `case "$id"`.
6. Old test contradicts model, untouched (`git diff --name-only | grep live-defaults` = 0): `box/tests/bats/live-defaults.bats:76,107` treats `$BOX_M_PERSIST_DIR/auth.json` as durable, now projection + gate target.
7. Dry-run omits migration/transition/legacy coords required §6/§9; gates inside `if (( ! dry_run ))`.
8. `state-remove` only effective scope `box/lib/auth-ops.sh:372-404` (global dies `:383-384`); no inactive-scope/custom-root sweep.
9. §10.10/11 + Phase-4 missing: `lib/run.sh`/`lib/docker.sh` untouched, no old-image/supervisor rejection, no stopped-container check.
10. Validation: `__unset__` accepted `box/lib/auth.sh:140-175`; `BOX_STATE_CONFIG=""`/`BOX_AUTH_ROOT=""` silently default `:40,:210`; `policy_source:190-191` skips config validation; `jq`-absent fail-open `box/lib/auth.sh:345,414`, `box/lib/auth-ops.sh:430`.

Cleanliness:

- Triplicated auth-dir (`box/lib/test-state.sh:258`, `box/lib/auth.sh:232`, `box/lib/state.sh:114-130`); old `box_project_identity` still live `box/lib/launcher.sh:92,458`.
- Dead: `box_config_get_optional` `box/lib/config-file.sh:138` zero callers; `box/lib/auth-ops.sh:134` `if False`; `.gitignore:49-50` comments out `/.agents/`+`/specs/` leaving them untracked — do not commit.
- Static: `bash -n` + `py_compile` + `verify-config` + `gen-verify` + `gen-pins` + `check-pins` PASS; `make -C box verify-static` fails only on missing `shellcheck` binary, not code.
