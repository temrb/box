# Containerized coding harnesses

Muse, OpenCode, and Codex run in separate Debian images through rootful Docker
and gVisor (`runsc`). Handwritten `box-m`, `box-o`, and `box-c` wrappers share
filesystem preflight, pin validation, identity, networking, and containment.

Start with the [harness index](docs/harnesses.md) and
[acceptance record](docs/acceptance.md). Implemented integration does not imply
accepted native policy, authenticated operation, or ARM64 runtime support.
OpenCode permissions are configurable approval defaults within Docker/gVisor
containment. Shipped OpenCode is pinned v2 (standalone binary, native v2 config).

```bash
make -C box setup                     # from the repository root
export PATH="$HOME/.local/bin:$PATH"
cd ~/projects/my-app
box-m --dry-run
box-o --dry-run
box-c --dry-run
```

If setup reports an unsafe config ancestor, see
[troubleshooting](docs/troubleshooting.md#setup-rejects-a-writable-config-ancestor)
for the metadata check and repair steps before rerunning setup.

Setup installs every launcher and template. `--only <id>` selects the image to
build; `--skip-build` installs without building. Invoke these options through
`bash box/setup.sh`. Reruns preserve installed pins and the selected `box`
default; a fresh install selects Muse. Native login is a separate step in each
harness guide. Empty protected `providers.env` is sufficient for device login.
New images must expose auth supervisor contract 3; rebuild older images through
`make build-<stem>`. Auth scope is configurable per harness (`BOX_AUTH_SCOPE`,
`BOX_M/O/C_AUTH_SCOPE`, or `~/.config/box/state.toml`; Muse defaults to
global, OpenCode/Codex to project); first launch after upgrade with legacy
credentials requires explicit `make -C box auth-migrate|auth-init`.

The source layout is `harnesses/<id>/` for native configuration, image policy,
pins, launch/install/update/validation adapters, and verification partials;
`lib/` for shared primitives; `verify.d/` for shared verification sections;
and generated `verify-<id>.sh` for self-contained stdin delivery. Images use
one `Dockerfile`; host installation/build/update flows use Make targets and
registry records in `lib/tools.sh`. User state is outside the checkout.

- [Architecture and generated pin table](docs/architecture.md)
- [Setup, usage, verification, recoverable reset, full state inventory, and code-only uninstall](docs/operations.md)
- [Upgrades, template refresh, policy rebuild, and recovery](docs/upgrades.md)
- [Troubleshooting and runtime selection](docs/troubleshooting.md)
- [Adding a harness](docs/adding-a-tool.md)
- [Security, resources, lifecycle audit and evidence](docs/security-resource-audit.md)

## Disclaimer

Unofficial wrappers, no affiliation with Meta, OpenAI, or the OpenCode
maintainers. Bring your own accounts: use remains subject to the
Meta/OpenAI/OpenCode terms of service, including account usage and rate
limits. No credential pooling: each user authenticates with their own
credentials; never commit or share `auth.json`, API keys, or
`providers.env` contents. Wrappers are MIT (see root `LICENSE`);
underlying tools keep their own licenses (OpenCode MIT, Codex CLI
Apache-2.0, Muse proprietary). Built images use local-only
per-UID/GID tags (for example `box-m:<ver>-u<uid>-g<gid>` via
`box/lib/build.sh`); do not `docker push`, export, or share built
images — especially Muse images containing the proprietary binary.
Automatic update checks are disabled for reproducible builds; you
remain responsible for applying mandatory upstream updates promptly
through the pin update flow.

`make -C box verify-static` runs recursive shell syntax, declared JSON/TOML
parsing, generated-output and pin consistency, ShellCheck, and Bats.
`make -C box pins` checks the pin invariant separately. Runtime gates and
account-dependent gates are recorded separately from static success.
