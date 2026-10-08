# Operations

[Harness index](harnesses.md) · [Architecture](architecture.md) ·
[Upgrades](upgrades.md) · [Acceptance](acceptance.md)

### 5. Host prerequisites

Linux, rootful Docker Engine >= 25, registered `runsc` and `runc`, and a normal
non-root host UID/GID are required. Install Docker and gVisor from their official
instructions; verify `docker version`, `docker info`, and `runsc --version`.
Rootless/userns remapping and macOS hosts are not covered by this mapping design.
Native ARM64 runtime support remains unaccepted until tested on that architecture.

Host tools: Bash, coreutils, findutils, util-linux (`flock`), jq, curl, and Python 3.11+ for TOML
and project hardlink inspection. Git is optional but recommended (repository-root discovery, identity
inference); without it, launch from the project root or pass `--project-root`.
All launchers inspect project inode links with isolated Python before mounting. Static verification also requires ShellCheck, Bats and ripgrep.
On Debian install validation packages with the package manager; verify Python
with `python3 -c 'import tomllib'`. The root GitHub workflow installs these tools
and invokes the same Make gates.

### 6. Image builds

```bash
make -C box build
make -C box build-m
make -C box build-o
make -C box build-c
```

Only Make builds images, through `lib/build.sh`. Pins come from packages via
`lib/pins.sh`. Tags include exact version and `-u<uid>-g<gid>`; build verifies
labels/user and exact binary version. `make clean` removes current pinned
images for your UID/GID, retaining volumes, host state, configs, and networks;
older-version images need explicit inventory/removal. No native account is
needed to build. Tags include the exact version plus `-u<uid>-g<gid>` and
are local only. Never `docker push`, save, or export built images.
A build pass does not establish login or permission acceptance.

### 8. Setup and migration

Concurrent setup runs for the same home directory wait for one another before
planning or changing installed files. The home directory itself is locked;
no lock file is created, and the lock is released when setup exits.

```bash
make -C box setup
bash box/setup.sh --only codex
bash box/setup.sh --skip-build
bash box/setup.sh --default codex --skip-build
export PATH="$HOME/.local/bin:$PATH"
```

Setup installs all templates/pins/wrappers/packages, isolates CLI configs,
creates/verifies all dedicated bridge networks, checks registered runtimes, and
builds all images unless selected/skipped. `--only` selects the build, not a
partial launcher installation. Reruns preserve differing installed pins and the
existing registered `box` symlink; a fresh install defaults to Muse. Templates
refresh with one `.bak`, while existing live Muse/Codex settings/auth remain.
OpenCode's live host config refreshes with backup. Authentication, build status,
and native verification are reported separately.

Installed files are wrappers and `box-m-login`, `lib/*.sh`, package shell code
under `~/.local/bin/harnesses/<id>`, and configs/pins under registered
`~/.config/box-*` directories. Source paths may move inside packages without
changing installed leaf names. Installed commands run without the checkout.
Generators/builds/updaters remain bundle tools. See native guides for template
adoption and preference migration; do not restore an entire stale template over
new native policy.

Setup validates source records, configuration and native structural assertions,
and planned destinations before writes. Persistent parents must be symlink-free,
owned by you or root, and not group/other-writable (root sticky scaffolding is
allowed). Auth caches fail on unsafe owner/mode without content diagnostics or
silent repair. Custom state roots must remain outside projects in both
containment directions. Fix path metadata deliberately after identifying the
actual intended location; do not weaken checks to get setup to run. If setup
names a writable ancestor, use the diagnostic and conditional repair in the
[troubleshooting guide](troubleshooting.md#setup-rejects-a-writable-config-ancestor).

Pre-rename installations used `muse-sandbox`, `opencode-sandbox`, `muse-login`
and `sb-m`, `sb-o`, `sb-m-login`. Setup removes those old executable names but
never migrates secrets, native caches, or transcripts. Inventory old config
roots/images/networks/volumes, stop dependent containers, and explicitly transfer
only reviewed preferences or credentials to the intended protected store. Keep
old state until its replacement is validated; no path-based auto migration is
supported. Old v1 npm/NodeSource OpenCode installs must explicitly sync to the
current three-pin file before rerunning setup. Setup rejects incompatible installed pins during read-only planning; valid differing v2 pins are preserved.

Explicit image overrides must match the installed native-version and artifact
pins, UID/GID and auth contract. A different image tag cannot bypass these
checks. Use the pin update and image sync procedures for client upgrades.

### 9. Daily usage and persistence

Run from a physical project directory, not the entire home or a parent
containing state/config/credentials. The nearest Git root (or explicit
`--project-root`) mounts at `/workspace`; the client starts in the launch
subdirectory. External Git worktrees fail preflight. Regular-file hardlinks
must have every alias inside the selected project; use an independent copy
or `git clone --no-hardlinks` for externally linked trees. Unreadable or
changing hardlink inventories and nested mounts refuse. Inspection is bounded
to one million entries and 256 directory levels and does not read file bytes. Symlink aliases of a
launch directory use the same physical-path hash; moves
and UID/GID changes create new volume/home identities. Link-heavy trees
(for example JavaScript `node_modules/.bin`) may exceed the 500-symlink
preflight scan cap; truncation warns and continues (see architecture §7).

```bash
box-c --dry-run
box-c --runsc --version
box-c --runsc --shell -c 'id; codex --version'
box-c --docker-fallback --shell -c 'id'
```

Substitute the chosen wrapper. Launcher flags precede `--shell`; after it,
arguments go to Bash. `--dry-run` is read-only, does not contact the daemon,
does not read key values, and leaves homes/templates/settings/CLI state
untouched. It validates shape and paths, not authentication or runtime health.
Normal native runs use runsc and refuse after failed runsc DNS/startup probes.
Only `--docker-fallback` selects runc; `BOX_<stem>_ALLOW_FALLBACK=0` forbids
that explicit choice. Shell runs skip DNS probes.
DNS probes have the same memory/swap, CPU and PID ceilings as sessions. Their
30-second timeout has a two-second kill grace; cleanup removes only the ID
recorded by that probe. INT/TERM/HUP cancellation does not start a fallback.
Cleanup is best-effort if the daemon becomes unavailable or the host/wrapper
is killed with SIGKILL; a cleanup warning names the exact container to inspect.

Git identity uses selected `BOX_M`, `BOX_O`, or `BOX_C` prefix per field, then
other registered prefixes in order, then global Git config. Launchers do not
use repo-local identity. Set `BOX_<stem>_GIT_NAME` and `_GIT_EMAIL` to pin it.
Opt-in `_EXTRA_GIDS` must be numeric, nonzero; host groups are not inherited.

The shared `~/.config/box/providers.env` is user-owned, mode 600 (400 accepted),
outside projects, literal LF-only allowlisted `KEY=value` lines. Unknown,
duplicate, empty-valued, or CRLF entries fail; file contents are never sourced.
An empty protected file is valid for keyless native login. Muse forwards its
Meta key; OpenCode forwards none; Codex imports/forwards its OpenAI key only
through explicit API-login/API-mode selection. Inherited keys are cleared.
See [Muse](../harnesses/muse/README.md),
[OpenCode](../harnesses/opencode/README.md), and
[Codex](../harnesses/codex/README.md) for native login/logout and model behavior.

| State | Lifetime |
|---|---|
| Installed templates/pins | Until explicit refresh/sync/uninstall |
| Canonical auth objects (`~/.config/box/auth/<harness>/u<uid>/[global\|projects/<hash>]`, override `BOX_AUTH_ROOT`) | Selected auth identity per scope; retained across restarts, setup reruns, and uninstall-code-only; removed only by explicit exact-identity removal |
| Muse native config home (non-auth) | Settings snapshot source/trust across projects and restarts; `auth.json` inside is a temporary projection only |
| OpenCode `box-o-v2` project named volume | `/persist/config/opencode` client preferences plus sessions/saved approvals and existing data/state for that physical project; credential rows are temporary projections only; legacy `box-o` volumes untouched |
| Codex project host home (non-auth) | Preferences/trust/transcripts/sessions/history/logs; `auth.json` inside is a temporary projection only |
| Codex project named volume | SQLite runtime state |
| Shared `/home/box/.cache` tmpfs and other tmpfs siblings | Discarded when container exits |

Do not place native caches in the project. No host native auth is automatically
imported. Template refresh, logout, volume reset, host-home reset, and uninstall
have different consequences; they are not interchangeable.

### 9a. Auth scope, migration, and lifecycle tools

Auth scope is configurable per harness with documented precedence: harness
runtime scope (`BOX_M_AUTH_SCOPE`/`BOX_O_AUTH_SCOPE`/`BOX_C_AUTH_SCOPE`),
common `BOX_AUTH_SCOPE`, harness scope in `~/.config/box/state.toml` (or
`BOX_STATE_CONFIG`), common `auth.default_scope` there, then the registry
fallback (Muse `global`, OpenCode/Codex `project`). Setup seeds the policy
file with no scopes and preserves it; changing policy selects a different
identity and never copies credentials. `BOX_C_AUTH` selects credential
forwarding only, never scope. Dry-run reports execution domain, effective
scope, policy source, canonical auth directory, native projection,
migration/transition requirements and legacy candidate coordinates, and
unchanged non-auth identities without reading credentials, opening
databases, taking locks, or contacting Docker.

First launch after upgrade refuses to run when legacy credentials exist
without a completed migration record. Operate explicitly (backed by the same
resolver; inspection stays in launcher dry-run):

```bash
make -C box state-plan HARNESS=<id> PROJECT=<path>
make -C box auth-migrate HARNESS=<id> PROJECT=<path> [DB_PATH=<file>]
make -C box auth-copy HARNESS=<id> SRC_SCOPE=<s> [SRC_HASH=<h>] DST_SCOPE=<s> [DST_HASH=<h>] [PROJECT=<path>]
make -C box auth-init HARNESS=<id> PROJECT=<path>
make -C box auth-recover HARNESS=<id> PROJECT=<path> [NATIVE=<file>] [DB_PATH=<file>]
make -C box state-remove HARNESS=<id> PROJECT=<path> [EXECUTE=1]
# Full canonical auth inventory for this harness/user, including historical roots:
make -C box state-remove HARNESS=<id> PROJECT=<path> ALL_PROJECTS=1 INCLUDE_GLOBAL=1
# Add AUTH_ROOT=/absolute/old/root for a root used before discovery was recorded.
make -C box project-reset HARNESS=<id> PROJECT=<path> [KEEP_AUTH=1] [EXECUTE=1]
```

`auth-migrate` journals `planned → staged → destination-committed →
verified → source-retired → complete`, preserves the source until
verification, keeps a protected rollback copy, and retires legacy auth from
its importer path. Scope changes need `BOX_AUTH_TRANSITION=fresh|use-existing`
or an explicit copy with `PROJECT=<physical-path>`; this acknowledges that
project only after successful copying, with the destination scope selected by
the current policy. Copies without `PROJECT` transfer credentials and leave
project acknowledgments unchanged. Nothing is merged or overwritten implicitly. Copied OAuth
tokens may share a single-use refresh lineage: prefer fresh login for
independent long-lived accounts. Native logout updates the selected canonical
identity (one account only for OpenCode); refresh is collected on exit.
Interrupted runs keep the projection authoritative until `auth-recover`
collects it; missing projections are errors, never stale-restore permission.
Concurrent launches on one auth identity fail promptly (one active writer).

Large dependency trees and builds should use disk-backed project directories
under `/workspace`, with `TMPDIR`/package-cache overrides there when supported.
Confirm the host filesystem is disk-backed: binding a directory from host tmpfs
still consumes memory. `/tmp`, `/var/tmp`, `/run` and `~/.cache` consume the
session's shared 8 GiB budget alongside processes and shared memory; equal
memory/swap limits disable container swap. Individual tmpfs capacity is not
reserved memory or a shared aggregate allowance. Cross-filesystem `mv` copies
bytes before deleting the source and can exhaust that budget. On failure,
verify source and destination integrity before retrying; partial files may exist.
Project-local caches persist and need deliberate disk cleanup. See the
[measured comparison and policy limits](security-resource-audit.md#3-incident-reassessment).

### 11. Verification

```bash
make -C box verify-static
make -C box pins
cd ~/projects/disposable-check
box-m --runsc --shell -s -- README.md < /path/to/box/verify-muse.sh
box-o --runsc --shell -s -- README.md < /path/to/box/verify-opencode.sh
box-c --runsc --shell -s -- README.md < /path/to/box/verify-codex.sh
```

Pass an existing project file. Optional second argument is a project test
command, executed only after containment gates. Never supply unreviewed project
code to verification. Repeat explicitly with `--docker-fallback` and record its
result separately. Outputs are generated from shared/package partials and
embedded helpers; edit sources then run `gen-verify.sh`, never edit outputs.

`make -C box verify-native` runs the disposable unauthenticated evidence driver
under explicit runsc and runc, cleans up its own project volumes/homes, and
returns failure while any native/account gate is unmet. It is separate from CI
static checks.

Run `make -C box build-o` then `make -C box verify-native-opencode` for focused
production OpenCode checks under explicit runsc and hardened runc. This uses the
installed launcher and validated SHA256 pins, with disposable per-project state;
it cleans up every fixture container and volume. No archive override or duplicate
candidate image is maintained. A successful focused result covers unauthenticated
policy/state behavior only; real login/model/resume, ARM64 and remote CI are separate.

Static gates cover recursive shell syntax, declared JSON/TOML, structural native
validators, generated-output parity, pins including per-stage consumption,
ShellCheck, and Bats. Bats uses throwaway homes/projects, mocks for selected
updater paths, and optional disposable live networks. If home is read-only,
`BOX_TEST_PROJECT_ROOT` may select a writable legitimate project parent with
safe ancestors; `/tmp` remains denied as a project and checks are never bypassed.

Full native verifiers intentionally fail if login is unavailable, inspection
fails, versions/policy differ, or a required native/account gate is unmet. Codex's
standalone embedded app-server probe creates ephemeral threads without a model
turn and cleans up its process group. Record login, provider/model request,
restart/resume, two-store persistence, architecture, and runtime separately.
Do not treat a config fixture, successful version command, API DNS probe, or
archive digest as authenticated/native architecture evidence. A real GitHub
workflow run is required to close CI discovery; local YAML inspection is not it.
Current results and unmet gates live in [acceptance](acceptance.md).

### 13. Reset and uninstall

First list exact targets and dependent containers. Stop/remove only confirmed
containers using those stores before deletion. Never glob-delete another
project's volumes or custom roots. Use the resolver-backed inventory
(non-secret, exact descriptors; never reconstruct names with inline
hash/prefix shell):

```bash
make -C /path/to/box state-plan HARNESS=<muse|opencode|codex> PROJECT="$PWD"
# Machine-readable descriptors for scripts (no manual hash reconstruction):
BOX_TOOL=inventory BUNDLE_DIR=/path/to/box bash -c '
  source "$BUNDLE_DIR/lib/preflight.sh"
  source "$BUNDLE_DIR/lib/state.sh"
  box_state_context "$1" "$(id -u)" "$(id -g)" "$PWD" production
  box_state_resolve auth
  box_state_resolve volume
' _ <id>
# Dry-run also reports effective auth scope, policy source, canonical auth
# directory, native projection, migration/transition requirements and legacy
# coordinates without credential reads:
box-m --dry-run; box-o --dry-run; box-c --dry-run
```

Copy the exact confirmed volume name into `docker ps -a --filter volume=NAME`
and `docker volume inspect NAME`. After dependent containers are stopped and
removed, `docker volume rm NAME` removes only that volume. Inventory the host
home using metadata and filenames; never print cache contents.

- Muse project reset removes project volume state and the acknowledged project
  auth identity (with `project-reset`, or retain it with `--keep-auth`); global
  auth is never removed by reset. Explicit exact-identity removal affects the
  selected scope only.
- OpenCode project reset removes sessions, saved approvals, native
  state and client preferences on the exact `box-o-v2` volume plus the
  acknowledged project auth identity (unless `--keep-auth`); legacy `box-o`
  volumes remain untouched.
  host config is separate. Native logout updates the selected canonical
  identity (one account) without resetting project state.
- Codex project reset requires both its exact host home and volume. Removing
  only the volume retains transcripts; removing only the home retains
  SQLite state. Native logout updates the selected canonical identity,
  retaining other home state; provider-file keys remain until separately removed.
- Defaults reset refreshes/replaces templates and explicitly selected preference
  files after backup; it does not require deleting authentication/transcripts.

Canonical auth removal discovers recorded historical roots as well as the current
and default roots. `ALL_PROJECTS=1` includes every validated project identity;
`INCLUDE_GLOBAL=1` explicitly includes global auth. Every identity is checked
before deletion starts, and execution holds its stable lock. Protected rollback
copies and completed journals are included. Active leases, pending collection,
incomplete journals, unknown artifacts, foreign identities, and redirected
paths refuse deletion; recover projections first. Root discovery starts when
an auth object is prepared by this version. Earlier unrecorded custom roots
must be supplied with `AUTH_ROOT` (or repeated `--root` in the operational CLI).
The default command removes canonical auth objects; `FULL=1` additionally
inventories and removes the recorded native stores and installation state. Provider files remain a
separately explicit target.

Execution also requires a successful Docker container-liveness query for every
canonical auth bind. Auth locks under `state-index/locks/auth-<digest>.lock`
survive removal so recreation uses the same serialization boundary. Do not
delete these lock files while launchers or lifecycle operations may be running.
Before deleting any auth member, removal publishes protected, durable
`auth-<digest>.lock.removal.json` checkpoints. After an interruption, rerun the
same `state-remove` command with the same harness, project/root and scope flags.
Remaining members must match their recorded inode, mode and byte digest;
changed or unknown members refuse recovery. Launch/init refuse identities with
pending removal checkpoints. The checkpoint contains identity metadata and
digests, without credential values. It is removed after successful auth cleanup.

File adapter publication uses private temporary files and flushes the staged
file and destination directory around replacement. Muse/Codex export, install
and scrub refuse redirected parents, symlink destinations, shared file inodes
and files owned by another user. Unsupported payloads preserve the existing
canonical envelope. Existing reset lock files must be regular, owned by the
invoking user, have one link and mode 600 (400 is accepted for validation);
unsafe locks refuse before auth locks are created or Docker removal starts.
The complete reset checkpoint additionally records native-home members and the
Engine creation identity of its exact volume. Full-removal checkpoints record
the fixed inventory and explicit provider/code choices before deletion.
Both operations re-inspect a surviving volume immediately before deletion and
compare its creation identity with the protected checkpoint. Missing or changed
identity evidence refuses deletion and retains the checkpoint. Docker removes
volumes by name, so this check does not protect against a Docker administrator
replacing the volume between inspection and removal.

Project reset now checkpoints the native home, exact volume creation identity,
and auth-retention choice under `state-index/resets/`. Launchers refuse reuse
until the same reset completes. Resume with the original `KEEP_AUTH` and native
root overrides. Changed home members or a replacement volume refuse recovery.
This covers the implemented deletion boundaries; native execution and power-loss
acceptance still require the runtime gates in the acceptance record.

Full state removal uses the native discovery index and re-resolves every saved
coordinate against the registry. Its read-only preview also resolves the current
project's native stores and installed templates/backups before any discovery
record exists. Live launches record native roots/volumes;
register older roots explicitly before removal. Historical discovery accepts a
removed physical project path only with `HISTORICAL=1`, without recreating it:

```bash
BOX_C_STATE_ROOT=/absolute/old/root make -C /path/to/box state-discover HARNESS=codex PROJECT=/physical/old/project HISTORICAL=1
make -C /path/to/box state-remove HARNESS=codex PROJECT="$PWD" FULL=1
make -C /path/to/box state-remove HARNESS=codex PROJECT="$PWD" FULL=1 EXECUTE=1
make -C /path/to/box uninstall-code HARNESS=codex            # preview
make -C /path/to/box uninstall-code HARNESS=codex EXECUTE=1
```

`FULL=1` includes all recorded native project homes/volumes, the registered
OpenCode v1 legacy volume for each recorded physical project, global native
homes, both auth scopes across discovered custom roots, protected rollback
copies, binding/discovery records, installed templates/pins and their backups.
Legacy v1 credentials are never imported. Unknown historical roots/projects
must be registered explicitly; no prefix or wildcard grants removal authority.
Add `REMOVE_CODE=1` to include the harness's installed code, or
`PROVIDER_FILE=/absolute/external/providers.env` to separately select an external
credential file. Provider contents are never printed. Shared library files are
removed only when no other registered launcher remains. Unlisted bin/lib files
are preserved. Empty parent directories, shared root-discovery metadata,
Docker CLI metadata under the index and permanent lock inodes remain.

Full removal takes an exclusive harness lifecycle lock, validates native
projection locks, container liveness and every file manifest before deletion,
and writes an outer checkpoint under `state-index/removals/`. Rerun the original
command to resume an interruption. A durable completion marker prevents final
checkpoint cleanup from treating newly recreated state as an old target. Use
the repository bundle for recovery if installed code was already removed.
Docker images/networks and unregistered state remain separately explicit
uninstall targets, inventoried as described below.

Lifecycle Make flags (`EXECUTE`, `FULL`, `KEEP_AUTH`, `REMOVE_CODE`,
`INCLUDE_GLOBAL`, `ALL_PROJECTS`, and `HISTORICAL`) accept `1` to enable and
`0` or omission to disable. Other values fail before operational state access.
In particular, `EXECUTE=0` always previews and never authorizes deletion.

For uninstall, inventory registered launcher names/default symlink, package
code directories, shared library files, config/pin/CLI directories, networks,
all image versions for your UID/GID, every project volume, and custom/global
state roots. Use `lib/tools.sh` records as the inventory. Remove only confirmed
files and registered networks/images after dependent containers are gone.
Do not remove the whole `~/.local/bin` or unowned `lib/` files. Explicitly choose
whether to retain provider credentials, Muse global state, OpenCode volumes,
Codex project homes/volumes, template backups, and custom roots. A code-only
uninstall retains those stores; full removal deletes their auth/preferences/
transcripts and cannot be described as a volume-only reset. Leave source and
repository developer configuration separate from installed/native state.

## Live defaults and subdirectory launches

Run from any repository subdirectory. The nearest Git root is mounted and the
client starts in the requested subdirectory. For a non-Git tree use
`box-m --project-root /path/to/tree` (also supported by `box-o` and `box-c`);
the root must contain the physical launch directory. Put launcher flags before
`--shell`. State is keyed to the workspace root: every subdirectory of one
project shares a single volume/home. Subdirectory-keyed volumes/homes from
earlier releases are orphaned by the rekey (same
`<state-prefix>-u<uid>-g<gid>-<hash>` shape, subdirectory hash); inventory `docker
volume ls`, validate the new root-keyed state, then remove the orphans. No
auto-migration is performed.

Edit installed defaults, or refresh them with setup after changing checkout
templates. Every subsequent launch uses the current defaults, including existing
projects. `BOX_M_CONFIG`, `BOX_O_CONFIG`, and `BOX_C_CONFIG` replace this layer.
Put partial directory overrides in `.muse/settings.json`, `.codex/config.toml`,
or native `opencode.json(c)` / `.opencode/opencode.json(c)` files. Inheritance
begins at the mounted root; siblings do not contribute. Codex project settings
require native trust. Muse settings saves against the read-only snapshot are
unsupported. UI preferences do not carry forward to later launches.

Legacy preference backups use `.box-legacy` and mode 600. Do not remove homes
or volumes to refresh preferences: these also contain auth, trust and sessions.
Dry-run reports root, container working directory, selected defaults and
recognized directory configuration paths without mutation.

Reset/discovery control-file operations use directory descriptors, no-follow
opens, bounded reads and fsynced publication. Control JSON reads/publications
are limited to 16 MiB; individual reset members to 256 MiB. Oversized, shared,
redirected or changed members refuse while retaining the existing checkpoint.
File removal records include inode identity, bytes and change time. Older
checkpoints without change-time evidence refuse automatic deletion; retain
them and reconcile their exact members before retrying. These checks do not
protect against a compromised invoking user or host root.

Host Python helpers use isolated imports (`python3 -I`), including TOML parsing
and Codex trust migration. Project modules and inherited Python import settings
do not participate in these helpers.

Launcher cancellation bounds Docker stop to 10 seconds plus a 2-second kill
grace, then gives the Docker client 2 seconds before KILL and reaping. Failed
container stops emit a warning with the container name. `box-m-login` forwards
cancellation to its delegated launcher and waits for cleanup; a 16-second bound
covers that launcher cleanup before forced termination.

Native acceptance captures OpenCode validation into its disposable fixture.
Checkout evidence is refreshed only through the explicit regeneration target.
For a separate capture, `box/regen-validation.sh --output-dir DIR` writes
`resolved-config.json` and `config-stderr.txt` there; `--check` validates without
writing either artifact.

Auth-mutating operations require successful Docker liveness queries even for
disposable namespaces. Unavailable or failing queries refuse migration/copy/
recovery. Image contract `org.box.auth-contract=3` is required, including explicit
image overrides: it adds the reserved/preparing/projected handshake. An unused
reservation can be released without importing its legacy native file; a prepared
projection remains authoritative until collection/recovery succeeds.

### Manual qualification on dedicated CI runners

The `qualify-native` workflow accepts a manually selected amd64 or arm64
platform. It runs only in `temrb/box` on the repository's default branch,
uses the protected `box-native-qualification` environment and requires a
self-hosted runner labeled `linux`, `box-native` and the chosen platform.
Configure environment approval/branch restrictions before attaching a runner
with Docker administrative access. Fork pull requests never trigger this job;
the workflow supplies no reusable account secrets.

Set the environment variable `BOX_QUALIFICATION_ROOT` to an existing user-owned
mode-700 project parent outside the checkout and protected production stores.
Install the documented tools, rootful Engine and runsc on that dedicated host.
A read-only path/tool check is available locally:

```bash
BOX_QUALIFICATION_ROOT=/home/runner/box-qualification \
BOX_QUALIFICATION_PLATFORM=amd64 \
bash -p box/tests/native/ci-qualification.sh --check
```

The runner clears production selectors and provider keys, creates a unique
private home/project/evidence tree, installs into that home, and builds only
through Make targets. Each attempted gate records its exit code and log hash;
gates blocked by installation/build failure are marked `not-reached`. Exact
run coordinates and logs remain on the dedicated runner for review. Native
drivers retain responsibility for their exact Docker cleanup; review reported
failures before retiring the run tree. Local images remain local and are never
uploaded as CI artifacts. Dedicated-account, VM/power-loss and staged rollout
qualification still require their separate drivers and evidence.


The `qualify-disposable` workflow additionally runs account-independent gates on
fresh GitHub-hosted amd64 and ARM64 VMs. Its push trigger is limited to the
qualification branch; manual runs are restricted to the default branch. It
installs the complete signed gVisor APT package using the
[official installation procedure](https://gvisor.dev/docs/user_guide/install/),
records the observed runtime/Engine/platform and immutable image IDs, and
uploads only gate logs/provenance. Images, native stores and credentials are
excluded from artifacts. Skipped required static/live cases fail the gate.
GitHub's [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
describes the separate VMs and architectures. Account and restart/durability
gates still require their own qualified environment; a successful host build
cannot close them.
