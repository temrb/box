# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154
muse_channel_url='https://api.meta.ai/muse-code/channels/muse-stable'
muse_download_base='https://lookaside.facebook.com/lookaside/muse/download/'
# Resolve Muse pins. Sets want_muse_version/_amd64/_arm64. Skips the manifest
# fetch when the target equals the current pin (explicit or seed).
resolve_muse() {
  local explicit=${1:-} channel_json version manifest_url manifest_json got algo
  if box_update_seed MUSE "$explicit" --muse Muse want_muse_version want_muse_amd64 want_muse_arm64; then return 0; fi
  if [[ -n "$explicit" ]]; then
    if [[ "$explicit" == "$MUSE_VERSION" ]]; then
      want_muse_version=$MUSE_VERSION
      want_muse_amd64=$MUSE_SHA256_AMD64
      want_muse_arm64=$MUSE_SHA256_ARM64
      return 0
    fi
    assert_url_safe_version "$explicit" 'muse version'
    manifest_url="${muse_download_base}?channel=muse&version=${explicit}&file=manifest.json"
    version=$explicit
  else
    channel_json=$(fetch_url "$muse_channel_url") || die 'Cannot fetch the Muse channel manifest.'
    version=$(printf '%s' "$channel_json" | jq -e -r '.version | strings') \
      || die 'Cannot parse the Muse channel version.'
    manifest_url=$(printf '%s' "$channel_json" | jq -e -r '.manifest_url | strings') \
      || die 'Cannot parse the Muse channel manifest URL.'
    case "$manifest_url" in https://*) ;; *) die 'Muse manifest URL must be https.';; esac
    if [[ "$version" == "$MUSE_VERSION" ]]; then
      want_muse_version=$MUSE_VERSION
      want_muse_amd64=$MUSE_SHA256_AMD64
      want_muse_arm64=$MUSE_SHA256_ARM64
      return 0
    fi
    assert_url_safe_version "$version" 'muse channel version'
  fi
  manifest_json=$(fetch_url "$manifest_url") || die "Cannot fetch the Muse manifest for $version."
  got=$(printf '%s' "$manifest_json" | jq -e -r '.version | strings') \
    || die "Cannot parse the Muse manifest version for $version."
  [[ "$got" == "$version" ]] || die "Muse manifest reports $got, want $version."
  algo=$(printf '%s' "$manifest_json" | jq -e -r '.checksum_algorithm | strings') \
    || die "Cannot parse the Muse manifest checksum algorithm for $version."
  [[ "$algo" == "sha256" ]] || die "Muse manifest checksum algorithm is $algo, want sha256."
  want_muse_version=$version
  want_muse_amd64=$(printf '%s' "$manifest_json" | jq -e -r '.artifacts.x86_linux.checksum | strings') \
    || die "Cannot parse the Muse x86_linux checksum for $version."
  want_muse_arm64=$(printf '%s' "$manifest_json" | jq -e -r '.artifacts.aarch64_linux.checksum | strings') \
    || die "Cannot parse the Muse aarch64_linux checksum for $version."
}

box_harness_resolve() {
  resolve_muse "${1:-}"
  new_pin[MUSE_VERSION]=$want_muse_version
  new_pin[MUSE_SHA256_AMD64]=$want_muse_amd64
  new_pin[MUSE_SHA256_ARM64]=$want_muse_arm64
}
