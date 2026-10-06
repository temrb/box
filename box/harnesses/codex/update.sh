# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # updater-owned pin map and fetch primitives
box_harness_resolve() {
  local explicit=${1:-} version release arch asset digest url file computed listing companion
  if box_update_seed CODEX "$explicit" --codex Codex 'new_pin[CODEX_VERSION]' 'new_pin[CODEX_SHA256_AMD64]' 'new_pin[CODEX_SHA256_ARM64]'; then return 0; fi
  if [[ "$explicit" == "$CODEX_VERSION" ]]; then return 0; fi
  if [[ -n "$explicit" ]]; then
    assert_url_safe_version "$explicit" 'Codex version'
    release=$(fetch_url "https://api.github.com/repos/openai/codex/releases/tags/rust-v$explicit") || die 'Cannot fetch Codex release.'
  else
    release=$(fetch_url https://api.github.com/repos/openai/codex/releases/latest) || die 'Cannot fetch latest stable Codex release.'
  fi
  version=$(printf '%s' "$release" | jq -er 'select(.prerelease == false and .draft == false) | .tag_name | select(startswith("rust-v")) | ltrimstr("rust-v")') || die 'Codex release must be stable.'
  [[ -z "$explicit" || "$version" == "$explicit" ]] || die 'Codex release version mismatch.'
  [[ "$version" != "$CODEX_VERSION" ]] || return 0
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Invalid stable Codex version.'
  for arch in x86_64 aarch64; do
    asset="codex-package-$arch-unknown-linux-musl.tar.gz"
    digest=$(printf '%s' "$release" | jq -er --arg name "$asset" '[.assets[] | select(.name == $name)] | select(length == 1) | .[0].digest') || die "Missing Codex asset digest: $asset"
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die 'Invalid Codex asset digest.'
    url="https://github.com/openai/codex/releases/download/rust-v$version/$asset"
    file=$(box_mktemp_file codex-artifact) || die 'Cannot stage Codex artifact.'
    computed=$(box_fetch_verify "$url" "$file") || die "Cannot download Codex asset: $asset"
    if [[ "sha256:$computed" != "$digest" ]] || ! listing=$(tar -tzf "$file"); then
      rm -f -- "$file"; die "Corrupted/incomplete Codex asset: $asset"
    fi
    for companion in bin/codex bin/codex-code-mode-host codex-resources/bwrap codex-path/rg codex-package.json; do
      if ! grep -Fxq "$companion" <<<"$listing"; then
        rm -f -- "$file"; die "Missing Codex companion: $companion"
      fi
    done
    rm -f -- "$file"
    if [[ "$arch" == x86_64 ]]; then new_pin[CODEX_SHA256_AMD64]=${digest#sha256:}; else new_pin[CODEX_SHA256_ARM64]=${digest#sha256:}; fi
  done
  new_pin[CODEX_VERSION]=$version
}
