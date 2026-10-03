# OpenCode v2 cutover evidence — 2026-10-02

In-place v2 only: active v1 compatibility, duplicate candidate image/config/pins,
archive overrides and rollback scaffolding are retired. Historical raw evidence
is retained, including its superseded or invalid PASS labels.

Initial audit: shipped client preference persistence FAILED (tmpfs parent);
ordinary permission inspection FAILED (unavailable events); saved approvals
UNVERIFIED; hard-denial PASS invalid (absence of completion counted as denial).
The results below replace those claims for the production implementation.

## Identity and scope

Uncommitted working tree based on `1d212452ece8b095cf3de98673eeccda08160883`.
The [SHA256 source manifest](opencode-v2-cutover-source.sha256) identifies the
actual tested launcher, config, native probe, guards, tests, generator and shared
sources. Linux x86_64/amd64; UID/GID 1000:1000; Docker Engine 29.8.1;
gVisor `runsc release-20260921.0`, OCI spec 1.2.1.

Production image: `box-o:2.0.6-u1000-g1000`, image identity
`sha256:09673097761d95ebb69b3cd9976fec807456ed44d3ffc73ce97e21b31b0be3be`.
Image user and all three labels were checked against installed SHA256 pins.

- Version: `2.0.6`
- amd64: `228deae7b0c7d604ba236956da246e1c5109bc9269b327d0208240599490689c`
- arm64: `c074bec6fd05256aaa44525a9986418626e0045994437f30e82b3ece092919d8`

Fixtures used disposable user-owned directories directly under the real home;
ancestor/credential guards were retained. No provider/account credentials were
imported, and no external model was called. Build/permission/state success does
not establish authenticated operation.

## Observed results

| Command/check | Observed outcome |
|---|---|
| `make -C box verify-static` | PASS, exit 0: syntax, configuration, generated parity, pin consistency, ShellCheck and all **349 Bats tests**. [Retained output](opencode-v2-cutover-static.txt). |
| `make -C box pins verify-generated` | PASS, exit 0. |
| `make -C box build-o` | PASS, exit 0: production standalone archive hash/layout/ELF/version and image user/label assertions. [Build output](opencode-v2-cutover-build.txt). |
| `make -C box verify-native-opencode` | PASS, exit 0: installed production launcher under explicit **`--runsc`** and **`--docker-fallback`**. [Native output](opencode-v2-cutover-native.txt). |
| Installed-pin recovery | Incompatible installed pins reject before configuration/launcher refresh. Validated image + atomic pin synchronization followed by setup recovers. Valid differing v2 pins retain preservation behavior in Bats. |
| Source capture | Regeneration and `--check` through the installed launcher PASS on both explicit runtimes. Ordered `permissions`, `default_agent` and `update` match the shipped source record; artifacts replace only after comparison and redaction. This is source inspection, not enforcement. |
| Preferences/state | `cli.json` and state markers survive container restart. Config siblings are writable on `/persist/config/opencode`; host `opencode.json` rejects writes. A second physical project has neither marker nor saved approval. Legacy fixture marker remains untouched; dry-run creates no files/volumes. |
| Permission matrix | All 25 requested tool cases per runtime have matched native evidence; no unavailable cases. Build/explore `.env` and suffix reads/writes ask; examples allow; external asks report `/tmp/*`. Custom agent, project override and `--auto` complete execution. Explicit deny survives `--auto`. |
| Durable approvals | Initial matched ask, native API `always` approval and saved-record inspection, then matched completed read; a new container with the same project store allows the read. Explicit deny still rejects after saving and restarting. A second project asks. |
| Native credential path/hygiene | Pinned `debug paths` locates credentials/sessions/saved approvals in `/persist/data/opencode/opencode/opencode.db`; `auth.json` is a legacy importer, not native v2 login storage. Guarded ordinary/shell entrypoint uses umask 077; database and journal owner/mode/type/parent-link checks fail without silent repair. Fresh database mode 600 observed. Bats covers unsafe modes, symlinks and non-files. |
| Account readiness | An empty native credential store explicitly FAILS readiness under each runtime. The unconditional promotion-failure placeholder is removed; concrete auth, metadata, version, config/writability and native source checks remain. |
| Fixture cleanup | PASS: every fixture container/volume removed. Independent final Docker inventory found no OpenCode fixture containers or `box-o-v2` volumes. Real legacy volumes were not modified. |

The loopback provider's context limit was corrected to avoid compaction before
tool execution; title requests return text rather than tools. Classification
requires the requested tool/path and exact permission resource. Ask requires
native request plus refusal, allow requires completed execution, and deny requires
explicit `Permission denied` evidence. Empty/malformed output, unrelated resources,
pending/error tools, provider/startup failures and timeouts fail regressions.

The saved-approval test initializes the pinned server's native agent API before
using its experimental permission API, then proves the saved rule through real
tool execution and container restart. `--auto` remains separate coverage.

## Unmet acceptance gates

- Real provider `/connect` login, successful model turn, restart and resumed
  session under amd64 runsc: **UNMET**. Per user instruction, provider/account
  setup remains native and user-driven; no account was seeded or imported.
- Native ARM64 execution: **UNMET**. Artifact/ELF support is not runtime evidence.
- Actual repository-root GitHub workflow run for this working tree: **UNMET**.
  Local static success is not remote-CI acceptance; these changes are uncommitted.
