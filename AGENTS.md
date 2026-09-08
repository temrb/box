# AGENTS.md

## Overview

Containerized Muse + OpenCode sandbox (Debian + Docker + gVisor `runsc`).
The real project lives in `box/` — start at `box/README.md`
(quickstart, layout, doc index).

## Build & setup

- `make -C box setup` — first run on a fresh host (configs, launchers, networks, all images).
- `make -C box build` / `make -C box build-<stem>` — all images / one image for your UID/GID (`build-m`, `build-o`; needs Engine + runsc).
- Shape-check before real runs: `box-m --dry-run`, `box-o --dry-run` (launcher flags must precede `--shell`).

## Test & verify

- `make -C box test` — bats unit suite (`box/tests/bats/`).
- `make -C box verify-static` — bash -n + JSON + generated checks + shellcheck + bats (fast-first; same checks CI runs in `box/.github/workflows/verify.yml`).
- `make -C box pins` — pin consistency (`pin-check` + `verify-pins-generated`).
- `make -C box verify-generated` — assert `box/verify-*.sh` match `box/gen-verify.sh` output.
- Never hand-edit generated files: edit `box/verify.d/` partials, then regenerate with `box/gen-verify.sh` (`box/gen-pins.sh` for the pin table).

## Code style

- Source shared shell code with `source`.
- Use the `.sh` extension for shell library files.
- Use the `.bats` extension for test files.
- Single tool registry: `box/lib/tools.sh` — new tools are data rows plus the bounded surfaces in `box/docs/adding-a-tool.md`; never branch on tool name in shared `box/lib/` code.
- Thread pins only via `box/lib/pins.sh` (single pin-threading home); never `grep`+`cut` `box/version-*.env` ad hoc.
- `make` targets only — never hand-run `docker build` (see `box/docs/upgrades.md`).

## Security

- Never commit live credentials: `providers.env`, `*.providers.env`, and `meta-api-key` are git-ignored (root `.gitignore`).
- Credential files must be mode `600` (`400` accepted), owned by you, and live outside the project (enforced by `box/lib/preflight.sh`).
- Never print key values: forward via `--env NAME` only, never `=value`.
- Don't relax the `ask` rules in `box/opencode.json` (`*.env`, `external_directory`).

## Docs

- `box/README.md` — quickstart, layout, doc index.
- `box/docs/architecture.md` — decisions, config, verified pin table (§4), launchers, isolation.
- `box/docs/operations.md` — prerequisites, builds, setup, daily usage, verification, reset.
- `box/docs/upgrades.md` — upgrade + sync procedures (`make` targets only).
- `box/docs/troubleshooting.md` — symptom table + fallback runners.
- `box/docs/adding-a-tool.md` — 7-step recipe for a new registry tool.
