#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
exec > >(tee -a /var/log/vm-provisioning.log) 2>&1
echo "Starting PostgreSQL provisioning"
[[ $(id -u) == 0 ]] || exit 1
target=/var/lib/postgresql
die() { echo "$*" >&2; exit 1; }
if dpkg-query -W -f='${Status}' postgresql-16 2>/dev/null | grep -qx 'install ok installed'; then
  die "Existing PostgreSQL installation; refusing to modify storage"
fi
root_source=$(findmnt -n -o SOURCE /)
root_disk=$(lsblk -s -nrpo NAME,TYPE "$root_source" | awk '$2=="disk"{print $1}' | sort -u)
[[ "$root_disk" == /dev/sda ]] || die "Unexpected root disk layout; manual review required"
mapfile -t disks < <(lsblk -dnpo NAME,TYPE | awk '$2=="disk"{print $1}')
extra=()
for disk in "${disks[@]}"; do
  [[ "$disk" == "$root_disk" ]] || extra+=("$disk")
done
[[ ${#extra[@]} -le 1 ]] || die "Multiple extra disks; manual review required"
mountpoint -q "$target" && die "Existing PostgreSQL mount"
if [[ -e "$target" ]]; then
  [[ -d "$target" && ! -L "$target" ]] || die "Unexpected data path"
  [[ -z "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die "Data path not empty"
fi
if findmnt --fstab --mountpoint "$target" >/dev/null 2>&1; then
  die "Existing fstab entry"
fi
install -d -m 0755 "$target"
if [[ ${#extra[@]} == 1 ]]; then
  disk=${extra[0]}
  [[ "$disk" == /dev/sdb ]] || die "Expected additional VMware disk /dev/sdb"
  [[ "$(lsblk -nrpo NAME "$disk" | wc -l)" -eq 1 ]] || die "Disk has partitions or dependent devices"
  [[ "$(lsblk -dnro RO "$disk")" == 0 ]] || die "Disk read-only"
  [[ -z "$(lsblk -nrpo MOUNTPOINT "$disk" | tr -d '[:space:]')" ]] || die "Disk mounted"
  [[ -z "$(wipefs --noheadings --output TYPE "$disk")" ]] || die "Disk has existing signatures"
  # Require a completely zero-filled disk, not just absence of recognizable signatures.
  bytes=$(blockdev --getsize64 "$disk")
  cmp -s -n "$bytes" "$disk" /dev/zero || die "Disk is not empty (or read failed); refusing to format"
  mkfs.ext4 -L pgdata "$disk"
  uuid=$(blkid -s UUID -o value "$disk")
  [[ -n "$uuid" ]] || die "Filesystem UUID missing"
  cp -a /etc/fstab /etc/fstab.pre-postgresql
  printf 'UUID=%s %s ext4 defaults 0 2\n' "$uuid" "$target" >> /etc/fstab
  systemctl daemon-reload
  mount "$target"
  mountpoint -q "$target" || die "Data mount failed"
  install -d /etc/systemd/system/postgresql@16-main.service.d
  printf '[Unit]\nRequiresMountsFor=%s\nConditionPathIsMountPoint=%s\n' "$target" "$target" > /etc/systemd/system/postgresql@16-main.service.d/storage.conf
  systemctl daemon-reload
  echo "Dedicated PostgreSQL data disk mounted"
else
  echo "Using system disk for PostgreSQL data"
fi
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=180 install -y postgresql-common
# Set initdb options before the server package creates its default cluster.
install -d -m 0755 /etc/postgresql-common/createcluster.d
printf "initdb_options = '--data-checksums'\n" > /etc/postgresql-common/createcluster.d/99-deploy-soft.conf
apt-get -o DPkg::Lock::Timeout=180 install -y postgresql-16 postgresql-client-16
systemctl enable --now postgresql
pg_isready -h 127.0.0.1 -p 5432
runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 -Atc 'SHOW data_directory;'
[[ "$(runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 -Atc 'SHOW data_checksums;')" == on ]] || die "Data checksums not enabled"
echo "PostgreSQL data checksums enabled"
echo "PostgreSQL provisioning complete; remote access not enabled"
