# Architecture audit acceptance

## Current continuation: ordered leases and qualification (2026-10-08)

The [latest progress record](../../specs/implementation-progress.md) records
renewed exact-source hosted qualification, an ordered host lock-set API,
lease-aware schema-2 authority, bounded OpenCode trigger refusal and a
Make-driven pinned disposable native storage gate. All three amd64 synthetic
native fixtures pass; ARM64 fixture execution is pending. Neither synthetic
fixtures nor running CI close native/account/power-loss or production cutover
gates. The current schema-1/contract-3 launchers still mount canonical state.

## Earlier baseline, hosted Docker and ext4 observations (2026-10-08)

Q01's source-baseline/qualification-harness criteria are complete. The
[progress record](../../specs/implementation-progress.md) contains exact
snapshots, source comparisons, artifact digests and measured outcomes.
The other 33 broad tasks remain open; production is schema 1 / contract 3
and still exposes canonical state. The additive host-only store has 15
synthetic authority regressions and is not activated. Its ordered host lease
protocol has seven subprocess tests and remains separate from production
contract-3 orchestration.

**CI/S/U:** Both static runs for snapshots `0c678872…` and `146bbca6…`
passed. Local static verification after the MCP/privacy/registration changes
passed 564 cases with zero failures and five Docker-dependent skips.
The later initialization-preservation guard has focused passing checks;
final exact-snapshot verification remains required.

**D/CI:** [Run 37803020849](https://github.com/temrb/box/actions/runs/37803020849)
built all three local images through Make and passed all four live Docker
cases on amd64 and ARM64. Native acceptance refused missing Docker runsc
registration. The workflow now registers runsc and verifies it before building.

**P/CI:** [Run 37804119119](https://github.com/temrb/box/actions/runs/37804119119)
passed real ext4 block/inode ENOSPC on both architectures: canonical and journal
survive, and the same transaction retries to revision 1. This is bounded local
filesystem evidence, not power-loss or production-supervisor recovery.

**N:** Fresh pinned amd64 Codex passes synthetic MCP file-store loading,
server/endpoint-specific logout, mode repair, empty-map handling, last-member
unlink and malformed-store preservation. Provider auth/history remain intact.
Real OAuth/callback/rotation/concurrency and alternate-store gates remain open.

No complete native manifests, schema-2/contract-4 lifecycle cutover, dedicated
account acceptance, staged rollout or release acceptance are claimed.

## Q01 transfer comparison groundwork (2026-10-08)

**U:** The read-only `specs/compare-baselines.py` checker validates inventory
digests and compares HEAD/status and complete source members before VM
qualification. All four `baseline.bats` tests pass with `/persist` as the
protected test parent, including transfer drift and malformed/forged/nonregular
input refusals. Two idle same-host captures compare equal. Python AST parsing
and whitespace checks pass. No VM transfer or runtime qualification is claimed.
The [handoff](../../specs/handoff-next-step.md) records the command and limits.
Q01–Q06, dedicated accounts, durability, ARM64 and actual CI remain open;
Docker/runsc/qualified VM access is still unavailable. Existing work is preserved.

**S/U:** Sequential static verification exited 0: **536 passed, 0 failed,
5 Docker-dependent skips** (541 cases), with syntax, compilation, configs,
generated checks, pins and ShellCheck passing. It used temporary tools via
`PATH=/tmp/shellcheck-v0.10.0:/tmp/box-bats-core/bin:$PATH` and
`BOX_TEST_PROJECT_ROOT=/persist make -C box verify-static`.
Log `/tmp/box-static-transfer-2026-10-08.txt`, SHA256
`9ac8e8b74ac88b05c64fba7b5cd886960fff48c8c7d81246656ad962aa672f78`.
The counts/log documentation update followed this run. No new D/N/A/P/CI
evidence or completed qualification checkbox is claimed.

[Harness index](harnesses.md) · [Operations](operations.md) ·
[Upgrades](upgrades.md) · [Security/resource audit](security-resource-audit.md)

Fresh 2026-10-02 lifecycle/resource audit evidence is recorded in the
[new report](security-resource-audit.md). Final `verify-static` passes all 372
Bats tests plus ShellCheck/configuration/generated checks; `pins` passes.
All three final Make image builds pass;
both explicit runtimes pass installed startup/containment and local native
policy/state checks. `verify-native-opencode` exits 0 for account-independent
checks. The full native driver now completes both runtimes after its cleanup-map
fix and exits 1 for unmet runsc transport and real account gates. Disposable
storage tests reproduce tmpfs OOM, sized-tmpfs ENOSPC and checksum-intact
disk-backed completion. Probe timeout and TERM cleanup pass; no authenticated,
ARM64 or remote-CI gate is closed by this evidence.

Follow-up plan review fixed prerequisite status and daemon-error client cleanup
in the disposable storage experiment. Fresh static verification passes all 374
Bats cases and `pins` passes. Runtime/build evidence above was not repeated by
this follow-up. The [report's coverage assessment](security-resource-audit.md#follow-up-plan-review)
keeps locally testable deferred cases distinct from external acceptance gates.

The F01–F17 implementation is present. Release acceptance remains incomplete:
OpenCode v2 is the in-place implementation; active v1 compatibility and rollback
scaffolding are retired. Earlier permission PASS claims are withdrawn: retained
ordinary cases reported unavailable, and the denial oracle could pass on empty
output. Shipped client preference persistence was **unverified and defective**
because its configuration parent was tmpfs. Saved approvals were **unverified**;
`--auto` did not establish durable approvals. Fresh results belong in the
[cutover evidence](evidence/opencode-v2-cutover.md).

Docker/gVisor containment defines accessible host resources; ordinary permissions
supply configurable approval defaults. Agent overrides and saved approvals may
allow asks; an explicit hard deny must still reject. Account/model/resume,
ARM64 runtime execution and an actual root GitHub workflow run remain unmet
until separately observed. Historical raw evidence is retained without treating
its PASS labels as current acceptance.

Evidence was collected on 2026-10-02 from the uncommitted working tree based on
`1d212452ece8b095cf3de98673eeccda08160883`, on Linux x86_64, UID/GID 1000:1000,
Docker Engine 29.8.1 and runsc release-20260921.0. That identifies the
historical baseline, not the current committed revision. Current changes are
based on committed `de7b03f` (2026-10-03 remediation: bounded readiness spawns,
registry/cache/git negatives, probe_url consumption, dead-branch removal,
guide wording). Static/native re-execution is now recorded in the
[security/resource audit](security-resource-audit.md); earlier retained outputs
remain historical for their prior trees. The source pin table in
[architecture](architecture.md) identifies all shipped artifact/toolchain pins.
Disposable installed packages were tested without importing host credentials.
The [retained native output](evidence/2026-10-02-native.txt) contains selected
assertions, with fixture container/volume identifiers removed.

| Gate | Result and scope |
|---|---|
| Static verification | `make -C box verify-static`: shell syntax, declared JSON/TOML, generated output, pins, ShellCheck and all Bats tests (349 at the 2026-10-02 baseline plus new registry/cache/git/pin negatives; exact count re-verified on re-run), exit 0 for the cutover working tree; [fresh retained output](evidence/opencode-v2-cutover-static.txt) is historical for that tree. Actual GitHub execution remains unmet. |
| Pin consistency | `make -C box pins` passes. |
| amd64 image builds | Muse 1.4.0-R4161.1, OpenCode 2.0.6 and Codex 0.160.0 build through Make and pass image user/label checks. Build stages assert exact normalized native versions (`opencode v2.0.6`). |
| Codex amd64 + arm64 artifacts | Both complete musl archives were downloaded again, hashed against published release digests, inventoried for required companions, and matched committed pins. This establishes artifact integrity/layout, not ARM64 execution. |
| Installed operation | All three native version startups and shared containment pass under explicit runsc and explicit hardened runc, from disposable installed packages. |
| Muse startup | Native echo provider starts with shipped settings and automatic subcommand-positioned sandbox bypass under both runtimes. No Meta inference/account claim. |
| Codex native policy | Both runtimes pass loaded requirements, effective configuration, ephemeral thread on-request/user/dangerFullAccess, reviewer rejection/fallback, and conflicting session/CLI credential-store/update-check/SQLite settings. No model turn. |
| OpenCode native policy | **PASS, account-independent**: production installed v2 launcher under both explicit runtimes; 25 matched tool cases each, explicit deny-over-auto, durable saved approvals/restart and deny-over-saved-approval. [Fresh evidence](evidence/opencode-v2-cutover.md) is historical for the prior tree. Evidence shows deny-over-auto and deny-over-saved separately, not the triple deny-over-auto-over-saved combination. Real login/model/resume remains UNMET. |
| Unauthenticated restart/state | Codex host home and named-volume markers survive restart and are absent from a second physical project. OpenCode shipped client preferences, state and saved approvals now pass production-launcher restart/two-project isolation; legacy fixtures remain untouched. Filesystem persistence only, not authenticated resume. |
| Auth-scope lifecycle (synthetic) | Registry auth records, policy precedence, global/project identity separation, migration/copy/init/recover journals, tombstone logout, lease serialization, scope-transition acknowledgment, and exact-identity cleanup are covered by the `auth-*`/`state` Bats suites with synthetic fixtures and fault injection. Synthetic credentials prove storage mechanics only; real login/refresh/logout/model/resume need dedicated test accounts (never production auth). |
| Setup reruns | Preserve selected default, differing installed pins, live preference and synthetic auth bytes; remove obsolete installed adapter code (obsolete-removal evidence is Docker-gated). Synthetic auth is not a valid login. Except OpenCode host `opencode.json`, refreshed with one `.bak`; volume state plus Muse/Codex live settings/auth are preserved. |
| Full generated verification, runsc | **UNMET**: all three stop at external DNS/HTTPS transport, before account readiness. Local policy/containment tests are recorded separately. |
| Full generated verification, runc | **UNMET**: egress reaches readiness, then all three fail missing native authentication. No credentials were imported. |
| Real authentication/model/resume | **UNMET** for all harnesses. Device login, explicit API-key login, auth-mode persistence, account policy compatibility and native session restart/resume require a real account and separate evidence. |
| Native ARM64 | **UNMET**: no ARM64 host execution. Archive/build-stage support must not be described as accepted ARM64 runtime support. |
| GitHub workflow discovery/execution | **UNMET**: workflow is at repository-root `.github/workflows/verify.yml` and invokes `make -C box`; no push/PR workflow run was performed for these uncommitted changes. |

The initial default build correctly refused a group-writable existing
`~/.config/box-c` ancestor. Builds were completed using a temporary CLI home;
the unsafe real directory was not repaired. The restricted-workspace Bats run
also correctly rejected its group-writable `/home/temur/Documents/Dev` ancestor.
The complete suite was run with normal-home disposable fixtures and Docker
access. These environmental rejections were not treated as product failures or
used to relax path checks.

The production-focused `make -C box verify-native-opencode` exercises installed
SHA256 pins, ordered source inspection, client preference restart/isolation,
matched tool asks/allows/hard denials and durable saved approvals across container
restarts under both explicit runtimes. Empty/malformed output, startup/provider
errors, pending tools and timeouts fail inspection. An ask never satisfies deny.
Account-independent success does not establish real provider authentication,
model operation or resumed sessions. Those remain separate acceptance gates.

| Finding | Implemented fix and evidence; remaining gate |
|---|---|
| F01 | Root workflow and `make -C box`; registry artifact/pin/state/adapter validation, including symlinked-source, duplicate pin/label/runtime/dest, and non-bind-state negatives. Actual GitHub run remains unmet. |
| F02 | Shipped v2 native config (ordered permissions, no image policy), structural order checks, mandatory native inspection and the passing production v2 permission/state/saved-approval matrix in retained evidence (historical for the prior tree). Title/no-tool route classifies unavailable (unit). Account/model/resume remain UNMET. |
| F03 | Read-only ancestor/owner/symlink/bidirectional containment planning before preparation, including custom protected roots and Docker CLI files/backups; rejection tests verify unchanged metadata/state, including group-writable ancestor failure atomicity (mode/hash/tmp unchanged). Check/use races remain best-effort, not atomic. |
| F04 | Complete Codex 0.160.0 package, both verified digests/layouts, native policy probes and two-store isolation. Authenticated operation and ARM64 remain unmet. |
| F05 | Explicit artifact roles, source/install/runtime paths, owners/modes, lifecycles and required consumers in `lib/tools.sh`; invalid format/mode/lifecycle, missing/unknown consumers, duplicate names, and orphan/colliding records fail. |
| F06 | Muse merge/theme/login/bypass and native install/update/validation logic live in harness packages; shared libraries retain generic orchestration. |
| F07 | Refresh-with-backup, preserve-installed-pins and the single managed-image lifecycle (Codex requirements only). Live defaults replace launch seeding; protected legacy backups retain preferences, while Codex home trust records and native state survive. See migration evidence below. |
| F08 | Native cache owner/type/mode/writability and parent-link checks fail without contents or silent repair; unsafe-cache negatives include direct symlink/dir/FIFO cases. Real cache/account validity remains untested. |
| F09 | Separate source and installed leaf names; recursive package installation/discovery/generation; installed operation without checkout and obsolete-code cleanup tested. |
| F10 | Format parsing, harness structural validators, generated expected values, per-stage pin consumption and bounded native inspection (readiness spawns wrapped in `timeout 30`); semantic negatives including Muse/OpenCode validator drift and stage-pin mutants. Missing native evidence fails acceptance. |
| F11 | OpenCode installs hash-verified standalone glibc archives (no npm/NodeSource); all stages assert exact `opencode v<VER>`. Build/user/label checks pass. |
| F12 | Probe metadata separated from native configuration; explicit package contracts and documented pin formats/extension surfaces. `probe_url` hosts match `probe_hosts` and network probes (muse exact URL equals settings `endpoint_transport.base_url`); semantic validation lives in `gen-pins --check`/`verify-config`, not `check-pins.sh`. |
| F13 | All launcher dry-runs plan without seeding, chmod, native preference changes, CLI writes, daemon contact or key reads; regression coverage. |
| F14 | Per-field identity across selected then registered prefixes then global Git (3-prefix ordering tested); keyless setup guidance and distinct install/build/auth/native status. Empty providers.env is valid; no missing-providers todo state. |
| F15 | Canonical guides inventory exact state/reset/logout/uninstall consequences, including both Codex stores, Muse `BOX_M_PERSIST_DIR` override consequence, and overridden roots; reruns preserve state except OpenCode host `opencode.json` (refreshed with backup) and remove obsolete code (Docker-gated evidence). Pin update pointers link to upgrades §12. |
| F16 | Correct duplicate-key/setup/updater comments; historical OpenCode capture explicitly lacks revision/pin/runtime/auth evidence and is not current acceptance. |
| F17 | Shared contracts, harness index and three canonical native guides with complete navigation/lifecycle coverage and pin-update pointers; this record separates implementation from validation. |

Reproduce static/build/native checks through [operations](operations.md).
`make -C box verify-native` intentionally returns failure for unmet gates and
cleans up its own fixtures. The focused `verify-native-opencode` target returns success only for its
account-independent checks; account, ARM64 and remote-CI acceptance remain separate.
Closing those gates requires recording the exact release, source revision,
architecture, explicit runtime, auth method and observed outcome. Existing
`harnesses/opencode/validation/REPORT.txt` remains historical;
`resolved-config.json`/`config-stderr.txt` are current redacted source
inspection, not enforcement/auth evidence.

## Live-default migration evidence (2026-10-04)

The launch architecture now separates physical launch state identity, mounted
workspace root and container working directory. Defaults are live on every launch;
Muse snapshots merge strict directory data, Codex mounts system defaults and
retains home trust records, and OpenCode resets global UI files under a volume
lock while retaining SQLite state. Historical evidence above predates this
migration; it does not establish acceptance of the changed lifecycle.

Focused Bats coverage checks sanitized Git discovery, ancestor roots, recognized
config containment, nested external Git metadata rejection, layered nested
preferences, empty-object behavior, default
refresh and override removal, Codex protected legacy backups and trust/history
retention, private Muse snapshot cleanup, native path/style listing without
contents, and launcher interruption with preference lock release. Generated readiness now checks read-only Muse settings and the Codex
system config. The required build and native targets were attempted in this
sandbox: Docker Engine/CLI on the trusted launcher path is absent, and native
acceptance also encounters the read-only host home. Native Codex trust/profile
loading and pinned OpenCode mixed-style precedence, image startup, live concurrent
clients, authenticated operation and account gates therefore remain unaccepted.

Final local verification: `make -C box verify-static` and `make -C box pins`
passed. Bats reported 392 cases: 353 passed and 39 skipped for unavailable
prerequisites (including the Docker CLI on the launchers' fixed trusted PATH).
Temporary ShellCheck/Bats binaries were used; executable disposable projects
lived under `/persist/box-tests` because host HOME is read-only and cache is
mounted noexec. All three image build targets and both native acceptance targets
were attempted and remain blocked as described above. No native/runtime or
account acceptance is inferred from static success.

## Auth lifecycle follow-up (2026-10-07)

The current working tree tightens Codex file credentials to a bounded subset
of the pinned [AuthDotJson](https://github.com/openai/codex/blob/a956835d020762cb2b570053af06f643a11c0ecc/codex-rs/login/src/auth/storage.rs)
API-key/ChatGPT OAuth format. Native payload validation also applies to copied
and recovered envelopes. Lease publication uses atomic replacement with file
and directory flushes, and fresh initialization and Codex home reset acquire
transaction locks. Removal inventories every acknowledged project auth object
and optionally global auth across recorded historical roots, including protected
rollback copies and completed journals. Unknown artifacts and unrecovered
projections refuse removal; old roots predating discovery require explicit input.

Muse non-empty credential membership remains unqualified: absent/empty stores
are supported, and non-empty exports/imports fail without retiring the source
or replacing the prior canonical revision. Production adapter qualification
remains an unmet rollout gate. This stricter behavior can leave a native login
projection authoritative with an active recovery lease; it must not be described
as accepted authenticated Muse operation.

`tests/native/auth-lifecycle.py` adds synthetic seed/restart/second-project/logout
checks for all three harnesses, both scopes and both explicit runtimes. Both
native drivers invoke it. These checks have not run here: Docker CLI/Engine is
absent, and `make verify-native` stops when creating its fixture in read-only
host HOME. Synthetic Muse coverage proves empty-store lifecycle only. Native
concurrency/interruption, transitions/conflicts, real refresh/rotation, model
turn/resume, ARM64 and actual remote CI remain unaccepted. Complete uninstall
still requires separately inventoried non-auth stores, legacy volumes/native
homes, install backups and explicit external provider files; canonical auth
inventory alone does not establish complete removal of those stores.

Final local validation for this follow-up: 55 targeted auth/state Bats cases
passed. `make -C box verify-static` passed with 486 Bats cases (481 passed,
5 skipped because the Docker CLI is absent). Temporary Bats and ShellCheck
0.11.0 were used, with `BOX_TEST_PROJECT_ROOT=/persist/box-tests`. The final
lease durability changes also passed targeted coverage and ShellCheck;
shell/Python/config/generated/pin checks and `git diff --check` passed.
Generated verification files were not edited or regenerated in this follow-up;
pre-existing generated diffs remain preserved. No image builds or runtime/account
acceptance are inferred from these checks.

### Handoff continuation: removal checkpoints and native storage (2026-10-07)

This continuation preserves the pre-existing uncommitted tree. Canonical auth
removal inventories without creating/repairing objects, acquires permanent
identity locks in deterministic order, requires Docker bind-liveness checks,
publishes durable per-member removal checkpoints before deletion, and resumes
after interrupted publication/member/directory deletion. Pending removal blocks
launch/init; recovery refuses changed or unknown members. The lock inode remains
outside the removed object. Full project reset uses this checkpoint protocol for
its auth portion only; native-home/volume deletion is not a complete transaction.

OpenCode validation and export now inspect private database/WAL/SHM copies,
reject redirected sidecars, unknown token-bearing tables and unsupported
key/OAuth payload fields, and preserve source bytes on rejection. Sidecars retain
one selection per integration, matching the pinned
[credential service](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/credential.ts).
Native value validation follows a bounded subset of the pinned
[credential schema](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/schema/src/credential.ts).
Selection publication uses private temporary files and file/directory flushes;
legacy single-selection sidecars resolve only their original credential ID.
These are synthetic fixture/storage checks, without pinned OpenCode native
database/account qualification.

On Linux x86_64, the available `/usr/local/bin/codex` reports `codex-cli 0.160.0`.
The historical command
`python3 -I box/tests/native/codex-auth-fixture.py --scratch-root /persist/box-tests`
passed native synthetic API-key file login/serialization, synthetic ChatGPT
OAuth loading, adapter import/export, native logout/tombstones, refresh-shaped
local writes, truncated-write source/envelope preservation, and unchanged
history/config markers. All homes and credentials were namespace-local and
disposable; network configuration pointed at a closed loopback port. No real
login, remote rotation, model turn or session resume ran. Binary version reporting
does not establish the shipped image's artifact provenance or runtime acceptance.
OAuth refresh-shaped writes are adapter evidence, not native refresh evidence.
The remote-rotation-before-local-durability limit remains an account gate.

That historical command is no longer accepted by the qualification driver.
Codex now requires explicit `--binary` and `--archive` inputs. It verifies the
host architecture's registry SHA256 and compares the executable with the
regular `bin/codex` archive member before executing even `--version`. Version
expectations come from `lib/pins.sh`. This establishes a provenance prerequisite;
no new pinned native or account qualification is claimed. Provider/MCP manifests,
MCP refresh/locking/callbacks and alternate stores remain Q05 blockers.

For all three host fixtures, provide `MUSE_BINARY`, `OPENCODE_BINARY`,
`OPENCODE_ARCHIVE`, `CODEX_BINARY`, and `CODEX_ARCHIVE` to
`make -C box verify-native-auth-host`, with an explicit writable
`BOX_TEST_PROJECT_ROOT`. A standalone Codex attempt uses:

```bash
python3 -I box/tests/native/codex-auth-fixture.py \
  --binary /path/to/package/bin/codex \
  --archive /path/to/codex-package-x86_64-unknown-linux-musl.tar.gz \
  --scratch-root /path/to/disposable-scratch
```

Use the aarch64 package on ARM64. Artifact verification alone does not qualify
ARM64 execution. The combined Muse/OpenCode fixtures currently require amd64.

On 2026-10-08, the updated host fixtures passed on x86_64 with downloaded
pin-matching Muse 1.4.0-R4161.1, OpenCode 2.0.6 and Codex 0.160.0 artifacts.
The installed Codex executable also matched its verified package member.
The Muse test establishes native file API-key replacement/logout and synthetic
adapter preservation. The OpenCode test establishes client-created database
schema, local native credential activation/removal, synthetic account/MCP row
projection, selection restoration and unrelated logical table preservation.
Codex establishes synthetic provider serialization/logout and adapter refusal
behavior. All fixture homes were disposable and removed; these are **N**
observations for those specific boundaries, without **D**, **A**, or ARM64
qualification. Real OAuth/account/importer/MCP refresh and crash gates stay open.
Source/artifact/log hashes and remaining gates are recorded in
[`native-qualification-2026-10-08.json`](../../specs/native-qualification-2026-10-08.json).

Targeted command, with pre-existing temporary Bats/ShellCheck on PATH and
`BOX_TEST_PROJECT_ROOT=/persist/box-tests`:

```bash
bats box/tests/bats/auth-lifecycle.bats box/tests/bats/auth-migration.bats \
  box/tests/bats/auth-adapters.bats box/tests/bats/auth-policy.bats box/tests/bats/state.bats
```

All 65 targeted cases passed. They include unchanged foreign bytes on inventory
and recovery refusal, permanent lock continuity across removal/recreation,
Docker liveness refusal, publication/deletion fault recovery, and discovery of
checkpoints after directory deletion. Fault injection models operation boundaries;
it does not certify power-loss/SIGKILL recovery or all native lifecycle stages.
`make -C box pins` and `git diff --check` passed.

An interim full static run failed the existing login process-group TERM cleanup
assertion, and focused repetition reproduced the failure. The login wrapper now
installs handlers before child startup and keeps its output reader draining
through group-signal cleanup, preventing a lost handler window and SIGPIPE while
the delegated launcher finishes collection. Both wrapper-only and process-group
TERM assertions passed five consecutive focused runs after this fix. This
qualifies the synthetic signal regression; actual Docker/native signal stages
remain separate gates.

Both `make -C box verify-native` and `make -C box verify-native-opencode` were
attempted and exited 2: `mktemp` cannot create `/home/box/.box-native.XXXXXX` on
the read-only host HOME. Docker CLI/Engine is also absent; Muse and OpenCode
pinned executables/fixtures are unavailable. Installed lifecycle checks across
all harnesses/scopes and both runtimes therefore remain blocked. Non-empty Muse
auth stays fail closed; exact backend/MCP membership and the trust filename
discrepancy remain unqualified. OpenCode account/control-account stores remain
explicitly unsupported when non-empty. Dedicated account acceptance, ARM64
execution and actual remote CI remain separate unmet prerequisites.

**The plan is not fully complete.** Independent implementation still needs full
resolver-backed inventory/removal of non-auth native homes/volumes, historical
native roots, legacy state, bindings/discovery metadata, install/template backups
and separately selected provider-file credentials, plus recovery of the entire
reset/removal transaction. The installed native drivers also still need the full
transition/conflict/setup/reset/uninstall/concurrency/interruption matrix from
the handoff. These unfinished implementation requirements are not passes and
are not relabeled as external prerequisite failures.

Final verification after the code changes: `make -C box verify-static` exited 0
with 496 Bats cases (491 passed, 5 Docker-dependent skips), plus shell syntax,
Python compilation, configuration, generated consistency, pins and ShellCheck.
The command used the pre-existing `/tmp/box-fix-bats/bin` and
`/tmp/shellcheck-v0.11.0` on PATH, `BOX_TEST_PROJECT_ROOT=/persist/box-tests`, and
`PYTHONPYCACHEPREFIX` inside the run-owned `/tmp/box-handoff.g4Pwqo` scratch
directory. The earlier signal failure and its remediation are recorded above.
Temporary scratch logs/cache were removed after recording results; the pre-existing
test tools and repository Python caches were retained. Disposable Bats/native
fixtures cleaned their own exact directories. No containers or volumes were
created, and no identified run-owned projections/checkpoints or scratch residue
remain. Generated files were not edited/regenerated, no image artifacts or live
credentials were added, and the user's prior changes remain uncommitted.

### Resumed continuation: file publication and reset lock validation (2026-10-07)

This run preserves the existing uncommitted working tree. Muse/Codex exports
and imports now stage with `mktemp`, flush the staged file, replace the exact
destination and flush its directory. File publication rejects redirected
parents, symlinks, hardlinks and foreign destination ownership before staging;
collection validates existing native file paths before reading payloads.
Tombstone install and scrub validate their exact targets. Predictable
`auth.json.tmp.<pid>` links are no longer staging destinations. Reset validates
all existing auth/volume/home projection lock inodes (type, owner, link count
and mode) before creating auth locks or opening a native lock for append.
This is narrower than full inventory authorization or full reset crash recovery.

The native Codex synthetic storage fixture passed again on Linux x86_64 with
`codex-cli 0.160.0`, using only a disposable home under `/persist/box-tests`.
It now also rejects adapter payload modes `agent_identity`, `pat`, `bedrock`,
`keyring` and `auto` while checking unchanged native source and canonical bytes.
Those are adapter refusal checks, not native execution of unsupported backends.
The previous distinction between native API-key/logout storage, synthetic OAuth
loading and adapter refresh-shaped writes still applies. No account was contacted.

Prerequisites were rechecked using executable lookup: Docker CLI, runsc, Muse
and OpenCode executables remain absent. Runtime acceptance was not attempted
without Docker. The pinned Muse backend/MCP/trust inventory and pinned OpenCode
2.0.6 database/account/native service lifecycle remain unqualified. Non-empty
Muse stays fail closed. Codex shipped-image provenance, native refresh/write
interruption and additional credential stores remain unaccepted. Account,
ARM64 and actual remote CI gates remain unmet.

**The plan remains incomplete.** Full resolver-backed inventory and recoverable
removal/reset of non-auth homes/volumes, historical native roots, legacy stores,
bindings/indexes, installation/template backups and separately selected provider
files remain unfinished implementation. The full installed lifecycle matrix
also remains unfinished implementation, in addition to unavailable runtime
prerequisites. No new claim of complete removal or adapter qualification is made.

Final-code verification: 67 targeted auth/state Bats cases passed. The first
new reset refusal run exposed a cross-filesystem hardlink fixture; moving its
synthetic foreign file onto the project fixture filesystem fixed the test.
`make -C box verify-static` exited 0 on the final code with 498 cases
(493 passed, 5 Docker-dependent skips), including syntax, Python compilation,
configuration, generated consistency, pins and ShellCheck. The command used
pre-existing `/tmp/box-fix-bats/bin` and `/tmp/shellcheck-v0.11.0` on PATH,
`BOX_TEST_PROJECT_ROOT=/persist/box-tests` and a run-local
`PYTHONPYCACHEPREFIX=/tmp/box-resume-checks.temporary/pycache`.
`make -C box pins`, `make -C box verify-generated` and `git diff --check` passed.
Generated scripts were neither edited nor regenerated during this run.

The run-created `/tmp/box-resume-checks.temporary` logs/cache were removed.
Bats fixtures and Codex TemporaryDirectory homes cleaned their exact directories.
No containers, volumes or images were created; no run-owned projections,
checkpoints, synthetic credentials or identified scratch residue remain.
Pre-existing test tools, repository caches and uncommitted changes were retained.
No production credentials were inspected or imported, and nothing was committed.

### Refactor completion audit and operational fixes (2026-10-07)

This continuation preserves the pre-existing uncommitted refactor. The current
tree already contains resolver-backed historical native discovery, recoverable
reset/full removal, exact installation/template/provider inventories and the
installed lifecycle driver. Earlier statements above that those implementations
are wholly absent describe older trees; they do not describe the current code.
Their presence does not establish native acceptance or complete adapter support.

Full-removal previews now include the current native coordinates even before
discovery has been recorded, plus exact installed templates, backups and binding
metadata, without creating the index. Lifecycle Make flags accept only omitted,
`0` or `1`; `EXECUTE=0` previews. Migration, recovery, removal and reset use the
isolated local Docker transport rather than ambient contexts/remote endpoints.
Scope acknowledgments publish through private temporary files with file and
directory flushes and reject shared binding inodes. Explicit `auth-copy` accepts
`PROJECT` to acknowledge one matching physical project after a successful copy.

OpenCode's internal native-envelope validation now supplies the required
revision; valid synthetic credential databases previously failed that check.
Its managed entrypoint refuses legacy importer files even when a migration
marker exists. Capture clears an inherited project-qualified fixture hash before
creating its independent scratch workspace. Regression tests cover these paths.

The installed synthetic lifecycle driver additionally specifies copy conflicts,
default reset, namespace cleanup refusal, capture independence and interrupted
OpenCode SQLite recovery. Operational recovery selects the runtime under test.
These additions have not executed here and are not PASS evidence.

The pinned Codex 0.160.0 disposable native storage fixture passed again: native
API-key serialization/logout, synthetic OAuth loading, adapter round trips,
refresh-shaped local writes, malformed/unsupported-state preservation and
unrelated history/config markers. It imported no production credentials and
performed no real account login, remote token refresh or model turn.

All three Make image builds and both native acceptance targets were attempted
and exited 2 because Docker CLI/Engine is unavailable; the local Engine socket,
runsc and Muse/OpenCode executables are absent. Pinned Muse non-empty backend,
MCP membership/trust naming, OpenCode account/control-account schemas and native
service/storage behavior still need qualification. Unsupported material remains
fail closed. Both-runtime installed acceptance, dedicated account operation,
ARM64 and remote CI remain open. Consequently the plan's end-to-end definition
of done is **not met**; static/synthetic checks cannot close these gates.

Final local `make -C box verify-static` exited 0 with 530 Bats cases:
525 passed and 5 Docker-dependent skips. Shell syntax, Python compilation,
configuration parsing, ShellCheck, generated consistency and pins passed;
`make -C box pins`, `make -C box verify-generated` and `git diff --check`
also passed. Final supervisor/entrypoint source-contract changes additionally
passed targeted syntax and ShellCheck validation. Temporary Bats 1.12.0 and
ShellCheck 0.11.0 were used from `/tmp/box-refactor-tools`, with disposable
projects under `/persist/box-tests` and Python cache outside the checkout.
The supervisor now enforces the shared `BOX_TOOL` sourcing contract; its image
entrypoint supplies that identity explicitly. Existing uncommitted work remains
uncommitted, generated scripts still match their prescribed generator, and no
production credentials or image artifacts were imported or exported.

## Sequential handoff verification (2026-10-08)

**S/U:** On the preserved working tree, the following sequential run exited 0:

```bash
PATH=/tmp/shellcheck-v0.10.0:/tmp/box-bats-core/bin:$PATH \
  BOX_TEST_PROJECT_ROOT=/persist make -C box verify-static
git diff --check
```

Syntax, Python compilation, configuration, generated output, pins and ShellCheck
passed. Bats reported **537 cases: 532 passed, 0 failed, 5 skipped**.
The skips require Docker CLI for dry-run shape, OpenCode volume persistence,
and three Docker config backup/staging checks; they remain unmet Docker gates.
The prior updater-lock contention case passed with suites run sequentially.
Log: `/tmp/box-static-handoff-2026-10-08.txt`, SHA256
`68b648bbac824c88020c5b5e810a50d234fdaba13cf9645fe321cd76724a7d59`.

Docker CLI, runsc and the local Engine socket remain absent on this x86_64
UID/GID 1000/1000 host. `/persist` is owned mode 700; project guards were
preserved. A qualified host and dedicated account are still needed for
Q02–Q06. No new **D/N/A/P/CI** observations or production cutover occurred.
Runtime, account, crash, ARM64 and exact-tree CI gates remain open. The full
implementation remains incomplete and unaccepted.

## Independent source inventory groundwork (2026-10-08)

**U:** Two new `baseline.bats` regressions pass for the read-only
`specs/capture-baseline.py` tool: source drift/missing members, credential
exclusion, symlink non-following and refusal of observed checkout-status changes
before JSON output. Run:
`BOX_TEST_PROJECT_ROOT=/persist /tmp/box-bats-core/bin/bats box/tests/bats/baseline.bats`.
The tool records source hashes, HEAD/status, host identity and tool availability;
it does not qualify artifacts, runtimes, accounts or durability. Capture requires
idle writers and is not an atomic snapshot. Q01–Q06 remain open, as do runtime,
account, crash, ARM64 and exact-tree CI acceptance. Existing changes are retained.

**S/U:** The sequential static run exited 0 with **534 passed, 0 failed,
5 Docker-dependent skips** (539 cases), using the same temporary Bats/ShellCheck
PATH and `/persist` project parent shown above. Syntax, compilation, configs,
generated output, pins and ShellCheck passed. Baseline Python syntax and
`git diff --check` also pass. Log `/tmp/box-static-baseline-2026-10-08.txt`,
SHA256 `1abeca6dac86e485fb138db085f3482c11ea23a035f0a2f7d81edbcef0a10990`.
Repeated idle captures matched and emitted mode-600 local inventory files.
No new D/N/A/P/CI evidence closes the remaining qualification gates.


## Independent groundwork continuation — 2026-10-08

Policy resolution now reports scope and source from one validated result;
shadowed selectors and unsafe absent-default-config ancestors refuse. Project
preflight rejects external hardlinks, unreadable/changing inventories and nested
mounts. Reset/discovery helpers use bounded descriptor-relative host operations,
fsynced publication and exact file removal with change-time evidence. The new
host lock primitive has local subprocess contention, SIGKILL-release and exec
inheritance observations; production lifecycle durability remains unqualified.

Canonical envelope validation is now pure for all three adapters. OpenCode
verification needs no database initialization or SQLite access. Explicit image
names retain native-version and artifact label requirements. A manual protected
self-hosted qualification workflow is present but has not been executed.

Fresh pinned amd64 host fixtures passed for Muse, OpenCode and Codex with
synthetic credentials and disposable state. This is **N** storage evidence;
it does not establish dedicated-account login/rotation, complete MCP membership,
Docker/runsc containment, ARM64, power-loss recovery, rollout or actual **CI**
execution. Current source checks/results and remaining gates are recorded in
[the implementation progress log](../../specs/implementation-progress.md#policy-host-filesystem-and-adapter-continuation--2026-10-08).
