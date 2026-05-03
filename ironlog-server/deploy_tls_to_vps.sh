#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="${IRONLOG_DEPLOY_SERVER:-root@89.110.84.41}"
REMOTE_DIR="${IRONLOG_DEPLOY_DIR:-/opt/ironlog}"
CONTROL_PATH="${TMPDIR:-/tmp}/ironlog-deploy-%r@%h:%p"
SSH_OPTS=(
  -o ControlMaster=auto
  -o ControlPersist=5m
  -o ControlPath="${CONTROL_PATH}"
)
RSYNC_SSH="ssh -o ControlMaster=auto -o ControlPersist=5m -o ControlPath=${CONTROL_PATH}"

echo "Deploying IronLog API TLS stack to ${SERVER}:${REMOTE_DIR}"

ssh "${SSH_OPTS[@]}" "${SERVER}" "mkdir -p '${REMOTE_DIR}/schemas' '${REMOTE_DIR}/docs' '${REMOTE_DIR}/deploy-backups'"
ssh "${SSH_OPTS[@]}" "${SERVER}" "cd '${REMOTE_DIR}' && tar --exclude='./deploy-backups' -czf 'deploy-backups/pre-deploy-$(date +%Y%m%d-%H%M%S).tgz' . || true"

rsync -az --delete -e "${RSYNC_SSH}" \
  "${ROOT_DIR}/ironlog-server/app" \
  "${ROOT_DIR}/ironlog-server/tools" \
  "${ROOT_DIR}/ironlog-server/Dockerfile" \
  "${ROOT_DIR}/ironlog-server/requirements.txt" \
  "${ROOT_DIR}/ironlog-server/docker-compose.yml" \
  "${ROOT_DIR}/ironlog-server/Caddyfile" \
  "${SERVER}:${REMOTE_DIR}/"

rsync -az --delete -e "${RSYNC_SSH}" \
  "${ROOT_DIR}/schemas/" \
  "${SERVER}:${REMOTE_DIR}/schemas/"

rsync -az --delete -e "${RSYNC_SSH}" \
  "${ROOT_DIR}/docs/" \
  "${SERVER}:${REMOTE_DIR}/docs/"

ssh "${SSH_OPTS[@]}" "${SERVER}" "cd '${REMOTE_DIR}' && touch .env && \
  grep -q '^IRONLOG_DOMAIN=' .env || printf '\nIRONLOG_DOMAIN=v170184.hosted-by-vdsina.com\n' >> .env && \
  grep -q '^IRONLOG_SCHEMAS_DIR=' .env || printf '\nIRONLOG_SCHEMAS_DIR=./schemas\n' >> .env && \
  grep -q '^IRONLOG_DOCS_DIR=' .env || printf '\nIRONLOG_DOCS_DIR=./docs\n' >> .env && \
  (ufw allow 443/tcp || true) && \
  docker compose config >/dev/null && \
  docker compose up --build -d && \
  docker compose ps && \
  docker compose logs --tail=120 caddy"

echo
echo "Deployed. Check:"
echo "  https://v170184.hosted-by-vdsina.com/health"
echo "  https://v170184.hosted-by-vdsina.com/docs"
echo "  https://v170184.hosted-by-vdsina.com/agent-instructions/plan-import"
