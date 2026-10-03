# Architecture audit acceptance

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
| F07 | Refresh-with-backup, preserve-installed-pins, atomic seed-if-absent and the single managed-image lifecycle (Codex requirements only); empty Codex TOML and preferences survive; concurrent seeding tested. |
| F08 | Native cache owner/type/mode/writability and parent-link checks fail without contents or silent repair; unsafe-cache negatives include direct symlink/dir/FIFO cases. Real cache/account validity remains untested. |
| F09 | Separate source and installed leaf names; recursive package installation/discovery/generation; installed operation without checkout and obsolete-code cleanup tested. |
| F10 | Format parsing, harness structural validators, generated expected values, per-stage pin consumption and bounded native inspection (readiness spawns wrapped in `timeout 30`); semantic negatives including Muse/OpenCode validator drift and stage-pin mutants. Missing native evidence fails acceptance. |
| F11 | OpenCode installs hash-verified standalone glibc archives (no npm/NodeSource); all stages assert exact `opencode v<VER>`. Build/user/label checks pass. |
| F12 | Probe metadata separated from native configuration; explicit package contracts and documented pin formats/extension surfaces. `probe_url` hosts match `probe_hosts` and network probes (muse exact URL equals settings `api.base_url`); semantic validation lives in `gen-pins --check`/`verify-config`, not `check-pins.sh`. |
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
