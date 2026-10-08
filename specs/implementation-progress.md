# Implementation progress — 2026-10-08

## Baseline gate completion and filesystem observations — 2026-10-08

**Q01 is complete for its stated source-baseline/qualification-harness criteria.**
Initial status and source hashes are retained; repeated strict idle captures
match; actual fetched Git blobs and both hosted runners verify publication;
static checks reproduce; Docker/runsc tools and exact artifact/host identities
are observed on disposable amd64 and ARM64 VMs. Every unmet higher-category
native/account/power-loss/architecture/release gate remains explicit. This
completes only the baseline task, not the host-only architecture or release.
The remaining 33 broad task checkboxes stay open.

Both architectures in initial run `37803020849` built all three images through
Make and passed all four live Docker cases; both native gates correctly refused
unregistered runsc. Verified amd64 artifact `11562881557` ZIP SHA256:
`bbb07a9cbd8b2566530dafc3b2ef7dface855425c5ba980519f516ce150236fd`.

**P/CI:** Run `37804119119`, snapshot
`146bbca636613b6db16e7e9e97d11fbce7ddffbb`, passed real bounded ext4 block and
inode exhaustion on both architectures. ENOSPC preserved canonical revision 0
and the reserved journal; after exact filler removal, the same transaction
committed revision 1. Artifacts were downloaded and their ZIP digests verified:

- amd64 `11563167730`: `93c0af4166c1117b45ab205e1e67294b208c165bb3890e0cb7ffa106ba1244d7`.
- arm64 `11562788492`: `1be4cbe41f332cc7e824fc24ef7c1861700b11ffe88eb877a16eddfa21eabe3a`.

Both static CI runs for that snapshot passed. Its native gates still fail for
unregistered runsc. Registration is fixed in the subsequent snapshot
`d7940f7ffabb55d6cee5bdfe7bff1b10d75fc963`, qualification run `37805630389`.
These filesystem passes do not establish power-loss, VM restart, production
supervisor recovery, daemon failure or a general filesystem support policy.

**S/U:** Full local static verification after MCP/privacy/registration changes
passed: 564 cases passed, zero failures, five Docker skips (569 cases).
Log `/tmp/box-static-final-continuation.log`, SHA256
`de0c76deeebbf3233cab55b84994ffc362ad3ec346a0677f5417eb5a05fc85dc`.
Subsequent authority review tightened initialization: unknown/legacy authority
members and unacknowledged staging files refuse without shadowing or deleting
source. All 14 internal authority tests and 14 focused Bats cases pass; Python
compilation and whitespace checks pass. This last guard needs the final exact
snapshot verification. It does not activate any production schema conversion.

## Native MCP mechanics and first hosted results — 2026-10-08

Fresh pinned amd64 Codex package SHA256
`4fcc47ab57f52ff75363951a8761146cd10c8288bd86fed45487dbb204a16b71`
matched the registry and extracted executable before execution. Extended the
native fixture from exact pinned `rmcp-client/src/oauth.rs` definitions, without
adding a production member manifest or modifying a native adapter.

**N (synthetic native mechanics):** Codex MCP file-store loading, exact
server/endpoint-key logout, other-entry preservation, native 600 mode repair,
last-member unlink, empty-map no-rewrite and malformed-store preservation pass.
Independent provider auth and history bytes remain unchanged. Native CLI calls
use a disposable home, forced file backend and closed loopback endpoints;
no account authentication or token rotation is performed. OAuth issuance,
callbacks, refresh locks/concurrency and alternate stores remain unqualified.
Log `/tmp/box-codex-member-qualification/native.log`, SHA256
`153135f5c5bad196d094765dfec3b7843dc0e5977339928749eb3799f37b69b5`.

**CI/S/U:** Both static runs for snapshot
`0c6788728f927ed02717b656f0ed6182b6fb6f40` completed successfully.
**D/CI:** Its ARM64 hosted qualification built all three local images with Make,
recorded immutable image IDs/pins/user, and passed all four live Docker cases.
Static, pins, generated and disposable install gates also pass without skips.
Artifact `11562122756` from run `37803020849` was downloaded and verified:
ZIP SHA256 `42a626902c234a829f751b290a7cb027a2863c77476748bdf5b9d2c68a845b3d`.
Native/OpenCode gates failed because Docker had no registered `runsc`, despite
the signed gVisor package being installed. This is an environment setup defect;
it does not establish runtime/native acceptance. Ubuntu ARM64 kernel
`6.17.0-1022-azure`, Engine `28.0.4`, runsc `20260928.0`, cgroup v2, overlay2,
UID/GID 1001/1001 were actually observed.

The hosted setup now explicitly runs `sudo runsc install --runtime=runsc`,
restarts its disposable Engine before builds, and requires `has("runsc")`.
Default launchers still fail closed, with no automatic fallback. The native
lifecycle driver now withholds command arguments/captured output in failure
and timeout exceptions; five provenance/privacy regressions pass (**U**).

**S/U:** Local full static verification with the authority primitive passed:
563 passing cases, zero failures, five Docker-dependent skips (568 cases).
Log `/tmp/box-static-authority.log`, SHA256
`b62bd971b2d4829cd698bfaccb56e221c3bc46b8b63f284829119c10ef80fd44`.
This run preceded the later MCP/privacy/registration edits; their focused native
and provenance checks pass, with final full verification pending.
Actual fetched Git blobs for snapshot `146bbca636613b6db16e7e9e97d11fbce7ddffbb`
compare equal to its dirty inventory using `--publication` (not merely two
local captures). Subsequent edits require a newer qualification snapshot.

## Host-only authority and hosted qualification continuation — 2026-10-08

Preserved the dirty checkout; initial Git status and source capture are at
`/tmp/box-start-status.txt` and `/tmp/box-start-baseline.json`. The initial
source manifest is `6b2237f846d7c0b580cd3e4952298a092833268c2f1e8f716b7eb22809c49bdf`.
Local Engine/runsc remain absent; the process has no effective capabilities,
no sudo, and no Engine socket. The connected GitHub app is usable.

Published the preserved source through Git objects to the existing draft PR #3
branch, without changing the local branch/index or importing remote code.
Snapshot `0c6788728f927ed02717b656f0ed6182b6fb6f40` includes the preceding
volume identity fix and explicit publication comparison. An idle recheck of
its source baseline compared equal. Both disposable hosted runners passed
source comparison and prerequisite installation; run
[37803020849](https://github.com/temrb/box/actions/runs/37803020849) is executing
amd64/ARM64 Make build/runtime/native gates. Static runs are
[37803027075](https://github.com/temrb/box/actions/runs/37803027075) and
[37803020791](https://github.com/temrb/box/actions/runs/37803020791).
Scheduled/running steps do not establish D/N/CI acceptance.

`compare-baselines.py --publication` compares complete source membership,
content digests, types, sizes and executable intent. It explicitly permits
Git's HEAD/status and read/write mode normalization. Its default retains strict
checkout comparison. The workflow compares the captured dirty inventory before
qualification; the inventory is outside the source scope under `.qualification/`.
Eight baseline/workflow regressions pass (**U**). Historical CI log retrieval
now succeeds: job `113211751561` failed because the inventory test invoked
unavailable `rg`. The current workflow already installs ripgrep.

Added `box/lib/auth-store.py` as an additive host-only schema-2 primitive.
It uses `host-fs.py` for private bounded reads, stable nonblocking external
locks and fsynced publication. Trusted host code supplies semantic validators
and a content-addressed manifest identifier; native data cannot supply paths,
revision numbers, transaction IDs, stages or manifests. All members require
explicit presence/absence; tombstones agree with whole-identity absence.
Corrupt/unknown canonical state is preserved. Revisions never reset implicitly.

Reservation, validated pending export, canonical publication, verified-scrub
acknowledgement and completion are distinct durable phases. Pending evidence
is retained, and recovery refuses a changed base/export. A crash after canonical
publication can reconcile the same transaction without a second revision.
Locks remain outside the canonical identity, close on exec, and inherited
fork callers cannot exercise a parent's lease authority. Journals contain
only revision/digest/transaction metadata, never credential payloads.

**U:** Thirteen synthetic authority tests pass, including independent-process
contention and actual SIGKILL after seven durable file/journal boundaries,
fsync failure, missing/corrupt pending exports, source preservation, hostile
members, replaced authority paths/locks and fork inheritance. These tests do
not establish VM restart/power-loss, filesystem exhaustion, real token rotation,
native service quiescence or production-supervisor recovery.

Added a hosted-VM-only real ext4 exhaustion driver with two bounded 32 MiB
loop filesystems. It verifies actual ENOSPC and the corresponding free-block
or free-inode exhaustion, preserves the canonical revision/reservation, frees
only exact fixture members, and retries the same transaction. Mount cleanup
checks the recorded mount ID. The workflow runs it only after source comparison
and prerequisite success, even when another qualification gate fails. Shell
syntax, ShellCheck and Python compilation pass locally (**S**); actual execution
is pending hosted observation, with no P pass claimed yet.

This primitive is deliberately not wired to contract-3 launchers. No complete
native manifests have been qualified; no schema-2/contract-4 cutover or schema-1
conversion is activated. Current launchers still expose canonical state.
C05/L01/L02 and all broad acceptance tasks remain open. Dedicated account access
and restart-controlled filesystem hosts remain required for A/P gates; hosted
CI cannot substitute for those gates.

## Removal continuation — final volume identity check

Preserved the existing dirty implementation. Reset and full removal now
re-inspect a surviving volume immediately before `volume rm`, then validate its
creation identity against the protected transaction checkpoint through
`state-transaction.py verify-volume`. A replacement, missing recorded authority,
malformed identity or failed Engine query refuses deletion. An absent volume
continues through the existing recovery path without a delete. Empty Engine
creation timestamps/drivers refuse. Operator documentation describes the
remaining Docker administrator race because the Engine deletes by name.

Added integration regressions for a volume replaced between preparation and
deletion in both public removal paths, and checkpoint-preservation checks for
malformed, duplicate-key, missing and changed identity evidence. These are
**U** observations using a synthetic Engine, not actual Docker qualification.

The current host is Linux amd64, UID/GID 1000/1000, with no Docker CLI, runsc or
local Engine socket. `make -C box build`, `verify-native` and
`verify-native-opencode` were attempted and refused for missing Docker.
`make -C box test-live` exited zero with all four cases skipped; this provides
no passing **D** evidence. Five filesystem driver regressions and eight actual
local synthetic locking/replacement observations pass, retaining Q06's explicit
unqualified power-loss, VM, exhaustion, production-supervisor and Docker gates.

The connected GitHub app reports the historical PR #3 snapshot
`85ed4ee168d6e385bd022228e5faca9d5174c8fd` had a failed public static run
`37747311284`. Fetching its detailed job log timed out. This historical result
does not establish CI for the current local tree. No remote write, credential
mutation, schema/contract cutover or release acceptance was performed.

**S/U final code verification:** Sequential
`PATH=/tmp/shellcheck-v0.10.0:/tmp/box-bats-core/bin:$PATH
BOX_TEST_PROJECT_ROOT=/persist make -C box verify-static` exited 0:
**561 passed, 0 failed, 5 Docker-dependent skips** (566 cases). Syntax, Python,
configuration, generated output, pins and ShellCheck pass. Log:
`/tmp/box-static-2026-10-08-current.log`, SHA256
`72937f8aafa4f3fba6011e8b1f8da92c73fe62bb9d10529381890ddf03ec99d7`.
The final edit after this run only records these results in this progress log.
All 34 complete-task acceptance checkboxes remain subject to their stated
dependencies and evidence; the blueprint is not complete end to end.

## Policy, host filesystem and adapter continuation — 2026-10-08

Preserved the existing dirty checkout and continued independent groundwork.
No schema-2/contract-4 activation, account login, migration, deployment or
production credential mutation was performed.

- C02: scope/source now share one validated parse. Default state-config
  ancestry is checked even when the file is absent; failed parsers publish no
  partial result. Invalid shadowed fallback, helper-runtime and transition
  selectors refuse. Codex root aliases compare normalized protected coordinates.
  Removed the unused optional configuration getter.
- C04: added `box/lib/host-fs.py` for bounded descriptor-relative no-follow
  reads, unique-key JSON, fsynced atomic publication, stable nonblocking locks,
  exact member/directory deletion and change detection. Reset journals, reset
  member reads/removal and discovery reads use this API. Reset walks no longer
  silently skip unreadable directories. File deletion records include change
  time; older checkpoints without that evidence refuse automatic deletion.
  Lock descriptors close on exec. Remaining auth/native/installation consumers
  have not all been consolidated onto these primitives.
- C04: added project hardlink inspection using two agreeing inode inventories.
  Internal links pass; external links, unreadable/changing trees and nested
  mounts refuse. Filename delimiters are data and file contents are not read.
  Boundaries are one million entries and 256 levels. These checks do not protect
  against a compromised invoking user or host root.
- A03: all canonical adapters provide pure envelope validation. OpenCode no
  longer needs an initialized scratch database for canonical copy/recovery
  verification. Shared validation rejects duplicate JSON keys, invalid integer
  revisions, unknown header authority, unsafe files and unsupported payloads.
  This does not qualify SQLite mutation or complete native credential schemas.
- R02: explicit image overrides no longer bypass native-version/artifact labels.
  Immutable image-ID and exact native compatibility qualification remain open.
- T01: added manual protected/default-branch `qualify-native` workflow and a
  disposable runner driver with per-gate exits/log hashes and not-reached
  records. No reusable account secrets are supplied. Runner/environment setup
  and actual remote execution remain required.
- Documentation: corrected stale Muse login/fallback help, workspace-root
  identity text, host Python prerequisites, image override behavior, filesystem
  bounds and qualification workflow operation.

**U:** 125 policy/launcher/removal integration cases and 35 adapter/migration/
workflow/filesystem cases passed in focused runs. The host filesystem driver
passed 14 cases, including actual independent-process lock contention, SIGKILL
release, stable inode retention and close-on-exec behavior. The existing Q06
probe still passes five regressions and eight local observations. These do not
establish production lifecycle recovery, power-loss or Docker failure behavior.

**N:** Fresh official pinned Muse, OpenCode and Codex artifacts matched registry
SHA256 pins. `make -C box verify-native-auth-host` passed on amd64 with disposable
synthetic credentials and the new pure-verification calls. Native API-key
storage, logout, adapter round-trip and refresh-shaped writes passed; synthetic
OAuth/OpenCode rows remain distinct from real account/rotation/MCP qualification.
Log: `/tmp/box-native-foundations.txt`. The downloaded artifacts and extracted
binaries are private temporary inputs, not committed or shared image exports.

**D gates attempted:** `make build` and both native acceptance Make targets
refused because Docker is absent. `make test-live` returned zero with all four
cases skipped for absent Docker/daemon; it supplies no Docker passing evidence.
Logs: `/tmp/box-required-{build,live,opencode,native}.txt`.

The initial static run overlapped active edits and exposed installed-fixture
copies missing Python helpers, plus a cross-filesystem hardlink fixture. Those
fixtures were corrected; that run is not final-tree acceptance. A subsequent broad run passed 558 cases with five Docker skips (563 total),
then final review corrected an access-time false refusal in the OpenCode reader
and added a passing regression. The final sequential static log is
`/tmp/box-final-static.txt`; its exit/counts are reported in the final response. All broader blueprint tasks retain their complete
acceptance gates. Docker/runsc, complete native manifests, dedicated accounts,
VM/filesystem durability, ARM64, rollout and actual remote CI remain unqualified.

### Actual CI and disposable VM continuation

A separate draft PR #3 snapshots the implementation on top of `dev` / PR #2;
the original local branch and dirty files remain in place. Its first public
static run failed in exactly one Bats case because ripgrep was not installed.
The CI/bootstrap package lists and qualification prerequisites now declare
ripgrep. Public CI is being rerun on the subsequent snapshot.

Added a trusted-ref `qualify-disposable` workflow for fresh GitHub-hosted Ubuntu
amd64/ARM64 VMs, with the complete official signed gVisor package, private
qualification homes, runtime/Engine/image provenance, and log-only artifacts.
This enables actual account-independent Docker/runtime attempts through the
connected GitHub app. The dedicated self-hosted workflow remains available
for suitable protected hosts. No image is pushed/saved/exported and no reusable
account secrets are supplied. Skipped required static/live cases fail the
qualification driver. Account and VM-restart/power-loss gates stay separate.
Results are pending; a scheduled job or image build is not qualification.

## Q06 continuation — exec descriptor inheritance

Extended the host-filesystem probe with two actual subprocess/exec cases.
With `close_fds=True` and no explicitly passed lock descriptor, closing the
parent descriptor releases the lock while the child remains alive. With
`pass_fds` explicitly retaining the locked open-file description, the child
keeps the lock after the parent closes its descriptor; SIGKILL and reaping the
child then release it. Both final-release checks passed. This establishes
the synthetic Python subprocess behavior on this host, not the inheritance
policy of the production shell/supervisor/Docker paths.

Child acknowledgements now use a bounded read after a five-second readiness
wait, avoiding an unbounded readline on malformed child output. Common cleanup
kills/reaps the exact child. A failure-injection regression confirms that an
acknowledgement failure releases the parent lock and reaps the child.

```bash
python3 -I specs/test-qualify-host-filesystem.py
python3 -I specs/qualify-host-filesystem.py --scratch-root /persist
git diff --check
```

All five regressions and eight reported observations passed; whitespace checks
passed. Q06 stays open for production descriptor inheritance and transaction
recovery, power-loss/VM restart, disk/inode exhaustion, Docker/daemon failures,
and filesystem support policy. No production state or credentials were used.
No full static suite, account, Docker, platform or CI qualification is claimed.

## Q06 continuation — bounded host filesystem observations

Added `specs/qualify-host-filesystem.py`. It requires an explicit user-owned
mode-700 scratch root with nonsymlink ancestry, creates a unique disposable
directory, and operates only on synthetic lock/revision files. Child lock
acquisition is acknowledged before contention is tested; waits are bounded,
and the child is reaped on failure. Cleanup removes only its own temporary
directory. This is qualification tooling, not a production filesystem API.
Run it with writers idle and a trusted scratch parent; ancestry checks do not
protect against concurrent replacement by the host user.

On this host (UID/GID 1000/1000), the following command passed all four
observations: independent-process lock contention, lock release after actual
SIGKILL, unchanged stable-lock inode, and old/new complete reader contents
across file fsync, atomic replacement and directory fsync:

```bash
python3 -I specs/qualify-host-filesystem.py --scratch-root /persist
python3 -I specs/test-qualify-host-filesystem.py
make -C box verify-shell verify-python verify-config verify-generated pins
git diff --check
```

All three driver regressions passed: real observations with foreign-sentinel
preservation/exact cleanup, refusal of symlink ancestry or writable scratch
roots, and failure/cleanup after injected fsync error. The listed Make checks
and whitespace checks passed. Bats and ShellCheck are absent in this session;
no new full static/unit pass is claimed. Previous `/tmp` tool and log paths
are historical and are unavailable in this container session.

**Q06 remains open.** Successful fsync and process-kill observations do not
establish power-loss durability, VM restart recovery, descriptor inheritance,
disk/inode exhaustion, supported filesystem policy, Docker-client/daemon
failure, or the production transaction recovery state machine. No production
credentials/state were accessed or mutated. Docker/runsc and dedicated account
qualification remain unavailable, so dependent cutover and release acceptance
remain open. The existing dirty implementation was preserved.

## Q01 continuation — transferred source comparison

Added `specs/compare-baselines.py` and its invocation to the VM handoff.
The read-only checker validates schema/member shapes and recomputes both
manifest digests before comparing HEAD, complete checkout status and every
member's kind/hash/size/mode/symlink target. Exit 0 indicates equal source,
1 reports drift, and 2 refuses invalid input without printing payloads.
Reads are bounded, regular-file-only, no-follow and checked for observed
replacement/change. Host facts, checkout roots and capture timestamps may
differ. Archive integrity, credential auditing and runtime qualification
remain separate requirements. This check does not make capture atomic.

**U:** All four `baseline.bats` tests pass, including two new transfer tests
covering source differences, altered modes/targets, added/missing members,
HEAD/status changes, forged digests, duplicate JSON keys, invalid schemas,
nonregular/symlink input and size limits. Command:
`BOX_TEST_PROJECT_ROOT=/persist /tmp/box-bats-core/bin/bats box/tests/bats/baseline.bats`.
Two idle local captures compared equal; their mode-600 inventories are under
`/tmp/box-transfer-{source,destination}-2026-10-08.json`. This was a same-host
comparison, not a VM transfer. Python AST parsing and `git diff --check` pass.

Docker, runsc, qualification VM and dedicated account access remain absent.
Q01 remains open until transferred-tree/environment acceptance; Q02–Q06 and
dependent cutover work remain open. No D/N/A/P/CI evidence, production auth
mutation, commit or publication occurred. Existing dirty work is preserved.

**S/U:** Sequential `PATH=/tmp/shellcheck-v0.10.0:/tmp/box-bats-core/bin:$PATH
BOX_TEST_PROJECT_ROOT=/persist make -C box verify-static` exited 0 with
**536 passed, 0 failed, 5 Docker-dependent skips** (541 cases). Shell syntax,
Python compilation, configs, generated consistency, pins and ShellCheck passed.
The specs comparator also passed the separate AST/focused checks above.
Log: `/tmp/box-static-transfer-2026-10-08.txt`, SHA256
`9ac8e8b74ac88b05c64fba7b5cd886960fff48c8c7d81246656ad962aa672f78`.
This evidence precedes the final documentation-only counts/log update;
it does not constitute exact-final-tree CI or VM acceptance.

Work preserves the pre-existing tracked and untracked implementation. The
starting tracked patch and source hash/status inventory were saved locally as
`/tmp/box-implementation-baseline.patch` and
`/tmp/box-implementation-baseline.json`. These temporary files are local
working evidence, not release qualification or a credential backup.

## Implemented fixes

- **R01:** Default DNS/startup probe failures refuse the launch. No probe return
  code can select runc. Explicit `--docker-fallback`, its prohibition, explicit
  `--runsc`, and shell/dry-run behavior are retained. Informational and logout
  commands skip DNS health checks while retaining final Docker gates. Login
  help, transport remediation, operations and security documentation agree.
- **C03:** Disposable bind-root validation no longer treats a state override
  resolved beneath the task root as a production root. Registry production
  defaults and overrides outside that root still participate in collision
  checks. The valid Codex test override now passes; production collisions and
  symlink escapes still refuse.
- **C04:** All operational Make selectors and native fixture paths are frozen
  from their literal values and exported. Recipes reference shell environment
  variables instead of interpolating operator strings into shell source.
  Optional selectors and runtime overrides use the same transport.
- **T01:** Annotated OpenCode EXIT/signal callback definitions with narrowly
  scoped SC2317 suppression alongside their existing SC2329 annotations.
  These functions are called indirectly through registered traps.

These are completed defect fixes within larger tasks. C03 descriptor
consolidation, C04 no-follow filesystem primitives/hardlink handling, and R01
native/runtime qualification remain open. No contract-4 cutover is claimed.

## Verification

The 40 tests in `auto-runtime.bats`, `test-state.bats`, and `make-inputs.bats`
pass with:

```bash
BOX_TEST_PROJECT_ROOT=/workspace /tmp/box-bats-core/bin/bats \
  box/tests/bats/auto-runtime.bats box/tests/bats/test-state.bats \
  box/tests/bats/make-inputs.bats
make -C box verify-shell verify-python verify-config verify-generated pins
git diff --check
```

Syntax, configuration, generated outputs, pins and whitespace passed. Bats
was obtained in `/tmp/box-bats-core`; ShellCheck 0.10.0 was unpacked under
`/tmp`. Neither tool was installed into the user's home or bundled project.

The full unit run across 36 files completed with 448 passing and 83 failing
cases (before the final added launch-tail regression, which passes in the
40-test targeted run). Logs are in `/tmp/box-unit-results.txt`. The repository
static target reached ShellCheck and failed on SC2317 findings in existing
OpenCode trap callbacks. Those annotations were corrected and that file
passes `shellcheck -x`. Changed shell files also pass `shellcheck -x`; no
complete `verify-static` pass is claimed. Static log:
`/tmp/box-static-results.txt`.

Broader tests encountered environment constraints: the real
home is read-only, and `/workspace` is group-writable and on the production
project denylist. Guards were preserved. Docker, runsc, shipped Muse/OpenCode
binaries, account refresh/logout/MCP, crash durability, ARM64 and remote CI
remain unqualified. The 34-task blueprint is not complete or accepted end to
end. Next dependencies are registry/adapter qualification, no-follow host
store primitives, host-only transaction authority, and exact-ID lifecycle
supervision before auth contract cutover.

## Continuation — native qualification prerequisites

The dirty checkout was inspected before editing. All earlier changes are
retained. No production auth contract, canonical mount, migration, or native
store was changed in this slice. Q02–Q06 still block the dependent cutover.

- **Q05 prerequisite:** The Codex host fixture now requires explicit binary
  and package paths. Before native execution it selects the host architecture's
  registry digest through `lib/pins.sh`, checks the complete archive SHA256,
  and checks the supplied executable against the single regular executable
  `bin/codex` member. The expected native version also comes from the pin API.
  No PATH-discovered binary or version-string-only provenance is accepted.
- **Q03/Q04 prerequisite:** Muse and OpenCode host fixtures explicitly refuse
  architectures other than their currently implemented amd64 qualification.
  Pin lookup runs in privileged Bash with a minimal environment. Native
  diagnostics record artifact digest/version and limits of the synthetic
  checks. OpenCode records the client-created SQLite schema fingerprint before
  synthetic additions and refuses empty schema evidence. These changes do not
  supply the missing native manifests or account observations.
- **C04 transport coverage:** `CODEX_BINARY` and `CODEX_ARCHIVE` use the existing
  literal environment transport. The combined Make target requires every
  explicit artifact input. A regression covers hostile artifact path strings.
- **Docs:** Acceptance records retain the old Codex observation as historical
  evidence and document the stricter reproducible invocation. No broader task
  checkbox has been closed.

**U:** All 45 focused tests pass, including four new provenance refusals/order
checks and the new Make artifact-path regression:

```bash
BOX_TEST_PROJECT_ROOT=/persist /tmp/box-bats-core/bin/bats \
  box/tests/bats/native-provenance.bats box/tests/bats/make-inputs.bats \
  box/tests/bats/auto-runtime.bats box/tests/bats/test-state.bats
```

Log: `/tmp/box-focused-continuation.txt`. The provenance tests use synthetic
packages and a fixture pin API; they are unit evidence, not pinned artifact or
native acceptance. **S:** Python compilation and whitespace checks pass.

**S/U broad checks:** The full static run completed unsuccessfully, recorded at
`/tmp/box-static-continuation.txt`. Syntax, Python compilation, configuration,
generated output, pins and ShellCheck passed. Its `/workspace` Bats phase had
418 passes, 85 failures and 34 skips; many failures explicitly cite the preserved
writable-ancestor/project guards. This is not a complete static pass, and the
85 failures have not each been independently classified.

A separate full Bats run used `/persist` as the writable protected project
parent, log `/tmp/box-unit-continuation-persist.txt`, without changing guards:
531 passes, one failure, five skips (537 cases). The failed case was
`update --check with current seeds reports up to date`; its isolated rerun
passed after the concurrent suites exited. The updater takes a nonblocking
exclusive lock on the same bundle directory even for `--check`, so contention
between the two broad runs is the likely cause; the original failed assertion
did not retain its command diagnostic. Do not describe that broad run as an
unqualified pass. The five skips remain explicit test gates.

```bash
BOX_TEST_PROJECT_ROOT=/persist /tmp/box-bats-core/bin/bats \
  --print-output-on-failure \
  --filter 'update --check with current seeds reports up to date' \
  box/tests/bats/update.bats
```

Future broad runs should use `/persist` and run sequentially to avoid the shared
bundle-maintenance lock. `git diff --check` and the recorded qualification source
hash comparison pass on this final slice.

**N continuation:** After the user supplied official Muse/OpenCode site links,
the pinned artifacts were downloaded to `/tmp` from the Dockerfile's official
URLs. All three matched their registry SHA256 pins. The installed Codex also
matched `bin/codex` in the verified complete package. Each updated fixture passed
with `--scratch-root /persist`; disposable homes were removed. Logs:
`/tmp/box-native-muse-continuation.txt`,
`/tmp/box-native-opencode-continuation.txt`,
`/tmp/box-native-codex-continuation.txt`. Source/artifact/log hashes are in
[`native-qualification-2026-10-08.json`](native-qualification-2026-10-08.json).
OpenCode's client-created schema fingerprint before synthetic additions was
`1595725dab445c6cfabc638fafa2d9bc66a2d1f9c5f038b33996f419702dd971`.
It is an observation, not the complete approved mutation contract. Native
synthetic passes do not close dedicated-account or Docker release gates.

**Remaining gates:** On this x86_64 host, UID/GID are 1000/1000. Docker and runsc
remain unavailable; dedicated account/runtime access has not been supplied.
Q02 runtime/network/callbacks, Q03 Muse device/MCP/trust,
Q04 OpenCode native importer/account/service contract, Q05 Codex MCP/alternate
stores and real refresh, Q06 crash/filesystem durability, ARM64 and actual CI
remain open. The next dependent production changes require these qualifications;
the blueprint is incomplete and unaccepted.

## Sequential handoff verification — 2026-10-08

**S/U:** The requested sequential static run exited 0 on the preserved tree:

```bash
PATH=/tmp/shellcheck-v0.10.0:/tmp/box-bats-core/bin:$PATH \
  BOX_TEST_PROJECT_ROOT=/persist make -C box verify-static
git diff --check
```

Shell syntax, Python compilation, config parsing, generated consistency, pins,
and ShellCheck passed. Bats completed 537 cases: **532 passed, 0 failed,
5 skipped**. All five skips require the missing Docker CLI (dry-run shape,
OpenCode volume persistence, and three Docker config backup/staging cases).
These are host limitations and unmet Docker verification gates, not passes.
The previously contended updater case passed in this sequential run.
Log: `/tmp/box-static-handoff-2026-10-08.txt`; SHA256:
`68b648bbac824c88020c5b5e810a50d234fdaba13cf9645fe321cd76724a7d59`.

Prerequisites were rechecked: Linux x86_64, UID/GID 1000/1000; `/persist`
is owned by that user with mode 700. Docker CLI, runsc, and the local Docker
socket are absent. The user has not identified an accessible qualified host or
dedicated test account. A disposable Linux amd64 VM with a local filesystem,
rootful Engine, runsc, SSH and snapshot/restart control is the proposed next
qualification environment. Its actual versions and behavior must be observed.

No production implementation or auth cutover was performed in this slice.
No new **D/N/A/P/CI** evidence was obtained. Q02–Q06 and all dependent
acceptance gates remain open; no blueprint task was checked off. Existing
changes and permission guards were preserved; nothing was committed or published.

## Independent Q01 groundwork — source baseline capture (2026-10-08)

Added `specs/capture-baseline.py` to reproduce the source inventory on the dirty
checkout and qualification host. It emits JSON to stdout with HEAD/status,
source SHA256/modes, host facts and tool lookup results. It excludes provider/auth
files and ignored/non-source artifacts, records symlink targets without reading
them, and refuses observed replacement or file/status changes. Run with writers
idle; this is not an atomic snapshot. No native client, Docker, home or auth
store is accessed. The handoff documents scope and transfer comparison.

**U:** Both `baseline.bats` regressions pass: synthetic source drift, missing
members, credential exclusion and symlink handling; changing checkout status
refuses before JSON publication. Command:

```bash
BOX_TEST_PROJECT_ROOT=/persist /tmp/box-bats-core/bin/bats box/tests/bats/baseline.bats
```

Q01 remains open pending full baseline/qualification acceptance. Q02–Q06 and
their dependent cutover gates remain open. No new D/N/A/P/CI claim is made.

**S/U:** Sequential `PATH=/tmp/shellcheck-v0.10.0:/tmp/box-bats-core/bin:$PATH
BOX_TEST_PROJECT_ROOT=/persist make -C box verify-static` exited 0:
**534 passed, 0 failed, 5 skipped** (539 cases). All five skips require Docker
CLI. Syntax, Python compilation, configuration, generated checks, pins and
ShellCheck pass; the baseline tool also passes a separate Python AST parse.
`git diff --check` passes. Log: `/tmp/box-static-baseline-2026-10-08.txt`, SHA256
`1abeca6dac86e485fb138db085f3482c11ea23a035f0a2f7d81edbcef0a10990`.
Repeated idle source captures matched; output was mode 600. The final source
inventory is `/tmp/box-source-baseline-2026-10-08.json`. Logs and inventories
are temporary local evidence, not release acceptance.
