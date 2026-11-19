#!/usr/bin/env bash
set -Eeuo pipefail
install -d -m 0755 /usr/local/sbin
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 3 https://raw.githubusercontent.com/Shuryatko/Deploy_Soft/e3e8b0a962da2b8f46ff2817957d0b05d9566b89/VM-Provisioning/scripts/expand-postgresql-disk.sh -o "$tmp"
bash -n "$tmp"
install -m 0755 "$tmp" /usr/local/sbin/expand-postgresql-disk.sh
cat > /etc/systemd/system/expand-postgresql-disk.service <<'EOF'
[Unit]
Description=Expand dedicated PostgreSQL ext4 data disk
After=local-fs.target
RequiresMountsFor=/var/lib/postgresql
Before=postgresql@16-main.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/expand-postgresql-disk.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now expand-postgresql-disk.service
