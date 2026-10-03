#!/bin/bash -p
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
script_dir=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")
exec bash "$script_dir/harnesses/opencode/capture-validation.sh" "$@"
