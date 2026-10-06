# OpenCode harness

[Shared setup and containment](../../docs/operations.md) ·
[Acceptance](../../docs/acceptance.md) · [Harness index](../../docs/harnesses.md)

`box-o` installs the pinned v2 standalone glibc binary (`opencode-linux-x64-baseline`
amd64, `opencode-linux-arm64` arm64) from `https://opencode.ai/files/bin`, verified
by SHA256 before extraction. `version-opencode.env` holds exactly three pins:
`OPENCODE_VERSION`, `OPENCODE_SHA256_AMD64`, `OPENCODE_SHA256_ARM64`. Build with
`make -C box build-o`. No npm, NodeSource, or Node.js is used; the image installs
Python for the native probe. The [host config](config/opencode.json) is native v2:
`$schema`, `default_agent: plan`, `update: disable`, and an ordered `permissions`
array (`* allow` first, then `read`/`edit` `*.env`/`*.env.*` ask, `*.env.example`
allow, `external_directory *` ask last; last-match-wins). No `lsp`, no singular
`permission`, `shell` (not `bash`), `edit` (not `write`/`patch`). No model/provider
is seeded and no provider key is forwarded.

Docker/gVisor containment is the access boundary. Ordinary permissions are
configurable approval defaults: permissive custom agents, project overrides, and
session `--auto`/saved approvals may allow asks according to upstream behavior;
deny always wins and saved approvals never override deny. No experimental deny
policy is shipped. The historical v1 universal-prompt matrix is retained in the
acceptance record, with its former requirement superseded. Project features remain
available. v2 does not run language servers: use project compiler, lint, and
typecheck commands, as described in the
[upstream migration guide](https://opencode.ai/v2/docs/migrate-v1/).
See [permissions](https://opencode.ai/v2/docs/permissions),
[providers](https://opencode.ai/v2/docs/providers), and
[config](https://opencode.ai/v2/docs/config).

Setup refreshes the live host file at `~/.config/box-o/opencode.json`, with one
`.bak` for a differing predecessor. It is mounted read-only under a writable
volume parent at `/persist/config/opencode` with `XDG_CONFIG_HOME=/persist/config`; the parent persists for native resources. Saved global `cli.json`, `tui.json`, and `opencode.jsonc`
preferences are backed up once as protected `.box-legacy` files and removed before
each client run, under a volume lock. SQLite auth, sessions and approvals remain.
`BOX_O_CONFIG` replaces the installed default immediately. Native discovery merges
direct `opencode.json(c)` from root to launch directory, then `.opencode` configs
in the same order; every `.opencode` config outranks every direct config. Relative
resources remain beside their source configs.
Review and migrate preferences from the backup rather than blindly restoring
obsolete v1 values. There is no image-owned policy; ordinary permissions are
host defaults, not containment. Never open converted v2 state with v1.

Start `box-o`, then use native `/connect`, or the native auth command. The pinned v2 binary stores credentials, sessions and saved approvals in
`/persist/data/opencode/opencode/opencode.db` on the physical project's volume.
`opencode debug paths` confirms the app-suffixed native data/state directories.
The database and its `-wal`/`-shm` journals must be regular, user-owned,
writable and mode 600, with symlink-free parents. Both ordinary and shell runs
use the guarded image entrypoint with umask 077; unsafe existing stores fail
without silent repair. Never dump database contents to diagnose login. An empty
protected shared provider file is sufficient. Login/model acceptance requires a
real provider account; a nonempty cache alone is not evidence of valid auth.

Use `box-o auth logout` for native logout. A project-volume reset removes that
project's provider login, sessions, state, saved approvals, and client preferences. Host config deletion resets the shipped template but does not remove volume auth. Full uninstall handles
both explicitly; `validation/resolved-config.json` is redacted source inspection, not permission
enforcement or authenticated evidence. `validation/REPORT.txt` remains historical.

OpenCode v2 volumes are named `box-o-v2-u<uid>-g<gid>-<physical-path-hash>`.
Legacy `box-o-u...` volumes are left untouched and never imported automatically.
Reset only the selected v2 volume after stopping dependent containers; keep or
remove legacy volumes separately after reviewing their contents. Moves and
UID/GID changes create fresh identities; physical symlink aliases share state.

Run `make -C box verify-native-opencode` after `make -C box build-o` for
account-independent production checks. Readiness inspects native source records
and credential hygiene; a nonempty cache alone cannot certify model/resume.
Pin update: see [upgrades §12](../../docs/upgrades.md) (`update-check` →
`update` → `gen-verify.sh`/`gen-pins.sh` → `verify-static` + `pins` →
`build-o` → `sync-pins-o`). OpenCode v2 ships no image policy.
