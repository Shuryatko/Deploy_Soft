#!/usr/bin/env bash
set -Eeuo pipefail
exec > >(tee -a /var/log/vm-provisioning.log) 2>&1
echo "Starting Portainer provisioning"
docker info >/dev/null
install -d -m 0750 /opt/portainer
cd /opt/portainer
if [[ ! -f compose.yaml ]]; then
  cat > compose.yaml <<'EOF'
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: always
    ports:
      - "9443:9443"
      - "8000:8000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
volumes:
  portainer_data:
    name: portainer_data
networks:
  default:
    name: portainer_network
EOF
fi
docker compose config --quiet
docker compose up -d
for ((i=0;i<60;i++)); do
  if curl -kfsS --max-time 3 https://127.0.0.1:9443/api/status >/dev/null; then
    docker compose ps
    echo "Portainer provisioning complete"
    echo "Open https://<VM-IP>:9443 and create the administrator account promptly."
    exit 0
  fi
  sleep 2
done
docker compose logs --tail=50
echo "Portainer HTTPS readiness check failed" >&2
exit 1
