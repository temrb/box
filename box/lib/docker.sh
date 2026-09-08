# shellcheck shell=bash
# box/lib/docker.sh — isolated Docker CLI plus engine/runtime/image/
# network asserts and the dry-run/exec tail. Requires lib/preflight.sh
# (die, BOX_TOOL, box_realpath); never executed directly.
# shellcheck disable=SC2034,SC2154 # launcher-owned globals (docker_cmd, args,
# host_uid/host_gid, dry_run, container, volume, ...) are set by the sourcing
# launchers; standalone analysis cannot see that.

[[ -n "${_BOX_DOCKER_LOADED:-}" ]] && return 0
_BOX_DOCKER_LOADED=1

: "${BOX_TOOL:?caller must set BOX_TOOL before sourcing lib files}"

# Inspect format shared by the assert and ensure paths. Pipe-delimited (never
# space-delimited): Docker renders a missing option as `<no value>`, which
# contains a space and would shift a space-split `read`.
_BOX_NETWORK_INSPECT_FORMAT='{{.Driver}}|{{.Internal}}|{{index .Options "com.docker.network.bridge.enable_icc"}}|{{index .Options "com.docker.network.bridge.enable_ip_masquerade"}}'

# Isolated Docker CLI configuration. Unsets poisoning-prone host vars,
# resolves the docker binary, and enforces <dir>/config.json content `{}`.
# A pre-existing config with proxies, credStore, or currentContext would
# otherwise leak host egress/auth into sandbox operations: back it up
# (single .bak, mode 600, overwritten) and reset it with a WARNING. Repairs
# 700/600 permissions even when present. Single generation is deliberate
# (see operations.md §8): the backup may be credential-bearing, so numbered
# rotation would multiply secret copies for no recovery benefit.
# Writes are atomic (mktemp file + rename). Refuses symlinked config
# dirs (install/chmod would follow them).
# Sets globals: docker_bin, docker_cli_config, docker_cmd (array).
# Usage: box_docker_cli <cli_config_dir>
box_docker_cli() {
  local cli_dir=${1:-} existing tmp_cfg
  [[ -n "$cli_dir" ]] || die 'Internal error: empty Docker CLI config dir.'
  unset DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH DOCKER_CONFIG
  unset DOCKER_BUILDKIT BUILDKIT_HOST BUILDKIT_PROGRESS
  # Prefix expansion unsets exactly BUILDKIT_*/BUILDX_* without scanning the
  # whole environment via compgen. Unquoted on purpose: variable names cannot
  # contain spaces or glob characters, and quoting would collapse the list
  # into one word.
  # shellcheck disable=SC2086
  unset ${!BUILDKIT_@} ${!BUILDX_@}
  docker_bin=$(command -v docker 2>/dev/null || true)
  if [[ -z "$docker_bin" || ! -x "$docker_bin" ]]; then docker_bin=/usr/bin/docker; fi
  if [[ ! -x "$docker_bin" ]]; then docker_bin=/usr/local/bin/docker; fi
  [[ -x "$docker_bin" ]] || die 'Install Docker Engine from the official repository.'
  docker_cli_config=$cli_dir
  [[ ! -L "$docker_cli_config" && ! -L "$docker_cli_config/config.json" ]] \
    || die 'Docker CLI configuration path must not be a symlink.'
  install -d -m 700 -- "$docker_cli_config" \
    || die 'Cannot create the Docker CLI configuration directory.'
  chmod 700 -- "$docker_cli_config" \
    || die 'Cannot secure the Docker CLI configuration directory.'
  # Allocate a fresh mktemp file (mode 600). RETURN covers the normal
  # return; EXIT covers die/exit paths inside this function (RETURN alone is
  # skipped on exit). Both are cleared after the explicit rm below so no
  # stale trap (or stale local $tmp_cfg reference) persists past the return.
  # Callers set no EXIT trap of their own, so chaining is unnecessary.
  # (No stale-tmp sweep: mktemp names are unique per run; sweeping risks
  # deleting a concurrent run's file.)
  tmp_cfg=$(mktemp "$docker_cli_config/.config.json.tmp.XXXXXX") \
    || die 'Cannot create temporary Docker CLI configuration.'
  trap 'rm -f -- "$tmp_cfg"' RETURN EXIT
  if [[ -s "$docker_cli_config/config.json" ]]; then
    existing=$(tr -d '[:space:]' < "$docker_cli_config/config.json") \
      || die 'Cannot read the Docker CLI configuration.'
    if [[ "$existing" != '{}' ]]; then
      cp -p -- "$docker_cli_config/config.json" "$docker_cli_config/config.json.bak" \
        || die 'Cannot back up the unexpected Docker CLI configuration.'
      chmod 600 -- "$docker_cli_config/config.json.bak" \
        || die 'Cannot secure the Docker CLI configuration backup.'
      # Subshell umask: the write needs 077 but the change must not leak
      # into the caller (mktemp already made $tmp_cfg mode 600 regardless).
      ( umask 077; printf '{}\n' > "$tmp_cfg" ) \
        || die 'Cannot reset the Docker CLI configuration.'
      chmod 600 -- "$tmp_cfg" \
        || die 'Cannot secure the Docker CLI configuration.'
      mv -f -- "$tmp_cfg" "$docker_cli_config/config.json" \
        || die 'Cannot reset the Docker CLI configuration.'
      printf '%s: WARNING: unexpected %s/config.json replaced with {} (backup: config.json.bak).\n' \
        "$BOX_TOOL" "$docker_cli_config" >&2
    fi
  else
    ( umask 077; printf '{}\n' > "$tmp_cfg" ) \
      || die 'Cannot initialize the Docker CLI configuration.'
    chmod 600 -- "$tmp_cfg" \
      || die 'Cannot secure the Docker CLI configuration.'
    mv -f -- "$tmp_cfg" "$docker_cli_config/config.json" \
      || die 'Cannot initialize the Docker CLI configuration.'
  fi
  rm -f -- "$tmp_cfg" 2>/dev/null || true
  trap - RETURN EXIT
  chmod 600 -- "$docker_cli_config/config.json" \
    || die 'Cannot secure the Docker CLI configuration.'
  docker_cmd=("$docker_bin" --config "$docker_cli_config" --host unix:///var/run/docker.sock)
}

# Assert the local Engine is rootful (rootless/userns-remapped Engines need a
# different UID-mapping design) and recent enough for the
# `bind-recursive=disabled` mount flags (Engine >= 25). Uses global
# docker_cmd. No arguments.
box_assert_engine() {
  local security_options server_version server_major
  security_options=$("${docker_cmd[@]}" info --format '{{json .SecurityOptions}}') \
    || die 'Local Docker Engine is unavailable.'
  case "$security_options" in
    *name=userns*|*name=rootless*) die 'Rootless/userns-remapped Engine requires a different UID mapping design.' ;;
  esac
  server_version=$("${docker_cmd[@]}" version --format '{{.Server.Version}}') \
    || die 'Cannot determine Docker Engine version.'
  server_major=${server_version%%.*}
  [[ "$server_major" =~ ^[0-9]+$ ]] \
    || die "Cannot parse Docker Engine version: ${server_version:-unknown}"
  ((10#$server_major >= 25)) \
    || die "Docker Engine >= 25.0 is required (found $server_version)."
}

# Assert the sandbox image exists, matches the invoking UID/GID, and (unless
# an explicit image override is set) carries the pinned-version label plus
# the supply-chain integrity labels. Label pairs come from the registry
# (single source; a typo'd key would otherwise silently disable pinning).
# The first pair is the version pin (position 0 convention, shared with
# box_image_tag); the rest are integrity labels compared from a single
# combined inspect (one daemon round trip, same pattern as lib/build.sh).
# Pin values were regex-validated when the version file was parsed and are
# recorded in the image labels at build time; comparing them here closes the
# version-only substitution gap. Uses the box_file_pin map set by
# box_load_version_file. Callers must source lib/tools.sh.
# Usage: box_assert_image <image> <file_version> <version_file> <tool-id> <override_is_set:0|1>
box_assert_image() {
  local image=${1:-} expected=${2:-} vfile=${3:-} tool=${4:-} override=${5:-0}
  local image_info image_user image_label label_value
  [[ -n "$image" && -n "$expected" && -n "$vfile" && -n "$tool" ]] \
    || die 'Internal error: missing image assertion arguments.'
  box_require_tool "$tool"
  local first_pair lkey
  first_pair=$(box_tool_field "$tool" label_pins); first_pair=${first_pair%% *}
  lkey=${first_pair#*:}
  image_info=$("${docker_cmd[@]}" image inspect \
    --format "{{.Config.User}}|{{index .Config.Labels \"$lkey\"}}" "$image") \
    || die 'Build the image for your UID/GID first.'
  [[ "$image_info" == *'|'* ]] || die 'Cannot parse image inspect output.'
  IFS='|' read -r image_user image_label _rest <<<"$image_info"
  [[ -z "${_rest:-}" ]] || die 'Cannot parse image inspect output.'
  [[ "$image_user" == "$host_uid:$host_gid" ]] || die 'Image UID/GID differs; rebuild with your current IDs.'
  if ((override)); then
    printf '%s: WARNING: explicit image override %s; pinned-version and integrity label checks skipped (UID/GID still enforced).\n' \
      "$BOX_TOOL" "$image" >&2
  else
    [[ "$image_label" == "$expected" ]] \
      || die "Image label reports ${image_label:-none}, but $vfile pins $expected; rebuild the image or update the pin file."
    # Remaining integrity labels ride one combined inspect (same single-format
    # pattern as lib/build.sh), then compare per key so each mismatch still
    # names its label. The '|' join is safe: pin regexes admit no pipes.
    local pair pin key want first=1
    local -a want_keys=() want_values=()
    for pair in $(box_tool_field "$tool" label_pins); do
      if ((first)); then first=0; continue; fi # version already compared above
      pin=${pair%%:*}; key=${pair#*:}
      want=${box_file_pin[$pin]:-}
      [[ -n "$want" ]] || die "Internal error: missing $pin pin for image assertion."
      want_keys+=("$key")
      want_values+=("$want")
    done
    if ((${#want_keys[@]} > 0)); then
      local label_fmt='' label_got='' i
      for i in "${!want_keys[@]}"; do
        label_fmt+="${label_fmt:+|}{{index .Config.Labels \"${want_keys[$i]}\"}}"
      done
      label_got=$("${docker_cmd[@]}" image inspect \
        --format "$label_fmt" "$image") \
        || die "Cannot inspect image labels."
      local -a got_values=()
      IFS='|' read -r -a got_values <<<"$label_got"
      ((${#got_values[@]} == ${#want_keys[@]})) || die 'Cannot parse image inspect output.'
      for i in "${!want_keys[@]}"; do
        label_value=${got_values[$i]}
        [[ "$label_value" == "${want_values[$i]}" ]] \
          || die "Image ${want_keys[$i]} label mismatch; rebuild the image or update $vfile."
      done
    fi
  fi
}

# Shared dedicated-bridge policy check over pipe-delimited
# `docker network inspect` output. Single home for the policy so the launcher
# assert and the setup ensure path can never drift apart. Dies on violation.
# Usage: box_assert_network_policy <network> <policy>
box_assert_network_policy() {
  local network=${1:-} policy=${2:-} net_driver net_internal net_icc net_masq _rest
  [[ -n "$network" ]] || die 'Internal error: empty network name.'
  [[ -n "$policy" ]] || die 'Internal error: empty network policy.'
  IFS='|' read -r net_driver net_internal net_icc net_masq _rest <<<"$policy"
  [[ -z "${_rest:-}" ]] || die 'Internal error: malformed network policy.'
  [[ -n "$net_driver" && -n "$net_internal" && -n "$net_icc" && -n "$net_masq" ]] \
    || die 'Internal error: incomplete network policy.'
  [[ "$net_driver" == "bridge" ]] || die "Unexpected sandbox network driver: ${net_driver:-none}"
  [[ "$net_internal" == "false" ]] || die "Sandbox network must not be internal-only: ${net_internal:-none}"
  [[ "$net_icc" == "false" ]] || die "Sandbox network requires enable_icc=false: ${net_icc:-none}"
  [[ "$net_masq" == "true" ]] || die "Sandbox network requires enable_ip_masquerade=true: ${net_masq:-none}"
}

# Assert the dedicated bridge network policy field-wise.
# Usage: box_assert_network <network>
box_assert_network() {
  local network=${1:-} policy
  [[ -n "$network" ]] || die 'Internal error: empty network name.'
  policy=$("${docker_cmd[@]}" network inspect --format "$_BOX_NETWORK_INSPECT_FORMAT" "$network") \
    || die 'Create the dedicated network using the setup instructions.'
  box_assert_network_policy "$network" "$policy"
}

# Ensure the dedicated bridge network exists with the shared policy (create
# it when missing; re-assert field-wise when present, including after an
# inspect-then-create race). Prints `created` or `verified` to stdout for the
# caller's status line. Two networks are kept (box-m + box-o);
# this helper only shares the policy handling.
# Usage: box_ensure_network <network> <docker-cmd...>
box_ensure_network() {
  local network=${1:-}
  shift || die 'Internal error: missing network ensure arguments.'
  (($# > 0)) || die 'Internal error: missing docker command.'
  local -a cmd=("$@")
  local policy
  if policy=$("${cmd[@]}" network inspect --format "$_BOX_NETWORK_INSPECT_FORMAT" "$network" 2>/dev/null); then
    box_assert_network_policy "$network" "$policy"
    printf 'verified'
  else
    if "${cmd[@]}" network create --driver=bridge \
        --opt com.docker.network.bridge.enable_icc=false \
        --opt com.docker.network.bridge.enable_ip_masquerade=true \
        -- "$network" >/dev/null; then
      printf 'created'
    elif policy=$("${cmd[@]}" network inspect --format "$_BOX_NETWORK_INSPECT_FORMAT" "$network" 2>/dev/null); then
      box_assert_network_policy "$network" "$policy"
      printf 'verified'
    else
      die "Cannot create network $network."
    fi
  fi
}

# Assert the requested OCI runtime is registered with the Engine before
# attempting `docker run`, so a missing gVisor install fails with remediation
# instead of the raw daemon error `unknown or invalid runtime name: runsc`.
# Never falls back automatically: runsc stays the default and runc requires
# explicit --docker-fallback (see box_check_fallback).
# Reads globals: docker_cmd, fallback_requested (defaults to runsc when unset,
# e.g. setup.sh which never parses launcher args).
# No arguments.
box_assert_runtime() {
  local runtimes wanted
  if [[ "${fallback_requested:-0}" == 1 ]]; then wanted=runc; else wanted=runsc; fi
  runtimes=$("${docker_cmd[@]}" info --format '{{json .Runtimes}}') \
    || die 'Local Docker Engine is unavailable.'
  case "$runtimes" in
    *"\"$wanted\""*) : ;;
    *)
      if [[ "$wanted" == runsc ]]; then
        die "Container runtime 'runsc' (gVisor) is not registered with Docker. Install gVisor per docs/operations.md §5 ('runsc install' + 'systemctl restart docker'), or explicitly use --docker-fallback for hardened runc."
      else
        die "Container runtime 'runc' is not registered with Docker."
      fi
      ;;
  esac
}

# Print the docker command under --dry-run, otherwise assert engine/runtime/
# image/network and exec. Reads globals: dry_run, docker_cmd, args, image,
# file_version, version_file, container, volume.
# Usage: box_docker_exec <tool-id> <network-name> <override:0|1>
box_docker_exec() {
  local tool=${1:-} network=${2:-} override=${3:-0}
  [[ -n "$tool" && -n "$network" ]] || die 'Internal error: missing exec arguments.'
  if ((dry_run)); then
    printf '%q ' "${docker_cmd[@]}" "${args[@]}"
    printf '\n'
    exit 0
  fi
  box_assert_engine
  box_assert_runtime
  # shellcheck disable=SC2154 # file_version is set by the launchers before this tail runs (cross-file).
  box_assert_image "$image" "$file_version" "$version_file" "$tool" "$override"
  box_assert_network "$network"
  printf 'Container: %s\nState volume: %s\n' "$container" "$volume" >&2
  exec "${docker_cmd[@]}" "${args[@]}"
}
