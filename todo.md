# Unified box security, authentication, and lifecycle implementation blueprint

**Active checklist:** `/workspace/todo.md`.

**Historical planning constraint:** The original Plan Mode audit proposed
`specs/todo.md` without editing files. Implementation is now underway in the
existing checkout; current evidence is recorded below and in the progress log.

**Audit baseline:** `/workspace`, branch `dev`, HEAD `c85d13ca5706ba865bdede73b8aa8021df8a28ff`, including the existing uncommitted implementation.

## Implementation progress — 2026-10-08

Implementation has started against the existing dirty checkout. See
[`specs/implementation-progress.md`](specs/implementation-progress.md) for
completed fix surfaces, reproducible checks, and remaining qualification.
The latest continuation adds policy consolidation, host filesystem primitives,
external-hardlink detection, pure adapter validation, mandatory image override
pins and a protected qualification workflow. Pinned synthetic native fixtures
pass; full runtime/account/durability and release acceptance remain open.
The full task checkboxes below remain open until their complete acceptance
criteria are established; implementing a defect does not close its broader task.

## A. Goal and final architecture

Build one system in which sandbox selection, project identity, authentication scope, native persistence, migration, supervision, and recovery use consistent contracts.

The selected design is:

- Rootful, local Docker remains the supported execution environment. Containers run as the invoking nonzero UID/GID.
- `runsc` is the default runtime. A failed registration, startup, or required network check fails the launch. Box never automatically changes to `runc`.
- Explicit `--docker-fallback` permits the supported runc compatibility mode, subject to the existing per-harness fallback prohibition. Host-wide runc installation and registration remain untouched.
- Canonical authentication, locks, migration records, and recovery journals are **host-owned control state and are never mounted into agent containers**.
- Authentication is projected into verified native stores under a serialized lease. Native preferences, trust, approvals, sessions, transcripts, databases, and project data retain their existing non-auth scopes.
- A host lifecycle supervisor owns the exact Docker container IDs, canonical publication, cleanup decisions, and recovery transitions. Container supervision manages client processes and native services; it has no Docker socket or canonical-state authority.
- Migration is explicit, source-specific, journaled, additive, and recoverable. Fresh initialization preserves displaced legacy credentials before native projection can overwrite them.
- Disposable verification resolves its execution domain before selecting state. It cannot import, mount, migrate, or delete production authentication.
- Native adapter support is qualified against the pinned client artifacts. Unknown credential schemas and backends fail explicitly while preserving their source.

### Authentication and persistence boundaries

Let:

- `H` be the registered harness.
- `U` and `G` be the invoking UID/GID.
- `P` be the first 20 hexadecimal characters of SHA256 of the physical selected workspace-root path.
- `R` be `BOX_AUTH_ROOT`, defaulting to `$HOME/.config/box/auth`.
- `T` and `N` be a validated disposable task root and namespace.

| State                    | Production location or identity                         | Scope                                       |
| ------------------------ | ------------------------------------------------------- | ------------------------------------------- |
| Canonical global auth    | `R/H/uU/global`                                         | Harness and UID                             |
| Canonical project auth   | `R/H/uU/projects/P`                                     | Harness, UID, physical project              |
| Test-global auth         | `T/N/auth/H/uU/global`                                  | Disposable namespace, harness, UID          |
| Test-project auth        | `T/N/auth/H/uU/projects/P`                              | Disposable namespace, harness, UID, project |
| Muse native config home  | Existing default or `BOX_M_PERSIST_DIR`                 | Existing global non-auth home               |
| Codex native home        | Existing state root plus `P/codex-home`                 | Project                                     |
| Production native volume | `<state_prefix>-uU-gG-P`                                | Project and UID/GID                         |
| OpenCode mixed database  | Existing project volume, native database path           | Project                                     |
| Codex SQLite state       | Existing project volume at `/persist/state/codex`       | Project                                     |
| External provider file   | Existing protected, explicitly selected `providers.env` | Independently managed                       |

Preserve the current auth fallback scopes: Muse global; OpenCode and Codex project.

A GID change retains the canonical auth identity. Existing non-auth volume naming remains UID/GID-sensitive. Recovery uses the recorded original native-store descriptor, including its original GID, rather than reconstructing it from the current group.

### Lifecycle ownership

The host holds stable locks throughout a launch. Locks alone do not establish whether a container survived a host-process crash; durable journals and exact Docker inspection provide that evidence.

The normal sequence is:

1. Resolve and validate configuration, execution domain, project, state descriptors, and requested runtime.
2. Validate Engine, network, immutable image ID, native version, and adapter contract without production authentication mounts.
3. Acquire lifecycle, auth, and native-store locks.
4. Verify migration, scope-transition, and interrupted-operation prerequisites.
5. Publish a reservation.
6. Create the agent container and durably record its exact ID.
7. Prepare native projections through the qualified adapter.
8. Durably record successful projection and start intent.
9. Start and attach to the exact container.
10. Establish container termination and native-service quiescence.
11. Export and validate resulting authentication.
12. Durably publish a pending collection, then the next canonical revision.
13. Scrub the native projection.
14. Complete the journal and remove the exact owned container.

File adapters may operate on verified host native files after their containers have stopped. SQLite parsing and modification run in a contained, network-disabled helper. Neither helper nor agent receives the canonical directory.

### Supported security guarantees

The system limits the host resources exposed to agents through explicitly authorized mounts, namespaces, capabilities, runtime selection, and resource ceilings.

It does not guarantee:

- Safety of writable selected project contents.
- Confidentiality of credentials deliberately supplied to the native client.
- Prevention of internet exfiltration under unrestricted egress.
- Protection against the invoking host user, Docker administrators, or host root.
- Unlimited workload success within finite memory and storage.
- Recovery of a remotely rotated token that the client never durably saved.
- Isolation of Muse’s existing shared non-auth trust home between projects.

These limitations must remain visible in operator documentation.

## B. Verified current-state baseline

### Checkout and preservation

The Git repository root is `/workspace`; the implementation is `/workspace/box`; historical planning inputs are `/workspace/specs`.

At audit completion:

- Branch: `dev`.
- HEAD: `c85d13ca5706ba865bdede73b8aa8021df8a28ff`.
- Tracked changes: 52 files, 1,804 insertions and 183 deletions.
- Porcelain untracked entries: 27, including directories such as `specs/`.
- `specs/todo.md`: absent.
- The existing modified/untracked status and tracked diff totals remained unchanged.
- The disposable Codex fixture removed its temporary home.
- No Docker resources, credentials, production state, application source, or tests were modified.

The checked-out HEAD corresponds to the open [PR #2](https://github.com/temrb/box/pull/2). The uncommitted auth implementation is additional local work; remote main is not its substitute.

Recent history includes disposable test namespace work, launcher/config hardening, setup serialization, registry refactoring, and the symlink-scan SIGPIPE fix. The GitHub issue listing returned the two pull requests; it did not establish a separate unresolved issue backlog.

### Current components

| Component                  | Current implementation                                                                   |
| -------------------------- | ---------------------------------------------------------------------------------------- |
| Registry                   | `lib/tools.sh`: harness, artifact, state, adapter, pin, and destination records          |
| Public invocation          | `box-m`, `box-o`, `box-c`, `box-m-login`                                                 |
| Shared launch path         | `lib/launcher.sh`, `lib/run.sh`, `lib/docker.sh`                                         |
| Filesystem and credentials | `lib/preflight.sh`, `lib/config-file.sh`                                                 |
| State/auth work            | `lib/state.sh`, `lib/auth.sh`, `lib/auth-ops.sh`                                         |
| Container supervision      | `lib/supervisor.sh`, `lib/supervisor-process.py`, OpenCode entrypoint                    |
| Native auth adaptation     | Three `auth.sh` adapters; OpenCode `auth-state.py` and `auth-volume.py`                  |
| Installation/build/update  | `setup.sh`, `lib/install.sh`, `lib/build.sh`, pin helpers and update/sync scripts        |
| Verification               | Shared/harness partials, generated verifiers, Bats, native drivers, root GitHub workflow |
| State removal              | Discovery, exact-member, and reset transaction Python helpers                            |

Installed operation currently copies wrappers, shared libraries, and harness adapters under `~/.local/bin`. Configuration and state remain outside the checkout.

### Pinned artifacts

| Dependency      | Current pin                                                                           |
| --------------- | ------------------------------------------------------------------------------------- |
| Debian base     | `trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132` |
| Muse            | `1.4.0-R4161.1`                                                                       |
| OpenCode        | `2.0.6`                                                                               |
| Codex           | `0.160.0`                                                                             |
| OpenCode source | `b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad`                                            |
| Codex source    | `a956835d020762cb2b570053af06f643a11c0ecc`                                            |

Both upstream source identities were independently verified. The Codex release tag resolves through an annotated tag to the listed commit.

Client artifact SHA256 values are architecture-specific in the existing version files. Builds validate downloaded artifacts and normalized native versions. Debian’s manifest digest is pinned; apt package resolution and the Dockerfile frontend remain separate provenance/reproducibility concerns.

### Existing protections established by source inspection

The current source constructs:

- Nonzero host-matched UID/GID execution.
- Capability dropping and no-new-privileges.
- Read-only root filesystem.
- Private IPC and cgroup namespaces.
- Dedicated masquerading bridge networks with ICC disabled.
- Nonrecursive, private project and native bind mounts.
- 8 GiB memory, equal memory/swap limit, four CPUs, and 512 PIDs.
- No supplied Docker socket, privileged mode, host namespace, or automatic supplementary-group inheritance.
- Explicit opt-in supplementary groups, excluding GID zero.
- Protected credential parsing, allowlisted literal LF-only entries, and NAME-only forwarding.
- Project/root/credential/state containment checks.
- External Git metadata rejection.
- Native cache and journal owner/type/mode checks.
- Strict scope values and validation of shadowed scope inputs.
- Stable external auth locks and recoverable removal checkpoints.

These are source-level findings. Actual enforcement for the current uncommitted tree has not been established under Docker or gVisor during this audit.

Rootful Docker access remains administrative host authority. Pinning the local socket prevents accidental endpoint redirection; it does not reduce the authority of the daemon or its authorized users. [Docker security documentation](https://docs.docker.com/engine/security/)

### Fresh checks executed

| Evidence category                  | Result                                                   |
| ---------------------------------- | -------------------------------------------------------- |
| Shell syntax                       | `make -C box verify-shell`: passed                       |
| Configuration/registry             | `make -C box verify-config`: passed                      |
| Generated verifiers                | `make -C box verify-generated`: passed                   |
| Pin checks                         | `make -C box pins`: passed                               |
| Python syntax                      | In-memory compilation of 19 Python files: passed         |
| Whitespace                         | `git diff --check`: passed                               |
| Native Codex storage               | Disposable synthetic fixture: passed                     |
| Bats                               | Not executed; binary unavailable                         |
| ShellCheck                         | Not executed; binary unavailable                         |
| Docker/runsc                       | Not executed; CLI, runtime, and local socket unavailable |
| Muse/OpenCode native clients       | Unavailable                                              |
| Real accounts/refresh/model/resume | Not executed                                             |
| ARM64                              | Not executed                                             |
| Remote CI                          | Not executed                                             |

There are 532 declared Bats cases in the current tree. Historical reports of 496, 498, or 530 cases describe earlier snapshots and are not fresh passes.

The available Codex executable reports `codex-cli 0.160.0`. Its synthetic fixture passed API-key storage/logout, synthetic OAuth loading, adapter round trips, local refresh-shaped changes, malformed/unsupported payload preservation, and unrelated marker preservation. This does not establish the executable’s shipped-image provenance or actual OAuth rotation.

### Live defects and incomplete integration

| Finding                                                        | Evidence and consequence                                                                                                                        | Tasks              |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| Automatic isolation downgrade                                  | `box_auto_runtime` changes to runc after failed runsc probes, including startup and timeout failures                                            | R01                |
| Writable host control state exposed                            | All three launch adapters mount the canonical object at `/run/box-auth`; OpenCode and shared supervisors modify canonical and lease files there | C05, R03, R04, L02 |
| Native mutations precede final runtime/image checks            | File launchers prepare preferences and auth before `box_docker_exec` validates the image/runtime/network                                        | R03, R04           |
| Lifecycle remains `docker run --rm`                            | No durable agent-container ID; termination/removal destroys useful evidence and complicates recovery                                            | R03, O02           |
| OpenCode canonical copy validation is incompatible             | `box_auth_verify_envelope` installs into a nonexistent scratch native path; OpenCode `cmd_install` requires an initialized native database      | A03                |
| Valid disposable Codex root rejected                           | `box_test_guard_bind_root` adds test `BOX_C_STATE_ROOT` to its production roots; reproduced with a pure read-only call                          | C03, T01, T02      |
| Migration acknowledgment is too coarse                         | A destination-level marker can suppress checks for a different legacy source; a nonempty canonical file can bypass a file legacy gate           | M01, M02           |
| Fresh initialization can displace legacy auth                  | `box_ops_init` writes a fresh marker without preserving the native source; later tombstone installation can scrub it                            | M02                |
| Muse supported auth subset conflicts with advertised workflows | Adapter currently accepts Meta API-key file shapes and rejects OAuth; device login and MCP remain unqualified                                   | Q03, A01           |
| Auth inventory incomplete                                      | Muse MCP and Codex `.credentials.json` are outside current provider adapters                                                                    | Q03, Q05, A01, A02 |
| Host SQLite path remains available                             | Explicit OpenCode `DB_PATH` routes can invoke database parsing on the host                                                                      | A03, M01           |
| SQLite schema checks incomplete as a security contract         | Columns/FKs are checked, but malicious or incompatible triggers/views and bounded database processing need explicit treatment                   | Q04, A03           |
| Multiple orchestration authorities                             | File host collection, container OpenCode collection, volume helper publication, and unused generic wrappers implement competing lifecycle paths | C05, R04, L02      |
| Install/update cutover lacks whole-package atomicity           | Setup replaces code file by file; its home lock differs from updater’s bundle lock and active launch ownership                                  | I01, I02           |
| Make input interpolation is unsafe                             | Dry-run expansion retains backticks inside shell double quotes for `PROJECT`; dollar-shaped names also undergo Make expansion                   | C04, T01           |
| Documentation contains stale architecture claims               | Physical launch directory versus workspace-root identity; image contract 2 versus 3; earlier “missing” fixes and outdated qualification claims  | D01                |

The Make finding is grounded in generated recipe inspection, not an executed injection experiment.

### Native state inventory and remaining qualification

| Harness  | Authentication                                                                                                                                                                        | Auth-adjacent and non-auth state                                                                                                                                                       |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Muse     | Current file adapter recognizes `schema_version=1`, `providers.meta.api_key`; native device/OAuth and MCP membership require qualification; external key translated to `META_API_KEY` | Existing global config/trust home, read-only settings snapshot, legacy preference backup, project data/state and `.muse` target                                                        |
| OpenCode | `credential` rows; token-bearing `account` and legacy `control_account` schemas; MCP credentials use integration identities                                                           | `credential.active`, `account_state`, and legacy active selection; sessions, approvals and other project records remain in mixed DB; config siblings and sidecars remain project-local |
| Codex    | Provider `auth.json`; separate MCP fallback `.credentials.json`; alternate auth and encrypted/keyring backends exist upstream                                                         | Project trust/config/history/sessions/logs; separate project SQLite state; native MCP lock directories; external provider keys                                                         |

Pinned Codex provider saving truncates its native auth file and logout unlinks it. A permanent file bind or credential symlink cannot reproduce those semantics reliably. [Pinned Codex storage source](https://github.com/openai/codex/blob/a956835d020762cb2b570053af06f643a11c0ecc/codex-rs/login/src/auth/storage.rs)

Pinned Codex MCP storage has its own aggregate-store and refresh coordination. Historical statements that Codex has no native locking must be confined to the provider file backend. [Pinned MCP storage](https://github.com/openai/codex/blob/a956835d020762cb2b570053af06f643a11c0ecc/codex-rs/rmcp-client/src/oauth.rs), [aggregate locks](https://github.com/openai/codex/blob/a956835d020762cb2b570053af06f643a11c0ecc/codex-rs/rmcp-client/src/oauth/store_lock.rs)

OpenCode’s verified upstream schemas include credentials, accounts, and account selection. Native activity, bootstrap migration, service termination, and mixed-record preservation remain qualification gates. [Credential schema](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/credential/sql.ts), [account schema](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/account/sql.ts)

## C. Source reconciliation and coverage matrix

### Historical input inventory

All six files under `specs/` were inventoried:

| Input                      | Size/relationship   | Use                                                        |
| -------------------------- | ------------------- | ---------------------------------------------------------- |
| `specs/plan.md`            | 988 lines           | Original auth architecture and implementation requirements |
| `specs/passes/plan.md`     | Byte-identical copy | Same requirements; not independent corroboration           |
| `specs/granular-issues.md` | 544 lines           | Security investigation requirements and candidate policies |
| `specs/passes/pass-1.md`   | 818 lines           | First implementation review and detailed findings          |
| `specs/passes/pass-2.md`   | 79 lines            | Consolidated gaps                                          |
| `specs/passes/pass-3.md`   | 2,211 lines         | Repeated inputs and subsequent verification narrative      |

The two plan copies have SHA256 `54acd88905ba1566e9c46f8a2781d555e0f1167df6536e2a0e1dfebca32db5cb`.

Retained repository evidence, including ignored files under `docs/evidence/`, was also examined for outcomes and freshness. Historical source manifests differ materially from the current tree; for example, the next-pass baseline manifest had 28 matching and 85 changed files.

### Material historical dispositions

| Historical requirement/finding                 | Current disposition                             | Evidence or selected resolution                                                                              | Tasks            |
| ---------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ---------------- |
| Declarative auth state per harness             | Largely satisfied                               | Registry has one auth record and default scope per harness                                                   | C01, T01         |
| Keep mixed homes/databases project-scoped      | Accepted                                        | Preserve existing non-auth boundaries                                                                        | C03, A01–A03     |
| Global/project scope support                   | Partially implemented                           | Policy exists; native breadth and lifecycle are incomplete                                                   | Q03–Q05, A01–A03 |
| Exact precedence and shadowed-value validation | Mostly satisfied                                | Current scope resolver checks all supplied scope values                                                      | C02, T01         |
| Empty roots/sentinel accepted                  | Superseded by fixes                             | Current setness tracking rejects these; retain negatives                                                     | T01              |
| Empty harness table should inherit             | Satisfied in current parser                     | Missing scope inherits; strict schema type checks exist                                                      | C02, T01         |
| Optional getter/missing handling               | Dead implementation                             | Getter has no consumers; remove it instead of retaining unused semantics                                     | C02              |
| UID-keyed auth, GID-keyed native volumes       | Accepted                                        | Preserve formulas; recovery retains original native coordinates                                              | C03, L02         |
| Single resolver                                | Partially satisfied                             | Formula helpers centralized, but launch and operations still independently orchestrate contexts              | C03              |
| Triplicated auth formula                       | Mostly superseded                               | Auth resolution delegates to domain helpers; remaining duplicated call sequences still require consolidation | C03              |
| Writable canonical object mount                | Rejected                                        | Exposes credentials plus host lifecycle metadata to agents                                                   | C05, R04         |
| Auth-only canonical envelope                   | Accepted with versioned expansion               | Existing provider-only envelope cannot cover qualified multi-member auth                                     | C05, A01–A03     |
| Native file bind/symlink auth                  | Rejected                                        | Native replacement/unlink semantics require regular projections                                              | A01, A02         |
| Shared global home implies global auth         | Rejected                                        | Non-auth scope and auth scope are separate                                                                   | C03, A01         |
| Global SQLite database for auth                | Rejected                                        | Would share sessions and approvals                                                                           | A03              |
| Active selection inside canonical auth         | Rejected except intrinsic credential binding    | OpenCode selections remain project-local                                                                     | A03              |
| One active writer per auth/native store        | Accepted                                        | Host stable locks plus durable lease; no container lock handoff                                              | L01              |
| Container owns canonical commit                | Superseded                                      | Host alone publishes canonical revisions                                                                     | C05, L02         |
| Create/record/start lifecycle                  | Required, absent for agent sessions             | Current launch still uses `run --rm`                                                                         | R03              |
| Unknown native backends fail explicitly        | Partially implemented                           | File subsets reject shapes; complete source/member detection is unqualified                                  | Q03–Q05          |
| Muse qualification only comments               | Superseded in part                              | Strict API-key subset and native fixture exist; OAuth/MCP remain blocked                                     | Q03, A01         |
| OpenCode account tables unsupported            | Superseded in source, conditional in acceptance | Adapter contains account handling; pinned native activity remains unproven                                   | Q04, A03         |
| OpenCode active selection is singular globally | Rejected                                        | Selection is per integration, plus separate account/org state                                                | A03              |
| Endpoint-bound MCP integration identity        | Accepted                                        | Preserve upstream IDs and validate endpoint identity; never remap by name alone                              | Q04, A03         |
| OpenCode live migration gate absent            | Superseded in part                              | Entry point checks credentials, but not complete source-specific adoption                                    | M01              |
| Legacy importer quarantine absent              | Superseded in part                              | Startup refusal exists; authorized quarantine/recovery still needs a complete operation                      | M01, M03         |
| OpenCode retire is a no-op                     | Superseded                                      | Current retire exports auth and scrubs; contained helper exists                                              | A03, M03         |
| Shared-library harness-name branch             | Superseded                                      | Legacy discovery now dispatches to adapters                                                                  | T01              |
| Dry-run lacks migration/transition coordinates | Superseded in launchers                         | Reporting exists; ensure complete descriptor use and safe metadata access                                    | C03, T01         |
| Dry-run must not read credentials or DBs       | Accepted                                        | Preserve and strengthen observation-based tests                                                              | T01              |
| Image supervisor compatibility absent          | Superseded in part                              | Contract 3 required even for overrides; version/adapter compatibility still insufficient                     | R02              |
| Stopped-client checks absent                   | Superseded in part                              | Docker mount-holder checks exist; exact CID lifecycle and full native-holder checks still needed             | R03, L02         |
| jq absence fails open                          | Superseded in principal auth operations         | Mandatory jq checks exist; malformed status handling still needs uniformity                                  | C02, T01         |
| Descriptor empty-pattern bypass                | Superseded                                      | Current guard compares complete resolver output                                                              | C03, T01         |
| FD leakage on `die`                            | Historical claim overstated                     | Process exit closes descriptors; the significant risk is incomplete lease/journal cleanup                    | L01, L02         |
| Test helper environment leak                   | Still applicable                                | `BOX_AUTH_TRANSITION`, auth/runtime/helper selectors are not uniformly cleared                               | T01              |
| Old Muse durable-auth test                     | Superseded by updates                           | Test changed; verify behavior against native qualification                                                   | T01, T02         |
| Native matrix incomplete                       | Implementation present, execution conditional   | Driver exists; disposable Codex guard currently blocks a valid fixture                                       | C03, T02         |
| Full removal only effective scope              | Superseded                                      | Current inventory includes inactive scopes and historical roots                                              | O01              |
| Whole reset/removal recovery absent            | Superseded in source, conditional in acceptance | Journals exist; actual crash/runtime integrity remains unqualified                                           | Q06, O01, T02    |
| Code-only uninstall preserves state            | Accepted                                        | Preserve explicit code/state boundaries during installation redesign                                         | I01, O01         |
| Source and destination conflicts never merge   | Accepted                                        | Pure envelope validation and semantic conflict checks required                                               | A03, M02         |
| Fresh init means no import                     | Accepted with correction                        | Preserve legacy backup before projection; do not silently destroy old credentials                            | M02              |
| Automatic fallback is acceptable if warned     | Rejected                                        | A warning does not make weakening isolation fail closed                                                      | R01              |
| Remove host runc to enforce policy             | Rejected                                        | Box-specific selection suffices; host runtime removal breaks unrelated workloads                             | R01              |
| Rootless/userns as immediate replacement       | Deferred, technically justified                 | Current socket and UID mapping differ; no qualified drop-in migration                                        | Q02, D01         |
| Arbitrary internet egress                      | Accepted tradeoff                               | Preserve normal networking; document host/LAN/metadata exposure                                              | T04, D01         |
| tmpfs executable support                       | Accepted                                        | Builds/scripts require executable scratch; retain nosuid/nodev and memory ceilings                           | O02, T04         |
| Universal smaller tmpfs limit                  | Rejected without workload evidence              | Historical ENOSPC and OOM do not identify a safe universal size                                              | O02              |
| Aggregate CPU/RAM/disk quotas                  | Accepted operational limitation                 | Per-container limits do not establish aggregate capacity or persistent disk quotas                           | O02, D01         |
| OpenCode archive excluded from context         | Rejected historical claim                       | Actual COPY/build evidence disproves absence                                                                 | R02              |
| Build context is a formal file allowlist       | Rejected current claim                          | Parent negations can reinclude descendants; enforce a tested allowlist                                       | R02              |
| Static/mock passes prove native behavior       | Rejected                                        | Separate evidence categories and release gates                                                               | T01–T04          |
| Historical runtime PASS proves current tree    | Rejected                                        | Relevant source hashes changed                                                                               | Q01, D01         |
| Codex has no credential locks                  | Narrowed                                        | Provider file lacks required coordination; MCP has native locks                                              | Q05, A02         |

### Existing repository audit findings

Preserve the useful F01–F17 work: registry/package boundaries, root workflow, strict parsers, cache guards, native configuration validation, pin threading, live defaults, dry-run isolation, and documentation structure. Their current acceptance must be rerun through T01–T04.

Disposition of the historical resource findings:

| Historical finding                                        | Disposition                                                                      |
| --------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Resource R01: tmpfs OOM/partial moves                     | Accepted workload risk; improve diagnostics and qualify representative workloads |
| Resource R02: probe resource/cleanup omission             | Source fix present; repeat race/daemon failure qualification                     |
| Resource R03: missing/duplicate pin labels                | Registry fix present; retain mutation negatives                                  |
| Resource R04: undeclared native cleanup map               | Fixed; retain driver regression                                                  |
| Resource R05: lost post-exit OOM evidence                 | Address with retained exact-container inspection before removal                  |
| Resource R06: false-success resource prerequisite/cleanup | Fixed; retain meaningful regressions                                             |

The retained `probe-races-before.jsonl` records `boundary_reached=false` and a readonly-variable error. Those records do **not** qualify create/start race handling.

## D. Architectural decisions and invariants

### D1. Runtime and platform policy

Support Linux with rootful local Docker Engine 25 or newer as the interface floor. Release support is restricted to host/runtime/storage combinations actually qualified by Q02, Q06, and T04.

Qualify amd64 first and arm64 separately. Artifact availability is not ARM64 runtime acceptance. macOS, Windows hosts, remote Docker contexts, rootless Engine, and userns-remapped Engine remain unsupported by this implementation.

The selected runtime is explicit in every agent, probe, and auth-helper invocation:

- Default: runsc.
- `--runsc`: runsc.
- `--docker-fallback`: runc, with a visible compatibility warning.
- `BOX_M/O/C_ALLOW_FALLBACK=0`: prohibit explicit runc too.
- A value of `1` permits the explicit choice and never enables automatic fallback.
- Invalid supplied fallback values fail before state access.
- Conflicting runtime flags fail with a usage diagnostic.

Network-required native workflows receive bounded runsc DNS/transport qualification. Offline version/help/status/logout and diagnostic shell workflows retain offline usability; they still require the selected runtime and containment checks. No failed probe authorizes a different runtime.

gVisor’s isolation differs from runc’s kernel namespace/seccomp boundary. OCI seccomp, guest capability reporting, and host protections must be graded against the qualified runtime configuration, not assumed equivalent. [gVisor architecture](https://gvisor.dev/docs/architecture_guide/intro/)

Rootless gVisor exists upstream, but the current host-matched UID design and pinned rootful socket are not a qualified rootless configuration. Supporting it requires a separate UID mapping, filesystem ownership, networking, and resource-enforcement design. [gVisor rootless documentation](https://gvisor.dev/docs/user_guide/rootless/)

### D2. Threat model

| Attacker                           | Intended protection                                                                        | Residual boundary                                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| Malicious agent/workload           | Contain access to selected project, native projection/state, allowed network and resources | Can destroy selected project and use supplied credentials                                                |
| Hostile project                    | Data-only host parsing; no project-controlled host execution; checked mounts/metadata      | Host tools later executing modified project content are outside the container boundary                   |
| Compromised native dependency      | Agent-side containment                                                                     | Build/install executes trusted supply-chain code before agent isolation; hashes do not prove benign code |
| Neighbor container                 | Separate namespaces, no shared auth control mounts, qualified bridge behavior              | Docker administrator can attach mounts/networks                                                          |
| Other unprivileged host user       | Protected roots/files/locks and safe filesystem operations                                 | Same-user/root authority and unsupported shared filesystems excluded                                     |
| Compromised invoking host user     | No guarantee                                                                               | Already has access to credentials and Docker authority                                                   |
| Remote network attacker            | No ordinary published agent ports; runtime containment                                     | Services and authentication flows exposed intentionally must be qualified                                |
| Docker daemon/host root compromise | No guarantee                                                                               | Can replace images, inspect secrets, and access host state                                               |

### D3. Registry and state interfaces

Retain `lib/tools.sh` as the only tool registry. Shared code dispatches by declared capability/storage mechanics, never by harness name.

Change canonical auth records to host-only state:

- Exactly one `auth` record per harness.
- `class=auth`, `scope=auth-policy`.
- A new supported `kind=host` value.
- Empty container runtime mount target.
- Explicit default scope, adapter schema, native-member manifest, and compatibility contract.
- Existing non-auth records and production naming remain intact.

Provide a versioned JSON descriptor interface for Python, launchers, operational commands, captures, and native tests. Keep legacy read-only descriptor output for existing consumers during transition.

Descriptors include domain, namespace where applicable, harness, state class, scope, UID/GID, full physical project path, project hash, protected root, native coordinates, adapter/manifest version, and expected image contract.

A descriptor is not deletion authority by itself. Operations re-resolve it against validated context and record actual filesystem/volume identity before mutation.

### D4. Configuration contract

Preserve:

1. Per-harness runtime scope.
2. Common runtime scope.
3. Per-harness scope in selected state TOML.
4. Common TOML scope.
5. Registry default.

Continue using `BOX_AUTH_SCOPE`, `BOX_M/O/C_AUTH_SCOPE`, `BOX_STATE_CONFIG`, and `BOX_AUTH_ROOT`.

`BOX_C_AUTH` remains independent credential-source selection.

Validate every supplied value, including unselected harness overrides and shadowed settings. Reject empty values, unknown keys, wrong types, duplicate TOML declarations, incompatible schemas, unsafe paths, and conflicting aliases. Compare native-root aliases after validated physical normalization.

No project config may set Box state roots, scope, runtime, adapter, migration authority, or Docker endpoint.

Native project configuration remains native client input. Shell hooks, plugins, MCP commands, and provider modules execute only inside the container.

### D5. Canonical schema and authority

Use canonical envelope schema 2 and image auth contract 4 for the completed multi-member architecture.

The envelope contains:

- Schema version, harness, adapter schema, and native-manifest identifier.
- Monotonic nonnegative integer revision.
- Whole-identity tombstone.
- Auth payload separated into qualified semantic members.
- Explicit absence for missing members when other members remain authenticated.
- Credential identity information required by native serialization.
- No project trust, preferences, active selections, sessions, approvals, or transcripts.

Member names and native coordinates come from the qualified manifest, not credential contents. Unknown member/backend/schema is an integrity refusal.

Schema 1 is read-only migration input. Conversion creates a protected rollback copy and atomically publishes schema 2 only through an explicit operation. Older launchers/images are not allowed to mutate schema 2 state.

Canonical state is authoritative while idle. After successful projection and possible client execution, the native projection is authoritative for uncommitted changes. A host pending collection becomes authoritative once its export has been validated and durably published.

Do not reset an invalid revision to zero. Do not treat malformed state, parser failure, missing files, or failed Docker queries as empty authentication.

### D6. Process and filesystem boundaries

Use host-only stable locks beneath the protected state index. Do not place removable lock authority inside an agent-writable native home.

Lock order:

1. Installation/global lifecycle lock when needed.
2. Harness lifecycle locks in registry order.
3. Auth identity locks in sorted descriptor order.
4. Native-store locks in sorted descriptor order.

All operational lock acquisition is nonblocking. Busy failures release acquired descriptors and do not mutate native auth. Docker subprocesses must not inherit lock descriptors unintentionally.

Use descriptor-relative, no-follow filesystem operations for host control state. Reject symlinks, unexpected hardlinks, unsafe ancestry, foreign ownership, and invalid modes before reading, replacing, or removing members.

For selected projects, retain existing checks and add external-hardlink detection: count links to each regular-file inode within the mounted tree and reject when its link count exceeds the internal count. Permit multiple links entirely within the selected tree. Reject changed or unreadable scan results.

This is preflight hygiene against unintended exposure, not a guarantee against a privileged host concurrently replacing paths.

### D7. Native adaptation

**Muse:** Retain the global non-auth home and project data/state. Project provider and qualified MCP authentication as regular native files. Preserve actual pinned trust membership without inferring the filename from current documentation. Device/OAuth support is a blocking gate.

**Codex:** Retain project `CODEX_HOME` and separate SQLite state. Manage provider `auth.json` and the qualified MCP `.credentials.json` independently inside one canonical identity. Preserve native MCP locking directories as synchronization state. Keep unsupported PAT, agent identity, Bedrock, keyring, and encrypted auth sources explicit and source-preserving.

Pinned managed requirements enforce provider file storage. MCP file mode lacks an equivalent demonstrated requirement in the inspected source: use qualified launcher/client invocation policy and detect unsupported native stores before collection. Do not invent a requirements key.

**OpenCode:** Retain the project mixed DB. Auth export/install/scrub includes only qualified credential/account records. Keep provider selections per integration and account/org selection in project state, keyed by complete auth identity, including root changes. Require explicit native selection when multiple candidates are available without a valid remembered choice.

SQLite initialization belongs to the pinned native client. Envelope validation must be a pure operation and must not require constructing a native database.

### D8. Networking and callbacks

Preserve unrestricted outbound networking in the normal bridge mode. ICC disabled and no published ports do not establish a host/LAN/metadata-service denylist.

Do not introduce automatic host firewall changes, host networking, privileged proxies, Docker sockets, or broad callback port publication.

Login adapters may expose only pin-qualified callback routes, exclusively for an explicit authentication operation. Any necessary published endpoint binds host loopback, uses the manifest’s validated port/address behavior, fails on collision, and is removed with the exact login container. Device/manual flows remain preferred where supported.

Q02–Q05 must establish the exact callback requirements. If a required flow cannot satisfy this contract, its support remains a release-blocking decision gate; no guessed port mapping ships.

Restricted egress is a separate optional deployment design, not a claimed property of this release.

### D9. Security invariants

| ID  | Invariant                                     | Violation observation                                                                |
| --- | --------------------------------------------- | ------------------------------------------------------------------------------------ |
| V01 | No automatic runtime downgrade                | Failed runsc probes never create a runc agent/helper                                 |
| V02 | Nonzero UID/GID and bounded authority         | Host inspect plus neutral container identity/capability checks                       |
| V03 | No host engine socket or host namespace       | Complete mount/namespace inspection and negative access tests                        |
| V04 | Canonical/control state never exposed         | Agent/helper mount inventories; attempted access cannot reach sentinel control files |
| V05 | Only resolved mount coordinates               | Host inspect compared with complete expected descriptor set                          |
| V06 | Test/production separation                    | Instrumented reads/mounts/removals show no production coordinates                    |
| V07 | Auth publication is validated and durable     | Fault injection and abrupt interruption preserve old or committed valid revisions    |
| V08 | Recovery precedes reuse                       | Interrupted journal prevents new projection of stale canonical state                 |
| V09 | Auth scope does not change non-auth scope     | Two-project/global/project markers and table snapshots                               |
| V10 | Selection/trust is not globalized with auth   | Canonical payload exclusion and second-project observations                          |
| V11 | No unknown credential source silently ignored | Backend/member/schema mutants refuse and preserve bytes                              |
| V12 | Legacy credentials survive transition         | Source/rollback inventory survives every pre-completion boundary                     |
| V13 | Cleanup targets exact owned resources         | Foreign/transplanted/recreated objects remain intact                                 |
| V14 | No secrets in Box arguments/reporting         | Synthetic sentinel scan of argv, journals, dry-run, diagnostics and captures         |
| V15 | Resource ceilings apply to all runners        | Host cgroup/inspect observations for agents, probes, and helpers                     |
| V16 | Host parses project inputs only as data       | Filename/config injection fixtures cannot execute host commands                      |

NAME-only environment forwarding protects command text, not Docker inspection. Docker administrators can inspect supplied environment values; the agent can use native credentials. Document those exposures rather than claiming V14 eliminates them.

## E. Dependency-ordered implementation checklist

Every task below includes its objective, reason, current evidence, implementation surface, required behavior, dependencies, acceptance, verification, and compatibility implications.

### Evidence-backed completed substeps

The task checkboxes below represent the full acceptance criteria for each task.
These smaller implementation and verification steps are complete and linked to
their evidence; they do not close a dependent runtime, native, account, or
release gate.

- [x] **Q01 groundwork:** source inventory capture, transfer comparison, and
  drift/refusal regression coverage. The cross-environment transfer and
  qualification handoff remain open. See
  [Q01 progress](specs/implementation-progress.md#independent-q01-groundwork--source-baseline-capture-2026-10-08).
- [x] **Q05 provenance prerequisite:** Codex fixture requires explicit pinned
  binary/package inputs and verifies package and executable digests. Native
  MCP/account qualification remains open. See
  [qualification progress](specs/implementation-progress.md#continuation--native-qualification-prerequisites).
- [x] **C03 defect fix:** disposable Codex state override beneath its task root
  is accepted while production collisions and symlink escapes still refuse.
  Full descriptor consolidation remains open. See
  [implemented fixes](specs/implementation-progress.md#implemented-fixes).
- [x] **C04 Make transport:** operational selectors and native fixture paths,
  including Codex artifact inputs, travel as exported data rather than shell
  source. No-follow filesystem operations and hardlink checks remain open.
  See [implemented fixes](specs/implementation-progress.md#implemented-fixes)
  and [qualification prerequisites](specs/implementation-progress.md#continuation--native-qualification-prerequisites).
- [x] **R01 fail-closed implementation:** automatic runc selection was removed;
  explicit runtime flags, prohibitions, and offline diagnostic paths are
  covered by focused regressions. Native runtime/network qualification remains
  open. See [implemented fixes](specs/implementation-progress.md#implemented-fixes).
- [x] **T01 ShellCheck defect fix:** OpenCode trap callbacks have the required
  indirect-call annotations. Full final-tree static, Bats, and mutation
  coverage remains open. See
  [implemented fixes](specs/implementation-progress.md#implemented-fixes).
- [x] **Q06 local probe:** synthetic lock contention, SIGKILL release, exec
  descriptor inheritance, stable inode, fsynced replacement, and refusal/
  cleanup regressions pass on this host. Production recovery, power-loss,
  restart, exhaustion, and Docker failure qualification remain open. See
  [Q06 progress](specs/implementation-progress.md#q06-continuation--exec-descriptor-inheritance)
  and [initial observations](specs/implementation-progress.md#q06-continuation--bounded-host-filesystem-observations).

- [x] **C02 policy groundwork:** scope and source resolve from one validated
  snapshot; absent default-config ancestry, duplicate TOML, shadowed values,
  runtime/transition selectors and normalized Codex root aliases have refusal
  coverage. The unused optional getter is removed. Full C02 remains open.
- [x] **C04 filesystem groundwork:** descriptor-relative bounded control reads,
  atomic fsynced publication, stable close-on-exec locks and exact removals
  are implemented in `box/lib/host-fs.py`; reset/discovery consumers use them.
  Project preflight detects external hardlinks without reading file contents.
  Remaining canonical/native consumers and durability qualification stay open.
- [x] **A03 pure validation defect:** all adapters validate canonical envelopes
  without constructing native stores. OpenCode verification requires no SQLite
  connection and rejects unknown members, duplicate keys and invalid revisions.
  Contained mutation/schema/account qualification remains open.
- [x] **R02 override prerequisite:** explicit image tags must satisfy the same
  version, integrity, UID/GID and auth-contract checks as default tags.
  Immutable image identity, native probing and contract-4 cutover remain open.
- [x] **T01 controlled workflow prerequisite:** a manual default-branch workflow
  targets protected dedicated self-hosted amd64/arm64 runners. It clears production
  selectors, records attempted/not-reached gates and retains exact evidence.
  Actual workflow, runtime, dedicated-account and platform execution remain open.
- [x] **O01 deletion defect fix:** reset and full removal re-inspect a surviving
  volume immediately before deletion and compare its creation identity with the
  protected checkpoint. Synthetic replacement/malformed-authority regressions
  preserve the replacement and checkpoint. Actual Docker qualification and the
  broader state-management task remain open.

### Phase 0 — Freeze evidence and qualify foundational behavior

- [ ] **Q01 — Capture the implementation baseline and qualification harness**

  **Objective/reason:** Establish a reproducible starting snapshot without replacing the existing uncommitted work.

  **Evidence:** The checkout, six historical files, current static checks, and Codex synthetic observations are recorded above. Runtime evidence is unavailable locally.

  **Surface/behavior:** Record hashes/status of relevant source, generated files, configuration, workflow, and tests; record host architecture, UID/GID, parsers, Engine/runtime availability, and artifact provenance. Qualification uses fresh disposable homes/projects and exact cleanup coordinates. Do not include credential values or treat this plan as evidence.

  **Dependencies:** None.

  **Acceptance/verification:** A subsequent implementer can identify source drift before editing; baseline safe checks reproduce. Every unexecuted category remains explicitly unqualified.

  **Compatibility/rollback:** Preserve all existing changes and historical evidence. Qualification creates no production state.

- [ ] **Q02 — Qualify runtime, platform, networking, and callback compatibility**

  **Objective/reason:** Prove the supported runsc boundary and required native network workflows before removing automatic fallback.

  **Evidence:** Source defaults to runsc but automatically selects runc on failures. Retained runtime evidence reports external DNS/HTTPS failures under runsc.

  **Surface/behavior:** Exercise isolated Make-built images under explicit runsc and runc. Record Engine/runsc versions, configured runtime arguments/platform, cgroup mode, storage driver, DNS/VPN configuration, IPv4/IPv6, host gateway/LAN/metadata routes, ICC behavior, and callback requirements. Diagnose transport failure without changing isolation. Establish approved callback manifest entries from actual native behavior.

  **Dependencies:** Q01.

  **Acceptance/verification:** Startup, DNS, HTTPS, login transport, and neutral containment checks pass for each supported pair. Registration/startup/DNS/timeout failures are distinguishable. Required callback flows work with loopback-only exposure or a verified device/manual flow.

  **Compatibility/rollback:** Do not claim every Engine ≥25 combination is supported. No host runc removal or automatic host-wide networking changes.

- [ ] **Q03 — Qualify the complete pinned Muse credential and trust contract**

  **Objective/reason:** Preserve advertised device login, refresh, logout, and MCP behavior instead of shipping an API-key-only migration.

  **Evidence:** The current adapter accepts a narrow API-key schema. A fixture exists, but Muse is unavailable here. Trust filename and MCP membership remain unresolved.

  **Surface/behavior:** Extend the Muse fixture and native guide evidence using the SHA256-verified pinned artifact. Inventory files and relevant records before/after API login, device login, refresh, logout, MCP login/logout, native selection, and interrupted writes. Separate trust, settings, sessions, selection, and credentials. Record empty representations, replacement/unlink behavior, backend switches, and writable refresh requirements.

  **Dependencies:** Q01.

  **Acceptance/verification:** Publish an exact native-member/schema manifest and source-preserving unsupported cases. Dedicated disposable account tests establish device/OAuth formats and MCP membership. Unknown backends cannot pass as empty auth.

  **Compatibility/rollback:** **Blocks Muse behavioral cutover.** Do not rename or delete either trust candidate speculatively.

- [ ] **Q04 — Qualify pinned OpenCode schema, selection, importer, and service behavior**

  **Objective/reason:** Establish safe auth-only operations on its mixed database.

  **Evidence:** Upstream credential/account schemas were verified. Current adapters handle their columns, but native service/bootstrap/account qualification is unavailable.

  **Surface/behavior:** Use the verified archive/binary to create databases natively. Record migrations, tables, columns, constraints, indexes, relevant triggers/views, reverse foreign keys, WAL/SHM behavior, and legacy import paths. Exercise native key/OAuth/MCP creation, account/org selection, switching, logout, service detach/restart, and account/control-account migration.

  **Dependencies:** Q01.

  **Acceptance/verification:** Freeze a native schema fingerprint and allowed payload/member contract. Auth transformations preserve unrelated logical table contents. Native services are reliably quiesced. Changed endpoint identity does not reuse unrelated MCP tokens.

  **Compatibility/rollback:** **Blocks OpenCode mutation cutover.** Unknown schema or legacy v1 conversion remains refused with source retained.

- [ ] **Q05 — Qualify pinned Codex provider, MCP, and alternate-backend behavior**

  **Objective/reason:** Extend proven provider mechanics to complete supported auth scope without globalizing other home state.

  **Evidence:** Fresh provider synthetic fixture passed; pinned source establishes `.credentials.json`, aggregate MCP locks, and additional auth backends. Artifact provenance and MCP native behavior remain unverified.

  **Surface/behavior:** Require explicit verified binary/package inputs in the Codex fixture. Qualify provider serialization, native logout, MCP file storage, issuer/endpoint/client binding, refresh locks, empty maps, unlink/replacement, and callback settings. Inventory encrypted/keyring/gateway/PAT/agent/Bedrock sources and classify them as supported managed, independently managed, or unsupported.

  **Dependencies:** Q01.

  **Acceptance/verification:** Publish exact provider/MCP manifests; native file mode survives supported overrides and directory config. Unsupported sources produce explicit preservation/refusal. Local refresh-shaped tests are separately labeled from real rotation.

  **Compatibility/rollback:** **Blocks expanded Codex auth cutover.** Retain current on-request/user-reviewer/file-store/SQLite requirements.

- [ ] **Q06 — Qualify host locking, filesystem durability, and abrupt failure semantics**

  **Objective/reason:** Prevent token loss through optimistic lock, rename, or crash assumptions.

  **Evidence:** Source contains fsync and stable-lock work; mocked boundary tests do not establish real SIGKILL/power-loss behavior.

  **Surface/behavior:** On isolated supported local filesystems, exercise lock inode continuity, descriptor inheritance, concurrent acquisition, atomic replacement, directory fsync, disk-full/inode-full conditions, host-supervisor SIGKILL, Docker client loss, daemon unavailability, and VM restart. Use bounded disposable fixtures.

  **Dependencies:** Q01.

  **Acceptance/verification:** Each acknowledged transaction is recoverable as a valid committed revision or a preserved incomplete operation; no stale projection can proceed. Unsupported network filesystems and volume drivers fail explicitly.

  **Compatibility/rollback:** **Blocks durability acceptance.** Never manufacture logout from a missing projection after abrupt failure.

### Phase 1 — Shared contracts and state foundations

- [ ] **C01 — Freeze the registry, threat model, and compatibility contract**

  **Objective/reason:** Give every consumer one enforceable architecture.

  **Evidence:** Registry contracts already exist, but auth records require a writable container bind and contract 3.

  **Surface/behavior:** Extend `tools.sh` validation for host-only canonical auth, native-member manifests, adapter schema 2, and image contract 4. Keep exactly one auth record, canonical `/persist`, existing artifact roles, and non-auth state records. Declare native helper/selection/callback capabilities as bounded data.

  **Dependencies:** Q01.

  **Acceptance/verification:** Registry mutants fail for missing/duplicate auth, orphan fields, unsupported storage mechanics, escaping manifest sources, incompatible adapter fields, and incomplete consumers. No shared harness-name branches.

  **Compatibility/rollback:** Contract 3 is historical compatibility input, not a valid contract for new cutover.

- [ ] **C02 — Consolidate strict policy parsing and invocation validation**

  **Objective/reason:** Resolve policy once and reject invalid settings before side effects.

  **Evidence:** Scope validation is substantially implemented; optional getter is unused, and implicit/default ancestry and other supplied selectors need uniform treatment.

  **Surface/behavior:** Consolidate `auth.sh` and `config-file.sh` policy validation. Validate all scope/runtime/root/config/transition/helper selectors. Normalize root aliases before comparison. Return effective policy plus source metadata from one result. Remove unused optional getter and sentinel/no-op remnants.

  **Dependencies:** C01.

  **Acceptance/verification:** Exhaustive precedence tests, duplicate TOML, empty tables, booleans/floats as schema, shadowed invalid values, unsafe default ancestors, and missing parser cases fail or inherit exactly as D4 specifies. No partial output is interpreted as success.

  **Compatibility/rollback:** Keep policy schema 1 and existing environment names; setup continues preserving the policy file.

- [ ] **C03 — Make descriptors authoritative across production and disposable workflows**

  **Objective/reason:** Eliminate independent launch/migration/reset formulas and repair disposable Codex execution.

  **Evidence:** Formula primitives exist, but call sequences are duplicated. A valid test Codex override was rejected during this audit.

  **Surface/behavior:** Refactor `state.sh`, `test-state.sh`, launcher adapters, operational commands, capture, and Python native consumers to use a complete context/descriptor result. Capture production roots before test overrides, then dispatch test state before any production discovery. Preserve default test formulas and project-qualified fixtures. Include root changes in auth identity/selection keys.

  **Dependencies:** C01, C02.

  **Acceptance/verification:** Aliases share identity; physical moves do not; UID/harness/namespace separate identities; GID changes preserve auth. Two projects in one namespace have independent native state and share only test-global auth. Missing/empty test selectors never reach production. Collision fixtures refuse.

  **Compatibility/rollback:** Preserve production names and legacy read-only descriptor output. Historical removed-project descriptors remain explicit inputs.

- [ ] **C04 — Secure host filesystem operations and Make argument transport**

  **Objective/reason:** Prevent agent-controlled data from redirecting host writes or becoming host shell code.

  **Evidence:** Existing guards are check/use operations; generated Make recipes interpolate input inside shell quotes. Project hardlinks are not currently inventoried.

  **Surface/behavior:** Add a shared Python no-follow filesystem primitive for control files, locks, atomic publication, and exact removal. Use opened directory descriptors, validate type/owner/mode/link count, and bound reads. Add external-hardlink project detection and NUL-safe scans. Export Make inputs as data and reference shell variables without injecting values into recipe code. Use privileged Bash mode consistently for supported entrypoints and nested host invocation.

  **Dependencies:** C03.

  **Acceptance/verification:** Backticks, dollar expressions, spaces, quotes, glob characters, control characters, hostile Python modules, symlinks, shared inodes, parent swaps, and special files cannot execute host code or alter foreign sentinels. Paths with legitimate spaces work.

  **Compatibility/rollback:** Diagnose unsupported hardlinked project layouts and recommend independent copies/`--no-hardlinks`. Do not claim protection against an already compromised host user.

- [ ] **C05 — Implement a host-only canonical store and transaction authority**

  **Objective/reason:** Remove canonical credential/control authority from agent-writable mounts.

  **Evidence:** Current publication exists in host `auth.sh`, shared supervisor, and OpenCode volume helper.

  **Surface/behavior:** Introduce `lib/auth-store.py` as the sole implementation of schema validation, revision publication, pending collection, identity metadata, and durable journals. Shell helpers delegate to it. Canonical directories/files are 700/600, user-owned, and unmounted. Use random private staging, file/directory fsync, exact revisions, bounded JSON, and explicit member absence.

  **Dependencies:** C01, C04.

  **Acceptance/verification:** Invalid canonical files are preserved; no revision defaults on corruption; competing writers cannot publish; agent payloads cannot choose host paths, revisions, journal stages, adapters, or deletion targets. Synthetic sentinel credentials do not appear in control metadata.

  **Compatibility/rollback:** Schema 1 is accepted only for explicit migration. Retain protected pre-conversion copies.

### Phase 2 — Locks and native adapters

- [ ] **L01 — Implement one host lock protocol for all lifecycle operations**

  **Objective/reason:** Serialize token mutation and native-store reuse without removable inode races or cross-runtime lock handoff.

  **Evidence:** Stable external auth locks exist, but native locks can live in agent-writable homes and orchestration has several paths.

  **Surface/behavior:** Implement the D6 lock hierarchy in the host lifecycle layer. Launch/login/logout/shell/copy/migration/recovery/reset/removal/install use the same stable identities. Native locks live outside projections. Use close-on-exec descriptors; acquire full lock sets before mutation; release on every refusal.

  **Dependencies:** C03, C04, C05, Q06.

  **Acceptance/verification:** Contenders fail promptly; opposite-direction copies cannot deadlock; root/scope changes do not bypass native-store locks; deleting/recreating objects does not create a second lock authority. Host death releases locks but leaves recovery ownership.

  **Compatibility/rollback:** Global auth serializes projects. Muse also serializes its shared native home even with project auth. Native MCP locks remain intact.

- [ ] **A01 — Implement the qualified Muse multi-member adapter**

  **Objective/reason:** Support the pinned authenticated workflows while preserving global non-auth state.

  **Evidence:** Existing regular-file API adapter and projection mechanics are reusable; OAuth/MCP qualification is incomplete.

  **Surface/behavior:** Implement pure envelope validation, manifest member discovery, install, export, scrub, and legacy retirement in the Muse adapter. Cover the Q03 provider/MCP members, empty representations, regular replacement/unlink, and selection classification. Keep settings snapshots, trust, sessions, and preference backups outside auth export.

  **Dependencies:** C05, Q03.

  **Acceptance/verification:** Qualified API/device/MCP login and logout round-trip; unknown shapes preserve native/canonical bytes; deleting provider auth does not erase MCP auth or trust; interrupted writes require recovery.

  **Compatibility/rollback:** No globalizing of data/state; no speculative trust rename; unsupported backends remain recoverable.

- [ ] **A02 — Implement qualified Codex provider and MCP members**

  **Objective/reason:** Apply auth scope to both supported provider and MCP credentials.

  **Evidence:** Provider mechanics passed; pinned MCP file/lock implementation is known upstream.

  **Surface/behavior:** Extend the Codex adapter to the Q05 members. Preserve issuer/client/URL binding and native lock state. Keep provider file requirements and apply the qualified MCP invocation policy. Detect recognized unsupported stores before projection/collection. Do not move project trust, sessions, history, encrypted general-purpose secrets, or SQLite state.

  **Dependencies:** C05, Q05.

  **Acceptance/verification:** Provider-only logout, MCP-only logout, partial member absence, API mode, synthetic OAuth loading, native MCP rotation, and scope transitions behave correctly. Unsupported backend creation cannot result in a successful incomplete collection.

  **Compatibility/rollback:** Additional upstream auth modes stay explicitly unsupported until qualified; source data remains intact.

- [ ] **A03 — Implement contained OpenCode projection and pure envelope validation**

  **Objective/reason:** Make copy/recovery usable and protect the host from parsing agent-modified SQLite.

  **Evidence:** Current envelope verification requires a nonexistent DB; raw `DB_PATH` can invoke host SQLite; column checks omit a complete trigger contract.

  **Surface/behavior:** Split pure envelope validation from native DB validation. Run all native DB work through the pinned contained helper, with network disabled, extension loading disabled, qualified trusted-schema behavior, schema/trigger/FK checks, bounded time/storage, and parameterized SQL. Retain credential/account IDs and metadata. Save/restore per-integration and account/org selection separately; require an explicit choice for ambiguity. Initialize schema through a bounded native client invocation.

  **Dependencies:** C05, Q04.

  **Acceptance/verification:** Canonical copy validates without a database. Install/export/scrub preserve unrelated logical records, WAL consistency, and selection. Trigger/schema/payload mutants fail before source mutation. Account-only auth triggers migration detection. No host SQLite open occurs.

  **Compatibility/rollback:** Preserve the mixed project DB and v2 paths. Unknown v1/schema inputs are refused. Snapshot imports do not falsely authorize retirement of another live source.

### Phase 3 — Runtime and container lifecycle integration

- [ ] **R01 — Replace automatic fallback with explicit runtime policy**

  **Objective/reason:** Make runsc failure fail closed.

  **Evidence:** `box_auto_runtime` currently downgrades on DNS, startup, and timeout errors.

  **Surface/behavior:** Replace automatic selection in launcher/run helpers. Classify diagnostics without changing runtime. Retain explicit flags and fallback prohibition; validate flags/settings before state access. Apply bounded probes only where network health is required, preserving offline diagnostics.

  **Dependencies:** C02, Q02.

  **Acceptance/verification:** For probe returns 1, 2, 124, 125, signal exits, malformed output, and missing runtime, no runc agent starts. Explicit runc works only when permitted. Shell/help/version/status/logout remain appropriately usable offline.

  **Compatibility/rollback:** This is an intentional default behavior change. Rollback must not restore automatic downgrade.

- [ ] **R02 — Enforce immutable image and native adapter compatibility**

  **Objective/reason:** Reject incompatible images before credential access.

  **Evidence:** Current contract-3 labels are enforced, but overrides skip pin checks and label checks occur after some mutations.

  **Surface/behavior:** Validate Engine, Linux/architecture, user, harness, contract 4, native version, adapter schema and manifest before production auth access. Resolve and reuse immutable image IDs. Overrides must satisfy the same native contract. Update Dockerfile, build/pin/sync helpers, generators and context tests. Pin the Dockerfile frontend after verified resolution; validate Codex archive structure before extraction; record local package provenance.

  **Dependencies:** C01, Q02, Q03, Q04, Q05.

  **Acceptance/verification:** Old, mislabeled, wrong-user, wrong-harness, wrong-version, wrong-manifest, retagged, and incompatible override images fail before native mutation. Actual context inventory excludes non-input files. Make remains the build interface.

  **Compatibility/rollback:** Older images require rebuild. Keep local-only image handling; never push/save/export Muse-containing images. Labels are compatibility evidence, not protection from Docker administrators.

- [ ] **R03 — Implement durable exact-ID host lifecycle supervision**

  **Objective/reason:** Own every reserve/create/start/stop transition and preserve recovery evidence.

  **Evidence:** Current agent path is `docker run --rm` with mount-filter liveness queries.

  **Surface/behavior:** Introduce `lib/auth-lifecycle.py` for Docker subprocess ownership. Validate prerequisites, acquire locks, reserve, `docker create`, record exact CID, prepare projections, record start intent, and `docker start --attach`. Track helper CIDs too. Inspect actual runtime/image/mounts before execution. Retain stopped containers until collection or preserved recovery state. Never infer ownership from a loose name prefix.

  **Dependencies:** L01, R01, R02.

  **Acceptance/verification:** Fault injection at every boundary yields an owned, recoverable state. Create succeeded but CID publication interrupted can be reconciled by exact transaction labels plus full inspect. Failed daemon queries preserve state. No unrelated container is stopped/removed.

  **Compatibility/rollback:** Preserve stdin, TTY detection, working directory, native arguments and exit status. New journals block old lifecycle assumptions.

- [ ] **R04 — Integrate all launch/auth/shell paths with process supervision**

  **Objective/reason:** Prevent detached native processes from writing during collection and eliminate competing wrappers.

  **Evidence:** OpenCode has a process wrapper; Muse/Codex rely on host traps around different entrypoints.

  **Surface/behavior:** Route all launch adapters and `box-m-login` through R03. Refactor container supervisor to run/reap/terminate processes only; remove canonical writes and `/run/box-auth` mounts. Put clients/shells in managed process groups; terminate remaining container-local agent/service processes before successful completion. Preserve native serve lifetime, Muse bypass rules, provider translation, Codex API/device modes and OpenCode shell hygiene. Implement only Q-qualified callback routes.

  **Dependencies:** R03, A01, A02, A03.

  **Acceptance/verification:** Ordinary, noninteractive, auth, shell, serve, wrapper-only signals, process-group signals, TERM-resistant children and detached services leave no concurrent native writer when collection begins. Callback listeners close with the exact auth container.

  **Compatibility/rollback:** Preserve 129/130/143 signal behavior where established. Shell-created native auth remains managed. No Docker socket or extra capability is introduced.

- [ ] **L02 — Implement collection, scrub, and recovery as one host state machine**

  **Objective/reason:** Prevent stale replay, ambiguous logout, and partial collection from losing tokens.

  **Evidence:** Current host/container/volume collection paths duplicate publication and recovery logic.

  **Surface/behavior:** Consolidate into C05/R03. After confirmed stop, export into private bounded staging, validate, publish pending collection with expected base revision and transaction ID, publish canonical, scrub, then complete. Resume each durable phase idempotently. Treat clean native logout as absence; abrupt missing/corrupt projection without a validated pending export is an integrity gate. Preparation interrupted before execution may be retried only from its recorded unchanged canonical revision.

  **Dependencies:** R04, Q06.

  **Acceptance/verification:** Crashes before/after export/publication/scrub/idle preserve authority. Refresh is not reverted; logout is not resurrected; failed scrub blocks reuse. Active or uninspectable CIDs cannot be collected. Recovery uses the recorded original native context after move/GID/root changes.

  **Compatibility/rollback:** Remove unused pseudo-recovery/run wrappers. Never restore old tokens merely because the projection cannot be read.

### Phase 4 — Migration and state-management operations

- [ ] **M01 — Implement exact legacy discovery and source-specific adoption gates**

  **Objective/reason:** Prevent one destination marker from authorizing overwrite of another legacy source.

  **Evidence:** Current gate uses destination marker/nonempty canonical status; OpenCode checks only its credential row count.

  **Surface/behavior:** Resolve all Q-qualified provider/MCP/account/importer members for the selected native descriptor. Store adoption records per exact source and destination, with schema/image compatibility and observed source identity. Detect new importer files after migration. Discover historical roots through explicit descriptors and revalidated indexes. Raw DB snapshots are processed only in contained helpers and do not authorize live-volume retirement.

  **Dependencies:** C03, C04, A01, A02, A03, L01.

  **Acceptance/verification:** Nonempty, empty, account-only, MCP-only, new legacy source, unknown format, missing source and transplanted adoption cases distinguish correctly. Dry-run lists coordinates and metadata without DB/credential reads.

  **Compatibility/rollback:** No automatic host-native home search, newest-project selection, or v1 conversion. Keep legacy sources until explicit migration or fresh initialization handles them.

- [ ] **M02 — Implement safe migrate/copy/init/scope transitions**

  **Objective/reason:** Preserve credentials through all supported operator choices.

  **Evidence:** Operations exist, but fresh init lacks source preservation and OpenCode copy validation is defective.

  **Surface/behavior:** Preserve Make entrypoints and use authoritative descriptors. Validate source/destination and complete lock sets before mutation. Export/validate source; reject differing nonempty destinations; accept identical payloads without merging. Fresh init requires an empty canonical destination and quarantines supported legacy auth into protected rollback storage before projection can erase it. Scope changes require `fresh`, `use-existing`, or explicit copy acknowledgment for one project. Record source-specific adoption only after verification.

  **Dependencies:** M01, L02.

  **Acceptance/verification:** Both scope directions, absent/identical/conflicting destinations, logout tombstones, custom roots, unsupported stores and multi-source conflicts preserve unselected sources. Copy never populates all projects or claims independent OAuth lineage.

  **Compatibility/rollback:** Keep external provider files independently managed. Preserve original schema/native representations for rollback.

- [ ] **M03 — Complete migration journals and credential-preserving rollback**

  **Objective/reason:** Make interruption and downgrade recoverable without destructive guessing.

  **Evidence:** Current migration journals exist, but publication/retirement behavior and raw/contained paths differ.

  **Surface/behavior:** Use one durable journal format with exact descriptors, transaction ID, base/destination revisions, compatibility versions, staged artifact identities and rollback coordinates. Implement planned, staged, committed, verified, retired and complete phases. File retirement preserves raw native bytes; SQLite retirement preserves auth-only export and selection while retaining mixed state. Rollback restores only stopped, verified exact targets; changed destinations require refusal.

  **Dependencies:** M02.

  **Acceptance/verification:** Interruption before/after each publication/retirement boundary is idempotently recoverable. Disk-full, unknown journal version, changed source/destination, concurrent transaction and unsupported downgrade retain recoverable data. Completed logout is never automatically overwritten by a legacy copy.

  **Compatibility/rollback:** Old clients must be stopped at cutover. Host users can deliberately bypass wrappers; document that unsupported action rather than claiming enforcement against Docker administrators.

- [ ] **O01 — Unify reset, removal, discovery, and code-only uninstall authorization**

  **Objective/reason:** Preserve the substantial existing removal work while integrating new descriptors, journals and installation layout.

  **Evidence:** Current code supports historical roots, exact members, reset checkpoints and full removal, with synthetic coverage.

  **Surface/behavior:** Route all operations through C03/L01/L02/M03. Default project reset removes project non-auth state and explicitly inventoried project auth across acknowledged roots; global auth remains. `KEEP_AUTH=1` retains project auth. Full removal inventories both scopes, historical roots/projects/GIDs, backups, retired members, selection/bindings, templates/pins/CLI backups and optional code/provider targets. Retain stable locks outside removed objects. Compare volume creation fingerprints before deletion.

  **Dependencies:** M03, C03, L01.

  **Acceptance/verification:** Active/unrecovered dependencies refuse. Whole-operation checkpoints survive member/home/volume/auth/metadata deletion. Recreated or changed resources are not removed. Unknown files remain and cause explicit refusal. Previews perform no secret reads or writes.

  **Compatibility/rollback:** Provider files require explicit selection; disclose that deleting the shared file affects other harnesses. Images/networks/build cache remain separate operator resources.

- [ ] **O02 — Add bounded diagnostics and owned-resource recovery**

  **Objective/reason:** Improve OOM/crash/orphan diagnosis without pretending per-session limits bound host capacity.

  **Evidence:** Current `--rm` loses exit/OOM evidence; probes are bounded; aggregate storage and concurrency are unbounded.

  **Surface/behavior:** Inspect exit/OOM/runtime state before exact removal. Produce non-secret diagnostics and exact recovery coordinates. Retain failed collection resources; report cleanup failure visibly. Apply consistent CPU/RAM/PID ceilings and core-dump suppression to agents/probes/helpers; give helpers bounded descriptors/time/storage. Specify a compatible bounded logging driver for sessions and no persistent Docker logs for credential-processing helpers. Preserve executable scratch and document large-build/cache placement.

  **Dependencies:** R03, L02.

  **Acceptance/verification:** OOM differs from cancellation/native failure; helper timeout and daemon failure cannot report success. Reduced-limit workload tests preserve remaining source checksums. Orphan recovery targets only recorded resources.

  **Compatibility/rollback:** No automatic volume expiry, global prune, unqualified scratch relocation, aggregate quota, or host firewall change.

### Phase 5 — Installation, updates, and atomic cutover

- [ ] **I01 — Install immutable code generations with atomic selection**

  **Objective/reason:** Prevent setup/launch interruption from mixing wrapper and adapter contracts.

  **Evidence:** Setup currently installs files individually and serializes only other setup runs.

  **Surface/behavior:** Stage a complete protected generation under `~/.local/lib/box/releases/<generation-id>`, validate its manifest and checks, then atomically select it through a protected `current` link. Stable public dispatchers resolve one generation once and execute its privileged-mode wrappers. Preserve config/state/default selection. Coordinate installation with lifecycle locks and journals. Retain previous generations while active/recovery/rollback references exist.

  **Dependencies:** C03, C04, R02, L01.

  **Acceptance/verification:** Failure or interruption before selection leaves the old complete package active; after selection the new complete package is active. Installed operation works without the checkout. Concurrent setup/update/launch cannot mix files. Unknown installed files are preserved.

  **Compatibility/rollback:** One-time migration inventories old `~/.local/bin/lib` and harness files. Code-only uninstall removes registered dispatchers and unreferenced generations, preserving shared generations needed by other harnesses.

- [ ] **I02 — Gate pin updates and image synchronization on adapter compatibility**

  **Objective/reason:** Stop a client upgrade from silently mutating state through an unqualified adapter.

  **Evidence:** Existing updater locks its bundle and validates pin/generated consistency, but native acceptance is not an activation prerequisite.

  **Surface/behavior:** Add qualification-manifest compatibility checks to update/sync/setup activation. Stage pin consumers and generation metadata durably; build through Make; validate actual native versions and image IDs; activate installed pins/code only when the corresponding adapter contract is qualified. Interrupted updates resume or restore the recorded prior generation. `--check` remains read-only.

  **Dependencies:** I01, M03, R02.

  **Acceptance/verification:** Concurrent updater, generation failure, build failure, SIGKILL and installed-pin mismatch cannot expose a mixed active contract. Unknown client versions refuse before production auth access. Same-version digest changes require renewed provenance checks.

  **Compatibility/rollback:** Preserve differing installed pins during setup. Retain previous images and generations for explicit rollback; no automatic source-schema downgrade.

### Phase 6 — Verification and documentation

- [ ] **T01 — Complete static, Bats, and mutation-based regression coverage**

  **Objective/reason:** Verify actual host behavior and rejection atomicity instead of function/flag presence.

  **Evidence:** Static subset passed; Bats/ShellCheck unavailable here; 532 cases are declared.

  **Surface/behavior:** Update auth/state/runtime/removal/setup/update/capture/native-wrapper suites and fixtures. Clear all ambient `BOX_*` auth/runtime/transition/helper selectors deliberately. Remove tests for dead helper APIs. Add mutants for unmounted canonical state, test-root classification, pure OpenCode validation, Make filename transport, source-specific adoption, fresh-init backup, image compatibility and journal corruption.

  **Dependencies:** O01, O02, I02.

  **Acceptance/verification:** `make -C box verify-static`, `pins`, and generated checks pass on the exact implementation tree. Invalid inputs preserve source bytes, modes, timestamps and foreign sentinels. Secret sentinel tests inspect actual subprocess arguments/output.

  **Compatibility/rollback:** Keep generated edits in partials and regenerate with prescribed tools; do not hand-edit outputs.

- [ ] **T02 — Execute installed native, scope, concurrency, and recovery workflows**

  **Objective/reason:** Qualify the complete integrated lifecycle through public installed entrypoints.

  **Evidence:** Drivers exist but are unexecuted against the current tree; the disposable Codex guard defect is reproduced.

  **Surface/behavior:** Extend native acceptance/lifecycle/auth drivers to three harnesses × two scopes × two explicit runtimes. Use project-qualified native stores in one namespace for global-sharing cases and separate namespaces for isolation negatives. Exercise clean exits, signals, detached services, reservation/start crashes, failed cleanup, transitions, migration conflicts, reset, full removal, setup rerun and checkout-independent execution.

  **Dependencies:** T01, R04, L02, M03.

  **Acceptance/verification:** Every required boundary is actually reached and observed. Foreign/production state remains untouched. Account-independent success is reported separately from missing account gates. Capture never mounts parent/production auth.

  **Compatibility/rollback:** No production credential import to make tests pass. Cleanup failure is a failed test.

- [ ] **T03 — Qualify dedicated-account authentication, refresh, selection, and resume**

  **Objective/reason:** Prove real native auth behavior that synthetic fixtures cannot establish.

  **Evidence:** No real account behavior was executed in this audit.

  **Surface/behavior:** Opt-in dedicated disposable test accounts log in directly into test state. Exercise supported API/device/browser flows, provider/MCP login, refresh/rotation, account selection, partial/full logout, model turn, session restart/resume, and interrupted refresh under each supported scope/runtime. Evidence records versions and outcomes without token/account details.

  **Dependencies:** T02, Q03, Q04, Q05.

  **Acceptance/verification:** Authentication and selection survive expected reuse; project auth isolates; global auth shares credentials without sharing project trust/sessions. Logout remains logged out. Rotation either survives recovery or stops with preserved evidence and a documented re-login requirement.

  **Compatibility/rollback:** **Release gate.** Provider/account policy restrictions are not converted into unit passes or silently waived.

- [ ] **T04 — Qualify actual containment, platforms, networks, and resource effects**

  **Objective/reason:** Verify effective behavior separately from mocked argument construction.

  **Evidence:** Current Docker/runsc observations are unavailable; retained evidence belongs to older trees.

  **Surface/behavior:** On supported amd64 and arm64 environments, inspect runtime/image/user/groups/mounts/namespaces/resources from the host and run neutral in-container probes. Test rootfs writes, unrelated host sentinels, canonical absence, socket absence, recursive/propagation behavior, safe privilege negatives, cgroups, IPv4/IPv6, ICC, callback exposure, and bounded workloads. Record LSM/seccomp meaning for each runtime.

  **Dependencies:** T02, Q02, Q06.

  **Acceptance/verification:** V01–V16 have observed positive and negative results. Missing fields are failures, not implicit zeroes. runc bounding capabilities must be empty; any runsc reporting tolerance is narrowly justified and does not waive effective/permitted/ambient capability checks.

  **Compatibility/rollback:** No destructive host experiments. Each supported architecture/runtime pair needs its own evidence.

- [ ] **D01 — Rewrite the operational documentation and evidence record coherently**

  **Objective/reason:** Replace conflicting historical claims with the selected architecture and measured support.

  **Evidence:** Architecture/acceptance/security docs contain stale identity, contract, implementation-status and qualification language.

  **Surface/behavior:** Update README, architecture, operations, upgrades, troubleshooting, security/resource audit, acceptance, adding-a-tool, harness index/guides, Make/launcher/login help and generated-verifier descriptions. Document host-only canonical state, scopes, serialization, unsupported backends, callbacks, external keys, all lifecycle commands, migration/rollback, install generations, resource limits and accepted network/trust risks.

  **Dependencies:** T01.

  **Acceptance/verification:** Every command example uses the correct installed/source interface and resolver output. Evidence distinguishes static, mocks, native storage, actual runtime, account, architecture and CI results. Historical findings remain labeled by baseline; no contradictory “complete” claims survive.

  **Compatibility/rollback:** Do not rewrite historical `specs` inputs. Document explicit runc intent and unsupported downgrade behavior.

### Phase 7 — Rollout and final acceptance

- [ ] **Z01 — Execute a staged, reversible rollout**

  **Objective/reason:** Separate additive groundwork from credential-changing activation.

  **Evidence:** The current uncommitted work enables managed behavior before all native/runtime gates are qualified.

  **Surface/behavior:** Follow section F: qualify, ship additive inspection/interfaces, stage compatible code/images, stop old clients, explicitly migrate/init, verify adoption, then activate managed launches. Use per-harness checkpoints and retain source/rollback copies. Any failed qualification prevents activation for that harness; it does not choose a weaker runtime.

  **Dependencies:** T03, T04, D01, I02.

  **Acceptance/verification:** Existing installations and projects complete upgrade/restart/reset/recovery and explicit rollback using documented commands. Interrupted rollout resumes from its journal. Old image/code combinations refuse before credential mutation.

  **Compatibility/rollback:** No intermediate stage exposes canonical control state, automatically weakens isolation, deletes legacy credentials, or enables dual writers.

- [ ] **Z02 — Perform the final independent coverage and acceptance audit**

  **Objective/reason:** Establish completion across source, behavior, documentation and operations.

  **Evidence:** This proposal has 34 unique task IDs; its dependency graph was checked for missing/forward dependencies and cycles.

  **Surface/behavior:** Reaudit the implemented tree and final planning/evidence artifacts against sections C, D9, G and I. Check all source requirements, active call paths, authority transitions, install surfaces, native members, generated outputs, cleanup ownership, release matrices and residual-risk statements. Record exact source hashes and unresolved results.

  **Dependencies:** Z01.

  **Acceptance/verification:** Every task has evidence; every significant requirement has a disposition; no incompatible authority or unowned failure path remains. Full checks and required native/account/platform/CI gates pass for every advertised combination.

  **Compatibility/rollback:** Do not mark completion based on budget, source presence, skipped gates, or historical passes.

## F. Migration, rollout, and rollback plan

### F1. Additive groundwork

First ship descriptor/configuration inspection, compatibility manifests, qualification fixtures, and protected discovery metadata.

During this stage:

- Existing auth is not moved.
- Setup preserves provider files, policy, live state and differing installed pins.
- New migration commands remain unavailable for unqualified adapters.
- No automatic scope change or credential import occurs.
- Fail-closed runtime policy can ship independently once Q02 confirms its supported workflows and diagnostics.

### F2. Atomic behavioral cutover

The following must activate together for a harness:

- Host-only canonical schema and publication.
- Native-member adapter and compatibility manifest.
- Image contract 4.
- Exact-ID lifecycle supervision.
- Source-specific migration/adoption gate.
- Collection/scrub/recovery.
- Installed generation selecting the corresponding code and image contract.

Do not activate a new launcher with an older image or a new projection adapter with old recovery semantics.

Before activation:

1. Inventory exact native/canonical sources and pending operations.
2. Stop old clients and services.
3. Acquire lifecycle/auth/native locks.
4. Stage protected credential-preserving rollback artifacts.
5. Verify source schemas and destination compatibility.
6. Publish migration/conversion transaction state.
7. Verify the canonical result and native projection privately.
8. Retire only the authorized old importer/auth members.
9. Publish completed source adoption.
10. Activate the compatible code generation and installed pins.

### F3. Existing canonical schema 1

Handle schema 1 as explicit migration input:

- Provider payloads retain their native meaning.
- Adding MCP support does not imply that previously unmanaged MCP auth is absent.
- Resolve all qualified native members before conversion.
- Refuse conflicting canonical/native credentials.
- Preserve schema-1 bytes and original native representations.
- Publish schema 2 atomically after validation.
- Record missing versus intentionally logged-out member state.
- Do not convert by opening and rewriting arbitrary payloads during launch.

### F4. Scope transitions

| Transition                | Required behavior                                                                             |
| ------------------------- | --------------------------------------------------------------------------------------------- |
| Project → existing global | Explicit acknowledgment; preserve project source                                              |
| Project → absent global   | Fresh login or copy one named source; no project enumeration/merge                            |
| Global → existing project | Explicit acknowledgment; reject conflicting copy                                              |
| Global → absent project   | Fresh login or copy to that project only                                                      |
| Root change               | Treat as an identity-coordinate transition; retain old root discovery                         |
| UID change                | Explicit migration between ownership contexts; no automatic chown                             |
| GID change                | Auth identity retained; native coordinates may change and require explicit recovery/discovery |
| Physical alias            | Same identity                                                                                 |
| Move/rename               | New project identity; old state retained and explicitly discoverable                          |

Copied OAuth credentials can share a refresh lineage. Serialization of one canonical identity does not make separate copies independently valid. Prefer independent login for long-lived project identities.

### F5. Interrupted launch and migration recovery

| Recorded stage                          | Authority and recovery                                                                                               |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Reserved; no native preparation         | Canonical remains authoritative; reconcile any exact created container before releasing reservation                  |
| Created/preparing; client never started | Verify helper termination and unchanged canonical base; retry recorded preparation or preserve for explicit recovery |
| Projected/starting/running              | Native projection may contain updates; establish exact container/helper termination before export                    |
| Collecting; no validated pending export | Preserve native projection; retry qualified export                                                                   |
| Valid pending collection                | Pending export is authoritative; verify transaction/base revision and finish publication                             |
| Canonical committed; projection remains | Finish scrub without exporting an empty replacement over the committed result                                        |
| Scrubbed; journal not complete          | Verify committed revision and complete journal                                                                       |
| Migration staged                        | Source retained; resume recorded transaction                                                                         |
| Migration committed/verified            | Verify destination and preserve source until authorized retirement                                                   |
| Source retired                          | Protected rollback remains; finish adoption record                                                                   |
| Missing/corrupt required projection     | Refuse stale restore; preserve canonical/rollback/journal and require explicit recovery or re-login                  |

Failed liveness queries are not proof of termination. Elapsed time, a stale PID, or a missing lock holder does not authorize recovery.

### F6. Downgrade and rollback

Rollback is explicit and requires stopped clients.

- Before behavioral activation, reselect the prior complete code generation and compatible pins/images.
- After schema/state mutation, reconcile every active/pending operation first.
- Restore only recorded native auth members, using the qualified reverse projection.
- Preserve unrelated native state; do not copy an entire OpenCode database to roll back credentials.
- Preserve current canonical and rollback copies before any reverse transformation.
- Unknown target versions/backends refuse.
- Older launchers must not run simultaneously against projected legacy stores.
- Logout is not automatically reversed by restoring an old credential backup.
- Runtime rollback does not restore automatic fallback.

### F7. Cleanup

Cleanup requires verified adoption and a documented release window.

Inventory inactive scopes, custom roots, historical projects/GIDs, raw rollback members, canonical backups, transaction staging, and code generations.

Cleanup never:

- Infers authorization from a prefix/glob.
- Deletes a recreated resource because its name matches an old target.
- Deletes shared global auth during project reset.
- Deletes external provider files implicitly.
- Pushes, saves, or exports local images.
- Removes host runc, shared networks, or build cache as part of auth migration.

## G. Verification and acceptance matrix

### G1. Evidence classes

Use these labels in every acceptance report:

- **S:** source/static checks.
- **U:** unit/mock/fault-injection checks.
- **D:** actual Docker/container observations.
- **N:** actual pinned native-client observations.
- **A:** dedicated-account observations.
- **P:** platform/filesystem/runtime qualification.
- **CI:** actual workflow execution.

A lower category cannot close a higher-category gate.

### G2. Workflow matrix

| Workflow                 | Required dimensions                                                              | Tasks/evidence                  |
| ------------------------ | -------------------------------------------------------------------------------- | ------------------------------- |
| Setup/install/reinstall  | Fresh/existing; installed pins differ; interruption/concurrency; checkout absent | I01, I02, T01, T02 — U/D        |
| Default launch           | Three harnesses; two scopes; runsc                                               | R01–R04, T02–T04 — D/N/A        |
| Explicit runc            | Three harnesses; two scopes; allowed/prohibited                                  | R01, T02, T04 — U/D/N/A         |
| Offline diagnostics      | Shell/version/help/status/logout; network unavailable                            | R01, R04, T02 — U/D/N           |
| API login                | Supported harnesses; file empty/populated; ambient key absent                    | A01, A02, T03 — N/A             |
| Device/browser login     | Exact pinned provider flows and callbacks                                        | Q02–Q05, R04, T03 — D/N/A       |
| MCP login/refresh/logout | Endpoint/issuer/client binding; partial logout; two projects                     | A01–A03, T03 — N/A              |
| Restart/model/resume     | Same project; second project; both scopes                                        | T02, T03 — D/N/A                |
| Selection                | Multiple integrations/accounts; missing/stale sidecar; logout replacement        | A03, T02, T03 — U/N/A           |
| Scope/root change        | Fresh/use-existing/copy; conflict; unrelated project unchanged                   | M01–M03, T02 — U/D/N            |
| Migration                | File/DB; empty/identical/conflict; legacy/importer/account/MCP                   | M01–M03 — U/N/A                 |
| Crash/recovery           | Host/client/helper/container SIGKILL; daemon failure; disk/inode full            | Q06, R03, L02, M03, T02 — U/D/P |
| Reset/removal/uninstall  | Both scopes, inactive roots, historical projects, replaced resources             | O01, I01, T02 — U/D/N           |
| Capture                  | Normal shell/test parent; global scope configured; malformed namespace           | C03, T01, T02 — U/D/N           |
| Upgrade/downgrade        | Old/new code/image/schema; interrupted pin activation                            | I02, M03, Z01 — U/D/N           |
| Architecture             | amd64 and arm64 independently                                                    | Q02, T04 — P/D/N                |
| CI                       | Root workflow on exact implementation revision                                   | T01, Z02 — CI                   |

### G3. Security observations

| Property                    | Controlled verification                                                                                          |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Runtime fail closed         | Make runsc initialization/probe fail; inspect that no runc agent/helper was created                              |
| Canonical control isolation | Inspect all mounts; attempt access to protected synthetic canonical/control sentinels                            |
| Mount allowlist             | Compare host inspect and guest mountinfo with expected descriptor destinations and bind options                  |
| Project exposure            | Synthetic symlink/hardlink/nested-mount/IPC fixtures; verify preflight refusal or contained namespace resolution |
| UID/groups/capabilities     | Host Config.User plus neutral `id`, `/proc/self/status`, capsh and safe privilege negatives                      |
| Rootfs/namespace isolation  | Attempt writes to image-owned files; inspect PID/IPC/cgroup/network modes and unrelated sentinels                |
| Socket absence              | Full mount inventory, known engine socket paths, and no inherited endpoint environment                           |
| Network behavior            | Controlled host/neighbor/IPv4/IPv6 servers; document actual reachability without claiming an egress allowlist    |
| Credential leakage          | Synthetic sentinels in argv, diagnostics, captures, transaction metadata and Docker log handling                 |
| Native refresh integrity    | Dedicated-account rotation and crash boundaries; inspect resulting valid native/canonical state privately        |
| SQLite preservation         | Before/after logical snapshots of non-auth tables and qualified constraints/triggers                             |
| Cleanup authority           | Foreign namespace/root/harness/UID descriptors and recreated-volume/filesystem fixtures remain unchanged         |
| Resource enforcement        | Host cgroup/inspect values; bounded allocator/process/scratch tests                                              |
| Installation atomicity      | Interrupt before/after generation selection while concurrent installed launches occur                            |

### G4. Commands and required driver behavior

Retain and run:

```bash
make -C box verify-static
make -C box pins
make -C box verify-generated
make -C box build
make -C box test-live
make -C box verify-native-opencode
make -C box verify-native
```

Use the native auth fixture target with explicit verified artifact inputs after Q03–Q05 update its contract.

Native drivers must:

- Record exact source/image/native/runtime versions.
- Use disposable projects under a valid project parent.
- Clear production selectors before test-domain resolution.
- Mark each attempted boundary as reached or not reached.
- Fail on unavailable/malformed/empty native evidence.
- Report account-independent results separately.
- Exit unsuccessfully when a required release gate is unmet.
- Clean only exact run-owned resources and report cleanup failures.

Add a controlled CI/native workflow for suitable self-hosted runners. It must not execute untrusted fork code with reusable account secrets or Docker administrative access. Public CI continues running daemon-free static/unit checks.

## H. Risks and residual limitations

| Risk                                                 | Classification and response                                                                           |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Muse device/MCP inventory unresolved                 | Blocking native gate Q03; no production cutover                                                       |
| OpenCode native mixed-store/account/service behavior | Blocking Q04; column presence alone is insufficient                                                   |
| Codex MCP and alternate-store behavior               | Blocking Q05; provider synthetic success does not close it                                            |
| Current runsc DNS/transport failures                 | Blocking Q02 for supported default workflows; no automatic runc substitute                            |
| Real crash/durability behavior                       | Blocking Q06; mocked journal boundaries are insufficient                                              |
| Required account workflows                           | Blocking T03 before full release acceptance                                                           |
| ARM64 execution                                      | Blocking T04 for advertising ARM64 runtime support                                                    |
| Actual remote workflow execution                     | Blocking CI acceptance; local static checks cannot substitute                                         |
| Supplied credential exfiltration                     | Accepted consequence of native clients plus unrestricted network                                      |
| Shared Muse non-auth trust                           | Accepted compatibility boundary; documented cross-project mutability                                  |
| Rootful Docker administration                        | Accepted host trust requirement                                                                       |
| Compromised upstream/build dependency                | Residual supply-chain risk; pinning/provenance reduce substitution, not malicious code                |
| Host filesystem races                                | Reduced by descriptor-relative operations; compromised same-user/root races remain outside guarantees |
| Project data destruction                             | Inherent authorized capability                                                                        |
| Native token rotated before local save               | Inherent provider/client failure window; preserve evidence and require re-login                       |
| Copied OAuth lineage                                 | Accepted copy limitation; independent login recommended                                               |
| Aggregate memory/disk/network exhaustion             | Operational limitation; per-container caps are not aggregate quotas                                   |
| tmpfs OOM and ENOSPC                                 | Workload/reliability risk; diagnostic and workload qualification tasks                                |
| Native logs/transcripts containing secrets           | Residual native behavior; do not promise complete redaction                                           |
| Optional restricted egress/rootless support          | Separate projects; no implied support or automatic host reconfiguration                               |

Foundational gates may supply exact native schema, member, or callback data. They do not authorize replacing the selected architecture with global mixed state, writable canonical mounts, automatic fallback, destructive conversion, or privileged host helpers.

## I. Definition of done

The integrated implementation is complete only when:

- All 34 tasks are implemented and independently verified.
- The final registry, state, auth, runtime, installation, migration and recovery contracts have one active implementation each.
- Every historical requirement/finding has the disposition recorded in section C, updated with final evidence.
- All three harnesses use default fail-closed runsc and explicit-only runc compatibility.
- No agent, probe, or auth helper mounts canonical credentials, stable locks, discovery indexes, migration journals or host control state.
- Every launch and helper is tied to exact container ownership and a durable lifecycle transition.
- Qualified provider and MCP credentials obey the configured global/project scope.
- Active selection, trust, approvals, sessions and transcripts retain their intended native scopes.
- Unsupported credential members, backends, client versions, images, filesystems and runtime environments refuse before unsafe mutation.
- Clean logout, partial logout, refresh, restart, model use and resumed sessions pass dedicated-account qualification.
- Interrupted execution and migration cannot silently restore stale credentials or manufacture logout.
- Migration and fresh initialization retain verified recoverable legacy data.
- Scope transitions never implicitly copy, merge, overwrite or populate unrelated projects.
- Project reset preserves global auth; code-only uninstall preserves state; full removal uses a complete exact inventory.
- Disposable tests/captures never access production auth or authorize production cleanup.
- Installed execution works without the source checkout and cannot mix code generations.
- Image/native/adapter compatibility is checked before production credential access, including overrides.
- Static/unit/generated checks pass on the exact final tree.
- Actual Docker/native/account/platform/CI evidence closes every advertised release gate.
- Security invariants V01–V16 have falsifiable passing observations.
- Documentation, help, Make interfaces, state descriptors and evidence records agree.
- Rollout and credential-preserving rollback have been exercised with disposable legacy installations.
- Final coverage, dependency, integration, implementability, security and freshness audits pass.
- Only then may the release be described as accepted end to end.

The audit’s currently executable checks passed, but Docker/runsc, Muse/OpenCode native behavior, complete MCP/auth schemas, real accounts, crash durability, ARM64 and remote CI remain explicit blocking qualification gates.
