#!/usr/bin/env bash
# Bounded real ext4 exhaustion on a disposable hosted VM, never auth/native data.
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
[[ $# == 1 && -d $1 && ! -L $1 ]] || { printf 'Usage: qualify-ext4.sh <private-scratch-parent>\n' >&2; exit 2; }
uid=$(id -u); gid=$(id -g)
((uid > 0 && gid > 0)) || { printf 'Use the normal qualification runner user.\n' >&2; exit 2; }
parent=$(realpath -- "$1")
[[ $(stat -c '%u:%a' -- "$parent") == "$uid:700" ]] || { printf 'Scratch parent must be owned and mode 700.\n' >&2; exit 2; }
for prerequisite in sudo mkfs.ext4 mount umount findmnt truncate python3; do
  command -v "$prerequisite" >/dev/null || { printf 'Missing filesystem prerequisite: %s\n' "$prerequisite" >&2; exit 2; }
done
sudo -n true
bundle=$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")/../..")
umask 077
scratch=$(mktemp -d "$parent/box-ext4.XXXXXXXX")
mountpoint="$scratch/filesystem"
mkdir -m 700 "$mountpoint"
mount_id=''
mount_active=0
# shellcheck disable=SC2317,SC2329 # EXIT trap
cleanup() {
  local rc=$? current
  if ((mount_active)); then
    current=$(findmnt -rn -M "$mountpoint" -o ID) || current=''
    if [[ -z "$mount_id" || "$current" != "$mount_id" ]] || ! sudo -n umount -- "$mountpoint"; then
      printf 'Filesystem cleanup refused or failed for exact recorded mount; evidence retained.\n' >&2
      rc=1
    fi
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
for kind in blocks inodes; do
  image="$scratch/$kind.ext4"
  truncate -s 32M -- "$image"
  if [[ $kind == inodes ]]; then
    mkfs.ext4 -q -F -m 0 -N 128 -- "$image"
  else
    mkfs.ext4 -q -F -m 0 -- "$image"
  fi
  sudo -n mount -t ext4 -o loop,nodev,nosuid,noexec -- "$image" "$mountpoint"
  mount_active=1
  mount_id=$(findmnt -rn -M "$mountpoint" -o ID)
  [[ "$mount_id" =~ ^[0-9]+$ ]] || { printf 'Cannot identify disposable ext4 mount.\n' >&2; exit 1; }
  sudo -n chown "$uid:$gid" -- "$mountpoint"
  chmod 700 -- "$mountpoint"
  python3 -I "$bundle/tests/native/qualify-exhaustion.py" "$mountpoint" "$kind"
  [[ $(findmnt -rn -M "$mountpoint" -o ID) == "$mount_id" ]] || { printf 'Disposable mount was replaced.\n' >&2; exit 1; }
  sudo -n umount -- "$mountpoint"
  mount_active=0
  mount_id=''
done
printf 'P: real disposable ext4 block/inode exhaustion passed; power-loss and VM restart remain unqualified.\n'
