# Adding a Tool

One registry row plus the bounded surfaces below — no shared-`lib/` branching edits. Copy the `muse` row/files as the template (`opencode` is atypical: `npm-pinned` with no shipped model or forwarded keys).

1. `lib/tools.sh`: append the id to `box_tool_ids` + one 18-field row (copy a sibling row; a tool reusing an existing `version_format` needs no parser change).
2. `version-<id>.env` (mode `644`, pins match the format regex) + `<id>.json` (valid JSON; keep `.model` top-level when the tool ships one).
3. `Dockerfile`: one `FROM base AS <id>` target (no-default `ARG`s, `LABEL`s, canonical per-stage `SHELL`, `ENTRYPOINT`).
4. `verify.d/`: `00-header-<id>.sh` + `30-network-<id>.sh` + `40-readiness-<id>.sh` + `60-probe-<id>.sh` + `99-footer-<id>.sh` (copy siblings; `30` must contain the `api_base_url` string, `40` must mirror the `config_base_path` value, and the model value when `pin_model=1`).
5. Thin hand-written launcher `box-<id>` (copy `box-o`; `BOX_TOOL` + registry lookups, explicit `docker run` flag body — never template-generated).
6. Sync + linkage: add the launcher and generated `verify-<id>.sh` to `Makefile` `SHELL_FILES` and `.github/workflows/verify.yml`; extend `tests/bats/config-linkage.bats` (registry row, `3 + 5 × tool_count` partials, `--dry-run` shape, `make -n build-<stem>` delegation).
7. Generate + gate: `bash gen-verify.sh && bash gen-pins.sh` (never hand-edit generated outputs), then `make verify-static && make pins`.

Do not touch: `lib/preflight.sh`, `lib/docker.sh`, `lib/run.sh`, `lib/pins.sh`, `lib/build.sh`, `setup.sh`, `gen-*.sh`, `check-pins.sh`, or `Makefile` rules (only the `SHELL_FILES` list). New credential key? Add one token to `BOX_CRED_KEYS` in `lib/config.sh` (shared data, not branching).
