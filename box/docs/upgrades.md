# Upgrades

### 12. Pin synchronization, templates, and policy

The authoritative pins are `harnesses/<id>/version-<id>.env`, parsed only through
`lib/pins.sh`. Setup preserves installed pins; updating a template does not
update an installed image or apply new preferences to an existing native home.
Run update and sync operations serially; rollback covers detected failures, not power loss or
concurrent writes.

```bash
make -C box update-check
make -C box update
bash box/update-pins.sh --check --only codex
bash box/update-pins.sh --only codex --codex 0.160.0
```

Existing `--muse VERSION` and `--opencode VERSION` flags remain available.
`--only <id>` excludes all other fetches and leaves their pins unchanged;
combining it with another harness's version flag fails before fetching.
`--check` validates candidates but changes no bundle or installed pins.
`--pins-only` writes bundle pins and regenerates without building/synchronizing.
Muse uses channel manifests; Codex uses stable official complete musl packages
and checks both downloaded archives against published digests and their
companion layout. OpenCode has no latest channel: pass an explicit `--opencode
VERSION` (digests are fetched from `https://opencode.ai/files/bin` for both
glibc archives, hash-checked before use). Environment seed seams are for
controlled tests; they do not certify artifacts or runtime behavior.

Every pin participates in change detection. Candidates pass the strict parser
before writes. Generation/consistency failure restores pin files, generated
verifiers, and the architecture table. Build failure after those checks leaves
new bundle pins in place and installed pins unchanged. An unchanged subsequent
update does not retry a failed build: use the recovery sequence explicitly.

```bash
bash box/gen-verify.sh
bash box/gen-pins.sh
make -C box verify-static
make -C box pins
make -C box build-c                  # select the affected harness
```

After a successful build, validate the corresponding image and atomically
synchronize installed pins (choose the affected launcher suffix):

```bash
make -C box sync-pins-c
```

The command requires an existing safe installed config directory. It accepts
missing or obsolete installed pins, stages and parses bundled pins, and checks
image UID/GID, version, and every integrity label before replacement. Identical
bytes remain unchanged after validation. Use no image override for acceptance.

New volume roots are user-owned mode 700. Existing named volumes retain their
metadata across rebuilds: inspect `/persist` owner/mode through the selected
wrapper shell, stop other dependent containers, and explicitly set mode 700 on
the exact volume if it is owned by you. A wrong owner requires separate reviewed
recovery; do not reset authentication/transcripts just to correct metadata.

All builds use `make build-<stem>`; never hand-run `docker build`.
Regeneration comes only from authoritative partials/assets. Static checks cannot
establish native enforcement, account compatibility, or architecture support.
Rerun the package acceptance probes and explicit runtimes on every policy or
release change. See [acceptance](acceptance.md) for remaining gates.
On every Muse pin bump, re-validate the template top-level keys against the
new binary: with the template as `~/.config/muse/settings.json`, run
`muse exec --provider echo --disable-sandbox <prompt>` and require zero
`tbh: ignoring unknown top-level member` warnings (1.4.0 accepts
`endpoint_transport.base_url`, rejects `$schema`/`api`/`approval_mode`/
`approval_judge`, and keeps approval CLI-only; `validate.sh` rejects the
retired keys).

### Mandatory upstream updates

Pins are a supply-chain freeze, not an exemption. When upstream mandates an
update, run `update-check` → `update` → `gen-verify.sh`/`gen-pins.sh` →
`verify-static` + `pins` → `build-<stem>` → `sync-pins-<stem>` promptly;
continued use of old pins after a mandate is out of scope. Automatic update
checks are disabled for reproducible builds only: `MUSE_NO_AUTO_UPDATE=1`,
`OPENCODE_DISABLE_AUTOUPDATE=1` plus `"update": "disable"`, and
`check_for_update_on_startup = false` (Codex defaults plus image policy).

Template refresh: edit the package config, run generators/checks, then rerun
setup. Setup refreshes installed templates with a single `.bak` backup.
All harnesses read refreshed defaults on the next launch, including existing
projects. Auth, trust, sessions and databases remain persistent. Legacy preference
files receive protected `.box-legacy` backups; keep durable preferences in installed
defaults or recognized directory configs. UI saves do not take precedence on later
launches. Migrate custom preferences from backups deliberately after review.
Managed-policy changes require rebuilding the image; refreshing a host template
alone does not change image-owned requirements (Codex; OpenCode v2 ships no
image policy).

### Auth-scope rollout

Changing auth scope selects a different canonical identity; setup and policy
changes never migrate login material. First live launch after upgrade refuses
when legacy credentials exist without a completed migration record — run
`make -C box state-plan` to inspect the selected identity, then `auth-migrate`
(legacy → selected identity, journaled with rollback), `auth-copy` (explicit
source → destination, no merge/overwrite), `auth-init` (fresh acknowledgment),
or `auth-recover` (interrupted lease/projection). Scope changes need
`BOX_AUTH_TRANSITION=fresh|use-existing` or explicit copy. Compatibility is
explicit discovery/import support, not dual-write; removal of legacy paths
never deletes remaining legacy credentials and requires recorded migration,
resolved transactions, inventoried rollback copies, and an elapsed release
window. Copied OAuth tokens may share refresh lineage: prefer fresh login for
independent accounts.

OpenCode v2 uses three SHA256 pins for standalone glibc archives; there is no
Node/NodeSource contract. Debian upgrades update the single manifest
list digest and `# pin-date:` in Dockerfile, regenerate the table, and rebuild
all harnesses. Preserve the architecture and authenticated acceptance limits.

Upstream v2 is shipped (2.0.6, standalone, native v2 config). Native checks use
the production image and installed launcher via `make -C box verify-native-opencode`.
Real amd64 runsc login/model/resume remain account gates. Ordered permissions
retain approval defaults and exception order; they do not enforce universal
prompting. Installed pins synchronize explicitly, never through setup preservation.

### OpenCode v2 installed-pin recovery

Setup validates existing installed pins before any configuration refresh, backup,
launcher replacement or metadata write. Obsolete npm/NodeSource pin files fail
this guard. Build the bundled v2 image first with `make -C box build-o`, then
run `make -C box sync-pins-o`, then rerun `make -C box setup`.
Check `"$HOME/.local/bin/box-o" --dry-run` and `--version`, then run
`make -C box verify-native-opencode` for both supported runtimes.
Valid differing v2 pins remain preserved. Legacy project volumes are never reused:
v2 uses `box-o-v2-u<uid>-g<gid>-<physical-path-hash>`. Review old state explicitly;
there is no automatic credential or session import and no active v1 rollback path.

Rebuild all selected images after the projection-phase handshake change; launchers
require `org.box.auth-contract=3` even for image overrides. Auth-envelope schema
and production volume/home identities are retained. Register historical native
roots with `state-discover` before `state-remove FULL=1`; interrupted reset/full
removal must complete before state is reused. Code-only uninstall is available
as `make uninstall-code HARNESS=<id>`, with `EXECUTE=1` for execution.
