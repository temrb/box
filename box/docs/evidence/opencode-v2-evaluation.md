# Historical candidate evaluation (superseded)

The implementation below is retired. Its permission and preference PASS claims
do not establish shipped acceptance; see [current cutover evidence](opencode-v2-cutover.md).
The v1 rollback recommendation below is superseded by the in-place v2 decision.

# OpenCode v2 candidate evaluation — promotion pending

Evaluation date: 2026-10-02. Working-tree baseline:
`1d212452ece8b095cf3de98673eeccda08160883` (uncommitted changes, not a release
revision). Linux x86_64, UID/GID 1000:1000, Docker Engine 29.8.1,
runsc release-20260921.0. Candidate image config digest:
`sha256:39ab60abf6f6eabb22a23a9d9bbd0df0db872e51596539f6e1a7d7db47546e2b`.
The [source hash manifest](opencode-v2-source.sha256) identifies evaluation
inputs in this uncommitted tree; [selected output](opencode-v2-preflight.txt)
records the four candidate executions. Evaluation volumes were verified absent
after cleanup.

The frozen candidate is **2.0.6**, selected from the upstream
[installation page](https://opencode.ai/v2/docs). No build resolves `latest`.
The SHA256 values below were computed from downloaded HTTPS release archives;
no independent signed checksum provenance is claimed.

| Architecture | Frozen URL | Archive SHA256 |
|---|---|---|
| amd64 baseline, glibc | `https://opencode.ai/files/bin/2.0.6/opencode-linux-x64-baseline.tar.gz` | `228deae7b0c7d604ba236956da246e1c5109bc9269b327d0208240599490689c` |
| ARM64, glibc | `https://opencode.ai/files/bin/2.0.6/opencode-linux-arm64.tar.gz` | `c074bec6fd05256aaa44525a9986418626e0045994437f30e82b3ece092919d8` |

Both archives contain exactly one regular executable, `opencode`. ELF headers
match x86_64 and AArch64 respectively. ARM64 was inspected, **not executed**.
The amd64 image uses the source Dockerfile's pinned Debian base, installs
Debian Python, and installs the hashed standalone binary without npm or
NodeSource. Its user and all three candidate pin labels are checked.

`make -C box evaluate-opencode-v2` builds a separate evaluation image, executes
four disposable preflights (first start and restart under explicit runsc and
hardened runc), then deletes its containers and volumes. The image remains for
inspection. It does not install candidate pins/config, import account state,
use v1 volumes, or change shipped defaults. Retained archive input can be
supplied with `OPENCODE_V2_ARCHIVES=/path` (`amd64.tar.gz`, `arm64.tar.gz`);
verification still uses the frozen pins. The artifact-only command is
`bash box/tests/native/opencode-v2/evaluate.sh --artifacts-only /path`.

Observed results on both runtimes, including restart:

- PASS: exact native startup output `opencode v2.0.6`.
- PASS: shipped v1 syntax normalizes to the expected ordered `.env` approval
  rules and external-directory ask, on separate disposable configuration/state.
- PASS: native v2 configuration source inspection returns the ordered rules,
  `default_agent: plan`, and `update: disable`.
- PASS: global config rejects writes; writable sibling `cli.json` fixture
  survives restart on the evaluation volume. This is filesystem preference
  persistence, not a native TUI preference-edit or authenticated resume test.
- FAIL: GET `https://opencode.ai/v2/docs` returns HTTP 403 on both runtimes.
  This is an endpoint rejection; it does not prove DNS or TLS failure.
- UNMET: real provider login, successful model turn, and resumed v2 session
  under amd64 runsc. No account or credentials were imported.
- UNMET: v2 native tool approval matrix (including saved approvals), full shared
  containment/network equivalence, clean-room base rebuild, two-project state
  isolation, unsafe v2 auth-cache checks, native ARM64 execution, remote CI.

The evaluator intentionally exits nonzero and **does not promote**. Shipped v2
pins, config, launch contracts, updater, and volumes are separate from this
evaluation; retain the v1 rollback bundle (pins, config, image policy,
npm/NodeSource dependencies, volumes) outside the shipped tree. The shipped
registry is `sha-pinned` (three keys); the retired v1 npm/NodeSource parser
branches are removed from shipped code. The candidate uses the shared SHA256
parser/assignment home in `lib/pins.sh`.

Ordinary permissions supply configurable defaults within Docker/gVisor
containment. Permissive agent overrides and saved approvals follow
[upstream behavior](https://opencode.ai/v2/docs/permissions); universal mandatory
prompting is no longer the acceptance requirement. Native hard denials are
separate, and no experimental deny policy is shipped. Historical v1 failures
remain unchanged in the [acceptance record](../acceptance.md). The v1 native
matrix now expects allows for its permissive-agent and `--auto` fixtures while
still failing missing inspection and unexpected outcomes.

Candidate v2 configuration removes `lsp`; run project compiler, lint, and
typecheck commands instead. See the
[migration guide](https://opencode.ai/v2/docs/migrate-v1/). Native source inspection
is not proof of native tool enforcement. The remaining integration work must
adapt provider fixtures/events, credential paths, service lifecycle, updater,
registry and installed-pin migration, then pass the account gates before
switching production. Never open converted v2 state with v1.

Verification after shipment (shipped v2 2.0.6, three SHA256 keys, no npm):

- `gen-verify.sh` and `gen-pins.sh` regenerated their outputs; generated parity
  and shipped pin consistency pass (`check-pins.sh`: Muse 1.4.0-R4161.1,
  OpenCode 2.0.6, Codex 0.160.0).
- `make -C box verify-static` green: syntax, declared JSON/TOML, generated
  parity, pins, ShellCheck 0.11.0, and all 345 Bats tests pass, including
  `Codex validator rejects unsupported seed and policy fields`
  (`tests/bats/audit.bats`) and all 11 `opencode-v2.bats` regressions
  (SHA256 load/cache-invalidation, missing/malformed digests, corrupt archives
  before Docker, shipped config-order, Dockerfile no-npm, label-mismatch,
  update explicit-version scoping, readonly-global/tmpfs, cli.json/unsafe-cache,
  probe compile/no-tautology).
- `make -C box build-o` green: `box-o:2.0.6-u1000-g1000` built + labels verified.
- `make -C box verify-native` (exit 1, UNMET as designed): all three pass native
  version startup and shared containment under explicit runsc and hardened runc;
  full generated verification stops at DNS/transport then auth (no credentials
  imported). Shipped v2 Python probe runs but tool-path inspection is currently
  `unavailable` for all 25 tool cases per runtime (fails closed, no false PASS);
  `deny/ask-matrix: configured deny survives --auto` PASSes. Codex native
  policy/state and setup rerun checks pass. Account login/model/resume, native
  ARM64, and remote CI remain UNMET and are not waived.

The old unconditional verifier failure remains a promotion-pending failure;
it no longer claims universal prompting as a requirement. It must be removed
only after replacement native tool and account checks exist and pass.
