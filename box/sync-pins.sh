#!/bin/bash -p
set -euo pipefail
BOX_TOOL=sync-pins.sh
bundle_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/pins.sh
source "$bundle_dir/lib/pins.sh"
# shellcheck source=lib/build.sh
source "$bundle_dir/lib/build.sh"
(($# == 1)) || die 'Usage: sync-pins.sh box-<stem>'
id=$(box_tool_id_for_launcher "$1") || exit 1
box_sync_installed_pins "$id" "$bundle_dir"
