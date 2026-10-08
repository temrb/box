# 1. Current-state inventory

**Recommendation:** add a declarative `auth` state to the existing registry, backed by a shared scope resolver and guarded lifecycle operations. Use an auth-only canonical store and client-specific projections into native storage. For the currently pinned clients, serialize access to each auth identity and preserve interrupted projections for recovery.

This avoids moving mixed homes or databases into global scope. It also avoids relying on file mounts or symlinks that break when a client replaces or deletes its credential file.

No repository files were modified.

## Investigation baseline

Inspected:

- Repository-local `AGENTS.md` and `box/README.md`.
- Production base: `b9303c487838b0bee4c7111829aa1c5b6d905a25`.
- PR #2 head and local checkout: `c85d13ca5706ba865bdede73b8aa8021df8a28ff`.
- All materially relevant PR changes, registry and launcher helpers, setup/install/preflight/configuration paths, harness adapters, capture, verification, Bats, native acceptance, lifecycle audit, and operational documentation.
- Pinned OpenCode `v2.0.6` source, commit `b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad`.
- Pinned Codex `rust-v0.160.0` source, commit `a956835d020762cb2b570053af06f643a11c0ecc`.
- Official client documentation where available.

The production base already has declarative `_BOX_STATES` records. PR #2 adds test identity resolution, stronger registry validation, and disposable cleanup authorization; it does not separate production authentication from mixed native stores. Its isolation contract must remain intact. [PR #2](https://github.com/temrb/box/pull/2)

The pinned releases are Muse `1.4.0-R4161.1`, OpenCode `2.0.6`, and Codex `0.160.0`. Native clients and Docker were not available for exercising Muse/OpenCode here; repository runtime evidence is historical evidence, not a fresh validation of authenticated behavior.

## Existing identities and ownership

Production project identity is:

- Physical workspace root selected by sanitized Git discovery or `--project-root`.
- `P = first 20 hexadecimal characters of SHA256(physical workspace-root path)`.
- Canonical project volume: `<state_prefix>-u<UID>-g<GID>-<P>`.

Current prefixes are `box-m`, `box-o-v2`, and `box-c`.

Physical aliases and symlinks resolve to the same identity. Moving or renaming the physical workspace changes `P`; old state remains.

Host persistent directories must be outside the project, user-owned, symlink-free, and protected from writable ancestors. Native credential caches require regular files, accepted credential modes, and writability for refresh. Docker images run as the invoking UID/GID. `/persist` starts with user-owned image seed directories.

## Muse

| Category                     | Verified storage/boundary                                                                                                      | Classification and existing lifecycle                                                  |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| Provider login credentials   | Host `~/.config/box-m/muse-config/auth.json`; parent overridden by `BOX_M_PERSIST_DIR`; mounted under `/home/box/.config/muse` | Auth; shared across projects                                                           |
| External API key             | Protected shared `providers.env`; only `MUSE_CODE_API_KEY` forwarded                                                           | External credential source; separately managed                                         |
| Trust                        | Repository describes `.trust.json` beside settings/auth                                                                        | Auth-adjacent security state; presently global                                         |
| Preferences/settings         | Installed host `settings.json`, directory overrides, private launch snapshot mounted read-only                                 | Unrelated; live configuration, not durable UI saves                                    |
| Legacy preferences           | `settings.json.box-legacy` in persistent Muse home                                                                             | Unrelated protected backup                                                             |
| Sessions/history/transcripts | Persistent native data/state roots; `/home/box/.muse` points to `/persist/data/muse`                                           | Unrelated project state                                                                |
| Native data/state            | `XDG_DATA_HOME=/persist/data/muse`, `XDG_STATE_HOME=/persist/state/muse`                                                       | Project volume lifecycle                                                               |
| Cache                        | Base image `XDG_CACHE_HOME=/home/box/.cache`                                                                                   | Container-lifetime unless written inside workspace/persist                             |
| Approvals                    | Native prompting/session behavior; no separate durable approval store established by repository evidence                       | Retain native/session lifecycle                                                        |
| Account/provider selection   | May be embedded in auth or settings; exact pinned representation is not established                                            | Must distinguish intrinsic credential identity from selection before adapter promotion |

The full Muse config parent is writable, with a read-only settings overlay. Setup prepares the default global home; launch validates `auth.json` only on live runs. Project-volume reset currently preserves global auth/trust.

Official Muse documentation establishes settings discovery through `XDG_CONFIG_HOME`, but documents `trust.json`, whereas the repository names `.trust.json`. Resolve that difference against the pinned binary before changing trust handling. [Muse extension locations](https://meta-models.github.io/muse-code-sdk/next/guides/extend/)

Muse also supports MCP OAuth credentials. Official documentation describes credential refresh and local removal on MCP logout, but the exact pinned credential filename/backend was not established. Do not silently include an unidentified MCP store in migration. [Muse MCP authentication](https://meta-models.github.io/muse-code-sdk/next/guides/extend/mcp-servers/)

Exact session/transcript leaf names are not proven by current repository evidence. The known containment boundary is the project volume and native data/state roots; retain that boundary.

## OpenCode

| Category                     | Verified storage/boundary                                                                                          | Classification and existing lifecycle                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| Provider/MCP credentials     | `/persist/data/opencode/opencode/opencode.db`, `credential` table                                                  | Auth; currently project-scoped                                       |
| Credential values            | `credential.value`: typed key or OAuth value, including refresh/access/expiry and metadata                         | Auth                                                                 |
| Saved account inventory      | `credential.id`, integration, label, method/connection metadata                                                    | Auth identity metadata                                               |
| Active credential selection  | `credential.active`                                                                                                | Auth-adjacent selection; currently project-scoped                    |
| Account tokens               | Schema contains `account` and legacy `control_account`, including access/refresh tokens                            | Auth-bearing schema; active use requires pinned adapter verification |
| Active account/org           | `account_state`; legacy `control_account.active`                                                                   | Auth-adjacent selection                                              |
| Sessions/history/transcripts | Same mixed SQLite database                                                                                         | Unrelated project state                                              |
| Saved approvals              | Same database, exercised by native permission probe                                                                | Unrelated project security state                                     |
| Preferences                  | `/persist/config/opencode`; `cli.json`, `tui.json`, `opencode.jsonc` backed up and removed before client execution | Unrelated; existing reset-on-launch policy                           |
| Host defaults                | `~/.config/box-o/opencode.json`, mounted read-only                                                                 | Unrelated installed configuration                                    |
| Data/logs/repos              | App-suffixed paths under `/persist/data/opencode`                                                                  | Unrelated project state                                              |
| Service state                | App-suffixed paths under `/persist/state/opencode`; service configuration under config parent                      | Unrelated project state                                              |
| Cache                        | App-suffixed cache beneath `/home/box/.cache`                                                                      | Container-lifetime                                                   |
| Legacy `auth.json`           | Legacy importer, not native v2 login store                                                                         | Legacy auth; must prevent uncontrolled re-import                     |

The entrypoint guards the database and its WAL/SHM files: regular, user-owned, writable, mode `600`, with non-symlink parents. It serializes preference reset, then releases that lock before execution.

Pinned source confirms:

- `Credential.Service` uses `Database.Service`.
- Credential creation, activation, update, and removal operate on the mixed database.
- Removing an active credential may activate another saved credential.
- Database initialization uses WAL, a busy timeout, and an in-process bootstrap semaphore. Those mechanisms do not establish safe cross-process OAuth refresh coordination.
- MCP integration identity includes a hash of server name and URL, rather than name alone.

Relevant source: [credential service](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/credential.ts), [credential schema](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/credential/sql.ts), [account schema](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/account/sql.ts), [database service](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/database/database.ts).

`OPENCODE_DB` redirects the database as a whole. It does not independently redirect auth. Moving that database globally would also share sessions and approvals. [OpenCode database location](https://opencode.ai/v2/docs/troubleshooting/)

Native logout removes a selected saved account; it does not necessarily remove every account for the provider. Preserve that distinction in UX. [OpenCode auth commands](https://opencode.ai/v2/docs/cli/commands/)

## Codex

| Category                       | Verified storage/boundary                                                                  | Classification and existing lifecycle                                                                     |
| ------------------------------ | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| Cached login                   | `<state_root>/<P>/codex-home/auth.json`                                                    | Auth; currently project-scoped                                                                            |
| Host home root                 | Default `~/.config/box-c/projects`; `BOX_C_STATE_ROOT`, legacy `BOX_C_STATE_DIR`           | Mixed project home                                                                                        |
| Container home                 | `/home/box/.codex`, `CODEX_HOME=/home/box/.codex`                                          | Project bind                                                                                              |
| Credential identity/mode       | Fields in `auth.json`, including API key or token/account material and refresh metadata    | Auth                                                                                                      |
| Provider selection/preferences | Installed/system configuration, home configuration, allowed native directory configuration | Unrelated or auth-adjacent selection                                                                      |
| Trust                          | `[projects.…].trust_level` retained in home `config.toml`                                  | Auth-adjacent security state; project home lifecycle                                                      |
| Sessions/transcripts/history   | Native home, including documented `history.jsonl`; other native session/log/cache files    | Unrelated project-home lifecycle                                                                          |
| SQLite runtime state           | `/persist/state/codex`, constrained by configuration and image requirements                | Unrelated project-volume lifecycle                                                                        |
| Approval defaults              | Installed config and image-owned requirements                                              | Unrelated policy                                                                                          |
| Approval/session facts         | Native runtime/session stores                                                              | Unrelated project lifecycle                                                                               |
| External API key               | Protected provider file, explicitly imported or forwarded through `BOX_C_AUTH=api`         | Separately managed external credential                                                                    |
| MCP OAuth                      | Separate native OAuth credential machinery                                                 | Auth, distinct from provider `auth.json`; exact supported store must be included in adapter qualification |

The launcher backs up home preferences, retains trust records, and releases its preference lock before container startup. Removing only the volume retains home auth/transcripts; removing only the home retains SQLite state.

Official documentation confirms file auth under `CODEX_HOME`, automatic refresh, and separate keyring modes. The repository enforces file credentials. [Codex authentication](https://learn.chatgpt.com/docs/auth)

Pinned file-storage source opens/truncates `auth.json` when saving and unlinks it when deleting. It does not supply a cross-process file lock in that backend. Therefore:

- A bind-mounted credential file cannot reliably support native unlink.
- A symlink alone cannot implement logout: deleting the symlink leaves the canonical target.
- Changing all of `CODEX_HOME` would change unrelated state scope.

[Codex 0.160.0 file-storage implementation](https://github.com/openai/codex/blob/a956835d020762cb2b570053af06f643a11c0ecc/codex-rs/login/src/auth/storage.rs)

## PR #2 test state

Verified current formulas:

- Volume: `box-test-<namespace>-<state_prefix>-u<UID>-g<GID>`.
- Codex home: `<BOX_TEST_TASK_ROOT>/<namespace>/codex-home`.
- Capture namespace: `<parent>-cap-<8hex>`.
- Partial or malformed test configuration fails closed.
- Overrides must remain inside the disposable task root.
- Cleanup checks exact resolver identity and recorded coordinates.
- Capture owns an independent namespace.
- Native drivers currently allocate different namespaces to different projects.

The last point means current native tests do not yet demonstrate two physical projects sharing one test-global auth identity. That coverage must be added without allowing production fallback.

# 2. Target architecture

## Declarative state model

Extend `_BOX_STATES`; do not replace it.

Add exactly one selectable `auth` state per harness. Add narrowly scoped state fields:

| Field            | Purpose                                                         |
| ---------------- | --------------------------------------------------------------- |
| `class`          | `auth` or existing non-auth class                               |
| `scope`          | Fixed scope or `auth-policy`                                    |
| `default_scope`  | Harness fallback: `global` or `project`; empty for fixed states |
| `adapter`        | Declared native storage adapter path                            |
| `schema_version` | Box auth envelope/adapter contract version                      |

Existing `kind`, `root`, `override`, `runtime`, `mode`, and `reset` remain. Auth records use:

- `class=auth`
- `scope=auth-policy`
- `kind=bind`
- Shared protected auth root
- `runtime=/run/box-auth`
- `mode=700`
- Explicit auth reset semantics

Retain existing home and volume records, but rewrite reset descriptions to distinguish non-auth contents from temporary native auth projections.

Validate that every harness has exactly one auth record, a supported adapter, a valid fallback scope, and its canonical `/persist` volume.

## Resolver boundaries

Add `box/lib/state.sh` as the authoritative state identity/location resolver.

Proposed functions:

- `box_state_context`: validated harness, UID/GID, physical project, execution domain.
- `box_state_resolve`: produces a descriptor for an explicitly requested state.
- `box_state_validate_descriptor`: validates a descriptor without mutation.
- `box_state_guard_operation`: authorizes an explicit operation against exact descriptors.
- `box_state_cli`: machine-readable descriptor output for Python/native consumers.

Add `box/lib/auth.sh` for:

- `box_auth_policy_resolve`
- `box_auth_plan`
- `box_auth_prepare`
- `box_auth_transition_plan`
- `box_auth_lease_reserve`
- `box_auth_recover`
- `box_auth_guard_remove`

The resolver returns structured metadata, including domain, harness, class, scope, UID, project hash where applicable, paths, mount target, adapter, and schema. Callers must not rebuild names.

This replaces duplicated identity logic in:

- `box_project_identity`
- Codex home derivation
- Muse persistent-home handling
- OpenCode capture volume derivation
- Operational reset examples
- Native acceptance/lifecycle inventories

Keep workspace discovery in `launcher.sh`; pass its existing physical-root result into the state resolver.

## Canonical auth and native projections

The canonical auth object contains **auth material only**. Native homes/databases remain their existing scopes.

Each adapter supports:

1. Validate supported native storage/schema.
2. Export auth without unrelated records.
3. Export selection separately.
4. Install a canonical auth projection.
5. Collect changes, including logout and refresh.
6. Scrub only the projection.
7. Recover an interrupted projection.

Use a versioned, mode-`600` `credentials.json` envelope:

- Harness and adapter schema.
- Auth revision.
- Native auth payload.
- Explicit absence/tombstone state.
- No project preferences, trust, approvals, sessions, or transcripts.
- No active account/provider selection unless inseparable from the credential’s intrinsic identity.

A canonical store is authoritative while idle. During an active lease, the recorded native projection is authoritative for uncommitted auth updates. Recovery must collect it before another launch can import the previous canonical revision.

This is a managed import/export layer, **not best-effort synchronization**. There are no periodic “last writer wins” copies.

## Why adapters are necessary

Shared code branches on declared storage mechanics or invokes the declared adapter; it never branches on harness names.

- Muse adapter: native file/backend semantics and unresolved pinned storage details.
- Codex adapter: file save/unlink behavior and native credential schema.
- OpenCode adapter: auth rows embedded in a mixed SQLite database, foreign keys, and selection fields.

These cannot reasonably be represented by path strings alone.

A future client-supported auth path can replace projection mechanics within its adapter. Scope configuration, identities, migration authorization, and launcher consumption remain unchanged.

## Concurrency contract

Initial implementation permits **one active writer per auth identity**.

Also lock each native projection store:

- Codex: project home.
- OpenCode: project database/volume.
- Muse: existing global native config home.

Consequences:

- Global auth serializes projects sharing that harness/user identity.
- Project auth permits independent projects, except Muse’s existing shared config parent still requires serialization.
- Busy launches fail promptly with non-secret identity metadata.
- Do not silently wait indefinitely.
- Login, logout, shell execution, refresh-capable runs, migration, reset, and recovery obey the same locks.

This restriction is required because SQLite writer locking does not coordinate remote token rotation, and Codex file storage does not provide the required inter-process serialization.

## Test-specific boundary

Keep in `test-state.sh`:

- Test activation/partial-configuration rejection.
- Namespace validation and generation.
- Task-root validation.
- Capture subnamespace ownership.
- Explicit test cleanup authorization.

Reuse only pure primitives: physical-project hashing, descriptor construction, numeric identity validation, and containment checks.

The dispatcher selects the test domain **before** evaluating production roots or legacy discovery. Tests never call production migration/import/recovery. A test descriptor cannot be converted into a production descriptor.

Extend test root exclusion using registry-declared protected roots, including the new auth root. Do not preserve its current hardcoded production-root list as a second authority.

# 3. Effective configuration matrix

## Defaults and user configuration

Preserve existing auth scope as registry fallbacks:

| Harness  | Registry fallback | Reason                         |
| -------- | ----------------- | ------------------------------ |
| Muse     | `global`          | Preserve current login sharing |
| OpenCode | `project`         | Preserve current isolation     |
| Codex    | `project`         | Preserve current isolation     |

Use optional, protected host configuration:

`~/.config/box/state.toml`

Proposed configuration:

```toml
schema_version = 1

[auth]
default_scope = "project"

[auth.harnesses.muse]
scope = "global"
```

Omitting `default_scope` means use harness registry fallbacks. Omitting a harness override means inherit the common policy, then its registry fallback.

For a new installation, seed a versioned file with no explicit scope settings. Setup reruns preserve it byte-for-byte.

## Runtime interface

- `BOX_AUTH_SCOPE`: common runtime policy.
- `BOX_M_AUTH_SCOPE`, `BOX_O_AUTH_SCOPE`, `BOX_C_AUTH_SCOPE`: harness runtime overrides, derived through existing registry `git_prefix`.
- `BOX_STATE_CONFIG`: optional absolute path to an existing protected state configuration.
- `BOX_AUTH_ROOT`: optional absolute protected root for canonical auth objects.

`BOX_C_AUTH` remains the independent authentication-mode/key-forwarding setting. It must never select persistence scope.

## Exact precedence

Highest first:

1. Selected harness runtime scope.
2. Common runtime `BOX_AUTH_SCOPE`.
3. Selected harness scope in installed/user configuration.
4. Common `auth.default_scope` in that configuration.
5. Selected harness registry fallback.

Configuration file selection:

1. Explicit `BOX_STATE_CONFIG`.
2. Optional default `~/.config/box/state.toml`.

Validate **all supplied values before resolution**, including shadowed values. An invalid lower-precedence value must not be hidden by a valid override.

## Validation and inheritance

- Accepted scope strings: exactly `global` or `project`.
- Unset environment variable: inherit.
- Set-but-empty variable: error.
- Omitted configuration key: inherit.
- Empty string, wrong type, unknown harness/key, unsupported schema, duplicate TOML declaration: error.
- Explicit missing config file: error.
- Missing implicit default config file: valid pre-upgrade absence.
- Present unreadable/unsafe config file: error.
- Unsafe root or conflicting legacy root aliases: error.
- No native project configuration may set Box auth scope.
- Never source configuration as shell code.
- Use `config-file.sh` for TOML parsing and a shared schema validator for optional fields.

Resolve and validate policy before creating directories, contacting Docker, inspecting native credentials, acquiring auth locks, or preparing projections.

Scope is configurable at runtime and durably through user configuration. Setup installs the interface; it does not migrate login material.

Changing policy selects a different identity. It does not implicitly copy or merge credentials.

# 4. State-layout design

The following are **proposed new paths**. Existing native paths remain as inventoried above.

Define:

- `H`: registered harness ID.
- `U`: validated nonzero host UID.
- `G`: host GID used for ownership/runtime compatibility.
- `P`: existing 20-hex physical-project hash.
- `R`: `BOX_AUTH_ROOT`, otherwise `$HOME/.config/box/auth`.
- `N`: validated disposable namespace.
- `T`: validated disposable task root.

## Production auth identities

| Scope   | Logical identity                       | Auth object directory |
| ------- | -------------------------------------- | --------------------- |
| Global  | `(production, H, auth, U, global)`     | `R/H/uU/global/`      |
| Project | `(production, H, auth, U, project, P)` | `R/H/uU/projects/P/`  |

Use UID, not GID, as the auth identity key: changing a user’s primary group must not silently create another login identity. Record and validate ownership; group ownership is operational metadata.

Existing non-auth volumes retain UID/GID naming.

Each auth object contains explicit leaves:

- `identity.json`: non-secret identity/schema metadata.
- `credentials.json`: auth envelope.
- `lease.json`: non-secret active/recovery record.
- `lock`: stable lock inode, never replaced.
- Explicitly recorded transaction/staging leaves during migration.

Mount only the selected object directory at `/run/box-auth`, writable, with existing non-recursive/private bind flags. Do not mount the shared auth root or all harness/user objects.

Directories: user-owned `700`. Files: user-owned `600`. Credential state must be writable. Reject unsafe existing metadata rather than silently repairing it.

## Test auth identities

| Scope        | Logical identity                    | Directory                   |
| ------------ | ----------------------------------- | --------------------------- |
| Test-global  | `(test, N, H, auth, U, global)`     | `T/N/auth/H/uU/global/`     |
| Test-project | `(test, N, H, auth, U, project, P)` | `T/N/auth/H/uU/projects/P/` |

“Global” in tests means shared only inside one disposable namespace. Another namespace gets another auth identity.

Retain PR #2’s current non-auth volume formula and Codex-home resolver for existing tests. Add dedicated scope tests with two projects in one namespace. Where those tests require independent non-auth stores, extend the test resolver with an explicit project-qualified fixture identity; never inline a new naming formula in callers.

No auth Docker volumes are required. Canonical auth is a protected bind; project `/persist` volumes remain unchanged.

## Auxiliary lifecycle metadata

Add a protected, non-secret index beneath `$HOME/.config/box/state-index/`:

- Known exact descriptors.
- Explicit custom roots.
- Project-to-auth binding acknowledgments.
- Native projection coordinates.
- Migration/recovery transaction identifiers.

Test indexes live under `T/N/`.

The index is discovery metadata, not deletion authority. Every operation re-resolves and validates each candidate. Missing entries never authorize prefix/glob cleanup.

Retain full physical paths in project descriptors for collision checking. If two paths produce the same truncated hash, fail; do not share state.

Moves change project auth identity but retain global auth identity. Physical aliases retain both identities.

# 5. Harness adaptation

## Muse

Modify `harnesses/muse/launch.sh` and `install.sh`:

- Remove the assertion that the persistent home itself defines auth scope.
- Continue resolving `BOX_M_PERSIST_DIR` as the non-auth native config home.
- Preserve existing trust, settings snapshot, preference backup, and project `/persist` behavior.
- Project the selected auth envelope into native `auth.json` while holding both auth and native-home leases.
- Collect refresh/login/logout changes before releasing the lease.
- Remove projected auth after successful collection.
- Keep auth backups outside the live native-home bind.
- Stop setup from inspecting native auth as part of ordinary installation.

Add `harnesses/muse/auth.sh` and bounded native qualification fixtures.

Before promotion, establish the pinned file backend, supported empty/no-login representation, logout behavior, and all additional credential stores. Unsupported/keychain-only behavior must fail explicitly; do not reinterpret an auth pointer as a plaintext token store.

Trust filenames and contents are excluded from auth export.

## Codex

Modify `harnesses/codex/launch.sh`:

- Keep existing project-home resolution and root alias agreement.
- Keep `CODEX_HOME` project-scoped.
- Keep `/persist/state/codex` project-scoped.
- Replace direct auth-home lifecycle assumptions with the resolved auth descriptor.
- Project the canonical provider login into the native home as a regular `auth.json`.
- Treat native removal as logged-out state; export a tombstone.
- Preserve trust rewrite, transcripts, history, logs, preferences, and SQLite state.

Add `harnesses/codex/auth.sh` with native schema validation and auth-only import/export.

Do not use file bind mounts or permanent credential symlinks. Do not change credential-store requirements to keyring/auto.

Preserve explicit API-key import and NAME-only forwarding. Provider-file credentials remain independently managed.

Qualify MCP OAuth storage separately; include discovered credential leaves as declared adapter members, with their corresponding selection/security state excluded. If a supported feature cannot be safely separated, reject its use under the new managed mode until qualified.

## OpenCode

Add `harnesses/opencode/auth-state.py` and `auth.sh`; update `entrypoint.sh`.

Implement schema-bound SQLite projection:

- Verify the pinned schema before operating.
- Use explicit column lists and parameterized statements.
- Export supported `credential` auth records.
- Preserve IDs, integration IDs, labels, values, method/connection metadata, and timestamps.
- Store `active` selections separately in project state.
- Handle supported `account`/legacy auth records only through a verified adapter schema.
- Preserve `account_state` and equivalent selections in project state.
- Do not export sessions, messages, events, saved approvals, workspace/project rows, configuration, caches, or logs.
- Restore selection only when its credential still exists.
- If multiple credentials exist and a new project has no selection, require explicit native selection; do not choose by timestamps.
- Allow an auth-selection operation without executing a model turn.

Place selection sidecar metadata under the existing project state root, for example `/persist/state/opencode/box-auth-selection.json`. Key selections by auth identity so switching scopes does not overwrite another scope’s remembered selection.

Use SQLite transactions and retain WAL/SHM hygiene. Stop and reap the native background service before collecting/scrubbing. Never edit the database concurrently with the client.

For a fresh native database, perform bounded native schema initialization before projection, then stop the service. Do not reconstruct the entire upstream schema in Box.

Scrubbing removes only supported auth rows and adjusts unavoidable credential foreign-key references. Saved selection is retained separately for restoration. Check unrelated tables remain unchanged.

Disable uncontrolled legacy `auth.json` import after migration. Detect and quarantine explicitly authorized legacy files outside normal native importer paths.

Include MCP credentials in the same scope only where integration identity is stable and endpoint-bound. The pinned MCP implementation hashes name and URL; preserve those IDs. Unknown credential payload/schema versions fail closed. [Pinned MCP integration identity](https://github.com/anomalyco/opencode/blob/b084acc55ea2cdb50e9c2ec49a8d9ab3608d43ad/packages/core/src/mcp/index.ts)

## Shared execution wrapper

Add an image-installed supervisor around ordinary, auth, and shell runs.

It must:

1. Validate the reserved lease and adapter version.
2. Acquire auth and projection locks in deterministic order.
3. Record projection preparation before modifying native auth.
4. Install auth.
5. Run and reap the client and supported background service.
6. Export valid resulting auth, including logout.
7. Atomically commit the canonical revision.
8. Scrub the native projection.
9. Mark the lease idle.

A shell run also needs the wrapper: it can execute native login/logout or alter credential storage.

Do not give the container Docker socket access.

# 6. Migration design

## Installation migration

Setup performs no credential migration.

On the first live launch after upgrade:

- Resolve policy and new auth identity.
- Inspect only explicitly resolved legacy stores for that harness/project.
- If legacy credentials exist without a completed migration record, refuse launch with an actionable migration requirement.
- Dry-run reports the prospective new location and legacy candidate coordinates without reading credential files/databases.

Provide explicit Make targets backed by the same resolver:

- `auth-migrate`: legacy native auth → selected canonical identity.
- `auth-copy`: explicitly selected canonical source → destination.
- `auth-init`: acknowledge a fresh identity without importing.
- `auth-recover`: resolve interrupted lease/transaction.
- `state-plan` and `state-remove`: lifecycle operations.

These are operational actions; inspection remains available through launcher dry-run.

## Source discovery

- Muse: exact resolved legacy `auth.json` and qualified credential members.
- Codex: exact selected project home and qualified credential members.
- OpenCode: exact selected v2 project volume/database, opened through a contained helper.
- Older root/subdirectory identities: explicit user-supplied descriptor.
- OpenCode v1 volumes: retain current no-auto-import policy; explicit unsupported migration unless separately qualified.

Do not search host-native credential homes or unrelated projects automatically.

## Preconditions

Before reading/exporting:

- Validate source and destination descriptors.
- Require stopped dependent clients and services.
- Acquire source, destination, and projection locks in sorted identity order.
- Validate ownership, modes, file types, symlink-free ancestry, and containment.
- Validate native schema.
- Require destination absent/empty or demonstrably identical.
- Reject destination conflict without mutation.
- Never allow a test transaction to name a production source or destination.

## Atomic transaction

Use a durable non-secret transaction journal with explicit source/destination coordinates and stages:

`planned → staged → destination-committed → verified → source-retired → complete`

Process:

1. Export source auth into a protected staging file beside the destination.
2. Validate exported native payload and selection separation.
3. Flush file and containing directory.
4. Publish destination without overwriting an existing winner.
5. Reopen and verify the committed payload privately.
6. Record committed destination revision.
7. Retire legacy auth from its active importer path only after verification.
8. Preserve an explicit protected rollback copy.
9. Complete the journal.

For SQLite, export through a consistent transaction/backup boundary; do not copy a live database file without its WAL state.

Rollback restores only explicitly recorded targets. Never merge stores.

## Project → global

- Configuration change alone does not copy credentials.
- If global auth exists, use it only after acknowledging the identity change.
- If absent, choose fresh login or explicitly copy one selected project identity.
- Do not enumerate projects and select the newest, first, or last.
- Multiple differing candidates produce a conflict requiring an explicit source choice or fresh login.
- Preserve every unselected source.
- A nonempty destination is never overwritten by default.
- Initial implementation does not merge account sets across sources.

## Global → project

- Each project starts with an independently selected identity.
- Require explicit acknowledgment: fresh login or explicit copy from global.
- Copy only into the selected project.
- Preserve the global source.
- Never populate all known projects automatically.
- Existing project credentials conflict with a copy unless identical.

Copied OAuth refresh tokens may not remain independently usable after either copy rotates or is revoked. Prefer fresh login for separate long-lived accounts; document this as provider behavior, not a guarantee of independent token validity.

## Scope-change acknowledgment

Record the last acknowledged auth identity for each physical project/harness.

When it changes, a live launch requires an explicit transition choice:

- `fresh`: initialize/use an empty destination without import.
- `use-existing`: acknowledge the selected existing destination.
- Explicit `auth-copy`: import from named source.

Do not infer acknowledgment from elapsed time or from an empty store.

## Interrupted operation/recovery

- Before destination commit: source remains authoritative.
- After commit but before retirement: journal identifies the committed destination; resume verification/retirement.
- After interrupted native execution: projection remains authoritative until collected.
- Failed validation leaves source, destination, and projection intact.
- Missing projection during required recovery is an error, never permission to restore stale credentials.
- Completed logout is a tombstone, preventing legacy re-import.

# 7. Implementation sequence

## Phase 1 — Freeze native adapter contracts

Files:

- New harness auth adapters and fixtures.
- `harnesses/opencode/auth-state.py`.
- Bounded native adapter verification scripts.
- Acceptance documentation.

Establish file/schema members, selection fields, logout, writable refresh behavior, service shutdown, and mixed-store exclusions.

**Checkpoint:** no production migration or scope support is enabled until pinned adapters pass synthetic native import/export/logout tests. Muse backend uncertainties must be resolved here.

## Phase 2 — Registry and configuration

Change:

- `lib/tools.sh`: state fields, auth records, validation.
- `lib/config-file.sh`: optional-key/schema parsing support.
- New `lib/auth.sh`: shared policy resolution.
- `setup.sh`, `lib/install.sh`: optional policy file installation/preservation.

Retain mandatory `BOX_TOOL` contracts.

**Checkpoint:** registry/config Bats cover every precedence and invalid-value case; setup failures leave files and metadata unchanged.

## Phase 3 — Authoritative state descriptors

Add `lib/state.sh`.

Change:

- `lib/launcher.sh`: separate workspace discovery from persistent state resolution.
- `lib/preflight.sh`: enumerate new protected roots from registry.
- `lib/test-state.sh`: test-domain dispatch, registry-backed production exclusions, auth test descriptors.
- Native Python consumers: call descriptor CLI.

Preserve existing production volume names and existing non-auth home formulas.

**Checkpoint:** read-only resolver tests prove physical aliases, moves, UID separation, harness separation, hash collisions, and test-domain isolation.

## Phase 4 — Lease and supervised container lifecycle

Change:

- `lib/run.sh`: attach resolved auth/projection descriptors.
- `lib/docker.sh`: durable auth-managed lifecycle.
- Dockerfile: install supervisor/adapters and required Python support.
- Wrapper sourcing/install discovery.

For auth-managed runs, replace anonymous `docker run --rm` lifecycle with:

1. Validate Engine/runtime/image/network.
2. Reserve under locks.
3. `docker create` with exact labels, mounts, and lease token.
4. Record immutable container ID before start.
5. Release reservation locks; start/attach.
6. Supervisor validates reservation and owns runtime locks.
7. Remove the exact container only after completed collection or recorded recovery state.

A reserved container blocks competing launches even before it starts. Host failure between creation/start leaves a recoverable reservation. Container failure leaves the persistent projection and lease.

Never infer container ownership from a loose name prefix.

**Checkpoint:** fault injection covers every reserve/create/start/import/commit/scrub boundary, host-client death, container death, daemon failure, and cleanup failure.

## Phase 5 — Harness launch integration

Change all three `launch.sh` adapters and OpenCode `entrypoint.sh`.

- Remove hardcoded production auth-scope policy.
- Retain native non-auth locations and existing preference behavior.
- Route ordinary/auth/shell execution through supervisor.
- Move auth validation into the shared live preparation/adapter path.
- Keep dry-run free of auth inspection.
- Preserve existing credential forwarding and approval rules.

**Checkpoint:** installed-launcher tests pass without checkout access; mount and entrypoint assertions reflect the supervisor.

## Phase 6 — Migration and lifecycle tools

Add resolver-backed Make targets and one shared operational entrypoint.

Implement exact descriptors for:

- Migration/copy/init/recovery.
- Project reset.
- Explicit auth removal.
- Code-only uninstall inventory.
- Full state removal inventory.

Replace documentation’s inline hash/name reconstruction with resolver output.

**Checkpoint:** conflict, interruption, rollback, and deletion-authorization tests pass; foreign targets remain unchanged.

## Phase 7 — Capture, verification, and native coverage

Change:

- `harnesses/opencode/capture-validation.sh`
- Harness `verify.d/40-readiness-*`
- Relevant shared verification fragments
- `tests/native/acceptance.sh`
- `tests/native/lifecycle-audit.py`
- `tests/native/opencode-state.py`
- `tests/native/probe-races.py` where container lifecycle expectations change

Capture always runs in a fresh disposable namespace, including when invoked from a normal production shell. It must not consume global auth merely to inspect configuration.

Regenerate `verify-*.sh` using `gen-verify.sh`; never edit generated scripts directly.

**Checkpoint:** `make -C box verify-static`, `pins`, and generated consistency pass. Build through Make, then run both explicit runtimes.

## Phase 8 — Documentation and controlled rollout

Update all surfaces listed below, record adapter/runtime/account evidence, and preserve legacy support until removal criteria are met.

# 8. Test plan

## Existing tests to rewrite

| Existing surface                                                              | Required conceptual change                                                     |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `tools.bats` registry completeness/state validation                           | Auth records, dynamic scope, adapters, schema and lifecycle validation         |
| `config.bats`: “project-identity derives stable volume and container names”   | Workspace identity versus resolver-produced state identities                   |
| `launchers.bats` dry-run/mount/shell tests                                    | Effective auth metadata and supervised entrypoint                              |
| `live-defaults.bats`: “Muse launch snapshots refresh defaults preserve auth…” | Preserve non-auth home behavior; canonical auth and projections are separate   |
| `live-defaults.bats`: interruption/lock test                                  | Preference lock release remains; auth lease remains until collection/recovery  |
| `live-defaults.bats`: Codex trust migration                                   | Trust/history unaffected by either auth scope                                  |
| `opencode-v2.bats`: config siblings and SQLite guard                          | Mixed database remains project-scoped; auth projection lifecycle added         |
| `test-state.bats` exact identity/cleanup tests                                | Add auth descriptors without weakening existing namespace guards               |
| `opencode-capture.bats`                                                       | Every capture owns disposable auth/non-auth state, including normal invocation |
| `setup.bats`                                                                  | Preserve policy, canonical auth, migration journals, and indexes               |
| `preflight.bats`                                                              | Registry-declared auth roots, custom roots, escapes                            |
| `split.bats`, `config-linkage.bats`, `gen-verify.bats`                        | New installed package/helpers and generated adapter-aware checks               |
| `cancellation.bats`, `run.bats`, `auto-runtime.bats`                          | Reserved/create/start lifecycle and exact cancellation ownership               |

Do not retain tests that equate “Muse home is global” with “auth must be global,” or “OpenCode volume is project-scoped” with “auth must be project-scoped.”

## New Bats classes

Add:

- `auth-policy.bats`
- `state.bats`
- `auth-lifecycle.bats`
- `auth-migration.bats`
- `auth-adapters.bats`

Cover:

| Class                 | Assertions                                                                                                            |
| --------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Registry/schema       | Missing/duplicate auth record; bad adapter; bad scope/schema; orphan fields; canonical `/persist` still required      |
| Policy                | Registry fallbacks, common default, per-harness overrides, every precedence combination                               |
| Invalid configuration | Empty/unknown/malformed values, wrong types, unknown keys/harnesses, shadowed invalid values, missing explicit config |
| Identity              | Global project independence; project isolation; aliases; moves; UID separation; GID stability; harness separation     |
| Paths                 | Unsafe owner/mode, relative root, ancestor symlink, escape, project overlap, comma/newline, non-file credential/lock  |
| Migration             | Empty destination, identical destination, differing accounts, explicit source choice, no automatic merge              |
| Switching             | Both directions; fresh/use-existing acknowledgment; unrelated project not populated                                   |
| Transactions          | Interruption at every journal stage, atomic publication, source retained until verified                               |
| Logout                | Tombstone, no legacy resurrection, partial-account logout semantics                                                   |
| Lease                 | Busy failure, deterministic lock order, dead reservation, live-container recovery refusal                             |
| Cleanup               | Exact identity required; wrong class/domain/harness/UID/project rejected; no wildcard/prefix authority                |
| Dry-run               | No credential reads, DB opens, locks, writes, migration, Docker contact, or secret output                             |
| Setup/uninstall       | Rerun preservation; code-only preservation; exact full-state removal                                                  |
| Legacy                | Root aliases, older project identities, unsupported v1 state, protected rollback copies                               |

Use fault-injection clients and fake Docker responses to test actual interruption boundaries. Do not test merely that functions echo expected implementation strings.

## Adapter verification

**Codex:**

- Synthetic valid native auth import.
- Native login status where account-independent.
- Native logout/unlink → canonical tombstone.
- File mutation/refresh-shaped write collected.
- Malformed/truncated auth preserves prior canonical revision and requires recovery.
- Trust, history, sessions and SQLite markers unchanged.

**OpenCode:**

- Fixture database created by the pinned client.
- Multiple key/OAuth credentials.
- Selection stored per project.
- Native account switching/logout.
- Auth-only export/import/scrub.
- Session/approval/project/config rows unchanged.
- WAL recovery and interrupted commit.
- Unknown schema/payload rejected.
- Native service stopped before collection.
- MCP endpoint identity retained.

**Muse:**

- Qualified file backend.
- Native empty/logout behavior.
- Auth mutation and recovery.
- Trust/settings/session markers unchanged.
- Backend/schema mismatch fails explicitly.

## Native acceptance and lifecycle audit

Expand both existing drivers to the Cartesian coverage:

- Three harnesses.
- Global and project auth.
- Explicit `runsc` and hardened-runc fallback.

Use a shared disposable namespace for two-project auth-scope cases. Separate namespaces remain necessary for foreign-namespace rejection.

Test:

- Restart persistence.
- Second-project sharing/isolation.
- Physical rename versus alias.
- Scope transitions and conflicts.
- Setup rerun.
- Project reset.
- Code-only uninstall.
- Full removal.
- Busy concurrent launch.
- Interrupted projection recovery.
- Exact cleanup authorization.
- Capture independence.
- Unsafe binds and runtime startup failures.

Synthetic credentials prove storage mechanics only. Real login, refresh/rotation, logout, model turn, and resumed session require separate opt-in account acceptance using dedicated test accounts authenticated directly into disposable state. Never import production auth to satisfy a test.

Keep ARM64 and actual CI execution as separately recorded gates.

# 9. Documentation and operational UX changes

Update:

- `box/README.md`
- `docs/architecture.md`
- `docs/operations.md`
- `docs/adding-a-tool.md`
- `docs/harnesses.md`
- All three harness READMEs
- `docs/troubleshooting.md`
- `docs/upgrades.md`
- `docs/acceptance.md`
- `docs/security-resource-audit.md`
- `box-m-login` help text
- Launcher usage/common flags
- Relevant planning/spec references to PR #2 formulas

Dry-run reports:

- Execution domain.
- Effective auth scope and policy source.
- Harness/user identity.
- Project hash only when relevant.
- Canonical auth directory.
- Native projection location.
- Unchanged non-auth home/volume identity.
- Migration/transition requirement based on non-secret metadata.
- Serialization policy.

It must not report account names, credential IDs, token hashes, file contents, native auth status, or database rows.

## Lifecycle contract

| Operation                | Auth                                                                                     | Unrelated project state                     | Existing global harness state         |
| ------------------------ | ---------------------------------------------------------------------------------------- | ------------------------------------------- | ------------------------------------- |
| Restart/repeated launch  | Restore selected identity; recover interrupted lease first                               | Retained                                    | Retained                              |
| Another project, global  | Same harness/user auth                                                                   | Separate                                    | Existing lifecycle retained           |
| Another project, project | Different auth identity                                                                  | Separate                                    | Existing lifecycle retained           |
| Physical move/rename     | Global unchanged; project fresh identity                                                 | Fresh existing path-derived identity        | Retained                              |
| Physical alias           | Same identity                                                                            | Same identity                               | Retained                              |
| Native logout            | Changes selected auth identity; may remove one account only                              | Retained except necessary invalid selection | Retained                              |
| Scope change             | Explicit destination/transition; no implicit copy                                        | Retained                                    | Retained                              |
| Setup rerun              | Retained; no migration                                                                   | Retained                                    | Retained                              |
| Project reset            | Removes selected project auth only under explicit reset semantics; global auth preserved | Selected project home/volume removed        | Preserved                             |
| Code-only uninstall      | Preserved                                                                                | Preserved                                   | Preserved                             |
| Full state removal       | Explicitly inventoried auth objects and backups removed                                  | Explicitly inventoried stores removed       | Explicitly inventoried stores removed |
| Dry-run                  | Metadata planning only                                                                   | Unchanged                                   | Unchanged                             |
| Disposable test          | Namespace-local auth only                                                                | Disposable stores only                      | Production untouched                  |
| Either runtime           | Identical persistence policy                                                             | Identical state scope                       | Identical lifecycle                   |

For project reset, make the operational interface explicit:

- Default `project-reset`: remove project non-auth state and project auth identities acknowledged for that project.
- Never remove global auth.
- `project-reset --keep-auth`: retain project auth.
- Refuse reset when an active/unrecovered projection depends on the target.
- Display all exact descriptors before destructive execution.

Full removal must include inactive scopes, custom roots, rollback copies, and recovery projections—not merely the currently effective auth identity. External provider-file keys require a separately explicit target.

# 10. Backward-compatibility and rollout plan

1. Preserve current registry fallback scopes.
2. Preserve current production volume names.
3. Preserve Codex project-home formulas and root aliases.
4. Preserve Muse’s existing non-auth global home and trust lifecycle.
5. Preserve OpenCode v2 project database and preference lifecycle.
6. Introduce auth configuration/descriptors before enabling migration.
7. Require explicit migration for existing credentials.
8. Keep rollback copies outside native importer paths.
9. Record completed migration and logout tombstones.
10. Reject older images lacking the supervisor/adapter contract, including explicit image overrides; UID/GID compatibility alone is insufficient.
11. Require stopped old clients before migration. Old launchers must not continue writing legacy auth after cutover.
12. Keep code-only uninstall state-preserving.

Legacy compatibility is explicit discovery/import support, not live dual-write or silent fallback.

Remove compatibility only after:

- Supported adapters pass native gates.
- Deployed state has recorded migration or explicit fresh initialization.
- Interrupted transactions are resolved.
- Operators can inventory/remove rollback copies.
- A documented release window has elapsed.
- Removal itself never deletes remaining legacy credentials.

# 11. Risks and open questions

1. **Muse pinned backend and complete auth inventory:** public documentation and repository assumptions do not establish every credential backend/file for `1.4.0-R4161.1`. This is a mandatory adapter qualification gate.
2. **Muse trust filename mismatch:** repository `.trust.json` versus current official `trust.json`; preserve existing files until the pinned behavior is observed.
3. **Additional Codex/Muse MCP credential stores:** provider auth is established; exact complete supported credential membership needs native qualification before claiming all auth is managed.
4. **OpenCode account-table activity:** token-bearing schemas are known, but their active use in the pinned application needs fixture/native verification. Unknown auth-bearing schema cannot be silently ignored.
5. **Serialization cost:** global auth initially permits one active run per harness/user. Removing that restriction requires proven cross-process refresh coordination or a client-supported independent auth backend.
6. **Native write interruption:** Codex writes its file directly; killing it during a write may corrupt the projection. Box can preserve the previous canonical revision and refuse stale reuse, but cannot guarantee recovery of a remotely rotated token never durably written by the client.
7. **OAuth copying:** separate copied stores may share a single-use refresh-token lineage. Independent project login is the reliable way to obtain independent sessions.
8. **Filesystem/runtime locking:** host/container lock behavior and crash recovery need validation under both supported runtimes and supported local filesystems. Do not promise network-filesystem support without evidence.
9. **Account-dependent acceptance:** real refresh, logout, model/resume, account policy, ARM64, and remote CI remain unverified by this planning investigation.

# 12. Definition of done

Implementation is complete only when:

- Every harness declares auth scope through registry/configuration.
- One resolver produces production/test auth identities and locations.
- No shared library selects auth policy by harness-name conditionals.
- Common and per-harness policy resolve with the documented precedence.
- Every supplied invalid value fails before state access or mutation.
- Global auth is separated by harness and host UID.
- Project auth uses existing physical-workspace semantics.
- Auth scope changes leave unrelated persistence scope unchanged.
- Native logout and refresh update the selected canonical identity.
- Mixed-store adapters export only verified auth material.
- Account/provider selection retains its existing non-auth scope.
- Active leases prevent concurrent writers and unsafe deletion.
- Interrupted runs recover before stale credentials can be restored.
- Scope switching never silently copies, merges, overwrites, or deletes credentials.
- Migration preserves its source until destination verification succeeds.
- Reset/uninstall/capture/native cleanup use exact resolver descriptors.
- No destructive operation relies on globs or loose prefixes.
- Disposable execution never reads, mounts, migrates, imports, or removes production auth.
- Dry-run reports non-secret policy/location metadata without auth inspection or side effects.
- Installed operation, both scopes, all three harnesses, and both runtimes have passing lifecycle coverage.
- Generated/static checks pass; account-dependent and architecture gates are accurately recorded.
- Documentation describes defaults, precedence, storage, serialization, transitions, recovery, logout, reset, and uninstall consistently.
