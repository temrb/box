# Containerized Muse + OpenCode Sandbox

Debian + Docker + gVisor (`runsc`) sandboxing for **Meta Muse Code**
(`muse` CLI / Meta Model API) and **OpenCode** (`opencode` CLI / native
`/connect` auth), sharing one hardened split-lib implementation
(`lib/preflight.sh` + `lib/config.sh` + `lib/docker.sh` + `lib/launcher.sh` +
`lib/run.sh` + `lib/pins.sh` + `lib/build.sh`) with thin per-tool launchers.

Layout: `Dockerfile` (targets `base`, `muse`, `opencode`), `version-muse.env` /
`version-opencode.env` (single pin source via `lib/pins.sh`), `box-m` /
`box-o` / `box-m-login` (one-command browser login with a clear terminal
link; bare `box` is the setup-managed default symlink, `box-m` out of the
box), `check-pins.sh`,
`gen-verify.sh` (+ `verify.d/` partials generating `verify-muse.sh` /
`verify-opencode.sh`), `gen-pins.sh`, `regen-validation.sh`, `Makefile`,
`settings.json` / `opencode.json`, `lib/` (see above), `setup.sh`, `docs/`.

Docs:

- `docs/architecture.md` — tooling diagnosis (§1 mirrored below), architecture decision (§2), configuration (§3), container definitions + verified pin table (§4), launchers + shared preflight (§7), isolation model (§10).
- `docs/operations.md` — prerequisites (§5), builds (§6), setup (§8), daily usage (§9), verification (§11), reset/uninstall (§13).
- `docs/upgrades.md` — upgrade + synchronization procedures (§12, `make` targets only — no manual `docker build` blocks).
- `docs/troubleshooting.md` — symptom table + fallback runners (§14).
- `docs/adding-a-tool.md` — 7-step recipe for registering a new tool behind the `lib/tools.sh` registry (bounded surfaces only, no shared-`lib/` edits).

### 1. Target Tooling & Configuration Diagnosis

Two CLIs run side by side, each in its own image/network/volume, sharing only the secret-file format (not its values):

| Dimension | OpenCode CLI | Native Meta Muse Code CLI |
|---|---|---|
| Binary / Runtime | Self-contained native executable (`opencode`, via `npm i -g opencode-ai`) | Native compiled Rust binary (`muse`) |
| Config Schema | JSON config (permission-only `opencode.json`, no provider map) | JSON settings (`settings.json` with `schema_version: 1`) |
| Instructions | Project-level `AGENTS.md` (or `CLAUDE.md`) | Project-level `AGENTS.md` (or `CLAUDE.md`) |
| Inner Sandboxing | Node/Bun permission rules (in-process; `permission.ask` for `*.env` / `external_directory`) — no inner bwrap, no bypass flag | OS sandbox (Linux Bubblewrap + seccomp; macOS Seatbelt) with `--disable-sandbox` outer-delegation bypass |
| Credential Env | Native `/connect` (`auth.json` on `/persist`, no manual key) | `providers.env` (`MUSE_CODE_API_KEY`) |
| Auto-Update | `OPENCODE_DISABLE_AUTOUPDATE=1` | `MUSE_NO_AUTO_UPDATE=1` |

### Quickstart

```bash
bundle_dir=/path/to/box
bash "$bundle_dir/setup.sh"          # see docs/operations.md §8
export PATH="$HOME/.local/bin:$PATH"
cd ~/projects/my-app
box-m-login                           # one-command Meta browser login (§9)
box-m --dry-run                       # shape check before real runs (§11)
box-o --dry-run                       # same for OpenCode
make -C "$bundle_dir" verify-static  # bats + bash -n + json + shellcheck + sync + generated
make -C "$bundle_dir" pin-check      # pins vs Dockerfile vs docs/architecture.md §4
```

Pinned releases and the verified pin table live in `docs/architecture.md` §4
(single source: `version-muse.env` / `version-opencode.env` via `lib/pins.sh`).
Upgrades: `docs/upgrades.md` §12. Diagnostics: `docs/troubleshooting.md` §14.
