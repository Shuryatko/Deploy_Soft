#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
exec > >(tee -a /var/log/vm-provisioning.log) 2>&1
echo "Starting Appsmith provisioning"
docker info >/dev/null
install -d -m 0750 /opt/appsmith
cd /opt/appsmith
if [[ -e compose.yaml || -e stacks ]] || docker container inspect appsmith >/dev/null 2>&1; then
  echo "Existing Appsmith instance; refusing to overwrite"; exit 1
fi
install -d -m 0750 stacks
cat > compose.yaml <<'EOF'
services:
  appsmith:
    image: appsmith/appsmith-ce:v2.7.0
    container_name: appsmith
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./stacks:/appsmith-stacks
EOF
docker compose config --quiet
docker compose up -d
for ((i=0;i<120;i++)); do
  state=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' appsmith)
  if [[ "$state" == "running healthy" ]] && curl -fsS --max-time 5 http://127.0.0.1:8080/ >/dev/null 2>&1; then
    docker compose ps
    echo "Appsmith provisioning complete"
    exit 0
  fi
  sleep 5
done
echo "Appsmith readiness timed out; inspect docker logs appsmith locally" >&2
exit 1
