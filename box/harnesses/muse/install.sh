# shellcheck shell=bash
# shellcheck disable=SC2154 # setup-owned globals
# Muse owns its global live settings/cache preparation.
# shellcheck source=harnesses/muse/native.sh
source "$bundle_dir/$(box_tool_field muse native_helper)"
box_harness_install_plan() {
  local home
  home="$HOME/$(box_state_field muse home root)"
  box_plan_directory "$home" >/dev/null
  box_assert_native_cache "$home/auth.json"
  [[ ! -L "$home/settings.json" ]] || die 'Muse settings must not be a symlink.'
  if [[ -e "$home/settings.json" ]]; then box_assert_owner_mode "$home/settings.json" 'Muse settings' nowrite; fi
}
box_harness_install_prepare() {
  local home
  home="$HOME/$(box_state_field muse home root)"
  box_prepare_directory "$home" 700 >/dev/null
  # Settings are generated per launch; setup prepares only persistent auth/trust.
}
