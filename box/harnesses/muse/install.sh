# shellcheck shell=bash
# shellcheck disable=SC2154 # setup-owned globals
# Muse owns its global live settings/cache preparation.
# shellcheck source=harnesses/muse/native.sh
source "$bundle_dir/$(box_tool_field muse native_helper)"
box_harness_install_plan() {
  local home
  home="$HOME/$(box_state_field muse home root)"
  box_plan_directory "$home" >/dev/null
  # Setup never inspects native auth: migration is an explicit live-launch
  # gate backed by the canonical store, not ordinary installation.
  [[ ! -L "$home/settings.json" ]] || die 'Muse settings must not be a symlink.'
  if [[ -e "$home/settings.json" ]]; then box_assert_owner_mode "$home/settings.json" 'Muse settings' nowrite; fi
  # Seed the versioned state-policy file without scope settings; reruns
  # preserve it byte-for-byte and never migrate login material.
  box_plan_directory "$HOME/.config/box" >/dev/null
}
box_harness_install_prepare() {
  local home policy
  home="$HOME/$(box_state_field muse home root)"
  box_prepare_directory "$home" 700 >/dev/null
  # Settings are generated per launch; setup prepares only the native home.
  policy="$HOME/.config/box/state.toml"
  if [[ ! -e "$policy" && ! -L "$policy" ]]; then
    printf 'schema_version = 1\n' >"$policy.tmp.$$" || die 'Cannot stage state policy.'
    chmod 600 -- "$policy.tmp.$$" || die 'Cannot secure state policy.'
    mv -f -- "$policy.tmp.$$" "$policy" || die 'Cannot install state policy.'
  fi
}
