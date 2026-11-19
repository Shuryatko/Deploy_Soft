#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
exec > >(tee -a /var/log/vm-provisioning.log) 2>&1
echo "Starting DbGate provisioning"
docker info >/dev/null
password_file=/run/dbgate-bootstrap/password
[[ -f "$password_file" ]] || { echo "Missing DbGate password"; exit 1; }
password=$(cat "$password_file")
[[ "$password" =~ ^[A-Za-z0-9_-]{16,128}$ && "$password" != REPLACE_WITH_* ]] || { echo "Use a unique DbGate password, 16-128 letters/digits/underscore/hyphen"; exit 1; }
install -d -m 0700 /opt/dbgate
cd /opt/dbgate
if [[ -e compose.yaml || -e .env ]] || docker container inspect dbgate >/dev/null 2>&1 || docker volume inspect dbgate_data >/dev/null 2>&1; then
  echo "Existing DbGate instance; refusing to overwrite"; exit 1
fi
printf 'DBGATE_PASSWORD=%s\n' "$password" > .env
unset password
cat > compose.yaml <<'EOF'
services:
  dbgate:
    image: dbgate/dbgate:7.3.6
    container_name: dbgate
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      LOGIN: admin
      PASSWORD: ${DBGATE_PASSWORD:?required}
      TZ: Europe/Kyiv
    volumes:
      - dbgate_data:/root/.dbgate
volumes:
  dbgate_data:
    name: dbgate_data
EOF
docker compose config --quiet
docker compose up -d
for ((i=0;i<60;i++)); do
  if [[ "$(docker inspect --format '{{.State.Status}}' dbgate)" == running ]] && curl -fsS --max-time 5 http://127.0.0.1:3000/ >/dev/null 2>&1; then
    rm -f "$password_file"
    docker compose ps
    echo "DbGate provisioning complete; verify login in browser"
    exit 0
  fi
  sleep 3
done
echo "DbGate readiness timed out" >&2
exit 1
