# Operations

Day-to-day use: host prerequisites, image builds, one-time setup, daily
usage, verification, and state reset. For internals see `architecture.md`;
for upgrades see `upgrades.md`; for diagnostics see `troubleshooting.md`.

### 5. Host Prerequisites & gVisor Setup

Linux-only. macOS is unsupported (runsc + UID/GID-matched rootful Engine are
Linux-only; use a Linux host or VM). Requires Docker Engine **>= 25.0** for
`bind-recursive=disabled` support (both launchers' mount flags), plus `runsc`
(gVisor), `realpath`, `git`, `jq`, `shellcheck`. Older Engines without `bind-recursive`
support fail closed: rebuild/upgrade the Engine; do not drop the flag. The
bats suite asserts GNU `stat -c` owner/mode checks and is Linux-only by
design (same as `lib/preflight.sh`; macOS `stat -f` is not supported).

Execute these commands on a supported Debian/Ubuntu host:

```bash
# 1. Install Docker CE
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
. /etc/os-release
sudo curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# 2. Install gVisor (runsc)
curl -fsSL https://gvisor.dev/archive.key | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | \
  sudo tee /etc/apt/sources.list.d/gvisor.list >/dev/null
sudo apt-get update
sudo apt-get install -y runsc
sudo runsc install
sudo systemctl restart docker

# 3. Add host user to docker group
sudo usermod -aG docker "$(id -un)"
# Log out and log back in to apply group changes!
```

---

### 6. Image Build Commands

Prefer `setup.sh` (§8), which runs both builds, or `make` (same `--file Dockerfile --target ...` builds through the isolated per-tool CLI configs):

> Never `.`/source a version file from an untrusted clone: sourcing executes
> arbitrary shell code. All pins load once per build inside `lib/build.sh`
> via the single `lib/pins.sh` home (`box_load_all_pins` over
> `box_load_version_file`; never `grep`+`cut`, so base64 `=` padding
> survives).

```bash
bundle_dir=/path/to/box
make -C "$bundle_dir" build-m
make -C "$bundle_dir" build-o
# or: make -C "$bundle_dir" build
make -C "$bundle_dir" pin-check
```

Point to the `make` targets above (same `--file Dockerfile --target ...` builds
with `--build-arg` threading from `lib/pins.sh`; `setup.sh` runs the same
builds through the isolated per-tool CLI configs). No `ARG` has a default, so
a bare `docker build --file Dockerfile` without `--build-arg` fails closed.

---

### 8. One-Time Setup

Preferred (builds all images, creates all networks, installs all launchers + `lib/`):

Every per-tool step below loops the `lib/tools.sh` registry — the single extension point for new tools (see `docs/adding-a-tool.md`). There are no per-tool installer branches: `--only` / `--default` take any registered id.

```bash
bundle_dir=/path/to/box
bash "$bundle_dir/setup.sh"
# Optional flags (default stays build-all to avoid stale-image confusion;
# known tool ids: muse opencode):
#   --help             usage
#   --only <id>        build one tool image only (e.g. --only muse)
#   --default <id>     point `box` at that tool's launcher (default: muse)
#   --skip-build       install configs/launchers/networks only (no image builds)
export PATH="$HOME/.local/bin:$PATH"
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"

# Git identity is automatic: each field resolves as primary env, then the
# other tool's env as fallback (muse prefers BOX_M_GIT_*; opencode prefers
# BOX_O_GIT_*), then `git config --global user.name/user.email` (that scope
# only; repo-local identity is ignored). Explicit env always wins per field;
# when inference supplies a field the launcher prints a NOTICE on stderr.
# Values must be single-line printable text (invalid values count as
# missing). No exports are needed when the global git config is set; to pin
# identity explicitly instead (e.g. reproducible CI), export:
#   export BOX_M_GIT_NAME='Your Name' BOX_M_GIT_EMAIL='you@example.com'
#   export BOX_O_GIT_NAME="$BOX_M_GIT_NAME" BOX_O_GIT_EMAIL="$BOX_M_GIT_EMAIL"

# Enter the API key (stored in shared mode-600 file; setup.sh created it
# empty). MUSE_CODE_API_KEY is the headless/CI path for muse (`box-m login`
# device login needs no key). OpenCode needs no manual key: connect natively
# inside opencode (`/connect`), which persists per project on the volume.
umask 077
IFS= read -r -s -p 'Enter MUSE_CODE_API_KEY: ' api_key; printf '\n'
printf 'MUSE_CODE_API_KEY=%s\n' "$api_key" >> "$HOME/.config/box/providers.env"
chmod 600 "$HOME/.config/box/providers.env"
unset api_key
```

#### Migrating from the pre-rename install (do this first)

The rename is a clean break: `setup.sh` never moves secrets or login state
on its own, and until you migrate, `box-*` sees empty providers and
logged-out state. Migrate an existing install in this order (the old config
dirs are left untouched, so the old install keeps working until you finish;
`setup.sh` prints this same reminder when it detects them):

```bash
# 1. Re-run the installer from the new bundle. It installs the new layout,
#    deletes the pre-rename ~/.local/bin artifacts, and builds the new
#    box-m:/box-o: images (old images are orphaned, never auto-removed).
bundle_dir=/path/to/box
bash "$bundle_dir/setup.sh"

# 2. Move secrets. Do this BEFORE filling the new file with the prompts
#    above: the new providers file is the empty one setup.sh just created,
#    so move the old file over it (mode is preserved). If you already
#    filled the new file, merge by hand instead of mv.
mv "$HOME/.config/sandbox/providers.env" "$HOME/.config/box/providers.env"
# Drop any BITDEER_API_KEY/OPENAI_API_KEY lines: the allowlist is now
# MUSE_CODE_API_KEY only (unknown keys hard-FAIL at launch).
sed -i '/^BITDEER_API_KEY=/d; /^OPENAI_API_KEY=/d' "$HOME/.config/box/providers.env"
chmod 600 "$HOME/.config/box/providers.env"

# 3. Move the Meta login (auth.json + .trust.json) into the new persist dir.
#    Leave settings.json behind and re-apply model prefs via /models
#    instead (the new seed is already in place; safety keys re-assert on
#    every launch).
mv "$HOME/.config/muse-sandbox/muse-config/auth.json" \
  "$HOME/.config/box-m/muse-config/"
[ ! -e "$HOME/.config/muse-sandbox/muse-config/.trust.json" ] || \
  mv "$HOME/.config/muse-sandbox/muse-config/.trust.json" \
    "$HOME/.config/box-m/muse-config/"

# 4. Rename git identity + launcher overrides in your shell rc: the old
#    names are no longer read. MUSE_GIT_* -> BOX_M_GIT_*,
#    OPENCODE_GIT_* -> BOX_O_GIT_*, and any launcher overrides take the new
#    BOX_M_*/BOX_O_* names (full list in architecture.md §7).
```

5. Verify with `box-m --dry-run` / `box-o --dry-run` from a scratch
project (§11), then remove the orphaned old images/networks/volumes and
the emptied old config dirs per the legacy cleanup in §13.

Rollback: names are the only change — check out the pre-rename bundle and
re-run its `setup.sh`; the old config dirs were never touched by the new
installer, so the old install keeps working.

Without `setup.sh` (fresh installs only — prefer `setup.sh`: it preserves
already-installed version pins per `upgrades.md`, backs up customized tool
configs to `*.bak`, creates `providers.env` exclusively with symlink refusal,
re-asserts existing network policy field-wise, and drives every daemon call
through the isolated per-tool CLI configs):

```bash
bundle_dir=/path/to/box
bash "$bundle_dir/setup.sh" --skip-build
make -C "$bundle_dir" build
```

Then verify with `--dry-run` before contacting the daemon for real runs.

Backups are single-generation by design (`*.bak`, overwritten — deliberate,
not laziness): both sites warn with the path so nothing is lost silently,
installed tool configs are regenerable from the bundle, and the docker-cli
backup may hold rejected credential-bearing configs, where numbered rotation
would multiply secret copies. Rotation would add cap/sweep bookkeeping for
no recovery benefit.

---

### 9. Daily Usage & Working Directory Semantics

Run from the repository root you want the agent to see. `box-m` and `box-o`
are the canonical commands; bare `box` runs the configured default (Meta
Muse out of the box — same as `box-m`):

```bash
cd ~/projects/my-app
box        # default (box-m unless switched)
box-m      # Meta Muse, explicitly
box-o      # OpenCode, explicitly
```

Switch the `box` default persistently with one installer run (no rebuild:
only the symlink is repointed, everything else is left alone):

```bash
bundle_dir=/path/to/box
bash "$bundle_dir/setup.sh" --default opencode --skip-build  # box -> box-o
bash "$bundle_dir/setup.sh" --default muse --skip-build      # box -> box-m
```

`box --help` prints `Usage: box …` plus this switch hint; `box-m --help`
prints `Usage: box-m …`.

#### Meta Browser Login
The sandbox container has no display/browser by design (no
`DISPLAY`/`WAYLAND`/`xdg-open` forwarding), so `muse login` prints a device
URL that must be opened in a **host** browser manually. `box-m-login`
is the one-command helper: it runs the device flow and
re-prints the `auth.meta.com` URL as a clear banner (clickable OSC-8
hyperlink + plain copy-paste URL + short code), then waits for approval:

```bash
cd ~/projects/my-app
box-m login     # AUTO runtime: every tool run probes runsc DNS, falls back only if needed
box login       # same via the default entry point (box-m unless switched)
box-m-login     # same + clear clickable-link banner in the terminal
```
One login covers both entry points: `box-m login` and `box-m-login` share the
single `box_auto_runtime` probe and the same global persistent dir
`~/.config/box-m/muse-config/` (`settings.json`, `auth.json`,
`.trust.json`). Log in once; later `box-m` runs reuse it. `settings.json` is
seeded there from `~/.config/box-m/settings.json` on first run and
never wholesale-overwritten afterward, so in-container `/models` changes
persist across runs; every launch still re-asserts the four safety-critical
keys (`approval_mode`, `approval_judge`, `telemetry.enabled`,
`api.base_url`) from the seed, reverting any in-container downgrade while
leaving `model`, `reasoning_effort`, and unknown keys alone.
No runtime flag is needed for any tool run: the launcher probes container
DNS under `runsc` first and stays on gVisor when healthy; only if the probe
fails does it auto-select the hardened-runc fallback with a single
`NOTICE` (plus the standard fallback `WARNING`, so the downgrade is never
silent). `box-m login` and `box-m-login` share this probe (one login persists
globally); `box-o` probes generic registry egress the same way. `--shell` runs
never probe (explicit-only diagnostics path): use `--docker-fallback` there
when needed, or `--runsc` anywhere to force gVisor with no probe.
`BOX_M_ALLOW_FALLBACK=0` / `BOX_O_ALLOW_FALLBACK=0` fails
closed with remediation instead of launching a run that would fail opaquely
inside.
`--docker-fallback` forces runc, `--runsc` forces gVisor.
Docker embedded DNS (`127.0.0.11`) is unreachable under `runsc` on VPN
hosts, which presents as `login failed: device flow transport error` (or
`failed to fetch model catalog` / `(model … not in catalog — using assumed
limits)` in TUI runs) — the AUTO probe heals this
without flags (see `troubleshooting.md` §14).

#### Working Directory & Relative Path Semantics
- Host `pwd -P` is mounted non-recursively to container `/workspace`. A subdirectory run mounts only that subdirectory (git commands may fail there, and the `.git` worktree check only inspects the mounted directory) — run from the repo root for full-repo access.
- Container working directory is set to `/workspace` (`--workdir=/workspace`).
- Relative paths passed to the CLI (`box-m src/server.ts`) or invoked inside the agent loop (`./build.sh`, `../`) resolve relative to the mounted directory (identical to host execution from that same directory).
- The mount flags `bind-recursive=disabled,bind-propagation=rprivate` ensure host submounts do not leak into the container and container mount events do not propagate back.

#### Non-Interactive CI / Headless Mode
```bash
box-m exec "Refactor auth middleware and run test suite"
box-o run "Refactor auth middleware and run test suite"
```
`exec` / `run` here are upstream CLI subcommands passed through verbatim — the sandbox adds no subcommands (everything after the sandbox flags is `"$@"` passthrough). Confirm subcommand names against the installed CLI (`muse --help`, `opencode --help`).

#### Interactive Debugging Shell
```bash
box-m --shell
box-o --shell
```

#### State Persistence Model

| Path inside container | Storage Type | Lifecycle |
|---|---|---|
| `/workspace` | Host project bind (`pwd -P`) | Persistent read-write |
| `/home/box/.config/muse` | Global host bind `~/.config/box-m/muse-config/` (`700`) | Persistent writable dir (`settings.json`, `auth.json`, `.trust.json`); shared across projects |
| `/home/box/.config/muse/settings.json` | Seeded file in the persistent bind (muse) | Writable; user-owned, persists across runs |
| `/home/box/.config/opencode` | `tmpfs` (`uid,gid,mode=700`) | Ephemeral writable dir (server/auth state); cleared on container removal |
| `/home/box/.config/opencode/opencode.json` | Host config bind (opencode) | Read-only file inside writable `tmpfs` parent (order matters) |
| `/persist/data/muse` + `/persist/state/muse` | Docker named volume `box-m-u<uid>-g<gid>-<hash>` | Persistent across runs |
| `/persist/data/opencode` + `/persist/state/opencode` | Docker named volume `box-o-u<uid>-g<gid>-<hash>` | Persistent across runs |
| `/home/box/.muse` | Symlink to `/persist/data/muse` | Persistent across runs |
| `/home/box/.local/share/opencode` | Symlink to `/persist/data/opencode` | Persistent across runs |
| `/home/box/.cache` | `tmpfs` | Cleared on container removal |

---

### 11. Verification Commands & Containment Proofs

Run the per-tool harness inside the sandbox (replace `README.md` with any existing tracked file; the second argument is an optional build/test command):

```bash
cd ~/projects/my-app
box-m --shell -s -- README.md 'make test || true' < /path/to/box/verify-muse.sh
box-o --shell -s -- README.md 'make test || true' < /path/to/box/verify-opencode.sh
```

The harnesses are generated from `verify.d/` partials by `gen-verify.sh`
(shared §§1-2/5 live once; §3-4/6 stay per-tool); checked-in outputs stay
stdin-deliverable. CI asserts generated == checked-in (`make verify-generated`,
which implies §§1-2/5 sync).

Static checks (no daemon needed; `shellcheck` is required, fail-not-skip):

```bash
bundle_dir=/path/to/box
make -C "$bundle_dir" verify-static
make -C "$bundle_dir" pins
```

`--dry-run` shape checks (no secret values; assert `--env NAME` form, `runsc` default, `bind-recursive=disabled`, `--pull=never`, `--read-only`, no `--tty`, isolated `--config .../docker-cli`). `--dry-run` never contacts the daemon, but it is not side-effect-free: `box-m --dry-run` still seeds + enforces the persisted `~/.config/box-m/muse-config/settings.json` safety keys (local files only; pinned by `tests/bats/launchers.bats`):

```bash
cd ~/projects/my-app
# Trailing-space match: provider keys pass as `--env NAME` (NAME-only, no
# `=value`). `--env KEY=value` assignments (GIT_*, *_AUTOUPDATE) end in `=`
# and are excluded by construction.
box-m --dry-run | grep -o -- '--env [A-Z_][A-Z0-9_]* ' | sort -u
box-o --dry-run | grep -o -- '--env [A-Z_][A-Z0-9_]* ' | sort -u
```

In a **second host terminal**, verify active container isolation properties (muse shown; repeat with `box-o` paths for the other tool):

```bash
read -r -p 'Active container name: ' box_container

# Verify runtime, capabilities, and security flags
docker --config "$HOME/.config/box-m/docker-cli" --host unix:///var/run/docker.sock inspect --format \
  'runtime={{.HostConfig.Runtime}} user={{.Config.User}} capdrop={{json .HostConfig.CapDrop}} security={{json .HostConfig.SecurityOpt}}' \
  "$box_container"
# Expected: runtime=runsc user=<uid>:<gid> capdrop=["ALL"] security=["no-new-privileges"]

# Verify mount destinations and sources
docker --config "$HOME/.config/box-m/docker-cli" --host unix:///var/run/docker.sock inspect --format \
  '{{range .Mounts}}{{printf "%s %s -> %s RW=%v\n" .Type .Source .Destination .RW}}{{end}}' \
  "$box_container"

# Assert negative host filesystem exposure
docker --config "$HOME/.config/box-m/docker-cli" --host unix:///var/run/docker.sock exec "$box_container" \
  bash -c 'test ! -e "$1" && test ! -e "$1/.ssh" && test ! -e "$1/.gnupg"' _ "$HOME"
```

Negative tests (must fail closed): system-dir project (`/tmp/foo`, `/srv/foo`, `/data/foo`, `/snap/foo`), tool-dir project (`~/.config/box`, `~/.local/bin`), in-project credentials/config/version files, symlinked `$HOME`/cred-dir escapes, project symlink into a credential path, CRLF version file, unknown cred key, empty cred value, GID 0 in `*_EXTRA_GIDS`, missing creds file, launcher flag after `--shell`, group/other-writable config or version file.

Redaction: never `cat`/`echo` `providers.env`; `--dry-run | grep -c KEY=` shape checks print counts, not values.

---

### 13. State Reset & Uninstallation

#### Project State Reset
To clear persistent state, sessions, and logs for a specific project without affecting workspace files, stop dependent containers first, then delete the volume:
```bash
docker --config "$HOME/.config/box-m/docker-cli" --host unix:///var/run/docker.sock volume ls \
  --filter "name=box-m-u$(id -u)-g$(id -g)-"
docker --config "$HOME/.config/box-o/docker-cli" --host unix:///var/run/docker.sock volume ls \
  --filter "name=box-o-u$(id -u)-g$(id -g)-"
read -r -p 'Exact volume name to delete: ' target_volume
case "$target_volume" in
  box-m-u*|box-o-u*) ;;
  *) echo 'Refusing: unexpected volume name.' >&2; exit 1 ;;
esac
docker --config "$HOME/.config/box-m/docker-cli" --host unix:///var/run/docker.sock ps -a \
  --filter "volume=$target_volume" --format '{{.ID}}' | xargs -r docker --config "$HOME/.config/box-m/docker-cli" --host unix:///var/run/docker.sock stop
docker --config "$HOME/.config/box-m/docker-cli" --host unix:///var/run/docker.sock volume rm "$target_volume"
```
(Use the matching tool CLI config for the volume prefix; `stop` before `rm` is required — Docker refuses to remove in-use volumes.)

#### Complete Uninstallation
```bash
bundle_dir=/path/to/box
make -C "$bundle_dir" clean
# Project volumes are intentionally NOT removed here (they hold session/state);
# list and remove them explicitly per Project State Reset above.
rm -f "$HOME/.local/bin/box" "$HOME/.local/bin/box-m" "$HOME/.local/bin/box-o" \
  "$HOME/.local/bin/box-m-login"
rm -rf "$HOME/.local/bin/lib"
muse_cli=(docker --config "$HOME/.config/box-m/docker-cli" --host unix:///var/run/docker.sock)
opencode_cli=(docker --config "$HOME/.config/box-o/docker-cli" --host unix:///var/run/docker.sock)
"${muse_cli[@]}" ps -a --filter "label=org.meta.muse.box=true" --format '{{.ID}}' | xargs -r "${muse_cli[@]}" stop
"${opencode_cli[@]}" ps -a --filter "label=org.opencode.box=true" --format '{{.ID}}' | xargs -r "${opencode_cli[@]}" stop
"${muse_cli[@]}" network rm box-m
"${opencode_cli[@]}" network rm box-o
rm -rf "$HOME/.config/box-m" "$HOME/.config/box-o"
# Shared providers file: remove only if no longer needed (contains secrets).
# rm "$HOME/.config/box/providers.env"
```

#### Pre-rename legacy cleanup
After the §8 migration is verified, the old install leaves orphaned
artifacts that `setup.sh` never touches (volumes hold session state;
images/networks may still be referenced). Remove them explicitly (plain
`docker` is fine here — one-off removals, no builds, no credentials):

```bash
# Old images (orphaned by the tag rename; `make clean` only covers
# box-m:/box-o:). List first — remove only tags from the old install.
docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^(muse-sandbox|opencode-sandbox):' || true
docker image rm "muse-sandbox:<ver>-u$(id -u)-g$(id -g)" "opencode-sandbox:<ver>-u$(id -u)-g$(id -g)"

# Old networks (after stopping any container still on them).
docker network rm muse-sandbox opencode-sandbox

# Old volumes: inspect names first — each holds that project's old session
# state, so delete only after confirming nothing needed is inside.
docker volume ls --format '{{.Name}}' | grep -E '^(muse-sandbox|opencode-sandbox)-u' || true
docker volume rm <exact-old-volume-name>

# Old config dirs (after the §8 migration moved secrets + login out).
rm -rf "$HOME/.config/sandbox" "$HOME/.config/muse-sandbox" "$HOME/.config/opencode-sandbox"

# Old launcher symlinks (sb-m, sb-o, sb-m-login) are deleted by setup.sh
# itself (pre-rename cleanup loop); remove by hand only if you never re-ran
# the new installer: rm -f "$HOME/.local/bin/sb-m" "$HOME/.local/bin/sb-o" "$HOME/.local/bin/sb-m-login"
```
