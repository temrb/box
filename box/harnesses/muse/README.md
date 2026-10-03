# Muse harness

[Shared setup and containment](../../docs/operations.md) ·
[Acceptance](../../docs/acceptance.md) · [Harness index](../../docs/harnesses.md)

`box-m` runs the pinned raw native Muse binary, SHA-256 verified at build time.
Pins live in `version-muse.env`; [config/settings.json](config/settings.json) is
the authoritative seed. `make -C box build-m` rebuilds the image.

Muse owns writable global settings/auth/trust at
`~/.config/box-m/muse-config`, mounted at `/home/box/.config/muse`.
`BOX_M_PERSIST_DIR` changes this protected root (include the overridden root
in reset/uninstall inventory, same as Codex overridden roots). Each physical project also has
its own named volume at `/persist`. Projects share native login/settings, while
project data/state remain separate. No host-native auth is automatically copied.

```bash
box-m-login                       # device login, prints browser link/code
box-m login                       # native device flow
box-m --version
```

Alternatively put `MUSE_CODE_API_KEY` in the protected shared provider file;
only this key is forwarded. Keep provider file values out of command arguments,
logs, and git. Cache `auth.json` must be user-owned, regular, writable, mode 600;
unsafe caches fail without automatic repair. Native authentication and a model
request are separate account-dependent acceptance gates.

At live startup the package enforces four seed values: approval mode, approval
judge, telemetry enabled, and API base URL. Model, reasoning, unknown preferences,
and existing theme choices survive; missing theme preferences may be imported
once from host-native settings. This is startup enforcement, not proof of
continuous managed requirements across native session overrides. Outer
Docker/gVisor containment is authoritative, so the box auto-injects the
official `--disable-sandbox` flag container-only, whereas upstream documents
it as opt-in for already-isolated environments. Opt out with empty
`BOX_M_INNER_FLAG` or an explicit flag; diagnostic and auth subcommands
(`login`, `logout`, `auth`, and others in `native.sh`) never receive it.
Approval prompts stay on (approval mode enforced in `native.sh`); this is not
approval circumvention. Per upstream docs this also lifts workspace
confinement for file tools and forces full egress, so do not copy this flag
to host use.
`BOX_M_INNER_FLAG` may select/disable it, and explicit flags are respected.
Session commands retain native subcommand-first order: for example
`box-m exec --provider echo "fixture"` places the automatic flag after `exec`.
Diagnostic/auth commands receive no automatic flag. The echo provider tests
startup without real inference and does not establish Meta account access.

Setup refreshes the installed seed with one `.bak`, seeds absent live settings,
and retains the legacy repair of empty JSON. To adopt a new seed in an existing
home, stop Muse, back up the exact live settings file, and explicitly replace it
with the reviewed template; do not remove `auth.json` or `.trust.json`. Subsequent
startup merging preserves other native preferences.

`box-m logout` clears native cached login, but a configured API key remains in
the provider file until explicitly removed. A project-volume reset removes only
that project's volume state. Removing the global Muse directory removes shared
login, preferences and trust for every project. Full uninstall must address both
stores separately; see the shared inventory-first reset procedure.
Pin update: see [upgrades §12](../../docs/upgrades.md) (`update-check` →
`update` → `gen-verify.sh`/`gen-pins.sh` → `verify-static` + `pins` →
`build-m` → `sync-pins-m`).
