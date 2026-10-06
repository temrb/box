#!/bin/bash -p
# setup.sh — one-time installer for the box tool sandboxes (registry-driven:
# every per-tool step loops lib/tools.sh ids, so new tools install free).
# Creates config dirs, installs all tool configs + launchers (+ shared
# lib/*.sh), creates all isolated bridge networks, and builds all
# images for the invoking UID/GID (see --help for --only/--skip-build).
# Safe to re-run: never overwrites providers.env; installed version pins are
# preserved when they differ from the bundle (sync them via
# make -C box sync-pins-<stem> (docs/upgrades.md)). Tool configs, launchers, and lib/*.sh are refreshed
# from the bundle on every run; Muse settings are generated per launch from
# live defaults (setup prepares only persistent auth/trust).
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
# shellcheck source=lib/install.sh
source "$bundle_dir/lib/install.sh"
# shellcheck source=lib/config-file.sh
source "$bundle_dir/lib/config-file.sh"

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
--default <id> selects the launcher; reruns preserve the existing default.
A fresh install defaults to the first registry tool (muse).
Re-run with another id to switch the default persistently.
EOF
  printf 'Known tool ids: %s\n' "$box_tool_ids"
}

# Default stays build-all to avoid stale-image confusion (no label
# pre-check by design: silent skips would hide skew between bundle pins and
# installed images — see docs/architecture.md Open Decisions).
setup_only=""
setup_skip_build=0
setup_default=""
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

# Reject leftover positionals and diagnose parser/pin prerequisites before
# creating directories, copying templates, or contacting Docker.
(( $# == 0 )) || die "Takes no positional arguments (got '$1')."
box_validate_registry "$bundle_dir"
for _setup_source in $(box_config_sources); do
  box_config_validate "$bundle_dir/$_setup_source"
done
unset _setup_source
for _setup_id in $box_tool_ids; do
  ( # shellcheck disable=SC1090 # registry fixes trusted adapter paths
    source "$bundle_dir/$(box_tool_field "$_setup_id" validate_adapter)"
    box_harness_validate "$bundle_dir"
  )
done
unset _setup_id
box_load_all_pins "$bundle_dir"

# Serialize setup for this physical home before inspecting installed state.
# Lock the directory itself so waiting installers cannot race through an
# unlinked lock file, and planning failures still leave the home untouched.
command -v flock >/dev/null || die 'flock is required (util-linux).'
_setup_home=$(box_plan_directory "$HOME")
exec {setup_lock_fd}<"$_setup_home" || die 'Cannot open setup lock.'
flock -x "$setup_lock_fd" || die 'Cannot acquire setup lock.'
unset _setup_home

# Validate file destinations as part of planning, before creating any dirs.
# install(1) can otherwise follow an existing destination symlink.
setup_plan_file() {
  local dest=$1
  [[ ! -L "$dest" && ( ! -e "$dest" || -f "$dest" ) ]] || die "Invalid installation destination: $dest"
  if [[ -e "$dest" ]]; then box_assert_owner_mode "$dest" 'Installed file' nowrite; fi
}
for _setup_lib in "$bundle_dir"/lib/*.sh; do
  setup_plan_file "$HOME/.local/bin/lib/${_setup_lib##*/}"
done
setup_plan_file "$HOME/.local/bin/box-m-login"
[[ ! -e "$HOME/.local/bin/box" || -L "$HOME/.local/bin/box" ]] || die 'Invalid default launcher destination.'
if [[ -L "$HOME/.local/bin/box" && -z "$setup_default" ]]; then
  _setup_current=$(readlink "$HOME/.local/bin/box")
  box_tool_id_for_launcher "$_setup_current" >/dev/null
fi
_setup_provider="$HOME/.config/box/providers.env"
[[ ! -L "$_setup_provider" && ( ! -e "$_setup_provider" || -f "$_setup_provider" ) ]] || die 'Invalid providers file destination.'
if [[ -e "$_setup_provider" ]]; then
  [[ "$(stat -c %u "$_setup_provider")" == "$host_uid" ]] || die 'Credentials file must be owned by you.'
fi

# Validate the complete directory inventory before the first filesystem write.
setup_step "[1/5] Docker CLI configs"
_setup_dirs=("$HOME/.config/box" "$HOME/.local/bin" "$HOME/.local/bin/lib" "$HOME/.local/bin/harnesses")
for _setup_id in $box_tool_ids; do
  _setup_cfg="$HOME/.config/$(box_tool_field "$_setup_id" config_dir)"
  _setup_dirs+=("$_setup_cfg" "$_setup_cfg/docker-cli" "$HOME/.local/bin/harnesses/$_setup_id")
  setup_plan_file "$_setup_cfg/$(box_tool_field "$_setup_id" version_file)"
  box_plan_installed_pins "$_setup_id" "$_setup_cfg/$(box_tool_field "$_setup_id" version_file)"
  setup_plan_file "$HOME/.local/bin/$(box_tool_field "$_setup_id" launcher)"
  for _setup_cli_file in config.json config.json.bak; do
    setup_plan_file "$_setup_cfg/docker-cli/$_setup_cli_file"
  done
  while IFS= read -r _setup_code; do
    _setup_relative=${_setup_code#"$bundle_dir/harnesses/$_setup_id/"}
    box_assert_relative_source "$bundle_dir" "harnesses/$_setup_id/$_setup_relative"
    _setup_parent="$HOME/.local/bin/harnesses/$_setup_id/$(dirname -- "$_setup_relative")"
    box_plan_directory "$_setup_parent" >/dev/null
    setup_plan_file "$_setup_parent/${_setup_code##*/}"
  done < <(find "$bundle_dir/harnesses/$_setup_id" -type f -name '*.sh' ! -path '*/verify.d/*')
  for _setup_state in $(box_tool_field "$_setup_id" states); do
    if [[ "$(box_state_field "$_setup_id" "$_setup_state" kind)" == bind ]]; then
      _setup_dirs+=("$HOME/$(box_state_field "$_setup_id" "$_setup_state" root)")
    fi
  done
  for _setup_asset in $(box_tool_field "$_setup_id" artifacts); do
    _setup_leaf=$(box_artifact_field "$_setup_id" "$_setup_asset" installed)
    [[ -n "$_setup_leaf" ]] || continue
    for _setup_dest in "$_setup_cfg/$_setup_leaf" "$_setup_cfg/$_setup_leaf.bak"; do
      [[ ! -L "$_setup_dest" && ( ! -e "$_setup_dest" || -f "$_setup_dest" ) ]] || die "Invalid installation destination: $_setup_dest"
      if [[ -e "$_setup_dest" ]]; then box_assert_owner_mode "$_setup_dest" 'Installed configuration' nowrite; fi
    done
  done
  _setup_adapter=$(box_tool_field "$_setup_id" install_adapter)
  if [[ -n "$_setup_adapter" ]]; then
    ( # shellcheck disable=SC1090 # fixed validated install adapter
      source "$bundle_dir/$_setup_adapter"; box_harness_install_plan )
  fi
  if [[ -d "$HOME/.local/bin/harnesses/$_setup_id" ]]; then
    while IFS= read -r _setup_old; do
      box_plan_directory "$(dirname -- "$_setup_old")" >/dev/null
      setup_plan_file "$_setup_old"
    done < <(find "$HOME/.local/bin/harnesses/$_setup_id" -type f -name '*.sh')
  fi
done
for _setup_dir in "${_setup_dirs[@]}"; do box_plan_directory "$_setup_dir" >/dev/null; done
for _setup_dir in "${_setup_dirs[@]}"; do box_prepare_directory "$_setup_dir" 700 >/dev/null; done
box_prepare_directory "$HOME/.local/bin" 755 >/dev/null
box_prepare_directory "$HOME/.local/bin/lib" 755 >/dev/null
box_prepare_directory "$HOME/.local/bin/harnesses" 755 >/dev/null
for _setup_id in $box_tool_ids; do
  box_docker_cli "$HOME/.config/$(box_tool_field "$_setup_id" config_dir)/docker-cli"
done
setup_ok "isolated CLI configs ready ($box_tool_ids)"

# Select the isolated CLI for <id> (sets global docker_cmd). Re-runs the
# idempotent dir ensure, so no per-tool snapshot arrays are needed.
setup_use_cli() {
  box_docker_cli "$HOME/.config/$(box_tool_field "$1" config_dir)/docker-cli"
}

setup_step "[2/5] Tool configs + launchers"
for _setup_id in $box_tool_ids; do
  for _setup_asset in $(box_tool_field "$_setup_id" artifacts); do
    _setup_leaf=$(box_artifact_field "$_setup_id" "$_setup_asset" installed)
    [[ -n "$_setup_leaf" ]] || continue
    box_install_tool_config "$bundle_dir/$(box_artifact_field "$_setup_id" "$_setup_asset" source)" \
      "$HOME/.config/$(box_tool_field "$_setup_id" config_dir)/$_setup_leaf" \
      "$(box_artifact_field "$_setup_id" "$_setup_asset" mode)"
  done
  _setup_adapter=$(box_tool_field "$_setup_id" install_adapter)
  if [[ -n "$_setup_adapter" ]]; then
    ( # shellcheck disable=SC1090 # fixed validated install adapter
      source "$bundle_dir/$_setup_adapter"; box_harness_install_prepare )
  fi
  # Replace code as a package after validating the source contract. User state
  # lives in .config, never in this code-only install tree.
  _setup_pkg="$HOME/.local/bin/harnesses/$_setup_id"
  while IFS= read -r _setup_code; do
    _setup_relative=${_setup_code#"$bundle_dir/harnesses/$_setup_id/"}
    box_prepare_directory "$_setup_pkg/$(dirname -- "$_setup_relative")" 755 >/dev/null
    [[ ! -L "$_setup_pkg/$_setup_relative" ]] || die 'Installed adapter must not be a symlink.'
    box_atomic_install "$_setup_code" "$_setup_pkg/$_setup_relative" 644
  done < <(find "$bundle_dir/harnesses/$_setup_id" -type f -name '*.sh' ! -path '*/verify.d/*')
  # This is a code-only package tree; remove obsolete installed shell code
  # only after the current source package has been validated and installed.
  while IFS= read -r _setup_old; do
    _setup_relative=${_setup_old#"$_setup_pkg/"}
    if [[ ! -f "$bundle_dir/harnesses/$_setup_id/$_setup_relative" ]]; then
      rm -f -- "$_setup_old"
    fi
  done < <(find "$_setup_pkg" -type f -name '*.sh')
done
unset _setup_id _setup_asset _setup_leaf _setup_adapter _setup_pkg _setup_code _setup_relative
# Installed version pins win over the bundle on re-runs: overwriting them
# here would silently revert an in-progress upgrade (see make -C box sync-pins-<stem> (docs/upgrades.md)).
for _setup_id in $box_tool_ids; do
  _setup_pin_file=$(box_tool_field "$_setup_id" version_file)
  box_install_version_pin "$bundle_dir/$(box_tool_field "$_setup_id" version_source)" \
    "$HOME/.config/$(box_tool_field "$_setup_id" config_dir)/$_setup_pin_file"
done
unset _setup_id _setup_pin_file
setup_ok "version pins in place (installed pins win on re-run)"
# Install the whole split lib/ dir (launchers source the split files via
# their own dir; the installed copy must match that layout).
[[ -f "$bundle_dir/lib/preflight.sh" ]] || die "Missing lib sources in $bundle_dir/lib."
for _lib in "$bundle_dir"/lib/*.sh; do
  box_atomic_install "$_lib" "$HOME/.local/bin/lib/$(basename -- "$_lib")" 644
done
unset _lib
_setup_names=""
for _setup_id in $box_tool_ids; do
  _setup_launcher=$(box_tool_field "$_setup_id" launcher)
  box_atomic_install "$bundle_dir/$_setup_launcher" "$HOME/.local/bin/$_setup_launcher" 755
  _setup_names+="$_setup_launcher "
done
unset _setup_id _setup_launcher
# box-m-login is a muse-only UX helper outside the registry (no twin).
box_atomic_install "$bundle_dir/box-m-login" "$HOME/.local/bin/box-m-login" 755
# `box` is the setup-managed default entry point: a relative symlink (same
# dir) so script_dir realpath resolution still finds the split lib/*.sh
# files. --default <id> points it at that tool's launcher; re-running with
# another id flips it persistently. Refuse non-symlink collisions (do not
# clobber). Usage prints the invoked name, so `box --help` says `box` (plus
# the switch hint) while `box-m --help` says `box-m`; BOX_TOOL stays
# canonical for error prefixes.
_default_target=$(box_install_default "$HOME/.local/bin/box" "$setup_default")
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
# all launchers default here; there is no old-path fallback. Never
# overwritten once created. Refuses symlinks (no truncate-through-link) and
# creates exclusively (noclobber) to close the check-then-create race.
setup_step "[3/5] Secrets + networks + runtime check"
providers_file="$HOME/.config/box/providers.env"
_setup_provider_result=$(box_install_provider_file "$providers_file")
if [[ "$_setup_provider_result" == created ]]; then
  setup_ok "created ~/.config/box/providers.env (mode 600, empty)"
  {
    # shellcheck disable=SC2016 # backticks are literal documentation.
    printf '  Optional API login: add literal KEY=value lines (LF only, `#` comments allowed):\n'
    printf '    MUSE_CODE_API_KEY=...      (Muse API login; device login is also supported)\n    OPENAI_API_KEY=...        (Codex explicit API-key login only)\n'
    printf '  Unknown or duplicate keys hard-FAIL at launch. Never commit this file.\n'
  } >&2
else
  setup_ok "providers.env present (protected mode, kept as-is)"
fi
unset providers_file _setup_provider_result

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
  if ! command -v jq >/dev/null; then
    setup_warn "cannot query Docker runtimes; jq is required."
  elif printf '%s' "$_setup_runtimes" | jq -e --arg w runsc 'has($w)' >/dev/null 2>&1; then
    setup_ok "runtime runsc (gVisor) registered"
  else
    setup_warn "runtime 'runsc' not registered; default runs fail closed until gVisor is installed (docs/operations.md §5) or you use --docker-fallback."
  fi
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
  _setup_vkey=$(box_version_key "$_setup_id")
  _setup_versions+="${_setup_versions:+, }$_setup_id ${!_setup_vkey}"
done
unset _setup_id _setup_vkey
setup_ok "version pins validated ($_setup_versions)"
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
      _setup_vkey=$(box_version_key "$_setup_id")
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
# fallback (each field across registered prefixes); an empty providers.env
# is valid for native device login.
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
# use, via box_git_identity_probe). The hint lists every prefix pair for
# the [todo] summary below. When env is incomplete, missing fields are
# inferred from `git config --global` (same validity rules the launchers
# enforce; invalid values count as missing). Explicit env always wins per
# field. Nothing is exported or persisted here: setup.sh stays
# non-interactive and only prints copy-paste lines (CI-safe; no prompts,
# no shell-rc writes).
_setup_need_git=0
_setup_probe_primary=$(box_tool_field "${box_tool_ids%% *}" git_prefix)
if box_git_identity_probe "$_setup_probe_primary"; then
  _setup_git_hint=$probe_git_hint
  if [[ -n "$probe_git_inferred" ]]; then
    setup_ok "git identity inferred from git config --global (launchers infer live; copy-paste to pin explicitly for reproducible CI):"
    for _setup_id in $box_tool_ids; do
      _setup_gp=$(box_tool_field "$_setup_id" git_prefix)
      printf '    export %s_GIT_NAME=%q %s_GIT_EMAIL=%q\n' \
        "$_setup_gp" "$probe_git_name" "$_setup_gp" "$probe_git_email" >&2
    done
    unset _setup_id _setup_gp
  else
    setup_ok "git identity set"
  fi
else
  _setup_git_hint=$probe_git_hint
  _setup_need_git=1
fi
unset _setup_probe_primary probe_git_name probe_git_email probe_git_missing probe_git_hint probe_git_inferred probe_git_raw_name probe_git_raw_email inferred_git_name inferred_git_email
# An empty providers.env is valid for keyless native login: there is no
# missing-providers todo state, so no _setup_need_providers flag.
_setup_verify_cmds=""
# Shared presence probe (lib/preflight.sh): same allowlist + shape rules as
# the launcher loader, so unknown keys and CR tails no longer count as filled.
# shellcheck disable=SC2086 # word-splitting BOX_CRED_KEYS into allowlist args is intentional.
if box_credentials_filled "$HOME/.config/box/providers.env" $BOX_CRED_KEYS; then
  setup_ok "provider credentials configured (native login is separate)"
else
  setup_ok "provider credentials empty; use the selected harness native login or explicitly configure an API key"
fi
for _setup_id in $box_tool_ids; do
  _setup_verify_cmds+="${_setup_verify_cmds:+ / }$(box_tool_field "$_setup_id" launcher) --dry-run"
done
unset _setup_id
if (( _setup_need_path || _setup_need_git )); then
  {
    printf '\n  [todo] still missing:\n'
    (( !_setup_need_path )) || printf '    1. Put ~/.local/bin on PATH (see docs/operations.md §8).\n'
    (( !_setup_need_git )) || printf '    2. Export git identity: %s.\n' "$_setup_git_hint"
    printf '\n  Verify with: %s (from a scratch project).\n' "$_setup_verify_cmds"
  } >&2
else
  {
    printf '\n  [done] installation complete; authentication and native verification are separate gates.\n'
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
unset _setup_need_path _setup_need_git _setup_local_bin setup_orig_path _setup_need_migrate
