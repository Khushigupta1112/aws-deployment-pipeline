#!/usr/bin/env bash
# Manual rollback: restores the previously deployed image recorded by
# deploy.sh in .previous-image / .current-image state files.
# Run on the EC2 instance: /home/ec2-user/app/rollback.sh
set -euo pipefail

APP_DIR="${APP_DIR:-/home/ec2-user/app}"
CONTAINER_NAME="aws-deployment-demo"
HOST_PORT="${HOST_PORT:-80}"
CONTAINER_PORT="3000"

cd "${APP_DIR}"

PREVIOUS="$(cat .previous-image 2>/dev/null || true)"
CURRENT="$(cat .current-image 2>/dev/null || echo "none")"

if [[ -z "${PREVIOUS}" ]]; then
  echo "[rollback] no previous image recorded — nothing to roll back to." >&2
  exit 1
fi

echo "[rollback] rolling back ${CURRENT} -> ${PREVIOUS}"

docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  --restart unless-stopped \
  "${PREVIOUS}"

if ./health-check.sh "http://127.0.0.1:${CONTAINER_PORT}/health"; then
  # Swap the state files so a second rollback can go back forward.
  echo "${PREVIOUS}" > .current-image
  echo "${CURRENT}" > .previous-image
  echo "[rollback] SUCCESS — now serving ${PREVIOUS}"
  exit 0
fi

echo "[rollback] FAILED — rolled-back image did not pass the health check." >&2
exit 2
