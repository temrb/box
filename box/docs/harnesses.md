# Harness index

| Harness | Launcher / build | Native configuration and authentication | Acceptance |
|---|---|---|---|
| [Muse](../harnesses/muse/README.md) | `box-m` / `make build-m` | Non-auth global config home; selectable auth scope (`global` default); Meta device login or API key | Startup enforcement implemented; account/model and ARM64 gates remain |
| [OpenCode](../harnesses/opencode/README.md) | `box-o` / `make build-o` | Read-only host config under writable persistent volume parent (no image policy); selectable auth scope (`project` default); native `/connect` | Configurable approval defaults; v2 shipped, account/model/resume gates remain |
| [Codex](../harnesses/codex/README.md) | `box-c` / `make build-c` | Writable project home (non-auth) and image requirements; selectable auth scope (`project` default); device login default, explicit API login | AMD64 native policy probe passes; authentication/resume and ARM64 gates remain |

Build commands run from `box/`, or use `make -C box` from the repository root.
All wrappers preserve the same project hashes, UID/GID tags, separate networks,
volume names, resource limits, and default selection contract. Read the
[acceptance record](acceptance.md) for exact evidence and unmet gates.

Shared guides describe shared behavior. Each harness guide owns native settings,
login, persistence, template adoption, logout/reset consequences, pin sources,
and native acceptance limitations. Add a row and a complete guide when adding
a harness; do not duplicate native configuration blocks in shared guides.

All harnesses share resolver-backed `state-discover`, recoverable `project-reset`,
`state-remove FULL=1`, and state-preserving `uninstall-code` operations. Image
contract 2 records auth projection phases; old contracts are refused, including
explicit image overrides. Runtime and native credential membership qualification
remain subject to the [acceptance record](acceptance.md).
