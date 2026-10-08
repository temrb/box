# Security, resource and lifecycle audit

Audit date: 2026-10-02 America/Chicago (runtime timestamps extend into
2026-10-03 UTC). Base revision: `de7b03f59f28d3f533acd377a86738fd267c8819`.
Evidence applies to the uncommitted working tree described below, not HEAD alone.

## 1. Executive summary

Three reproducible defects were repaired: timed DNS probes could leave
unlimited containers running; registry validation accepted duplicate or missing
pin-to-image-label mappings; and the full native evidence driver aborted before
runc verification because its cleanup map was undeclared. Focused regressions
cover probe resource arguments, timeout cleanup, startup failures, malformed
cleanup IDs, cancellation and trap restoration, and missing integrity labels.

A bounded cross-filesystem move reproduced OOM under both runsc and runc.
Explicitly sized tmpfs avoided OOM by returning ENOSPC, while disk-backed scratch
completed with intact destination bytes. This supports using verified disk-backed
project scratch for large builds. It does not justify a universal tmpfs cap or
introducing a persistent scratch store. Session defaults remain unchanged.

The proposed missing OpenCode `archive.py` build-input defect was disproved by
both a normal Make build and a disposable copy with changed validator bytes.
The directory negation in `.dockerignore` includes the required file. Session
`exec docker run --rm` is retained: metadata is removed, but recent daemon OOM
events can survive; replacing supervision would introduce terminal/signal risks.

## 2. System model

The audit reviewed shared libraries, all three harness adapters/configurations/
image inputs/native probes, generators and verification fragments, setup/update/
pin-sync flows, Make/CI, unit-test coverage, lifecycle documentation and retained
evidence. Root README, editor configuration, CODEOWNERS and commit template were
also inspected. Ignored credential files and local authenticated state were
excluded from content inspection. No full environments or credential contents
were collected. Historical evidence was treated as historical, including the
older native output that reported OpenCode inspection unavailable; the fresh
production v2 checks now succeed locally under both explicit runtimes.

Baseline: 22 modified tracked files and one untracked
`harnesses/opencode/__pycache__/native-probe.cpython-313.pyc`. Those changes were
preserved. A baseline diff was captured before editing. Audit edits overlap
`lib/launcher.sh`, `lib/tools.sh`, `tests/bats/audit.bats`,
`tests/bats/config-linkage.bats`, `docs/architecture.md` and `docs/acceptance.md`;
all other baseline edits remain outside this remediation. Incidental native
capture and tracked Python-cache changes produced by verification were restored.
The untracked baseline cache was retained.

Environment: Linux x86_64, Bats 1.11.0, ShellCheck 0.11.0, rootful Docker Engine 29.8.1, runsc
`release-20260921.0`, registered runsc/runc, Engine AppArmor/default seccomp and
private cgroup namespace. Docker needs sandbox escalation. Host `/tmp` is tmpfs;
the workspace is ext4. Tests use normal-home disposable fixtures because the
workspace's group-writable ancestors correctly fail persistent-state guards.
No host permissions were weakened. Build CLI homes were disposable.

| Object / boundary | Ownership, sharing and mutability | Lifecycle / cleanup |
|---|---|---|
| Host, local Docker socket | Docker access is host administrative authority; socket is not mounted into sessions | Host-managed; uninstalling wrappers does not uninstall Docker/runsc |
| Source checkout | User-editable scripts, templates, pins and generators; builds trust these bytes | Separate from installed packages and native state |
| Installed code | User-owned launchers, `lib/*.sh`, harness shell adapters in `~/.local/bin` | Setup replaces code; code-only uninstall retains native stores |
| Templates / pins / CLI config | Outside project, user-owned, no unsafe write bits; isolated CLI `{}` with one protected backup | Templates refresh with backup; valid installed pins survive setup and sync explicitly |
| `providers.env` | User-owned 600/400; literal allowlisted LF records, never sourced; selected keys forwarded by name | Empty valid for native login; retained until explicitly deleted |
| Image | UID/GID-matched non-root user; root-owned binaries and Codex requirements; label/version/digest validation | Local-only per-UID/GID tag; rebuilding does not reset native stores |
| Dedicated bridge | Outbound NAT, inter-container communication disabled; unrestricted destinations | Shared by harness sessions; remove only after dependent containers |
| `/workspace` | One writable physical project bind, nonrecursive/private; agent can modify/delete project bytes | Survives session/OOM; project moves change state identity |
| Muse native home (non-auth) | Writable host bind: preferences/trust; `auth.json` inside is a temporary projection only | Project-volume reset retains it; canonical auth removed only by explicit exact-identity removal |
| Canonical auth objects | `~/.config/box/auth/<harness>/u<uid>/[global\|projects/<hash>]`, mode 700/600; `/run/box-auth` mount is the object dir only | One active writer per identity; retained across setup reruns and code-only uninstall; scope changes need explicit transition; removal needs exact identity + idle lease |
| OpenCode v2 volume (non-auth) | Project config siblings, sessions/approvals, data/state; host config file read-only; credential rows are temporary projections only | Exact `box-o-v2` volume reset deletes this project's state; legacy volumes untouched |
| Codex project home (non-auth) + volume | Host preferences/trust/transcripts plus separate SQLite volume; `auth.json` is a temporary projection only | Both stores needed for full non-auth reset; two-project isolation checked without account auth |
| Scratch / shared memory | Read-only rootfs with executable `/tmp`, writable `/run`, `/var/tmp`, `~/.cache`; private IPC `/dev/shm` | Ephemeral; memory charged alongside processes, discarded on container removal |
| Probe tracking directory | Private mktemp directory, Docker-generated CID, shell-generated saved traps | Owned-ID removal on completion/timeout/signals; best-effort if daemon unavailable |

Identity is physical `pwd -P`, SHA-256 truncated to 20 hex characters;
volume names include harness namespace, UID/GID and hash. OpenCode v2 has a
separate namespace. Codex host-home paths use the project hash without UID/GID
in the path; an ownership mismatch fails preflight rather than migrating state.
Aliases retain identity; moves change it. Containers use unique random/time
names; parallel sessions intentionally share their project's native store.

`lib/config.sh:39` defines shared limits, threaded by `lib/run.sh:123` and now
the probe in `lib/launcher.sh`: 8 GiB memory, equal total memory/swap limit,
four CPUs and 512 PIDs. Equal memory/swap means no container swap allowance.
No explicit descriptor ceiling, aggregate concurrent-session quota, or disk quota
is added. The [six production-session inspections](evidence/security-resource-audit/controls.txt)
confirm effective UID/GID, selected runtime, memory/swap, CPU/PID ceilings,
read-only rootfs, private IPC/cgroup namespaces, dropped capabilities and
no-new-privileges for every harness under both explicit runtimes; no explicit
ulimit override is present. tmpfs capacities are separate ceilings, not reservations; they do not
partition the shared cgroup budget. Logs are capped at 10 MiB × three files
per session; persisted native logs, images, build cache, project trees and volumes
can still consume host disk. Resource enforcement was independently exercised
with reduced disposable limits, not by stressing an 8 GiB live session.

Explicit runtime selection and the fallback kill switch are preserved. Automatic
DNS/startup failure may choose hardened runc with NOTICE/WARNING; shell and
explicit runsc runs never auto-substitute. Cancellation now exits instead of
starting fallback. Config precedence and native cache guards retain their
existing rules. Muse shared auth/trust remain mutable; settings use read-only launch snapshots; native permission
settings are not a universal prompting or exfiltration boundary.

## 3. Incident reassessment

The plan supplies a reported OOM/cross-filesystem move incident, but contains no
raw incident telemetry or exact figures. No numeric attribution to that incident
is claimed. Copying into tmpfs strongly explains rising memory pressure; it does
not identify all shared-memory consumers or establish a cleanup race.

Reproduction uses approximately 160 MiB of non-sparse dependency-shaped files,
a 128 MiB cgroup, one CPU, 64 PIDs, no network or authentication, read-only
rootfs, dropped capabilities and disposable disk-backed source. Both runtimes
also execute a scratch script and compile/run a tiny C program before the move.
The [raw six-case results](evidence/security-resource-audit/storage.jsonl) retain
sampled host cgroup counters and final Docker state without environments.

| Runtime | Destination | Move result | OOM flag | Integrity / headroom |
|---|---|---|---|---|
| runc | Unsized tmpfs | 137 | true | All 160 source files retained and checksum-intact |
| runsc | Unsized tmpfs | 137 | true | All 160 source files retained and checksum-intact |
| runc | 32 MiB tmpfs | 1, ENOSPC | false | Source intact; incomplete destination; roughly 37 MiB sampled peak |
| runsc | 32 MiB tmpfs | 1, ENOSPC | false | Source intact; incomplete destination; roughly 53 MiB sampled peak |
| runc | Disposable ext4 bind | 0 | false | All destination files checksum-intact; source removed |
| runsc | Disposable ext4 bind | 0 | false | All destination files checksum-intact; source removed |

Disk-backed copies still reached the cgroup memory limit through reclaimable
file cache; the benefit is reclaimability, not zero memory use. Counter sampling
can miss a fast OOM: zero sampled events are not proof that no OOM occurred.
The final Docker OOM flag is decisive for these disposable containers. Host
cgroup counters, rather than runsc's virtual `/proc`, were sampled.

An initial control erroneously used host `/tmp` for the disk bind and also OOMed.
`findmnt` exposed that `/tmp` itself is tmpfs. Those runs were excluded from the
comparison and the experiment now rejects tmpfs/ramfs scratch parents.

A tiny sized tmpfs gives memory headroom but forces partial copies and breaks
larger workloads. These tests do not cover representative real package installs,
large compilations or dev servers, so no blanket production size policy is
adopted. Operational prevention is to use disk-backed project paths and supported
TMPDIR/cache overrides, with explicit host-disk cleanup. Persistent scratch is
not introduced. Every experiment starts from fresh fixtures; native restart
checks independently establish filesystem persistence, not authenticated resume.

## 4. Severity-ordered findings

Severity concerns impact; likelihood concerns the documented trigger; confidence
concerns supporting evidence. Findings below are not CVSS scores.

| ID | Severity / likelihood / confidence | Trigger, mechanism, affected state and protection | Reproduction / disposition |
|---|---|---|---|
| R01 | High / medium / high | Large cross-filesystem move into session tmpfs exhausts shared memory; processes and all tmpfs compete. Project files remain writable and copies may be incomplete. Existing cgroup ceiling protects the host from one unlimited session, not workload success. Source: `lib/run.sh:136`, `lib/config.sh:40`. | Both runtimes OOM in reduced fixtures. Prevention guidance and repeatable experiment added; global scratch policy deferred pending representative workloads. |
| R02 | Medium / medium / high | DNS probe timeout terminates Docker client without guaranteeing container termination; original probe had no memory/CPU/PID ceilings or ownership tracking. Surviving probe consumes host resources. Source: `lib/launcher.sh:208` onward. | Original TERM-resistant probe returned 137 after timeout kill grace; inspect showed running=true, Memory=0, PidsLimit=null. Removed immediately. Fixed timeout returns 124 and removes its container; TERM returns 143 and removes it. Same shared ceilings, bounded kill grace and CID-specific cleanup implemented. |
| R03 | Medium / low / high | Future registry edits could omit an integrity pin label or map a pin twice. Registry accepted such records, weakening its declared one-pin/one-label contract before build/launch. Current shipped mappings were complete. Source: `lib/tools.sh:256`. | Duplicate version mapping accepted before fix; existing negative failed. Require unique mapping for every declared pin. Duplicate/missing mapping negatives now pass. No shipped pin changed. |
| R04 | Medium / certain on full-driver path / high | Native acceptance referenced `seen[$volume]` without declaring an associative array under nounset; volume text was interpreted as arithmetic and `box` was unbound. It stopped before runc despite valid local policy checks. Source: `tests/native/acceptance.sh:190` onward. | Documented Make target aborted after runsc; declaration added. Full driver now completes both runtimes and persistence checks, then exits 1 for real unmet gates. |
| R05 | Low / high after removed session / high | `exec docker run --rm` removes State.OOMKilled and logs after exit; 137 alone is ambiguous. Source: `lib/docker.sh:302`, harness run arrays. | Disposable 64 MiB allocator returned 137; post-removal inspect failed; daemon event sequence retained create/attach/start/oom/die/destroy. Bounded event diagnostic documented. Supervision unchanged to preserve terminal and signal semantics. |
| R06 | Low / low / high | The storage experiment could exit 0 after a failed compiler prerequisite if the subsequent move succeeded; failure of Docker removal skipped terminating its client. Affects verification reliability, not production launchers. Source: `tests/native/resource-audit.py`, workload and cleanup helpers. | Follow-up offline regressions reproduce both prior behaviors. Prerequisites now fail immediately; expected move failures retain their status; a finally block reaps the client even when daemon cleanup raises. Docker removal failure remains visible. |

Disproved candidate: OpenCode archive validator excluded by build context.
`Dockerfile:133` copies it successfully, including after modifying its bytes in
a disposable bundle and building via Make. No allowlist change or fictitious
missing-input regression was added. Directory negations can include descendants;
the comment about “only actual image inputs” should not be read as a formal
file-by-file build-context secrecy guarantee. Credentials must remain outside the
checkout as already required.

Not reproduced as new defects: parser command injection, automatic broad group
inheritance, Docker socket mounting, recursive host bind exposure, cross-project
state reuse, silent explicit-runtime substitution or unsafe-cache auto-repair.
Existing tests and native containment/state checks provide scoped evidence.
Host check/use races, unsized aggregate storage and serial-update assumptions
remain documented limits, not disproved hazards.

## 5. Exact implemented changes

- `lib/launcher.sh`: shared probe ceilings, private IPC/cgroup namespace and no
  probe logs; private CID tracking, timeout kill grace, ownership-specific bounded
  cleanup, INT/TERM/HUP handling in the calling shell, restoration of caller
  signal traps, and cancellation excluded from fallback classification.
- `lib/tools.sh`: reject repeated pin mappings and require a label for each pin.
- `tests/native/acceptance.sh`: declare the associative cleanup map before the
  runtime matrix; no account gate relaxed.
- `tests/bats/auto-runtime.bats`: behavior regressions and updated timeout/CID
  mock; `audit.bats`: missing-label negative; `config-linkage.bats`: follow the
  timeout kill-grace syntax.
- `tests/native/resource-audit.py`: bounded repeatable storage comparison with
  disk-parent validation, source/destination checksums, counters, signal cleanup
  and exact container ownership. It creates no installed/native user state.
- Follow-up review: storage prerequisite failures stop before the move, and
  client cleanup runs even after a daemon error. `resource-audit-test.py` and
  `tests/bats/resource-audit.bats` add offline behavior regressions, including
  preservation of the expected move failure status.
- README index, operations, troubleshooting and this report: measured storage
  prevention, cleanup guarantees and OOM evidence limits. Architecture corrected
  its stale list of shared tmpfs mounts. Acceptance links fresh scoped evidence.

No upstream pins, native approval policies, state migrations, image exports,
new global locks, descriptor limits, blanket tmpfs caps or persistent scratch
stores were introduced. No verifier partial changed in this audit; generated
verifier and pin-table parity were checked without hand-editing generated files.

## 6. Verification outcomes

Fresh evidence: [full native assertions](evidence/security-resource-audit/native.txt),
[focused OpenCode assertions](evidence/security-resource-audit/opencode-focused.txt),
[storage experiment](evidence/security-resource-audit/storage.jsonl),
[probe/OOM observations](evidence/security-resource-audit/probes.txt), and
[implementation fingerprints](evidence/security-resource-audit/source.sha256).

- `make -C box verify-static` exits 0: syntax/configuration, generated parity,
  pin consistency, ShellCheck and all 372 Bats tests pass. `make -C box pins`
  independently exits 0; `git diff --check` passes.
- Narrow probe and registry regressions pass; the probe's resource/cleanup and
  cancellation negatives failed before remediation. Caller-trap preservation,
  invalid IDs and no-ID startup failures are exercised offline.
- Runtime probe reproduction uses the production function and Docker arguments,
  substitutes only a TERM-resistant DNS workload, and shortens the test timeout.
  Successful cleanup was checked by exact recorded CID and absent tracking path.
  A first subshell-based implementation failed the TERM test and was replaced
  with trapping the launcher shell itself; that failed approach is not shipped.
- Normal and changed-validator-byte OpenCode Make builds succeed. Final production
  Muse/OpenCode/Codex builds pass UID/GID and label checks with disposable CLI homes.
- Full native Make target completes both explicit runtimes: all harness native
  versions and shared containment, Muse echo startup, Codex native policy conflict
  checks, OpenCode permission/default/override/saved-approval/state checks, Codex
  two-store/two-project persistence, setup preservation and obsolete-code removal.
  It exits 1 because runsc external DNS/HTTPS and missing real authentication are
  still unmet. Its generic failure summary does not distinguish every transport
  gate; see the detailed UNMET lines.
- Focused OpenCode Make target exits 0 for account-independent checks, including
  incompatible installed-pin rejection and recovery, preserved differing valid
  pins, both explicit runtimes, client preferences and saved-approval isolation,
  legacy volume preservation, and cleanup. Real login/model/resume remain unmet.
- Workspace-root unit fixtures hit legitimate unsafe-ancestor rejections. Static
  verification uses the suite's normal disposable home fixtures instead; no
  guard was bypassed. Final static/pin results are retained in
  [static evidence](evidence/security-resource-audit/static.txt).

Reproduce the storage experiment only on disposable disk-backed scratch:

```bash
python3 box/tests/native/resource-audit.py \
  --image box-o:2.0.6-u$(id -u)-g$(id -g) --scratch-root "$PWD"
make -C box verify-static
make -C box pins
make -C box build
make -C box verify-native
make -C box verify-native-opencode
```

Build commands use current pins and local-only images. Runtime experiments
require rootful Engine access. Native drivers install into disposable homes;
ordinary setup/build/uninstall was not run against live authenticated stores.

### Follow-up plan review

The original implementation fingerprints all matched at review entry. The
storage-helper changes above postdate `source.sha256` and the six retained
runtime results; those original artifacts remain historical evidence. Runtime
and image builds were not repeated in this follow-up. Both new failure
regressions detect the prior control flow in offline negative controls.

Follow-up `make -C box verify-static` exits 0 with all 374 Bats cases;
`make -C box pins` and `git diff --check` pass. The first sandboxed attempt
failed fixture setup because the home directory was read-only; the successful
run used sandbox escalation for ordinary disposable home fixtures. See
[follow-up static output](evidence/security-resource-audit/recheck-static.txt)
and [updated source fingerprints](evidence/security-resource-audit/recheck-source.sha256).
Incidental changes to the two tracked Python cache files were restored; the
pre-existing untracked Python cache was preserved.

The eight report sections, lifecycle model, candidate dispositions, regression
coverage and generated-artifact checks address the implemented audit scope.
The plan is not fully verified end to end: the open cases in section 7 include
locally testable work (representative dependency/build/server workloads,
disk-full behavior, concurrent setup/update, interrupted-start races and project
move/UID changes), as well as external account/architecture/CI gates. Deferring
those cases is a coverage limitation, not evidence of success. Probe TERM
evidence covers an already created container; offline no-ID tests do not prove
cleanup across an actual interrupted Docker create/start race.

## 7. Unresolved gates

Real accounts, authentication/model requests and authenticated restart/resume;
ARM64 execution; external runsc DNS/HTTPS transport; actual remote GitHub CI;
representative dependency installation, large build/dev-server/cache workloads;
host disk-full behavior; power-loss/SIGKILL recovery; and concurrent setup/update
transactions remain unverified. Mocked failure/rollback tests do not certify
power-loss recovery. No live project or credential import was used to close them.

Reset/uninstall ownership and store boundaries were traced through registry and
docs and disposable fixtures were cleaned. A full destructive live uninstall,
UID/GID migration and real project move recovery were not performed. Their
instructions are inventory-driven and deliberately require explicit review of
which authentication/transcript stores to delete or transfer.

## 8. Residual risk

Agents can damage mounted project files, alter writable native state, use their
forwarded or native credentials and exfiltrate over unrestricted egress. gVisor
and hardened runc are distinct boundaries; runc requires an explicit fallback choice
and can be disabled. The rootful Docker socket on the host remains privileged.

One session's 8 GiB ceiling does not bound concurrent aggregate memory or host
persistent disk. tmpfs shares the cgroup budget and can still OOM. Larger real
workloads may need disk scratch, careful cache placement and host capacity
planning; the synthetic comparison cannot determine a safe universal size.
Named volumes/native logs/build cache do not auto-expire. Auth identities and
their native projections have serialization locks; those locks do not establish
safe concurrent writes to every unrelated native state store.

Path checks are best-effort check/use guards, not race-free openat/O_NOFOLLOW
transactions. Setup copies installed code/templates per file and is not a
whole-package atomic transaction. Updates should run serially; detected rollback
is not crash consistency. Probe cleanup is bounded but daemon failure, SIGKILL,
host failure or a Docker create/start race can prevent completion. Warnings name
an owned CID when available; operators must not broad-delete other sessions.
Post-removal daemon event history is finite and not a durable incident log.

### Auth removal follow-up (2026-10-07)

Canonical auth deletion now uses deterministic permanent identity locks,
read-only identity inventories, Docker bind-liveness checks and durable removal
checkpoints with per-member inode/mode/digest validation. Synthetic fault tests
cover checkpoint publication, member deletion and directory deletion, including
foreign-byte preservation on refusal. This does not qualify a full non-auth
uninstall or a crash-consistent whole-project reset. OpenCode validation/export
operate on private database/WAL/SHM copies; unknown token-bearing tables and
unsupported native credential payloads refuse before source mutation. Native
service-stop enforcement and pinned OpenCode database/account qualification
still need native runtime evidence. See the current [acceptance record](acceptance.md).

Lifecycle removal now uses re-resolved native discovery records and durable
exact-member manifests. Project reset records volume creation identity to refuse
replacement volumes. Full removal holds an exclusive harness lifecycle lock,
includes explicitly selected provider files and preserves unlisted installed
code. Its final completion marker prevents recovery from re-inventorying newly
created state. Permanent lock inodes remain outside removable auth objects.
These mechanisms have synthetic interruption coverage; actual runtime locking,
SIGKILL/power-loss stages and native refresh remain separate acceptance gates.
