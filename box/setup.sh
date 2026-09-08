#!/bin/bash -p
# setup.sh — one-time installer for the box tool sandboxes (registry-driven:
# every per-tool step loops lib/tools.sh ids, so new tools install free).
# Creates config dirs, installs all tool configs + launchers (+ shared
# lib/*.sh), creates all isolated bridge networks, and builds all
# images for the invoking UID/GID (see --help for --only/--skip-build).
# Safe to re-run: never overwrites providers.env; installed version pins are
# preserved when they differ from the bundle (sync them via
# docs/upgrades.md §12). Tool configs, launchers, and lib/*.sh are refreshed
# from the bundle on every run; persisted Muse user settings in
# muse-config/settings.json are seeded once and never overwritten.
set -euo pipefail
# Save the caller's PATH before the fixed tool PATH below so the final
# next-steps reminder can check whether ~/.local/bin is actually on it.
setup_orig_path=${PATH:-}
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

bundle_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f -- "${BASH_SOURCE[0]}")")
host_uid=$(id -u) || { echo 'setup.sh: Cannot determine UID.' >&2; exit 1; }
host_gid=$(id -g) || { echo 'setup.sh: Cannot determine GID.' >&2; exit 1; }
((host_uid > 0 && host_gid > 0)) || { echo 'setup.sh: Run as your normal non-root host user.' >&2; exit 1; }

BOX_TOOL=setup.sh
# shellcheck source=lib/preflight.sh
source "$bundle_dir/lib/preflight.sh"
# shellcheck source=lib/tools.sh
source "$bundle_dir/lib/tools.sh"
# shellcheck source=lib/config.sh
source "$bundle_dir/lib/config.sh"
# shellcheck source=lib/docker.sh
source "$bundle_dir/lib/docker.sh"
# shellcheck source=lib/launcher.sh
source "$bundle_dir/lib/launcher.sh"
# shellcheck source=lib/run.sh
source "$bundle_dir/lib/run.sh"
# shellcheck source=lib/pins.sh
source "$bundle_dir/lib/pins.sh"
# shellcheck source=lib/build.sh
source "$bundle_dir/lib/build.sh"

# Sectioned output so re-runs are easy to scan: headers on their own line,
# one result per line, warnings visually distinct. All status goes to stderr;
# docker build/inspect output still goes to stdout.
setup_step() { printf '\n==> %s\n' "$*" >&2; }
setup_ok() { printf '  [ok] %s\n' "$*" >&2; }
setup_warn() { printf '  [warn] %s\n' "$*" >&2; }

setup_usage() {
  cat <<'EOF'
Usage: setup.sh [--only <id>] [--default <id>] [--skip-build] [--help]
One-time installer for the box tool sandboxes (safe to re-run).
Default builds all images; --only builds one image; --skip-build installs
configs/launchers/networks only (no image builds).
--default <id> points `box` at that tool's launcher (default: muse).
Re-run with another id to switch the default persistently.
EOF
  printf 'Known tool ids: %s\n' "$box_tool_ids"
}

# Default stays build-all to avoid stale-image confusion (no label
# pre-check by design: silent skips would hide skew between bundle pins and
# installed images — see docs/architecture.md Open Decisions).
setup_only=""
setup_skip_build=0
setup_default="muse"
while (($#)); do
  setup_arg=$1; shift
  case "$setup_arg" in
    --only|--default)
      [[ -n "${1:-}" ]] || { echo "setup.sh: $setup_arg needs a tool id (known: $box_tool_ids)" >&2; exit 2; }
      case " $box_tool_ids " in
        *" $1 "*) : ;;
        *) echo "setup.sh: unknown tool id: $1 (known: $box_tool_ids)" >&2; exit 2 ;;
      esac
      if [[ "$setup_arg" == --only ]]; then setup_only=$1; else setup_default=$1; fi
      shift ;;
    --only-m|--only-o)
      echo "setup.sh: $setup_arg was removed; use --only <id> (known: $box_tool_ids)" >&2; exit 2 ;;
    --default-muse|--default-opencode)
      echo "setup.sh: $setup_arg was removed; use --default <id> (known: $box_tool_ids)" >&2; exit 2 ;;
    --skip-build) setup_skip_build=1 ;;
    --help|-h) setup_usage; exit 0 ;;
    --) break ;;
    -*) echo "setup.sh: unknown flag: $setup_arg (see --help)" >&2; exit 2 ;;
    *) echo "setup.sh: takes no positional arguments (got '$setup_arg')" >&2; exit 2 ;;
  esac
done
unset setup_arg

# Isolated Docker CLI configs (same helper the launchers use): unsets
# DOCKER_HOST/proxy/BUILDKIT poisoning vars and pins --config/--host for
# every daemon call below. Each tool gets its own CLI dir from the registry.
setup_step "[1/5] Docker CLI configs"
for _setup_dir in "$HOME/.config/box" "$HOME/.local/bin" "$HOME/.local/bin/lib"; do
  [[ ! -L "$_setup_dir" ]] || die "Refusing to follow symlink: $_setup_dir"
done
unset _setup_dir
for _setup_id in $box_tool_ids; do
  _setup_cfg="$HOME/.config/$(box_tool_field "$_setup_id" config_dir)"
  [[ ! -L "$_setup_cfg" ]] || die "Refusing to follow symlink: $_setup_cfg"
  box_docker_cli "$_setup_cfg/docker-cli"
done
unset _setup_id _setup_cfg
setup_ok "isolated CLI configs ready ($box_tool_ids)"

# Select the isolated CLI for <id> (sets global docker_cmd). Re-runs the
# idempotent dir ensure, so no per-tool snapshot arrays are needed.
setup_use_cli() {
  box_docker_cli "$HOME/.config/$(box_tool_field "$1" config_dir)/docker-cli"
}

_setup_cfgs=("$HOME/.config/box")
for _setup_id in $box_tool_ids; do
  _setup_cfgs+=("$HOME/.config/$(box_tool_field "$_setup_id" config_dir)")
done
install -d -m 700 -- "${_setup_cfgs[@]}"
unset _setup_id _setup_cfgs
install -d -m 755 -- "$HOME/.local/bin" "$HOME/.local/bin/lib"

# Persistent global Muse config (auth.json, .trust.json): user-level login
# shared across projects. Mode 700, symlink refusal, idempotent. The launcher
# also ensures it via box_ensure_persistent_config_dir; setup creates it
# early so re-runs repair mode even before any login.
# The config dir name comes from the registry (same lookup the install loops
# use); only the `muse-config` persist subdir is muse-specific by design.
_setup_muse_dir="$HOME/.config/$(box_tool_field muse config_dir)"
if [[ -L "$_setup_muse_dir/muse-config" ]]; then
  die "Refusing to follow symlink: $_setup_muse_dir/muse-config"
fi
install -d -m 700 -- "$_setup_muse_dir/muse-config"
chmod 700 -- "$_setup_muse_dir/muse-config" \
  || die "Cannot secure persistent Muse config dir."
# The persistent settings.json itself lives in this dir (seeded in step 2
# below, after the seed source is installed). The old file-inside-dir bind
# quirk that created an empty root-owned file here retired with the readonly
# bind; any leftover artifact is repaired by the seed helper at seed time.

# Tool configs are refreshed from the bundle, but an existing customized
# config is backed up (single .bak, overwritten) instead of silently clobbered.
# Single generation is deliberate (see operations.md §8): installed configs
# are regenerable from the bundle, so numbered rotation would add cap/sweep
# bookkeeping for no recovery benefit.
install_tool_config() {
  local src=${1:-} dest=${2:-}
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing tool-config paths.'
  [[ ! -L "$dest" ]] || die "Refusing to follow symlink: $dest"
  if [[ -e "$dest" ]] && ! cmp -s -- "$src" "$dest"; then
    cp -p -- "$dest" "$dest.bak" \
      || die "Cannot back up customized config: $dest"
    setup_warn "$dest customized; previous version saved to $dest.bak (overwritten)."
  fi
  install -m 644 -- "$src" "$dest"
}
setup_step "[2/5] Tool configs + launchers"
for _setup_id in $box_tool_ids; do
  _setup_cfg_file=$(box_tool_field "$_setup_id" config_file)
  install_tool_config "$bundle_dir/$_setup_cfg_file" \
    "$HOME/.config/$(box_tool_field "$_setup_id" config_dir)/$_setup_cfg_file"
done
unset _setup_id _setup_cfg_file
setup_ok "tool configs installed"
# Seed the persistent Muse settings file on first install only: existing
# user state (in-container /models changes) is never overwritten here. To
# adopt a new bundle default later, delete the destination file and re-run.
box_seed_writable_config "$_setup_muse_dir/$(box_tool_field muse config_file)" "$_setup_muse_dir/muse-config/$(box_tool_field muse config_file)"
unset _setup_muse_dir
# Installed version pins win over the bundle on re-runs: overwriting them
# here would silently revert an in-progress upgrade (see docs/upgrades.md §12).
install_version_pin() {
  local src=${1:-} dest=${2:-}
  [[ -n "$src" && -n "$dest" ]] || die 'Internal error: missing version-pin paths.'
  [[ ! -L "$dest" && ! -L "$src" ]] || die "Refusing to follow symlink in version-pin paths: $dest"
  if [[ ! -e "$dest" ]]; then
    install -m 644 -- "$src" "$dest"
  elif cmp -s -- "$src" "$dest"; then
    : # already synchronized
  else
    setup_warn "$dest differs from the bundle; keeping installed pins (sync via docs/upgrades.md §12)."
  fi
}
for _setup_id in $box_tool_ids; do
  _setup_pin_file=$(box_tool_field "$_setup_id" version_file)
  install_version_pin "$bundle_dir/$_setup_pin_file" \
    "$HOME/.config/$(box_tool_field "$_setup_id" config_dir)/$_setup_pin_file"
done
unset _setup_id _setup_pin_file
setup_ok "version pins in place (installed pins win on re-run)"
# Install the whole split lib/ dir (launchers source the split files via
# their own dir; the installed copy must match that layout).
[[ -f "$bundle_dir/lib/preflight.sh" ]] || die "Missing lib sources in $bundle_dir/lib."
for _lib in "$bundle_dir"/lib/*.sh; do
  install -m 644 -- "$_lib" "$HOME/.local/bin/lib/"
done
unset _lib
_setup_names=""
for _setup_id in $box_tool_ids; do
  _setup_launcher=$(box_tool_field "$_setup_id" launcher)
  install -m 755 -- "$bundle_dir/$_setup_launcher" "$HOME/.local/bin/$_setup_launcher"
  _setup_names+="$_setup_launcher "
done
unset _setup_id _setup_launcher
# box-m-login is a muse-only UX helper outside the registry (no twin).
install -m 755 -- "$bundle_dir/box-m-login" "$HOME/.local/bin/box-m-login"
# `box` is the setup-managed default entry point: a relative symlink (same
# dir) so script_dir realpath resolution still finds the split lib/*.sh
# files. --default <id> points it at that tool's launcher; re-running with
# another id flips it persistently. Refuse non-symlink collisions (do not
# clobber). Usage prints the invoked name, so `box --help` says `box` (plus
# the switch hint) while `box-m --help` says `box-m`; BOX_TOOL stays
# canonical for error prefixes.
_default_target=$(box_tool_field "$setup_default" launcher)
if [[ -e "$HOME/.local/bin/box" && ! -L "$HOME/.local/bin/box" ]]; then
  die "Refusing to clobber non-symlink: $HOME/.local/bin/box"
fi
ln -sfn "$_default_target" "$HOME/.local/bin/box"
setup_ok "launchers installed (${_setup_names}box-m-login; box -> $_default_target)"
unset _default_target _setup_names
# Pre-rename cleanup (clean break, delete outright): remove the pre-rename
# installed artifacts, including the sb-* accelerator symlinks the old
# installer created (sb-m -> muse-sandbox, sb-o -> opencode-sandbox,
# sb-m-login -> muse-login). Secrets and login state are NEVER moved here —
# the user migrates them with the explicit documented steps (see the summary
# reminder below and docs/operations.md §8).
for _legacy in muse-sandbox opencode-sandbox muse-login sb-m sb-o sb-m-login; do
  rm -f -- "$HOME/.local/bin/$_legacy"
done
unset _legacy

# Shared secret file (mode 600, 400 also accepted at launch). Clean break:
# both launchers default here; there is no old-path fallback. Never
# overwritten once created. Refuses symlinks (no truncate-through-link) and
# creates exclusively (noclobber) to close the check-then-create race.
setup_step "[3/5] Secrets + networks + runtime check"
providers_file="$HOME/.config/box/providers.env"
if [[ -L "$providers_file" ]]; then
  die "Refusing to follow symlink: $providers_file"
elif [[ ! -e "$providers_file" ]]; then
  # Subshell umask: the create needs 077 but the change must not leak
  # into networks/builds below (cf. lib/docker.sh subshelled umask).
  ( umask 077; set -o noclobber; : > "$providers_file" ) \
    || die "Cannot create exclusive providers file: $providers_file"
  # Re-check after create: a symlink swapped in between the pre-check and
  # the create would have been followed above.
  [[ ! -L "$providers_file" ]] || die "Refusing to follow symlink: $providers_file"
  chmod 600 -- "$providers_file" \
    || die "Cannot secure providers file: $providers_file"
  setup_ok "created ~/.config/box/providers.env (mode 600, empty)"
  {
    # shellcheck disable=SC2016 # backticks in the next line are an intentional literal.
    printf '  [todo] add literal KEY=value lines (LF only, `#` comments allowed):\n'
    printf '    MUSE_CODE_API_KEY=...      (muse; opencode needs no key — native /connect)\n'
    printf '  Unknown keys hard-FAIL at launch. Never commit this file.\n'
  } >&2
else
  providers_mode=$(stat -c %a -- "$providers_file") \
    || die "Cannot stat providers file: $providers_file"
  case "$providers_mode" in
    400|600) setup_ok "providers.env present (mode $providers_mode, kept as-is)" ;;
    *) chmod 600 -- "$providers_file" \
         || die "Cannot secure providers file: $providers_file"
       setup_ok "providers.env secured to mode 600" ;;
  esac
fi
unset providers_file providers_mode

# Dedicated bridge networks (idempotent). Outbound NAT on, inter-container
# communication off. Policy handling lives in box_ensure_network
# (lib/docker.sh), shared with the launcher assert so the two never drift;
# a pre-existing network with the wrong driver/options fails closed.
# This wrapper only maps the helper's `created`/`verified` verdicts onto
# setup.sh status lines.
ensure_network() {
  local net=${1:-}; shift
  local -a cmd=("$@")
  local result
  # The helper already diagnosed failures on stderr; exit preserves that.
  result=$(box_ensure_network "$net" "${cmd[@]}") || exit 1
  case "$result" in
    created) setup_ok "network $net created" ;;
    verified) setup_ok "network $net already exists (policy verified)" ;;
    *) die "Internal error: unexpected network ensure result for $net." ;;
  esac
}
for _setup_id in $box_tool_ids; do
  setup_use_cli "$_setup_id"
  ensure_network "$(box_tool_field "$_setup_id" network)" "${docker_cmd[@]}"
done
unset _setup_id

# Warn (do not fail) when gVisor `runsc` is not registered: image builds do
# not need a runtime, but default launcher runs will fail closed at
# box_assert_runtime until gVisor is installed (docs/operations.md §5) or the caller
# explicitly opts into hardened runc via --docker-fallback. Runtime
# registration is engine-global, so one query via the first registry id
# covers every tool.
_setup_first=${box_tool_ids%% *}
setup_use_cli "$_setup_first"
unset _setup_first
if _setup_runtimes=$("${docker_cmd[@]}" info --format '{{json .Runtimes}}' 2>/dev/null); then
  case "$_setup_runtimes" in
    *'"runsc"'*) setup_ok "runtime runsc (gVisor) registered" ;;
    *) setup_warn "runtime 'runsc' not registered; default runs fail closed until gVisor is installed (docs/operations.md §5) or you use --docker-fallback." ;;
  esac
else
  setup_warn "cannot query Docker runtimes; ensure the Engine is running."
fi
unset _setup_runtimes

# Validate the bundle pin files with the same strict parser the launchers
# use (LF-only, key allowlist, version + checksum/integrity regex), via the
# single lib/pins.sh home. This fails closed here instead of driving a build
# off files the launchers would reject.
box_load_all_pins "$bundle_dir"
_setup_versions=""
for _setup_id in $box_tool_ids; do
  _setup_vkey=$(box_tool_field "$_setup_id" pin_keys); _setup_vkey=${_setup_vkey%% *}
  _setup_versions+="${_setup_versions:+, }$_setup_id ${!_setup_vkey}"
done
unset _setup_id _setup_vkey
# NODE_VERSION is opencode-owned (only npm-pinned tool pins a toolchain);
# removing opencode would require dropping it from this status line.
setup_ok "version pins validated ($_setup_versions; node $NODE_VERSION)"
unset _setup_versions

setup_step "[4/5] Building images (u${host_uid}/g${host_gid})"
if ((setup_skip_build)); then
  setup_ok "image builds skipped via --skip-build (configs/launchers/networks still installed)"
else
# Single build home (lib/build.sh): previously duplicated `docker build`
# blocks lived here and in the Makefile recipes (with grep sync asserts in
# check-pins.sh); both now delegate to lib/build.sh.
for _setup_id in $box_tool_ids; do
if [[ -z "$setup_only" || "$setup_only" == "$_setup_id" ]]; then
_setup_vkey=$(box_tool_field "$_setup_id" pin_keys); _setup_vkey=${_setup_vkey%% *}
setup_step "-> $(box_tool_field "$_setup_id" image_prefix):${!_setup_vkey}-u${host_uid}-g${host_gid}"
box_build_image "$_setup_id" "$bundle_dir"
setup_ok "$_setup_id image built + labels verified"
fi
done
unset _setup_id _setup_vkey
fi

# Only remind about one-time setup that is still missing (avoids confusion
# on re-runs). PATH is checked against the caller's original PATH saved at
# the top (the tool PATH above is fixed); git identity mirrors the launcher
# fallback (any NAME + any EMAIL across BOX_M_/BOX_O_); providers.env
# counts as filled when it holds at least one active KEY=value line.
# A pre-rename install is detected by its old config dirs (old-name literals
# confined to this probe + the step-2 deletion loop): secrets/login are
# never moved automatically, so the summary points at the manual migration.
setup_step "[5/5] Summary"
_setup_need_migrate=0
for _setup_legacy_dir in "$HOME/.config/sandbox" "$HOME/.config/muse-sandbox" "$HOME/.config/opencode-sandbox"; do
  if [[ -e "$_setup_legacy_dir" ]]; then _setup_need_migrate=1; fi
done
unset _setup_legacy_dir
_setup_need_path=0
# Assigned first and quoted in the pattern so a glob-looking $HOME matches
# literally instead of acting as a case pattern.
_setup_local_bin="$HOME/.local/bin"
case ":${setup_orig_path:-}:" in
  *:"$_setup_local_bin":*) setup_ok "PATH includes ~/.local/bin" ;;
  *) _setup_need_path=1 ;;
esac
# Git identity is needed before first launch: any NAME + any EMAIL across
# every registry git prefix (same primary/fallback semantics the launchers
# use). The hint lists every prefix pair for the [todo] summary below.
# When env is incomplete, missing fields are inferred from
# `git config --global` (same validity rules the launchers enforce; invalid
# values count as missing). Explicit env always wins per field. Nothing is
# exported or persisted here: setup.sh stays non-interactive and only prints
# copy-paste lines (CI-safe; no prompts, no shell-rc writes).
_setup_git_name=""; _setup_git_email=""; _setup_git_hint=""
for _setup_id in $box_tool_ids; do
  _setup_gp=$(box_tool_field "$_setup_id" git_prefix)
  _setup_nv="${_setup_gp}_GIT_NAME"; _setup_ev="${_setup_gp}_GIT_EMAIL"
  [[ -n "$_setup_git_name" ]] || _setup_git_name=${!_setup_nv:-}
  [[ -n "$_setup_git_email" ]] || _setup_git_email=${!_setup_ev:-}
  _setup_git_hint+="${_setup_git_hint:+ and/or }${_setup_gp}_GIT_NAME/${_setup_gp}_GIT_EMAIL"
done
unset _setup_id _setup_gp _setup_nv _setup_ev
_setup_need_git=0
if [[ -n "$_setup_git_name" && -n "$_setup_git_email" ]]; then
  setup_ok "git identity set"
else
  box_infer_git_identity
  [[ -n "$_setup_git_name" ]] || _setup_git_name=$inferred_git_name
  [[ -n "$_setup_git_email" ]] || _setup_git_email=$inferred_git_email
  if [[ -n "$_setup_git_name" && -n "$_setup_git_email" ]]; then
    setup_ok "git identity inferred from git config --global (launchers infer live; copy-paste to pin explicitly for reproducible CI):"
    for _setup_id in $box_tool_ids; do
      _setup_gp=$(box_tool_field "$_setup_id" git_prefix)
      printf '    export %s_GIT_NAME=%q %s_GIT_EMAIL=%q\n' \
        "$_setup_gp" "$_setup_git_name" "$_setup_gp" "$_setup_git_email" >&2
    done
    unset _setup_id _setup_gp
  else
    _setup_need_git=1
  fi
fi
unset _setup_git_name _setup_git_email inferred_git_name inferred_git_email
_setup_need_providers=0
_setup_providers_file="$HOME/.config/box/providers.env"
# Shared presence probe (lib/preflight.sh): same allowlist + shape rules as
# the launcher loader, so unknown keys and CR tails no longer count as filled.
# shellcheck disable=SC2086 # word-splitting BOX_CRED_KEYS into allowlist args is intentional.
if box_credentials_filled "$_setup_providers_file" $BOX_CRED_KEYS; then
  setup_ok "providers.env filled"
else
  _setup_need_providers=1
fi
_setup_verify_cmds=""
for _setup_id in $box_tool_ids; do
  _setup_verify_cmds+="${_setup_verify_cmds:+ / }$(box_tool_field "$_setup_id" launcher) --dry-run"
done
unset _setup_id
if (( _setup_need_path || _setup_need_git || _setup_need_providers )); then
  {
    printf '\n  [todo] still missing:\n'
    (( !_setup_need_path )) || printf '    1. Put ~/.local/bin on PATH (see docs/operations.md §8).\n'
    (( !_setup_need_git )) || printf '    2. Export git identity: %s.\n' "$_setup_git_hint"
    (( !_setup_need_providers )) || printf '    3. Fill ~/.config/box/providers.env (mode 600).\n'
    printf '\n  Verify with: %s (from a scratch project).\n' "$_setup_verify_cmds"
  } >&2
else
  {
    printf '\n  [done] ready — images built, networks verified.\n'
    printf '  Verify with: %s (from a scratch project).\n' "$_setup_verify_cmds"
  } >&2
fi
unset _setup_verify_cmds _setup_git_hint
if (( _setup_need_migrate )); then
  {
    printf '\n  [todo] pre-rename config dirs detected: secrets + login were NOT moved\n'
    printf '  automatically. Migrate them with the explicit steps in\n'
    printf '  docs/operations.md §8 (migration), then clean up the old\n'
    printf '  images/networks/volumes per docs/operations.md §13.\n'
  } >&2
fi
unset _setup_need_path _setup_need_git _setup_need_providers _setup_providers_file _setup_local_bin setup_orig_path _setup_need_migrate
