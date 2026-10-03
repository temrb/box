# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154
opencode_files_base='https://opencode.ai/files/bin'
# Resolve OpenCode v2 pins. Sets want_opencode_version/_amd64/_arm64.
# No latest channel: pass --opencode VERSION (or seed BOX_UPDATE_OPENCODE_*
# together). Archive digests always come from the standalone glibc tarballs on
# opencode.ai/files/bin (hash-checked bytes, never npm integrity, never latest).
# Old v1 npm/NodeSource seeds fail closed with migration guidance.
resolve_opencode() {
  local explicit=${1:-} version arch platform url file computed
  if [[ -n "${BOX_UPDATE_OPENCODE_NPM_INTEGRITY:-}${BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_X64:-}${BOX_UPDATE_OPENCODE_NPM_INTEGRITY_LINUX_ARM64:-}${BOX_UPDATE_OPENCODE_NODE_VERSION:-}${BOX_UPDATE_OPENCODE_NODESOURCE_FINGERPRINT:-}${BOX_UPDATE_NODE_VERSION:-}${BOX_UPDATE_NODESOURCE_FINGERPRINT:-}" ]]; then
    die 'OpenCode v1 npm/NodeSource pins are retired (v2 uses standalone SHA256 archives). Set BOX_UPDATE_OPENCODE_VERSION plus BOX_UPDATE_OPENCODE_SHA256_AMD64 and BOX_UPDATE_OPENCODE_SHA256_ARM64 together; see docs/upgrades.md.'
  fi
  if [[ -n "${BOX_UPDATE_OPENCODE_VERSION:-}" ]]; then
    [[ -z "$explicit" ]] || die 'Conflicting OpenCode pins: --opencode and BOX_UPDATE_OPENCODE_VERSION are both set.'
    want_opencode_version=$BOX_UPDATE_OPENCODE_VERSION
    want_opencode_amd64=${BOX_UPDATE_OPENCODE_SHA256_AMD64:-}
    want_opencode_arm64=${BOX_UPDATE_OPENCODE_SHA256_ARM64:-}
    [[ -n "$want_opencode_amd64" && -n "$want_opencode_arm64" ]] \
      || die 'Partial OpenCode seed: set BOX_UPDATE_OPENCODE_VERSION plus BOX_UPDATE_OPENCODE_SHA256_AMD64 and BOX_UPDATE_OPENCODE_SHA256_ARM64 together.'
    return 0
  fi
  if [[ -n "${BOX_UPDATE_OPENCODE_SHA256_AMD64:-}${BOX_UPDATE_OPENCODE_SHA256_ARM64:-}" ]]; then
    die 'Partial OpenCode seed: set BOX_UPDATE_OPENCODE_VERSION plus BOX_UPDATE_OPENCODE_SHA256_AMD64 and BOX_UPDATE_OPENCODE_SHA256_ARM64 together.'
  fi
  if [[ -n "$explicit" ]]; then
    version=$explicit
  else
    die 'OpenCode has no latest channel: pass --opencode VERSION (see https://opencode.ai/v2/docs) or seed BOX_UPDATE_OPENCODE_VERSION plus BOX_UPDATE_OPENCODE_SHA256_AMD64 and BOX_UPDATE_OPENCODE_SHA256_ARM64 together; never resolves latest.'
  fi
  if [[ "$version" == "$OPENCODE_VERSION" ]]; then
    want_opencode_version=$OPENCODE_VERSION
    want_opencode_amd64=$OPENCODE_SHA256_AMD64
    want_opencode_arm64=$OPENCODE_SHA256_ARM64
    return 0
  fi
  assert_url_safe_version "$version" 'opencode version'
  want_opencode_version=$version
  for arch in amd64 arm64; do
    if [[ "$arch" == amd64 ]]; then platform=x64-baseline; else platform=arm64; fi
    url="$opencode_files_base/$version/opencode-linux-$platform.tar.gz"
    file=$(box_mktemp_file opencode-artifact) || die 'Cannot stage OpenCode artifact.'
    if ! curl --fail --silent --show-error --proto '=https' --tlsv1.2 --location --connect-timeout 15 --max-time 600 -o "$file" -- "$url"; then
      rm -f -- "$file"; die "Cannot download OpenCode asset: opencode-linux-$platform.tar.gz@$version"
    fi
    computed=$(sha256sum -- "$file"); computed=${computed%% *}
    [[ "$computed" =~ ^[0-9a-f]{64}$ ]] || { rm -f -- "$file"; die "Invalid OpenCode digest for $arch@$version."; }
    if ! python3 "$bundle_dir/harnesses/opencode/archive.py" "$file" "$arch"; then
      rm -f -- "$file"; die "Corrupted/incomplete OpenCode asset: $arch@$version"
    fi
    rm -f -- "$file"
    if [[ "$arch" == amd64 ]]; then want_opencode_amd64=$computed; else want_opencode_arm64=$computed; fi
  done
  [[ -n "${want_opencode_amd64:-}" && -n "${want_opencode_arm64:-}" ]] || die 'Partial OpenCode fetch: both architectures are required.'
}

box_harness_resolve() {
  resolve_opencode "${1:-}"
  new_pin[OPENCODE_VERSION]=$want_opencode_version
  new_pin[OPENCODE_SHA256_AMD64]=$want_opencode_amd64
  new_pin[OPENCODE_SHA256_ARM64]=$want_opencode_arm64
}
