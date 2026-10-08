# Architecture

See the [harness index](harnesses.md) for native contracts and
[operations](operations.md) for host procedures. Source layout follows the
architecture audit; the audit's old line references describe the pre-migration
working tree, not the current implementation.

### 2. Architecture decision

Rootful Docker Engine with gVisor `runsc`, a UID/GID-matched non-root user,
a writable physical project bind at `/workspace`, and a project-specific named
volume at `/persist` form the outer boundary. Each harness has its own image,
network, config directory, labels, and declared persistent state. No host daemon
socket, broad home mount, host credential directory, or cross-harness state
mount is supplied. Native permission settings are additional controls; their
acceptance must be demonstrated separately. OpenCode ordinary rules supply
configurable approval defaults; custom agent rules and saved approvals may
override asks. Native hard denials are separate from prompting. The former
universal-prompt requirement is superseded; containment remains the boundary.
Shipped OpenCode is v2 (pinned standalone, native v2 config). The
[v2 candidate evaluation](evidence/opencode-v2-evaluation.md) is retained for
reference and remains isolated from shipped v2 state and pins.

The dedicated bridge uses masquerade NAT with inter-container communication
disabled. It provides isolation and egress, not a destination allowlist. Normal
runs probe DNS under `runsc`; a failed probe may select hardened `runc` with a
NOTICE and WARNING. `--runsc` forces gVisor, `--docker-fallback` selects runc,
and `BOX_<stem>_ALLOW_FALLBACK=0` forbids fallback. Shell runs are explicit-only.

### 3. Configuration and package ownership

`lib/tools.sh` declares harness identity, fixed adapter files, source versus
installed pin names, artifact source/format/role/destination/lifecycle/mode/owner/
consumers, state scope/root/override/runtime/mode/reset consequences, auth
class (`auth` exactly once per harness, `non-auth` otherwise), auth-policy
scope, harness auth fallback (`default_scope`: Muse `global`, OpenCode and
Codex `project`), declared native storage adapter, and envelope schema
version, and the
volume-naming `state_prefix` (distinct from the container `network`; OpenCode
uses `box-o` for the network and `box-o-v2` for state). Records
are literal data. Validation rejects escaping paths, symlinked sources, duplicate
destinations, pin keys, and `state_prefix` values, orphan records, missing
build/host/validation consumers, a missing or non-`/persist` canonical
`volume` state, missing/duplicate auth records, bad auth adapters/scopes/
schemas, and orphan auth fields on non-auth states. Source config/policy directories are inventoried recursively.

### 3a. Auth state, policy, and canonical store

Each harness declares exactly one selectable `auth` state (`class=auth`,
`scope=auth-policy`, `kind=bind`, shared protected root `.config/box/auth`
overridden by `BOX_AUTH_ROOT`, runtime `/run/box-auth`, mode 700, reset
`auth-canonical-only`). `lib/state.sh` is the authoritative identity/location
resolver (workspace discovery stays in `lib/launcher.sh`); `lib/auth.sh` owns
policy resolution, canonical objects, leases, bindings, migration gates, and
adapter-backed projection. Shared code dispatches on declared storage
mechanics and registry fields, never on harness names.

Effective scope precedence (highest first): harness runtime scope
(`BOX_M_AUTH_SCOPE`/`BOX_O_AUTH_SCOPE`/`BOX_C_AUTH_SCOPE`, derived from the
registry `git_prefix`), common `BOX_AUTH_SCOPE`, harness scope in
`~/.config/box/state.toml` (or `BOX_STATE_CONFIG`), common
`auth.default_scope` there, then the registry fallback. All supplied values
are validated before resolution, including shadowed ones; set-but-empty,
unknown, wrong-type, unknown-harness/key, and unsupported-schema values fail
closed. `BOX_C_AUTH` selects credential forwarding only, never scope.
Setup seeds the versioned policy file with no scopes and preserves it
byte-for-byte; scope changes select a different identity and never copy or
merge credentials.

The canonical object holds auth material only (`identity.json`,
`credentials.json` versioned envelope with revision + tombstone, `lease.json`,
stable `lock`, plus explicit migration journals/rollback copies). Native
homes/databases keep their existing scopes; the selected object directory
alone mounts at `/run/box-auth`. While idle the canonical store is
authoritative; during an active lease the recorded native projection is
authoritative until collected. One active writer per auth identity (plus the
native projection lock); busy launches fail promptly. Scope changes require
an explicit transition (`BOX_AUTH_TRANSITION=fresh|use-existing` or explicit
`auth-copy`); migration is an explicit journaled `auth-migrate`/`auth-copy`/
`auth-init`/`auth-recover` operation (see operations). Dry-run reports
non-secret policy/location metadata only.

`harnesses/<id>/` owns native assets, launch behavior, upstream resolver,
validator, optional install adapter, and native verification partials. Shared
libraries orchestrate these contracts without branching on harness IDs. Muse
policy merging, directory settings snapshots, login parsing, and inner-sandbox bypass belong to
its package. JSON parsing uses jq; TOML parsing uses Python 3.11+ `tomllib`.
Shape parsing is separate from native semantic and runtime acceptance.

Setup installs public handwritten wrappers, `lib/*.sh`, and package shell
adapters beside them under `~/.local/bin`. Installed launchers resolve their
own physical location and use installed templates/pins; the checkout is not
needed to launch. Source generators/updaters/builds still use the bundle.

Template refresh backs up a differing predecessor to one `.bak`. Installed
pins survive setup reruns. Seed-if-absent preserves even empty live TOML;
Muse settings are generated per launch from live defaults (no seed repair).
The single managed-image
artifact is the Codex requirements policy (root-owned image file, image rebuild
required). See the individual
[harness guides](harnesses.md) for native paths and preference behavior.

### 4. Container definitions and pin table

<!-- pin-table-start -->
All images build from one `Dockerfile` (`--file Dockerfile --target muse|opencode|codex`, targets `base`/`muse`/`opencode`/`codex`) on `debian:trixie-slim` pinned to the manifest-list digest below (re-pin on every Debian point release; `check-pins.sh` asserts the single base digest matches this pin table) with Git, Bash, C/C++ toolchains, `fd`/`rg`/`jq`, an explicit `HOME=/home/box`, system-first `PATH` (writable `~/.local/bin` last), harness-specific persistent state at `/persist`, and a UID/GID-matched `box` user. The `base` target holds only common apt + user + common `ENV` (`XDG_CONFIG_HOME`/`XDG_CACHE_HOME`/`HOME`/`PATH`/`SHELL`); each tool target owns its extra packages, dirs/symlinks/seeds, state environment, auto-update opt-out, labels, and `ENTRYPOINT`. All `ARG`s (including `HOST_UID`/`HOST_GID`) have no defaults so bare builds fail closed. The single pin source is the version files (`lib/pins.sh` threads them into `setup.sh`, `check-pins.sh`, and `lib/build.sh`, which the `Makefile` delegates to); this table is generated by `gen-pins.sh` from the version files + Dockerfile and is verified by `make pin-check` + `make verify-pins-generated`.

| Pin (single source) | Value (`check-pins.sh` verifies) |
|---|---|
| Debian base digest | `sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132` (2026-09-06) |
| Muse `MUSE_VERSION` (`version-muse.env`) | `1.4.0-R4161.1` |
| OpenCode `OPENCODE_VERSION` (`version-opencode.env`) | `2.0.6` |
| Codex `CODEX_VERSION` (`version-codex.env`) | `0.160.0` |
<!-- pin-table-end -->

The table records supply-chain pins, not authentication or architecture
acceptance. Pin table is a supply-chain freeze; see upgrades for the
mandatory-update obligation. Authoritative pin files live in `harnesses/<id>/version-<id>.env`;
installed basenames remain unchanged. `lib/pins.sh` is the bundle-threading
home; installed launchers parse installed pin files with the same strict
`box_load_version_file` parser (installed-layout exception, no bundle needed). Every stage declares and consumes its own pins. Muse verifies the raw
binary SHA-256. OpenCode installs its executable from hash-verified standalone
glibc archives (x64-baseline/arm64) without npm, NodeSource, or a second
installation fetch. Codex verifies the
complete musl package and retains companion executables/resources. Builds and
readiness check exact normalized binary versions; labels are checked at launch.

### 7. Launchers and shared preflight

Wrappers use privileged Bash mode and a fixed system PATH. Project identity is
`pwd -P` hashed with SHA-256, first 20 hex characters; production volume naming
remains `<state-prefix>-u<uid>-g<gid>-<hash>` (registry `state_prefix`, not the
container network). Moves and UID/GID changes produce new identities. Test runs
resolve disposable `box-test-<ns>-` identities only through `lib/test-state.sh`,
never inline. Git identity resolves each field independently: selected harness prefix, other
registered prefixes in registry order, then global Git config. Explicit invalid
identity fails; invalid inferred identity counts as unavailable.

Preflight rejects system paths, the entire home, projects containing the home,
credential/config/install/state roots in either containment direction, host IPC,
and external Git metadata. Project symlinks are checked at the first 500 links;
truncation warns. This is bounded hygiene, not the container boundary. Custom
protected roots and their physical targets participate in the same checks.
Persistent preparation validates every existing ancestor for symlinks, owner,
unsafe write bits, and project overlap before mkdir/chmod. Root-owned sticky
scaffolding such as `/tmp` is allowed for state, but `/tmp` projects are denied.
Checks remain subject to host-side check/use races; do not concurrently replace
parents or expose state to other users.

`--dry-run` plans and validates without changing templates, persistent homes,
settings, modes, or Docker CLI state and without daemon contact. It does not
read credential values. Live CLI isolation pins the local socket, removes
Docker/build/proxy overrides, and writes `{}` atomically with a protected backup.
Provider files must be outside the project, user-owned, mode 600 or 400; literal
LF-only keys are allowlisted, duplicates/empty/unknown keys fail, and values are
forwarded only as `--env NAME`. Native cache checks inspect owner/mode/type
without contents and fail on unsafe caches rather than silently repairing them.

### 10. Isolation model and limits

All wrappers use `--cap-drop=ALL`, `no-new-privileges`, read-only rootfs,
nonrecursive private project/state binds, independent networks, and
8g RAM, 4 CPUs, 512 PIDs. Shared writable tmpfs paths are `/tmp`, `/var/tmp`,
`/run`, and `~/.cache`; harness-specific mounts
are declared in their launch adapters. OpenCode uses a writable persistent volume
config parent `/persist/config/opencode` with its host config file mounted
read-only and `XDG_CONFIG_HOME=/persist/config`. Its launcher adapter derives
`box-o-v2-u<uid>-g<gid>-<physical-path-hash>` volume identity from the registry
`state_prefix`; legacy `box-o`
volumes are left untouched. Data and state roots remain unchanged. Native v2
credentials/sessions/saved approvals use `/persist/data/opencode/opencode/opencode.db`;
the guarded entrypoint checks database/journal metadata and uses umask 077 in
ordinary and shell runs. Client preferences are reset under a volume lock on each launch; legacy preferences are backed up once.

The agent can change or delete mounted project files, use credentials available
inside its process, and exfiltrate over permitted egress. Native approval is
not a guarantee that every destructive command asks. The generated verifier
checks effective capabilities and NoNewPrivs. Nonzero bounding capabilities
are warnings only under runsc; runc requires an empty bounding set. Successful
inner bwrap/unshare probes warn rather than establish an escape. Both runtimes
must be tested separately, without automatic substitution in acceptance runs.

Rootless/userns remapping, stable project IDs, an egress broker, SBOM/signature
work, and broad runtime minimization remain separate projects.

## Live defaults and directory inheritance

Setup installs defaults independently of the checkout. Every launch reads the
latest installed defaults (or `BOX_M_CONFIG`, `BOX_O_CONFIG`, `BOX_C_CONFIG`).
Git discovery ignores inherited Git controls and finds the nearest root. An
explicit `--project-root PATH` selects an ancestor for non-Git trees. The whole
root mounts at `/workspace`; the client starts in the corresponding subdirectory.
Preflight checks apply to the mounted tree. State identity hashes the physical selected workspace root. Subdirectories
share its home and volume; older subdirectory identities remain discoverable
for explicit migration.

Registry `directory_configs` declares recognized locations in precedence order.
Native Codex trust, profiles and project field restrictions remain authoritative;
OpenCode native loaders handle JSONC, relative resources and style precedence.
Muse uses strict data-only JSON merging in its adapter and reapplies protected
settings after merging. Removing a directory override restores inheritance.
Preferences saved in a UI do not override defaults on later launches. Existing
resumed sessions retain native state; configuration governs startup and new
session defaults. Dry-run lists paths and precedence, without contents or writes.

Native state descriptors include optional declarative `leaf` and `volume_prefix`
fields. `leaf` names a project home below its physical-project shard;
`volume_prefix` names an explicitly registered historical volume family.
OpenCode's v1 family is inventoried for explicit removal and is never imported.
Production canonical volume names and auth-envelope schema 1 remain unchanged.

Launch identity hashing/volume naming now call `state.sh`. Live launches retain
non-secret native descriptor/root records under `state-index/native/<harness>`.
Inventory re-resolves those records, including historical physical paths, before
removal. They do not authorize arbitrary paths. A harness lifecycle lock is
shared by live launches/auth operations and exclusive during full removal or
code uninstall; auth/projection locks continue to enforce one writer per identity.

Image contract 2 adds durable `reserved`, `preparing` and `projected` lease
phases. Preparation is recorded before native auth mutation. Dead unused
reservations preserve canonical/legacy bytes; interrupted preparation is
collected before stale canonical credentials may be reused.

Tests may explicitly set `BOX_TEST_PROJECT_HASH` to the resolver's physical
project hash. This selects project-qualified native fixtures inside one test
namespace while retaining one test-global auth identity. Default PR #2 test
volume/home formulas are retained when this selector is unset; empty/malformed
selectors fail closed. All test volume/home/cleanup formulas remain in
`test-state.sh`.
