#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
exec > >(tee -a /var/log/vm-provisioning.log) 2>&1
echo "Starting Edge Agent provisioning"
docker info >/dev/null
[[ $(id -u) == 0 ]] || exit 1
config=/run/portainer-edge/enrollment
[[ -f "$config" ]] || { echo "Missing enrollment file"; exit 1; }
# Parse data, never source credentials as shell code.
mapfile -t fields < "$config"
[[ ${#fields[@]} == 2 ]] || { echo "Expected two enrollment lines"; exit 1; }
edge_id=${fields[0]}
edge_key=${fields[1]}
[[ "$edge_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || { echo "Invalid EDGE_ID"; exit 1; }
[[ "$edge_key" =~ ^[A-Za-z0-9+/=_-]+$ && ${#edge_key} -gt 32 ]] || { echo "Invalid EDGE_KEY"; exit 1; }
if docker container inspect portainer_edge_agent >/dev/null 2>&1 || docker volume inspect portainer_agent_data >/dev/null 2>&1; then
  echo "Existing agent or state volume; refusing to overwrite"; exit 1
fi
install -d -m 0700 /opt/portainer-edge-agent
cd /opt/portainer-edge-agent
[[ ! -e compose.yaml && ! -e .env ]] || { echo "Existing agent configuration; refusing to overwrite"; exit 1; }
printf 'EDGE_ID=%s\nEDGE_KEY=%s\n' "$edge_id" "$edge_key" > .env
unset edge_key edge_id fields
cat > compose.yaml <<'EOF'
services:
  agent:
    image: portainer/agent:2.45.3
    container_name: portainer_edge_agent
    restart: always
    environment:
      EDGE: "1"
      EDGE_ID: ${EDGE_ID:?required}
      EDGE_KEY: ${EDGE_KEY:?required}
      EDGE_INSECURE_POLL: "1"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - /:/host
      - portainer_agent_data:/data
volumes:
  portainer_agent_data:
    name: portainer_agent_data
EOF
# Do not print resolved configuration: it contains enrollment credentials.
docker compose config --quiet
docker compose up -d
sleep 5
[[ "$(docker inspect --format '{{.State.Status}}' portainer_edge_agent)" == running ]] || { echo "Agent not running"; exit 1; }
rm -f "$config"
docker compose ps
echo "Edge Agent container started; verify enrollment in Portainer UI"
