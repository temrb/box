# Architecture

Container internals for the Debian + Docker + gVisor (`runsc`) Muse + OpenCode
sandbox: tooling diagnosis, architecture decision, configuration, container
definitions with the verified pin table, launchers with shared preflight, and
the isolation model. For setup/usage/verification see `operations.md`; for
upgrades see `upgrades.md`; for diagnostics see `troubleshooting.md`.

### 2. Architecture Decision

Use **native rootful Docker Engine + gVisor `runsc`**, a UID/GID-matched non-root user, one read-write project bind (`/workspace`), one tool-config bind (writable seeded Muse `settings.json`, read-only OpenCode `opencode.json`), and one project-specific named state volume (`/persist`). Each tool gets an **isolated bridge network** with outbound masquerade NAT and disabled inter-container communication (`enable_icc=false`).

Shared vs. separate:

- **Shared:** split-lib preflight (`lib/preflight.sh`: denylist incl. `/snap`/`/srv`/`/data`/`/workspace`, `$HOME`/credential-dir, tool-dir guard, IPC scan, bounded symlink scan with SIGPIPE-safe truncation, git-worktree with `GIT_*` unset, strict version-file parser with owner/mode/outside-project checks, credentials parser unsetting inherited values and accepting mode `400`/`600`; `lib/tools.sh`: single declarative tool registry (every tool is a data row: launcher, network, labels, pins, probe hosts — shared code iterates it instead of branching); `lib/config.sh`: shared credential + terminal allowlists, probe timeout, container resources; `lib/docker.sh`: docker-cli isolation with atomic `{}` enforcement and `BUILDKIT_*`/`BUILDX_*` unset, rootful + `>= 25` engine assert with `10#`, requested-runtime assert (`runsc` default / `runc` under explicit fallback), pipe-delimited network assert, image assert covering version + SHA/integrity labels) plus shared launcher helpers (`lib/launcher.sh`: arg parsing with `--shell` ordering enforcement, project identity, extra-GIDs; `lib/run.sh`: git identity, hardened base args, key forwarding, runtime signal, muse bypass; `lib/pins.sh`: single pin-threading home; `lib/build.sh`: single image-build home) and one secret file `~/.config/box/providers.env` (mode 600, 400 accepted). Each launcher parses the shared file (`BOX_CRED_KEYS`); muse forwards `MUSE_CODE_API_KEY`, opencode forwards nothing (native `/connect`).
- **Separate:** images (`box-m` vs `box-o`), networks (`box-m` vs `box-o`), volumes (`box-{m,o}-u<uid>-g<gid>-<hash>`), config dirs (`~/.config/box-m/` vs `~/.config/box-o/`), labels (vendor roots plus a common `org.box.tool=muse|opencode`) — all declared as data rows in `lib/tools.sh`, the single extension point for new tools. No cross-tool mounts. The hardened `docker run` base (`--cap-drop=ALL`, `no-new-privileges`, `--read-only`, tmpfs mounts, resources, network — `box_base_args` in `lib/run.sh`, see §7) is factored into the shared lib with per-launcher deltas after it, so both launchers carry identical containment pinned by `--dry-run` shape tests; the `verify-*.sh` scripts are intentionally self-contained because they are delivered via stdin under `--shell` (see `operations.md` §11) and cannot source a shared file — they are generated from `verify.d/` partials by `gen-verify.sh` (CI asserts generated == checked-in).

Each launcher defaults to `runsc`. The explicit hardened-`runc` path for toolchains needing unsupported syscalls is `--docker-fallback` (e.g. `box-m --docker-fallback` / `box-o --docker-fallback`); there are no `*-docker` wrappers.

---

### 3. Global Configuration & Project Context

#### Muse Settings (`settings.json`)
The container owns a writable `settings.json` at `/home/box/.config/muse/settings.json`, seeded on first run from the host seed file — in-container `/models` changes persist in `~/.config/box-m/muse-config/` across runs. The seed default below is `muse-spark-1.3` with the approval judge on, talking to `https://api.meta.ai/v1`. The snippet mirrors `settings.json` byte-for-byte (pinned by `tests/bats/config-linkage.bats`); the endpoint pin is additionally cross-checked against `verify.d/40-readiness-muse.sh` by `gen-pins.sh --check` (the model is a user-mutable default, not a harness pin).

```json
{
  "$schema": "https://dev.meta.ai/schemas/muse-settings-v1.json",
  "schema_version": 1,
  "model": "muse-spark-1.3",
  "reasoning_effort": "max",
  "approval_mode": "on-request",
  "approval_judge": true,
  "telemetry": {
    "enabled": false
  },
  "api": {
    "base_url": "https://api.meta.ai/v1"
  }
}
```

#### OpenCode Config (`opencode.json`)
The container mounts `opencode.json` read-only at `/home/box/.config/opencode/opencode.json`. It carries no model or provider pins — only `permission` at `ask` for `*.env` / `external_directory` inside the sandbox (do not relax these to `allow`). Auth is native `/connect` only (`auth.json` on the per-project `/persist` volume, no manual key; see `operations.md` §8).

#### Project Context Instructions (`AGENTS.md` / `CLAUDE.md`)
Both tools read project-level instructions from `AGENTS.md` (or `CLAUDE.md`) in the workspace root. These guide planning and execution without modifying global settings.

---

### 4. Container Definitions & Dependencies

<!-- pin-table-start -->
All images build from one `Dockerfile` (`--file Dockerfile --target muse|opencode`, targets `base`/`muse`/`opencode`) on `debian:trixie-slim` pinned to the manifest-list digest below (re-pin on every Debian point release; `check-pins.sh` asserts the single base digest matches this pin table) with Git, Bash, C/C++ toolchains, `fd`/`rg`/`jq`, an explicit `HOME=/home/box`, system-first `PATH` (writable `~/.local/bin` last), tool-scoped `XDG_DATA_HOME`/`XDG_STATE_HOME` (`/persist/data|state/<tool>`), and a UID/GID-matched `box` user. The `base` target holds only common apt + user + common `ENV` (`XDG_CONFIG_HOME`/`XDG_CACHE_HOME`/`HOME`/`PATH`/`SHELL`); each tool target owns its extra packages, dirs/symlinks/seeds, `XDG_DATA_HOME`/`XDG_STATE_HOME`, auto-update opt-out, labels, and `ENTRYPOINT`. All `ARG`s (including `HOST_UID`/`HOST_GID`) have no defaults so bare builds fail closed. The single pin source is the version files (`lib/pins.sh` threads them into `setup.sh`, `check-pins.sh`, and `lib/build.sh`, which the `Makefile` delegates to); this table is generated by `gen-pins.sh` from the version files + Dockerfile and is verified by `make pin-check` + `make verify-pins-generated`.

| Pin (single source) | Value (`check-pins.sh` verifies) |
|---|---|
| Debian base digest | `sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132` (2026-09-06) |
| Muse `MUSE_VERSION` (`version-muse.env`) | `1.0.3-R2198.1` |
| OpenCode `OPENCODE_VERSION` (`version-opencode.env`) | `1.18.29` |
| Node `NODE_VERSION` (`version-opencode.env`) | `22.23.2-1nodesource1` |
| NodeSource `NODESOURCE_FINGERPRINT` (`version-opencode.env`) | `6F71F525282841EEDAF851B42F59B5F99B1BE0B4` |
<!-- pin-table-end -->

- **`Dockerfile --target muse`**: adds `bubblewrap` + `libseccomp2` (native probe discovery), downloads the raw static `muse` binary from the documented channel URL `https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=<version>&file=muse-{x86,aarch64}-linux` (manifest served by `https://api.meta.ai/muse-code/channels/muse-stable`; `--proto '=https' --tlsv1.2 --retry 3 --max-time 600`) with fail-closed SHA-256 verification (no fallback host; checksums pinned in `version-muse.env` from the channel `manifest.json`), plus binary asserts (`-x` + `-f` + not `-L`), persists `/persist/{data,state}/muse` with a `/home/box/.muse` symlink. `ENTRYPOINT` is `/usr/local/bin/muse`.
- **`Dockerfile --target opencode`**: installs Node.js `${NODE_VERSION}` exact via the upstream NodeSource repository (vendored APT key `keys/nodesource.asc` with fail-closed `${NODESOURCE_FINGERPRINT}` assert, both threaded from `version-opencode.env`), then verifies all three `dist.integrity` pins plus tarball hashes (see §10 supply chain) and installs per upstream docs with `npm install -g --no-audit --no-fund opencode-ai@${OPENCODE_VERSION}` after fail-closed pinned `npm view --json` + `jq -r` enforcement, plus `npm cache clean` and a normalized `opencode --version == pin` build assert (tolerates upstream output prefixes) with binary asserts (`-x` + `-f` + not `-L`). The upstream `curl|bash` install script is explicitly rejected for image builds (pipe-to-shell defeats fail-closed verification). Platform-binary `dist.integrity` pins are recorded in image labels and compared at run (see §7). No `bubblewrap` (OpenCode has no inner bwrap). Persists `/persist/{data,state}/opencode` with a `/home/box/.local/share/opencode` symlink. `ENTRYPOINT` is `/usr/local/bin/opencode`.

---

### 7. Launchers & Shared Preflight (`lib/`)

Launchers are thin: each resolves its tool identity (network, config/version defaults, image tag, forward keys, probe hosts, label asserts) from the `lib/tools.sh` registry row and keeps only tool-specific docker args plus login auto-runtime, with argument parsing, project identity, extra-GID handling, and the dry-run/assert/exec tail shared in `lib/` (`preflight.sh`: project/version/creds/config validators + portable `box_realpath`/`box_mktemp_*`; `tools.sh`: tool registry + fail-closed lookup; `config.sh`: shared allowlists, probe timeout, resources; `docker.sh`: CLI isolation, engine/image/network asserts, exec tail; `launcher.sh`: args, identity, GIDs, persist dirs, theme sync, DNS probe; `run.sh`: git identity, base args, key forwarding, runtime signal, muse bypass; `pins.sh`: single pin-threading home + shared structural asserts; `build.sh`: single image-build home with label compare), alongside all security checks:

- `box_preflight_project` — closed denylist (exact + subpaths; `/home` exact-only), physical `$HOME` resolution, 7 credential dirs (`.ssh .gnupg .aws .docker .git-credentials .netrc .config/gcloud`) guarded in both directions with resolved targets, explicit tool-dir guard (secret/config/bin dirs), comma/newline rejection, socket/device/FIFO scan (best-effort, check-then-mount), bounded symlink scan (first 500 links; SIGPIPE-safe truncation warning; fails on targets inside system dirs incl. `/snap`, `$HOME` root, or credential paths), git-worktree canonicalization (`realpath -m`, `GIT_*` env unset). Inspects `.git` in the current directory — the launchers always run with CWD == project.
- `box_resolve_config` — config must exist/readable, `realpath -e`, comma/newline rejection, owner + no group/other-write check, and outside-project enforcement (an in-project config would stay writable via `/workspace` despite its readonly bind).
- `box_load_version_file <file> <sha-pinned|npm-pinned> <KEY...>` — LF-only, `#` comments, literal `KEY=value`, CRLF rejection, strict key allowlist, version + checksum/integrity regex validation, plus canonicalization, owner/mode, and outside-project checks. The parser branches on pin-file format, never on tool name: callers pass the registry `version_format` + `pin_keys` for their tool id, so a new tool reusing a format needs no parser change. Integrity values are validated for well-formedness, recorded in image labels, and compared at run (see below); only the version feeds the image tag. `NODE_VERSION` + `NODESOURCE_FINGERPRINT` ride in `version-opencode.env` under the same strict parser.
- `box_load_credentials <path> <dry_run> <keys...>` — inherited allowlisted vars unset first (host-injected values cannot bypass checks); fail-closed except `--dry-run` (which exports nothing, so no keys are forwarded); outside-project (`realpath -e`), owner (numeric) + mode `600` (`400` accepted), LF-only literal parse, unknown keys hard-FAIL, empty values hard-FAIL, last-wins duplicates, exported for `--env NAME` pass-through only (never `=value`, never printed).
- `box_docker_cli`, `box_assert_engine`, `box_assert_runtime`, `box_assert_image`, `box_assert_network` — isolated CLI config (poisoning vars incl. `BUILDKIT_*`/`BUILDX_*` unset via prefix expansion, symlinks refused, atomic mktemp `{}` enforcement with a single mode-600 `.bak` backup (overwritten), `700`/`600` repaired), rootful-Engine + `>= 25` version assertion (`10#`-safe), requested-runtime assertion (`runsc` by default, `runc` only under explicit `--docker-fallback`; never automatic — a missing `runsc` fails closed with install vs. explicit-fallback remediation instead of the raw daemon `unknown or invalid runtime name`), UID/GID + version-label + SHA/integrity-label assertion (explicit image overrides print a WARNING and skip all pin checks), pipe-delimited network-policy assertion (immune to `<no value>` spacing).
- `box_parse_launcher_args`, `box_check_fallback`, `box_project_identity`, `box_extra_gids`, `box_ensure_persistent_config_dir`, `box_probe_runsc_dns`, `box_auto_runtime`, `box_docker_exec` — shared launcher plumbing. Launcher flags (`--docker-fallback`, `--runsc`, `--dry-run`) must precede `--shell` (a launcher flag after `--shell` is a hard error, never silently swallowed). Container names are `box-{m,o}-u<uid>-<rand>-<timestamp>`; project hashes use `sha256sum` with `${var%% *}` trailer split (first 20 hex chars). `--dry-run` never adds `--tty`, so its output is terminal-independent.

Per-tool specifics:

- **Credentials:** both launchers parse the shared file with the single-key allowlist `MUSE_CODE_API_KEY`; muse forwards it into its container (least privilege), opencode forwards nothing (native `/connect`). Shared file `~/.config/box/providers.env` (clean break — no legacy-path fallback). Unknown keys hard-FAIL in both.
- **Git identity:** each field resolves independently as primary env, then the other tool's env as fallback (`box_git_identity BOX_M BOX_O` / `box_git_identity BOX_O BOX_M`), then `git config --global user.name/user.email` (that scope only; repo-local identity is ignored). Explicit env always wins; when inference supplies at least one field the launcher prints a single `NOTICE` on stderr. Inferred values face the same validation as env (non-empty, single-line, printable); invalid inferred values count as missing. Still-missing fields fail closed naming the missing fields plus the `git config --global` and export remediations (never printing values).
- **Runtime flags:** `docker run` always passes `--pull=never` (saved images only; a missing image fails closed instead of pulling), `--read-only` with `--tmpfs` for `/tmp`/`/run`/`/var/tmp`/`~/.cache` (plus `~/.config/opencode` for OpenCode), private `--ipc`/`--cgroupns` (PID/UTS namespaces are private by default in docker), `--hostname=box`, and `--log-opt max-size=10m --log-opt max-file=3`. Muse mounts the global persistent dir `~/.config/box-m/muse-config/` at `/home/box/.config/muse` (single writable bind with `bind-recursive=disabled,rprivate`, seeded from the host seed file on first run): the tool owns `settings.json` there alongside `auth.json`/`.trust.json`, so in-container model changes persist globally. OpenCode keeps a writable `tmpfs` at `~/.config/opencode` before its readonly `opencode.json` bind (server/auth state stays ephemeral there). Both launchers pass `--env BOX_RUNTIME=runsc|runc` so the verify harnesses (§11) can grade `CapBnd` strictly on `runc` and tolerantly on `runsc`. Both launchers also forward the host terminal allowlist (`BOX_TERMINAL_KEYS`: `TERM`, `COLORTERM`, `TERM_PROGRAM`/`TERM_PROGRAM_VERSION`, `NO_COLOR`, `FORCE_COLOR`, `CLICOLOR_FORCE`) NAME-only so TUI color-depth detection matches the host terminal. Muse fills `tui.theme`/`tui.color_depth`/`tui.terminal_background` missing from the persisted file from the host-native `~/.config/muse/settings.json` (read on the host; only theme strings are copied, no host path is mounted); existing sandbox values always win.
- **Muse bypass:** automatically supplies `--disable-sandbox` (override via `BOX_M_INNER_FLAG`, empty disables) so outer Docker/gVisor is the containment layer while approvals stay on. Opt-out scan is full-`$@`: any `--disable-sandbox`/`=value`, custom-flag `=value`, or `--yolo` anywhere counts as already-supplied (no double-inject); denylist is `$1`-only by design (`--version`/`--help`/`-h` and the auth subcommands `login`/`logout`/`auth` as the first tool argument never get the bypass; `muse login` takes no arguments), so keep login invocations bare (`box-m login`; `muse --verbose login` still receives the bypass). OpenCode has no inner bwrap and injects no bypass flag.
- **Version overrides (testing):** `BOX_M_VERSION_FILE` / `BOX_O_VERSION_FILE`.
- **Automatic fallback on DNS failure only:** every tool run probes container DNS under `runsc` first via the single `box_auto_runtime` helper (`box_probe_runsc_dns` over each launcher's registry `probe_hosts`; shared code holds no per-tool default) and auto-selects hardened `runc` only when the probe fails, with one `NOTICE` + the standard `WARNING` (see `operations.md` §9). The healthy path stays on `runsc` with no output change (it still pays one probe-container round trip per tool run). Explicit controls remain: `--docker-fallback` forces hardened `runc` (stderr `WARNING` on every use); `--runsc` forces gVisor with no probe; `--shell` runs never probe (explicit-only diagnostics path); `BOX_M_ALLOW_FALLBACK=0` / `BOX_O_ALLOW_FALLBACK=0` fails closed with remediation instead of launching a run that would fail opaquely inside.
- **Docker CLI isolation:** private per-tool `docker-cli/config.json` containing `{}`.
- **Undocumented-elsewhere knobs:** `BOX_M_CONFIG` / `BOX_O_CONFIG` (tool config path; must be outside the project), `BOX_M_ENV_FILE` / `BOX_O_ENV_FILE` (providers file path), `BOX_M_IMAGE` / `BOX_O_IMAGE` (explicit image override; prints a WARNING, skips all pin-label checks), `BOX_M_EXTRA_GIDS` / `BOX_O_EXTRA_GIDS` (opt-in supplementary groups; comma-separated numeric GIDs, GID 0 rejected), `BOX_M_PERSIST_DIR` (global Muse config dir; defaults to `~/.config/box-m/muse-config/`, must stay outside the project).

---

### 10. Multi-Layer Isolation Architecture & Blast-Radius Limits

```text
+-------------------------------------------------------------------------------+
| Layer A: Tool-Native Sandboxing (Approvals & Policy)                           |
| - Muse: approval modes + approval judge + --disable-sandbox outer delegation   |
| - OpenCode: in-process permission rules (ask for *.env / external_directory)   |
+---------------------------------------+---------------------------------------+
                                        |
+---------------------------------------v---------------------------------------+
| Layer B: Outer Host/Container Sandboxing (Docker + gVisor runsc)              |
| - System call interception via userspace Sentry kernel                        |
| - Capability stripping: --cap-drop=ALL, --security-opt=no-new-privileges      |
| - Filesystem isolation: non-recursive rprivate bind to /workspace             |
| - Complete exclusion of host $HOME, credential dirs, Docker daemon socket     |
| - Cgroup constraints: 8g RAM, 4 CPUs, 512 PIDs (lib/config.sh)                |
+---------------------------------------+---------------------------------------+
                                        |
+---------------------------------------v---------------------------------------+
| Layer C: API & Provider Configuration                                          |
| - Muse: https://api.meta.ai/v1 via MUSE_CODE_API_KEY                          |
| - OpenCode: native `/connect` (`auth.json` on `/persist`, no manual keys)     |
+---------------------------------------+---------------------------------------+
                                        |
+---------------------------------------v---------------------------------------+
| Layer D: Inherent Blast-Radius Limits (Unconstrainable by Configuration)      |
| - Writable /workspace mount: agent can alter, corrupt, or delete project files|
| - Outbound network egress: HTTPS egress allows exfiltration                   |
| - In-memory secrets: container processes can inspect passed-through keys      |
+-------------------------------------------------------------------------------+
```

#### Layer A: Tool-Native Sandboxing
Muse Code includes an OS-level sandbox (Linux `bubblewrap` + seccomp). OpenCode enforces in-process permission rules instead — keep `permission.read/edit["*.env"]`, `permission.read/edit["*.env.*"]`, and `permission.external_directory` at `ask` in `opencode.json` (with the `*.env.example: allow` exception for templates).
The `opencode.json` top-level and `read`/`edit` `"*"` defaults stay `allow` by design: inside the outer Docker/gVisor containment the agent needs broad read/edit to work, so only secret-adjacent (`*.env`) and escape-adjacent (`external_directory`) surfaces prompt (pinned by `tests/bats/config-linkage.bats`; the effective merged config is diffed field-wise by `regen-validation.sh`). `*.env.example` overlaps `*.env.*` for names like `foo.env.example`; static JSON cannot prove upstream matcher precedence, so the coexistence is pinned in the same test file and precedence is verified live via `opencode debug config`.

#### Layer B: Outer Host/Container Sandboxing & The Nested Sandbox Clash (Muse)
The container runs with `--cap-drop=ALL`, `no-new-privileges`, and gVisor (`runsc`).
- **The Conflict**: `bubblewrap` relies on unprivileged user namespaces (`CLONE_NEWUSER`) and mount operations. Unprivileged `unshare -Ur` needs no capabilities, so the observed block under `runsc` is gVisor seccomp/`runsc` behavior — not `--cap-drop=ALL`/`no-new-privileges` alone. Do not assert the old causation. `verify-muse.sh` §6 records probe evidence (`bwrap --ro-bind / / true` and `unshare -Ur true` exit codes). Because Muse Code "fails closed", execution halts without a bypass.
- **The Resolution**: Outer containerization provides a stronger security perimeter than inner `bwrap`. The muse launcher automatically supplies `--disable-sandbox` (override via `BOX_M_INNER_FLAG`, empty disables) to bypass the inner bubblewrap probe while **retaining Muse Code's native approval engine**. OpenCode needs no bypass (no inner bwrap); `verify-opencode.sh` §6 therefore records only the `unshare` probe and omits any bwrap section.

#### Layer C: API & Provider Configuration
Muse traffic routes to Meta Model API (`https://api.meta.ai/v1`) via `MUSE_CODE_API_KEY`. OpenCode traffic routes to the user's `/connect`-chosen providers (no shipped endpoint, no forwarded keys). Keys are passed by name (`--env NAME`); never log `providers.env`.

#### Layer D: Inherent Blast-Radius Limits
Certain operational risks cannot be mitigated by sandbox configuration alone:
1. **Workspace Integrity**: `/workspace` must remain writable for the agent to perform edits and builds. Malicious or broken code can corrupt project files or Git history. *Mitigation*: snapshot/ephemeral worktree flow (snapshot → agent → `git diff` → explicit apply), disposable branches.
2. **Network Egress Exfiltration**: Each container requires outbound HTTPS (model APIs + package registries). Malicious code executed in the container could exfiltrate repository data or environment variables over HTTPS. Both default networks are full-egress NAT (`enable_ip_masquerade=true`). *Mitigation*: `--internal` + allowlist egress proxy (model APIs + registries, DNS logging), `--offline`/`--proxy-only` modes where supported.
3. **API Key Exposure**: Because provider keys are present in the container environment, any in-container process can inspect `/proc/self/environ`, and host-root can read them via `docker inspect`. This is inherent to env-pass-through. *Mitigation*: dedicated project keys with spending/rate limits, short-lived keys; recommended path is a `0400` tmpfs file or short-lived broker instead of `ENV` (not yet implemented).

Enabled by default: `--read-only` rootfs with `--tmpfs` for `/tmp`/`/run`/`/var/tmp`/`~/.cache` (plus `~/.config/opencode` for OpenCode; Muse uses a writable persistent bind there), `--pull=never`, `--log-opt max-size/max-file`, private `--ipc`/`--cgroupns` (PID/UTS namespaces are private by default in docker), and `--hostname=box`.

Additional hardening (not yet enabled; deferred):
- Split `/persist` data vs. state with a size quota; host append-only audit-log bind.
- Rootful docker-group membership is effectively host root; gVisor does not fix that. Path forward: rootless Engine, Podman, `--userns-remap`, later Kata/Firecracker. The launchers abort on rootless/userns-remapped Engines pending that redesign.
- Supply chain: `FROM debian:trixie-slim` pinned to the manifest-list digest in the §4 pin table above (all targets share one base pin; re-pin on every Debian point release); NodeSource APT key vendored as `keys/nodesource.asc` with fail-closed fingerprint assert from `version-opencode.env`; OpenCode install verifies `npm view` metadata pins plus tarball `sha512` hashes before install; remaining deferred: add SBOM (`syft`/`trivy`) + image signatures (Cosign), and move to multi-stage builds (builder verifies artifacts; runtime keeps only the CLI + `git/jq/rg/fd`).
- Baked `HOST_UID:GID` forces per-machine rebuilds (accepted for now; dynamic entrypoint is future work).

Explicitly out of scope: malicious image builder, kernel/gVisor 0-day, host-root adversary, side-channel exfiltration over allowed egress.

### Open Decisions (explicit calls, Phase 6)

- `LC_ALL=C` for the git-identity `[[:print:]]` check: **rejected** — forcing `C`
  would make the check ASCII-only and reject legitimate Unicode author names.
  The check stays locale-dependent; determinism comes from the explicit
  newline / carriage-return / control-character rejection in the launchers.
- Multi-stage builder (verify artifacts in a builder, ship only the CLI +
  `git/jq/rg/fd` without `gnupg`/`nodejs`/`npm` in the runtime): **deferred** —
  the OpenCode CLI's runtime toolchain needs are not proven hermetic here, and
  an untested stage split risks breaking builds. The tarball-hash check plus
  `npm cache clean` is the implemented control; SBOM/signatures stay deferred
  with it above.
- `setup.sh` label pre-check (skip rebuild when the image already carries the
  pinned labels): **rejected** — silent skips risk stale-image confusion; the
  default stays build-all with explicit `--only <id>` /
  `--skip-build` opt-outs instead.
