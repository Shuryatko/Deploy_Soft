# VM-Provisioning

Ubuntu Server 24.04 / vCenter cloud-init profiles for a clean template with DHCP, open-vm-tools and expand-root-lvm.service.

Use cloud-init config data in VM Customization Specifications. Metadata: set local-hostname uniquely for each VM. Do not reuse instance-id. Paste the corresponding cloud-init YAML into User data.

Base updates Ubuntu; Docker runs Base then installs Docker CE, Compose and Buildx from the official apt repository. Scripts are pinned to an immutable Git commit in the profiles. Review and update the pinned revision when promoting changes. No automatic reboot; check /var/run/reboot-required. Docker commands use sudo (no automatic root-equivalent group membership).

Recommended Docker VMDK: 20 GiB or larger. Logs: /var/log/cloud-init-output.log and /var/log/vm-provisioning.log. Verify with sudo cloud-init status --wait --long, sudo docker version, sudo docker compose version and sudo docker info. Test on a new VM before production.

Future profiles: Portainer, Appsmith, n8n, ZeroTier. Never commit credentials or agent enrollment keys.
