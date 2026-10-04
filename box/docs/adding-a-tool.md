# Adding a harness

Use the existing contracts without harness-name branches in shared `lib/`.
A fourth harness changes a registry package, explicit Docker stage/context
inputs, wrapper, generated artifacts, tests, index row, and native guide. It
should not require rewriting shared operational guides.

1. Add the ID in `lib/tools.sh` and all declared identity, pin, probe, package,
   and fixed adapter fields. Separate package sources from installed leaf
   names. Declare every config artifact with format, role, lifecycle, runtime
   path, owner, mode, and consumers, plus every persistent/ephemeral state
   record and exact reset consequence. Override fields list environment names,
   including aliases. Do not put executable expressions in records.
   `probe_url` is the canonical HTTPS endpoint: its host must appear in
   `probe_hosts` and in the harness `30-network` partial (muse exact URL equals
   its settings `api.base_url`).
2. Create `harnesses/<id>/config/`, optional `policy/`, unique
   `version-<id>.env`, and `launch.sh`, `update.sh`, `validate.sh`, optionally
   `install.sh`. Reuse a pin format only if its complete positional contract
   fits: `sha-pinned` means version plus two SHA-256 pins. A different
   toolchain requires an explicit new format rather than fake pins (the retired
   v1 npm/NodeSource format is not reused).
3. Write the native adapters. The resolver exports `box_harness_resolve` and
   changes only its declared `new_pin` keys. The validator exports
   `box_harness_validate`. Install adapters export read-only planning and
   preparation functions. Launch planning must complete before mutation;
   seed once, preserve preferences/empty files, enforce native cache hygiene,
   and use shared project identity and container primitives.
4. Add a handwritten public wrapper and one `FROM base AS <id>` stage.
   Declare/consume pins in that stage, preserve the canonical Bash SHELL,
   hash the retained installation inputs, assert exact normalized versions,
   set UID/GID and labels, and include only actual inputs in `.dockerignore`.
   Declare image policies as root-owned managed artifacts with build consumers.
5. Add five package `verify.d/` partials: `00-header`, `30-network`,
   `40-readiness`, `60-probe`, `99-footer`. Use the version `@@<PIN_KEY>@@`
   token and generated `@@ARTIFACT_<NAME>@@` structural expectations.
   Keep output self-contained: shared sections come from root `verify.d/`;
   native probe helpers must be embedded by the generator. Check native schema,
   requirements loading, effective layering, overrides, agent/session policy,
   and unavailable-inspection failures, with bounded cleanup and no model turn
   where possible. A syntax check or global config dump alone is insufficient.
6. Extend Bats for contract negatives, nested discovery, installed operation,
   read-only dry-run, safe rejected paths, concurrent seeding, credentials,
   updater selection/rollback, setup reruns, and state isolation. Make discovers
   recursive shell files, extensionless wrappers, partials, and declared config
   artifacts. Add credentials only to shared allowlist data, and forward the
   minimum native subset. Do not duplicate Make build or updater orchestration.
7. Add a canonical `harnesses/<id>/README.md` and row in
   `docs/harnesses.md`. Document login/logout, native settings, template refresh,
   migration, managed-policy rebuild, pin update, both state lifetime and exact
   reset/uninstall consequences, account/architecture limits, and test results.
   Regenerate with `gen-verify.sh` and `gen-pins.sh`; run `make verify-static`
   and `make pins`, build through Make, and run explicit runsc and runc probes.
   Record revision, exact pins, architecture, runtime, auth mode, and skipped
   checks in `docs/acceptance.md`. Require native ARM64 and a real workflow run
   before claiming those gates passed.

Unknown artifacts, escaping paths, duplicate destinations, and missing consumers
must fail validation. Native facts stay in package assets and guides; shared
docs link them. A new integration is implemented only after these changes and
accepted only when its declared runtime gates have evidence.

Declare `directory_configs` in native precedence order in the registry. Adapters
own native preference lifecycle and migration; shared libraries enumerate paths
and validate containment without branching on tool IDs.
