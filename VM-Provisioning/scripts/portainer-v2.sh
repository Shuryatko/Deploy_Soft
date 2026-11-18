#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
exec > >(tee -a /var/log/vm-provisioning.log) 2>&1
docker info >/dev/null
password=/run/portainer-bootstrap/admin-password
[[ -f "$password" ]] || { echo "Missing bootstrap password"; exit 1; }
[[ $(wc -c < "$password") -ge 12 ]] || { echo "Password too short"; exit 1; }
install -d -m 0750 /opt/portainer
cd /opt/portainer
[[ ! -e compose.yaml ]] || { echo "Existing compose file; refusing to overwrite"; exit 1; }
if docker volume inspect portainer_data >/dev/null 2>&1; then echo "Existing data volume; refusing to initialize"; exit 1; fi
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
cat > /run/portainer-bootstrap/override.yaml <<'EOF'
services:
  portainer:
    command: ["--admin-password-file", "/run/secrets/admin-password"]
    volumes:
      - /run/portainer-bootstrap/admin-password:/run/secrets/admin-password:ro
EOF
docker compose -f compose.yaml -f /run/portainer-bootstrap/override.yaml up -d
ready=0
for ((i=0;i<60;i++)); do
  if jq -Rs '{Username:"admin",Password:.}' < "$password" | curl -kfSs --max-time 5 -H 'Content-Type: application/json' --data-binary @- https://127.0.0.1:9443/api/auth -o /run/portainer-bootstrap/auth.json 2>/dev/null && jq -e '.jwt | strings | length > 0' /run/portainer-bootstrap/auth.json >/dev/null; then ready=1; break; fi
  sleep 2
done
rm -f /run/portainer-bootstrap/auth.json
[[ "$ready" == 1 ]] || { echo "Initial admin login failed"; exit 1; }
# Recreate without bootstrap arguments or secret mount.
docker compose -f compose.yaml up -d --force-recreate
rm -f "$password" /run/portainer-bootstrap/override.yaml
for ((i=0;i<60;i++)); do
  if curl -kfSs --max-time 3 https://127.0.0.1:9443/api/system/status >/dev/null 2>&1; then
    docker compose ps
    echo "Portainer v2 provisioning complete; initial admin verified"
    exit 0
  fi
  sleep 2
done
echo "Portainer readiness failed after recreation" >&2
exit 1
