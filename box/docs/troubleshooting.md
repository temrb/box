# Troubleshooting

### 14. Diagnostics and fallback runners

| Symptom | Check and remedy |
|---|---|
| Dry-run cannot find config/pins | Run setup; check the selected harness's `BOX_<stem>_CONFIG` and `BOX_<stem>_VERSION_FILE`. Pins live in packages in source, with unchanged installed leaf names. |
| Unsafe ancestor, symlink, owner, or mode | Inspect path metadata, including every ancestor. Choose a private user-owned state root outside projects; do not automatically repair an auth cache. |
| Native auth cache mode rejected | Stop the harness, confirm the actual owner, then explicitly set 600 only for the intended cache. Mode 400 provider files are accepted; native OAuth refresh requires writable 600. |
| Engine unavailable | Check access to the local rootful socket, Engine >= 25, and registered runsc/runc runtimes. Rootless/userns needs a separate mapping design. |
| Version or image label mismatch | Complete the build and installed-pin synchronization in [upgrades](upgrades.md). Setup keeps differing installed pins. |
| Dry-run works but launch fails | Dry-run does not contact Docker or authenticate. Check native startup and account gates separately. |
| runsc startup/DNS probe fails | Inspect runsc/Engine versions and daemon diagnostics. Explicit `--runsc` stays fail-closed; normal runs may fall back with NOTICE/WARNING. |
| Fallback forbidden | `BOX_<stem>_ALLOW_FALLBACK=0` intentionally blocks explicit and automatic fallback. Repair runsc rather than disabling the control. |
| OpenCode permissions appear correct globally | Agent/session layers still matter. See the [OpenCode guide](../harnesses/opencode/README.md); ordinary rules are configurable approval defaults; Docker/gVisor supplies containment. Native policy checks are separate from real `/connect` login/model/resume. |
| Codex policy probe fails | Check the exact pin, `/etc/codex/requirements.toml`, native loaded requirements, and account policy. Do not weaken requirements to pass. |
| Codex starts with no prior sessions | Confirm physical project path, UID/GID, and `BOX_C_STATE_ROOT`; moving a project changes its home/volume identity. Never merge transcripts/auth automatically. |
| Device login unavailable | Follow the native harness guide. Codex browser localhost callbacks require explicit forwarding; protected manual cache transfer is a fallback. |
| OpenCode server cannot write config siblings | Keep `/persist/config/opencode` on the project volume writable and its host config file read-only. |
| Model/provider rejected | Use native account-compatible selection and check account/provider access. No Codex/OpenCode model is seeded. |
| Exit 137 during copy/build/cache population | 137 alone is not proof of OOM. Use the printed container name with a bounded `docker events --since ... --until ... --filter container=NAME --filter event=oom` query. `--rm` removes post-exit inspection data; event history is finite and can be lost on daemon restart. Move large scratch work to a verified disk-backed project path, verify partial files, then restart. |
| DNS probe cleanup warning | Inspect/remove only the exact probe container ID in the warning after restoring daemon access. SIGKILL or host failure can bypass cleanup; do not remove unrelated sessions by a broad label/name filter. |

### Setup rejects a writable config ancestor

Setup stops before writing if a persistent config directory or one of its
ancestors is writable by group or other users. For example, if it reports
`/home/you/.config/box-c`, inspect the exact path it names:

```bash
stat -c '%A %a %U:%G %n' /home/you/.config/box-c
```

If the directory is yours and that shared write access is unintended, remove
group/other write permission from the reported path, then rerun setup from the
repository root:

```bash
chmod go-w /home/you/.config/box-c
make -C box setup
```

Replace the example path with the path from the error. If it is not owned by
you, or you are unsure whether other users rely on the access, stop and resolve
the ownership or intended permissions first. Do not recursively chmod the
whole config tree, change unrelated auth-cache permissions, or weaken setup's
path checks.

```bash
box-c --dry-run --runsc --version
box-c --runsc --version
box-c --docker-fallback --version
box-c --runsc --shell -c 'id; codex --version'
```

Substitute the selected wrapper. Launcher flags precede `--shell`; everything
after it is Bash passthrough. `--shell -c '...'` is valid; `--shell -- tool ...`
does not execute the tool as a command. Acceptance records explicit runsc and
hardened runc separately. Never describe a fallback result as a gVisor pass.
Historical config captures under the OpenCode package are not current runtime
or authentication evidence; see [acceptance](acceptance.md).
