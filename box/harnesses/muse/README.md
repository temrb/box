# Muse harness

[Shared setup and containment](../../docs/operations.md) ·
[Acceptance](../../docs/acceptance.md) · [Harness index](../../docs/harnesses.md)

`box-m` runs the pinned raw native Muse binary, SHA-256 verified at build time.
Pins live in `version-muse.env`; [config/settings.json](config/settings.json) is
the installed default source. `make -C box build-m` rebuilds the image.

Muse owns its native config home at
`~/.config/box-m/muse-config`, mounted at `/home/box/.config/muse`.
`BOX_M_PERSIST_DIR` changes this protected non-auth root (include the
overridden root in reset/uninstall inventory, same as Codex overridden
roots). Each physical project also has its own named volume at `/persist`.
Trust, settings sources, and project data/state remain in those non-auth
stores. Auth scope is configurable (`global` default, or `project`): the
selected canonical identity lives under `~/.config/box/auth/muse/...`
(override `BOX_AUTH_ROOT`) and is projected into native `auth.json` for the
run, then collected (login/logout/refresh) and scrubbed on exit. No
host-native auth is automatically copied; scope changes never merge stores.
See [operations §9a](../../docs/operations.md#9a-auth-scope-migration-and-lifecycle-tools).

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

At every launch, defaults merge with `.muse/settings.json` from the workspace
root to the launch directory. Objects merge recursively; arrays and scalars
replace earlier values. Two protected defaults (telemetry enabled, endpoint
transport base URL) apply after merging. Each launch receives a
private read-only settings snapshot. UI settings-save operations are unsupported;
put persistent preferences in defaults or directory files. Host themes are not
imported. Outer
Docker/gVisor containment is authoritative, so the box auto-injects the
official `--disable-sandbox` flag container-only, whereas upstream documents
it as opt-in for already-isolated environments. Opt out with empty
`BOX_M_INNER_FLAG` or an explicit flag; diagnostic and auth subcommands
(`login`, `logout`, `auth`, and others in `native.sh`) never receive it.
Approval prompts stay on (binary defaults on-request/on; the pinned release
accepts approval only as CLI flags, so directory files cannot weaken it);
this is not approval circumvention. Per upstream docs this also lifts workspace
confinement for file tools and forces full egress, so do not copy this flag
to host use.
`BOX_M_INNER_FLAG` may select/disable it, and explicit flags are respected.
Session commands retain native subcommand-first order: for example
`box-m exec --provider echo "fixture"` places the automatic flag after `exec`.
Diagnostic/auth commands receive no automatic flag. The echo provider tests
startup without real inference and does not establish Meta account access.

Setup refreshes installed defaults with one `.bak`. Changes apply on the next
launch, including existing projects. `BOX_M_CONFIG` replaces installed defaults.
Legacy settings are retained once as `settings.json.box-legacy` (mode 600);
canonical auth and native trust are preserved. Each launch uses its own settings
snapshot; auth and shared native-home leases permit one active writer.

`box-m logout` updates the selected canonical auth identity (a configured API
key remains in the provider file until explicitly removed). A project-volume
reset removes only that project's volume state (plus its acknowledged project
auth with `project-reset`, retained with `--keep-auth`); global auth is never
removed by reset. Explicit exact-identity removal affects the selected scope
only. Full uninstall must address all stores separately; see the shared
inventory-first reset procedure. Auth scope transitions need
`BOX_AUTH_TRANSITION=fresh|use-existing` or explicit `auth-copy`; first launch
after upgrade with legacy credentials requires explicit `auth-migrate` or
`auth-init`.
Pin update: see [upgrades §12](../../docs/upgrades.md) (`update-check` →
`update` → `gen-verify.sh`/`gen-pins.sh` → `verify-static` + `pins` →
`build-m` → `sync-pins-m`).

### Auth adapter qualification gate

The pinned Muse non-empty `auth.json` schema remains unqualified. The adapter
accepts only an absent file or `{}`; non-empty material fails collection and
migration without replacing the canonical revision or retiring its source.
An interrupted/failed collection leaves the native projection authoritative
and the lease active. Do not enable production migration until a fixture from
the pinned binary establishes credential membership, logout and refresh
behavior. Trust/settings and unidentified MCP stores are not auth exports.

Project reset uses an exact native-home/volume checkpoint; pass `KEEP_AUTH=1`
to retain project auth and preserve global auth by default. `state-remove FULL=1`
adds recorded historical native roots, both auth scopes, rollback copies and
installation state; register older coordinates with `state-discover` first.
`uninstall-code` preserves all state. These targets preview unless `EXECUTE=1`
is supplied; see [operations](../../docs/operations.md#13-reset-and-uninstall)
for recovery, custom roots and separately selected external provider files.
Images require auth supervisor contract 3; rebuild through the Make targets.
