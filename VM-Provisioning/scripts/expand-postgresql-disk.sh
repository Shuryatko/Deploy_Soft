#!/usr/bin/env bash
set -Eeuo pipefail
target=/var/lib/postgresql
# Only grow the dedicated whole-disk ext4 filesystem registered in fstab.
if ! mountpoint -q "$target"; then
  if findmnt --fstab --mountpoint "$target" >/dev/null 2>&1; then
    echo "Expected PostgreSQL disk is not mounted" >&2; exit 1
  fi
  echo "PostgreSQL uses system disk; skipping dedicated disk expansion"
  exit 0
fi
source=$(findmnt -n -o SOURCE --mountpoint "$target")
device=$(readlink -f "$source")
[[ -b "$device" && "$(lsblk -dnro TYPE "$device")" == disk ]]
[[ "$(findmnt -n -o FSTYPE --mountpoint "$target")" == ext4 ]]
uuid=$(blkid -s UUID -o value "$device")
[[ -n "$uuid" && "$(findmnt --fstab -n -o SOURCE --mountpoint "$target")" == "UUID=$uuid" ]]
resize2fs "$device"
df -h "$target"
