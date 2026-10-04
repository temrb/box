# Codex harness

[Shared setup and containment](../../docs/operations.md) ·
[Acceptance](../../docs/acceptance.md) · [Harness index](../../docs/harnesses.md)

`box-c` packages stable Codex 0.160.0 from official complete Linux musl archives.
`version-codex.env` pins both SHA-256 digests. The image preserves `bin/`,
`codex-path/`, `codex-resources/`, and package metadata, including the code-mode
host, bundled rg, and bwrap. Build with `make -C box build-c`. Verified ARM64
archive bytes/layout do not establish native ARM64 runtime support.

[config/config.toml](config/config.toml) is the live system default, including the
selected model and agent/UI preferences. Its approval, permission, credential,
update, and SQLite settings match the image policy. [policy/requirements.toml](policy/requirements.toml) is image-owned at
`/etc/codex/requirements.toml`, root-owned 644. It constrains on-request approval,
reviewer user, the box permission profile named `:danger-full-access`, file credentials, disabled update
checks, and SQLite at `/persist/state/codex`. The profile pairs
`approval_policy = "on-request"` with `approvals_reviewer = "user"`; it is a
compatible container pattern, more conservative than full bypass
(`--dangerously-bypass-approvals-and-sandbox`). Upstream does not bless this
exact TOML verbatim. Codex runs inside the outer Docker
boundary. These settings do not require approval for every operation.
[Official managed configuration](https://learn.chatgpt.com/docs/enterprise/managed-configuration)
describes precedence; account/cloud requirements may supersede local policy.
Incompatible account policy must be reported and must not silently weaken the
intended profile.

Each physical project has two stores:

| Store | Location | Consequence of removal |
|---|---|---|
| Native home | `$state_root/<hash>/codex-home`, mounted at `/home/box/.codex` | Settings, file auth, sessions, history, logs and native home state removed |
| Named volume | `box-c-u<uid>-g<gid>-<hash>` at `/persist` | SQLite runtime state removed |

`CODEX_HOME=/home/box/.codex`. Default state root is
`~/.config/box-c/projects`; `BOX_C_STATE_ROOT` overrides it. The initial
`BOX_C_STATE_DIR` spelling remains an alias; both must agree when set.
Hash and `codex-home` are always appended. Homes are user-owned 700,
symlink-free, outside projects. Empty existing TOML and unknown preferences are
preserved. Config must be regular, user-owned, without group/other write access;
`auth.json` must be writable 600 for refresh. No host credentials/settings are
automatically imported. Moves and UID changes require explicit state migration.

```bash
box-c login                        # defaults to login --device-auth
box-c login --device-auth
box-c login status
```

Login is project-specific. Device login depends on account/workspace support.
Default browser callbacks at localhost cannot be promised without forwarding.
If unavailable, authenticate with the same pin on your own trusted machine, stop both
clients, and explicitly copy its `auth.json` into the exact project's protected
home with mode 600 and matching owner; never commit it or merge native homes.
See [official authentication](https://learn.chatgpt.com/docs/auth).

For explicit API-key login, put `OPENAI_API_KEY` in the protected provider file:

```bash
box-c login --with-api-key          # launcher imports the key via native stdin
box-c login status
```

Default ChatGPT runs do not forward that key. `BOX_C_AUTH=api` permits key
forwarding for explicit API-oriented runs/shells; it does not itself perform
login. Cached auth mode and provider-file contents are distinct. `box-c logout`
removes native cached auth for this project; explicitly remove the provider-file
key too if it should no longer be available. Cache transfer/API mode persistence
still need account-dependent acceptance evidence.

Setup refreshes `~/.config/box-c/config.toml` with one `.bak`. Every launch mounts
`BOX_C_CONFIG` or that installed default read-only at `/etc/codex/config.toml`.
Native `.codex/config.toml` discovery runs from repository root to launch directory,
subject to native trust and project-field restrictions. Home preference overrides
are reset under an exclusive lock held throughout the client run. The original
home configuration is backed up once as `config.toml.box-legacy`; native project
trust records remain in the home config. Auth and transcripts are retained.
Policy changes require an image rebuild. `--dry-run` creates no home/config/CLI
state and does not read keys. No model turn is used by the
bounded [native probe](native-probe.py); it checks loaded requirements,
effective config, normalized thread policy, and conflicting native overrides.

A complete project reset removes both stores after exact inventory and stopped
containers. Removing only the volume retains auth/transcripts; removing only the
home leaves SQLite state. Full uninstall must include overridden roots and both
stores explicitly, as described in shared operations.
Pin update: see [upgrades §12](../../docs/upgrades.md) (`update-check` →
`update` → `gen-verify.sh`/`gen-pins.sh` → `verify-static` + `pins` →
`build-c` → `sync-pins-c`). Managed-policy rebuild requires an image rebuild.
