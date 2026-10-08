You are conducting a deep security architecture review of:

<https://github.com/temrb/box>

The purpose of this thread is **not yet to implement changes or produce the final remediation plan**. First, independently verify and deepen the existing findings, identify remaining live security issues and improvement opportunities, and establish enough evidence that a later thread can turn the results into a concrete, prioritized implementation plan.

## Goal

Determine how secure `box` currently is for running coding agents, especially untrusted or partially trusted agent-generated workloads, while preserving its intended functionality.

Focus on answering:

1. What are the actual trust boundaries?
2. What security properties are genuinely enforced versus merely documented?
3. Where can an agent, malicious project, compromised dependency, or compromised host user cross those boundaries?
4. Which residual risks are inherent to the chosen architecture versus fixable weaknesses?
5. Which improvements can materially strengthen security **without sacrificing current functionality or compatibility**?
6. Where would stronger security necessarily involve an explicit tradeoff?
7. Can `box` safely become effectively **runsc-only** while leaving `runc` installed for Docker/other workloads?
8. What must be true before claiming that the system fails closed rather than silently weakening isolation?

Do not assume prior conclusions are correct. Treat the information below as **starting hypotheses that must be verified against the current repository state**.

## Starting context from the previous review

The repository appears to use a **rootful Docker Engine** with gVisor `runsc` as its preferred runtime.

The containerized Muse, OpenCode, and Codex processes appear to run as a **non-root UID/GID matching the invoking host user**, despite build stages temporarily using root. Relevant observed behavior included:

- `box/Dockerfile` creates a `box` user from `HOST_UID` / `HOST_GID`.
- Runtime images ultimately set `USER ${HOST_UID}:${HOST_GID}`.
- Image-build stages temporarily switch to `USER 0:0` for package/software installation and then switch back.
- `box/lib/build.sh` appears to reject UID/GID 0 and instruct the operator to run as a normal non-root host user.
- Project preflight appears to reject `/`, `/root`, broad system paths, the whole home directory, credential directories, and other sensitive locations.

The shared container launch path in `box/lib/run.sh` appeared to include substantial hardening:

- `--user "$host_uid:$host_gid"`
- `--cap-drop=ALL`
- `--security-opt=no-new-privileges`
- read-only root filesystem
- private IPC namespace
- private cgroup namespace
- bounded memory, CPU, and PID counts
- limited tmpfs mounts
- dedicated bridge networking
- explicit project/state mounts rather than broad host-home mounting

The repository's own security audit stated that it did **not** reproduce:

- Docker socket mounting into agent sessions
- broad supplementary group inheritance
- recursive host-bind exposure
- cross-project state reuse
- parser command injection
- silent explicit-runtime substitution

Verify all of these statements independently.

## Important runtime finding to investigate

The launchers appear to distinguish two OCI runtimes:

- `runsc`: gVisor, intended as the stronger isolation boundary.
- `runc`: standard Linux container isolation, described by this project as a hardened fallback.

Current behavior appears to be:

- normal non-shell runs begin with `runsc`;
- a failed runsc startup/DNS probe may automatically select `runc`;
- that fallback emits NOTICE/WARNING output;
- explicit `--runsc` does not fall back;
- explicit `--docker-fallback` selects `runc`;
- shell runs do not automatically choose a fallback;
- `BOX_M_ALLOW_FALLBACK=0`, `BOX_O_ALLOW_FALLBACK=0`, and `BOX_C_ALLOW_FALLBACK=0` appear capable of forbidding fallback.

The previous review's tentative recommendation was:

> Keep `runc` installed/registered on the host, but make `box` fail closed on `runsc` failure by default. Do not automatically weaken the sandbox. If `runc` is needed, require an explicit user action such as `--docker-fallback`.

Deeply verify whether this recommendation is technically sound and whether it causes any compatibility, setup, verification, authentication, networking, shell, architecture, or operational regressions.

Also distinguish carefully between:

1. **preventing `box` from using `runc`;**
2. **unregistering/removing `runc` from Docker entirely.**

Do not conflate them.

Determine exactly which repository code, setup paths, tests, verification scripts, documentation, CI assumptions, or unrelated Docker behavior depend on `runc` continuing to exist.

## Rootful Docker trust boundary

A major architectural question is rootful Docker itself.

The previous analysis concluded that:

- the **agent container does not appear to receive the Docker daemon socket**, which is important;
- however, access to the rootful Docker daemon on the host is itself effectively host-administrative authority;
- therefore the threat model must distinguish an agent escaping its sandbox from malicious code already executing as the host user with access to Docker.

Investigate this carefully.

Establish:

- how the launcher obtains Docker access;
- which socket/context/host it permits;
- whether it pins or validates the Docker endpoint;
- whether `DOCKER_HOST`, Docker contexts, CLI plugins, environment overrides, configuration files, aliases, shell functions, or project-controlled paths could redirect or influence Docker execution;
- whether being in the `docker` group is assumed;
- whether any host-side code path before container creation can execute project-controlled content;
- whether rootful Docker is truly required by current gVisor and UID/GID design;
- whether rootless Docker or Docker `userns-remap` could ever provide equivalent functionality;
- what exactly would break if rootless/userns were introduced;
- whether the current documentation's statement that rootless/userns require a separate mapping design is still accurate.

Do not recommend rootless Docker merely because it sounds safer. Determine whether it can actually preserve this project's functional and security invariants.

## Host-side launcher attack surface

Treat the code that executes **before the Docker boundary exists** as security-critical.

Review all relevant launcher/bootstrap/preflight/setup paths, including at minimum:

- `box-m`
- `box-o`
- `box-c`
- `box-m-login`
- `setup.sh`
- `lib/preflight.sh`
- `lib/tools.sh`
- `lib/config.sh`
- `lib/docker.sh`
- `lib/launcher.sh`
- `lib/run.sh`
- `lib/build.sh`
- tool-specific launch/install/native/update adapters

Investigate:

- PATH attacks
- shell-function/import attacks
- hostile environment variables
- `BASH_ENV` / shell startup behavior
- command substitution
- unsafe `eval`
- unsafe `source`
- project-controlled configuration
- symlink attacks
- path traversal
- TOCTOU/check-use races
- Git environment poisoning
- Git linked worktrees/submodules
- malicious filenames
- newline/control-character injection
- unsafe ownership/mode assumptions
- temporary-file handling
- signal handling
- cleanup races
- Docker CLI configuration poisoning
- update/install races
- concurrent setup/update execution
- inherited file descriptors
- supplementary groups
- unexpected device/socket/FIFO exposure
- host namespaces

Identify both exploit paths and defenses.

## Container boundary review

Verify the effective runtime configuration rather than relying only on command construction.

For each harness and relevant runtime, inspect or reproduce where feasible:

- effective UID/GID
- supplementary groups
- capabilities and `CapBnd`
- `NoNewPrivs`
- seccomp
- AppArmor/SELinux behavior
- root filesystem writability
- mounted paths
- recursive bind behavior
- propagation settings
- `/proc`
- `/sys`
- `/dev`
- devices
- IPC
- PID namespace
- network namespace
- cgroup namespace
- hostname
- Docker socket absence
- host socket absence
- privileged mode absence
- host PID/network/IPC absence
- resource limits
- mount flags such as `nosuid`, `nodev`, and `noexec`/`exec`
- whether executable tmpfs is required
- whether any writable location permits a realistic privilege-boundary bypass
- whether gVisor changes or ignores any Docker security options

Pay particular attention to the differences between **runsc and runc**. Do not assume flags have identical security meaning under both runtimes.

## Network / exfiltration boundary

The repository appears intentionally to allow outbound networking and does not enforce a destination allowlist.

The previous review considered this a residual risk rather than necessarily a bug because coding agents may require arbitrary internet access.

Investigate:

- exact network configuration;
- inter-container communication controls;
- access to host services;
- loopback behavior;
- Docker gateway/host reachability;
- metadata-service exposure in cloud environments;
- IPv4/IPv6 differences;
- DNS behavior;
- whether an agent can scan/reach LAN services;
- whether gVisor changes relevant behavior;
- credential exfiltration possibilities;
- whether the project could offer an optional restricted-egress mode without breaking the normal unrestricted mode.

Do not simply recommend disabling networking.

Determine what useful security modes could coexist with full current functionality.

## Credential and persistent-state review

Map every piece of state and every credential path for Muse, OpenCode, and Codex.

Determine:

- what exists on the host;
- what is bind-mounted;
- what resides in Docker volumes;
- what is global across projects;
- what is per-project;
- what persists between sessions;
- what authentication information is accessible to the agent;
- whether secrets are passed by value or variable name;
- whether `/proc` or child processes can expose those values;
- whether secrets can leak to logs, dry runs, `docker inspect`, crash output, command lines, or persisted transcripts;
- whether a compromised project can modify persistent trust/approval/auth state in ways that affect later projects;
- whether persistence boundaries match documentation.

Pay special attention to any state deliberately shared across projects.

## Project filesystem boundary

The agent is intentionally allowed to modify the selected project. That is a required capability, not automatically a vulnerability.

Determine whether it can influence anything outside that project through:

- symlinks
- hard links
- bind behavior
- mount recursion
- linked worktrees
- Git metadata
- submodules
- Unix sockets
- devices/FIFOs
- nested mounts
- mount points introduced after preflight
- rename/move races
- TOCTOU
- host processes interacting with project files
- filesystem-specific behavior

Evaluate whether the existing preflight logic provides a meaningful security boundary or only best-effort hygiene.

Clearly distinguish inherent writable-project risk from unintended host filesystem exposure.

## Supply-chain and image integrity

Review:

- pinned base-image digest
- tool artifact URLs
- SHA-256 validation
- architecture-specific artifacts
- archive validation
- Docker build context exposure
- auto-update disabling
- version labels
- image tag construction
- image inspection before launch
- mutable local images
- image override mechanisms
- Dockerfile build inputs
- package-manager trust
- provenance/SBOM/signature opportunities
- update workflow
- rollback behavior
- stale installed pins
- compromised upstream release scenarios

Determine which supply-chain risks are already mitigated and which remain meaningful.

## Resource and denial-of-service risks

The repository's existing audit appears to identify residual operational risks including:

- tmpfs competing with the container memory cgroup;
- OOM from large cross-filesystem moves;
- no aggregate limit across concurrent sessions;
- persistent images/build cache/volumes/logs consuming host disk;
- possible cleanup failures after daemon failure/SIGKILL/host failure;
- project/state persistence across sessions.

Revalidate these and search for additional DoS paths involving:

- disk
- inodes
- file descriptors
- processes/threads
- CPU
- memory
- swap
- logs
- network bandwidth/connections
- Docker daemon resources
- concurrent sessions
- decompression/archive bombs
- build contexts
- state databases
- probe containers

Classify whether each is security, reliability, or both.

## Existing repository security audit

Read the repository's current security/resource audit and its referenced evidence, but do not accept it uncritically.

At minimum review:

- `box/docs/security-resource-audit.md`
- architecture documentation
- operations documentation
- troubleshooting documentation
- acceptance records
- generated/static/native verification scripts
- Bats tests
- runtime evidence referenced by the audit

Check whether its evidence still matches the current source revision.

Where possible, trace claims back to exact code and tests.

Identify:

- stale evidence;
- assumptions not exercised;
- tests that only inspect generated arguments rather than effective runtime state;
- untested architecture differences;
- untested failure paths;
- tests capable of passing while the security invariant is broken.

## Runsc-only policy question

Give special attention to this proposed policy:

> `box` should use gVisor/runsc by default and fail closed if runsc is unavailable or its startup/network probe fails. `runc` may remain installed and registered, but `box` should only use it following explicit user intent.

Determine:

- whether it preserves every supported normal workflow;
- whether device/browser login has runtime-specific needs;
- whether localhost callbacks work;
- whether Muse/OpenCode/Codex behave differently;
- whether DNS/HTTPS reliability makes this operationally problematic;
- whether ARM64 changes the answer;
- whether setup currently insists on both runtimes;
- which tests intentionally require the runc matrix;
- whether verification should continue testing runc even if production defaults become runsc-only;
- whether `BOX_*_ALLOW_FALLBACK=0` currently blocks both automatic and explicit fallback, and whether those semantics are desirable;
- whether a better policy is to remove automatic fallback while retaining explicit `--docker-fallback`.

Do not assume “disable runc completely” is equivalent to the safer policy.

## Security controls worth verifying as invariants

Determine whether these should become explicit automated invariants:

- no Docker/Podman/container-engine socket in any agent container;
- never `--privileged`;
- never `--cap-add`;
- capabilities remain empty;
- `no-new-privileges` remains enabled;
- agent runtime UID/GID is never 0;
- no host PID/IPC/network namespace;
- root filesystem remains read-only;
- only allowlisted host mounts exist;
- project bind remains nonrecursive/private as intended;
- host credential directories are never mounted;
- broad `$HOME` is never mounted;
- fallback cannot occur silently;
- runsc-required mode truly fails closed;
- resource ceilings remain applied to both probes and real sessions;
- image labels/pins match expected values before execution;
- Docker endpoint cannot be redirected by hostile project input.

Assess whether each invariant is currently enforced in code, tested statically, tested dynamically, both, or neither.

## Threat-model matrix

Analyze at least these attacker positions separately:

1. Malicious instructions/model behavior inside the coding agent.
2. Malicious repository/project contents.
3. Malicious dependency/build script executed by the agent.
4. Compromised upstream Muse/OpenCode/Codex binary.
5. Compromised container image/build dependency.
6. Malicious process already executing as the invoking host user.
7. Another local unprivileged user.
8. Another container on the same Docker host.
9. Remote network attacker reaching services started by the agent.
10. Docker daemon or host-root compromise.

For each, state what `box` is expected to defend against and what is intentionally outside its threat model.

## Method

Use the current repository, not recollection.

Inspect source, tests, documentation, recent relevant history, and open repository issues/PRs where useful. Compare documentation to implementation.

Run non-destructive static tests and safe disposable runtime experiments where feasible. Do not use live credentials, production projects, or destructive host operations.

For important claims, provide direct evidence such as:

- file and function;
- relevant line/range;
- exact runtime flag;
- test name;
- runtime inspection;
- reproducible command;
- commit/history context where relevant.

Distinguish clearly between:

- **Verified**
- **Likely but not fully verified**
- **Unverified**
- **Disproved**

Do not infer security properties solely from comments.

## Decision standard

Optimize for meaningful security improvement, not checkbox hardening.

Do not recommend a control merely because it is conventionally considered safer. For every proposed improvement area, determine:

- exact threat mitigated;
- whether the threat is realistic under this architecture;
- current protection;
- remaining exposure;
- compatibility impact;
- performance impact;
- UX/operational impact;
- maintenance burden;
- whether equivalent functionality is preserved.

Prefer improvements that strengthen isolation while retaining all intended capabilities.

If a security gain inherently requires loss of functionality, identify that tradeoff explicitly rather than claiming it is free.

## Expected output

Produce an evidence-backed security assessment suitable as direct input to a later implementation-planning thread.

Include:

### 1. Executive assessment

A concise judgment of the current architecture and its strongest/weakest boundaries.

### 2. Verified architecture

A precise description of host → Docker → runtime → container → mounts/network/state trust boundaries.

### 3. Finding register

For every meaningful finding, give:

- ID
- title
- severity
- likelihood
- confidence
- affected threat model
- evidence
- exploit/failure mechanism
- existing mitigation
- residual exposure
- whether it is a live issue, accepted risk, false positive, or documentation/test gap

Order by risk, not file location.

### 4. Runsc/runc conclusion

Give a dedicated conclusion on:

- automatic fallback;
- explicit fallback;
- removing `runc` from `box`;
- removing `runc` from the host;
- what can be changed with effectively no functionality loss.

### 5. Rootful-Docker conclusion

Explain exactly what risk remains because the daemon is rootful, who can exploit it, and whether any practical architecture change can reduce that risk without breaking the current design.

### 6. Improvement candidates

List security improvements supported by the evidence.

Do **not** turn this into the final implementation plan yet. For each candidate, record only enough information for later planning:

- security benefit
- functionality impact
- likely implementation surface
- prerequisite/dependency
- test/acceptance criteria that would eventually prove the improvement

### 7. No-regression security invariants

Define the properties that future changes must never weaken.

### 8. Evidence gaps

State what could not be conclusively verified and what test/reproduction would close each gap.

### 9. Planning inputs

End with a compact set of facts and decisions that a subsequent agent can use to create the concrete remediation/improvement plan.

Do not implement changes in this phase. Do not open PRs or modify the repository. The objective is to solidify the evidence and identify the genuinely live issues before planning remediation.
