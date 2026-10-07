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
consumers. Git is optional but recommended (repository-root discovery, identity
inference); without it, launch from the project root or pass `--project-root`.
JSON launchers retain their existing prerequisites; they do not load
Python during launch. Static verification also requires ShellCheck and Bats.
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

### 9. Daily usage and persistence

Run from a physical project directory, not the entire home or a parent
containing state/config/credentials. The nearest Git root (or explicit
`--project-root`) mounts at `/workspace`; the client starts in the launch
subdirectory. External Git worktrees fail preflight. Symlink aliases of a
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
Normal native runs may automatically fall back after failed runsc DNS/startup
probes with NOTICE/WARNING. Set `BOX_<stem>_ALLOW_FALLBACK=0` to forbid it;
acceptance runs explicitly select their runtime. Shell runs never auto-select.
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
| Muse global host bind | Auth/settings/trust across projects and restarts |
| OpenCode `box-o-v2` project named volume | `/persist/config/opencode` client preferences plus SQLite credentials/saved approvals and existing data/state for that physical project; legacy `box-o` volumes untouched |
| Codex project host home | Preferences/file auth/sessions/history/logs |
| Codex project named volume | SQLite runtime state |
| Shared `/home/box/.cache` tmpfs and other tmpfs siblings | Discarded when container exits |

Do not place native caches in the project. No host native auth is automatically
imported. Template refresh, logout, volume reset, host-home reset, and uninstall
have different consequences; they are not interchangeable.

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
project's volumes or custom roots. From the project, derive its production
volume/home identity without accessing secrets (test runs use disposable
`box-test-<ns>-` identities via `lib/test-state.sh`, never this formula):

```bash
BOX_TOOL=inventory bash -c '
  source /path/to/box/lib/tools.sh
  project=$(pwd -P)
  hash=$(printf "%s" "$project" | sha256sum); hash=${hash:0:20}
  for id in $box_tool_ids; do
    prefix=$(box_tool_field "$id" state_prefix)
    printf "%s volume: %s-u%s-g%s-%s\n" "$id" "$prefix" "$(id -u)" "$(id -g)" "$hash"
  done
  printf "Codex home: %s/%s/codex-home\n" "${BOX_C_STATE_ROOT:-${BOX_C_STATE_DIR:-$HOME/.config/box-c/projects}}" "$hash"
  printf "Muse global home: %s\n" "${BOX_M_PERSIST_DIR:-$HOME/.config/box-m/muse-config}"
'
```

Copy the exact confirmed volume name into `docker ps -a --filter volume=NAME`
and `docker volume inspect NAME`. After dependent containers are stopped and
removed, `docker volume rm NAME` removes only that volume. Inventory the host
home using metadata and filenames; never print cache contents.

- Muse project reset removes project volume state, retaining global auth,
  settings and trust. Explicit global-home removal affects every project.
- OpenCode project reset removes provider login, sessions, saved approvals, native
  state and client preferences on the exact `box-o-v2` volume; legacy `box-o`
  volumes remain untouched.
  host config is separate. Native logout can clear login without resetting it.
- Codex project reset requires both its exact host home and volume. Removing
  only the volume retains auth/transcripts; removing only the home retains
  SQLite state. Native logout clears that project's cached auth, retaining
  other home state; provider-file keys remain until separately removed.
- Defaults reset refreshes/replaces templates and explicitly selected preference
  files after backup; it does not require deleting authentication/transcripts.

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
