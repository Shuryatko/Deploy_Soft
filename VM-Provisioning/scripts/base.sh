#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > >(tee -a /var/log/vm-provisioning.log) 2>&1
echo "Starting base provisioning"
systemctl start expand-root-lvm.service
apt-get -o DPkg::Lock::Timeout=180 update
apt-get -o DPkg::Lock::Timeout=180 upgrade -y
apt-get -o DPkg::Lock::Timeout=180 install -y ca-certificates curl
echo "Base provisioning complete"
if [[ -f /var/run/reboot-required ]]; then echo "Reboot required after provisioning"; fi
