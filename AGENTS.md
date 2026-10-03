# AGENTS.md

## Overview

Containerized Muse + OpenCode + Codex sandbox (Debian + Docker + gVisor `runsc`).
The real project lives in `box/` — start at `box/README.md`
(quickstart, layout, doc index).

## Build & setup

- `make -C box setup` — first run on a fresh host (configs, launchers, networks, all images).
- `make setup` takes no args — pass `--only <id>`, `--skip-build`, `--default <id>` via `bash box/setup.sh ...` (see `box/docs/operations.md` §8).
- `make -C box build` / `make -C box build-<stem>` — all images / one image for your UID/GID (`build-m`, `build-o`, `build-c`; needs Engine + runsc).
- Built image tags are per-UID/GID and local-only — never `docker push`, save, or export them (Muse images contain a proprietary binary).
- Shape-check before real runs: `box-m --dry-run`, `box-o --dry-run`, `box-c --dry-run` (launcher flags must precede `--shell`; `--dry-run` is read-only, validates shape/paths only, never auth or runtime health).

## Test & verify

- `make -C box test` — bats unit suite (`box/tests/bats/`); single file: `bats box/tests/bats/<name>.bats` (e.g. `tools.bats`, `pins.bats`).
- `make -C box verify-static` — bash -n + JSON/TOML + generated checks + pin consistency + shellcheck + bats (fast-first; same checks CI runs in `.github/workflows/verify.yml`).
- `make -C box verify-config` / `verify-shell` — configuration parsing / shell syntax only (TOML requires Python 3.11+ `tomllib`; shellcheck runs on generated harnesses, not `verify.d/` fragments).
- `make -C box pins` — pin consistency (`pin-check` + `verify-pins-generated`).
- `make -C box verify-generated` — assert `box/verify-*.sh` match `box/gen-verify.sh` output.
- Never hand-edit generated files: edit shared `box/verify.d/` and native `box/harnesses/<id>/verify.d/` partials, then regenerate with `box/gen-verify.sh` (`box/gen-pins.sh` for the `docs/architecture.md` §4 pin table).
- `make -C box verify-native` / `verify-native-opencode` need Engine + runsc and fail on unmet native/account gates by design — separate from CI static checks, never treat as unit failures.

## Code style

- Source shared shell code with `source`.
- Callers must set `BOX_TOOL=<id>` (or `make`/`inventory`) before sourcing any `box/lib/*.sh` — sourcing fails closed without it.
- Use the `.sh` extension for shell library files.
- Use the `.bats` extension for test files.
- Single tool registry: `box/lib/tools.sh` — new tools are data rows plus the bounded surfaces in `box/docs/adding-a-tool.md`; never branch on tool name in shared `box/lib/` code.
- Thread pins only via `box/lib/pins.sh` (single pin-threading home); never `grep`+`cut` `box/harnesses/<id>/version-<id>.env` ad hoc.
- Parse configuration via `box/lib/config-file.sh` (JSON with jq, TOML with Python 3.11+); dispatch on format, never tool ID.
- `make` targets only — never hand-run `docker build` (see `box/docs/upgrades.md`).

## Security

- Never commit live credentials: `providers.env`, `*.providers.env`, and `meta-api-key` are git-ignored (root `.gitignore`).
- Credential files must be mode `600` (`400` accepted), owned by you, and live outside the project (enforced by `box/lib/preflight.sh`).
- `providers.env` is never sourced and never printed: literal LF-only allowlisted `KEY=value` lines, forwarded via `--env NAME` only, never `=value`.
- Don't relax the `ask` rules in `box/harnesses/opencode/config/opencode.json` and its image policy (`*.env`, `external_directory`).

## Docs

- `box/README.md` — quickstart, layout, doc index.
- `box/docs/architecture.md` — decisions, config, verified pin table (§4), launchers, isolation.
- `box/docs/operations.md` — prerequisites, builds, setup, daily usage, verification, reset.
- `box/docs/upgrades.md` — upgrade + sync procedures (`make` targets only).
- `box/docs/troubleshooting.md` — symptom table + fallback runners.
- `box/docs/adding-a-tool.md` — package/registry recipe for a new harness.

- `box/docs/harnesses.md` — harness index and canonical native guides.
- `box/docs/acceptance.md` — current evidence and explicit unmet runtime/account/CI gates.
