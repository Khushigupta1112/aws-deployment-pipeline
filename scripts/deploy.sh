#!/usr/bin/env bash
# Runs ON the EC2 instance (uploaded by the CI workflow on every deploy).
# Pulls the exact image tag produced by CI, replaces the running container,
# verifies health, and rolls back to the previous version on failure.
#
# Usage (from /home/ec2-user/app): ./deploy.sh <image-tag>
# Required env: AWS_REGION, ECR_REGISTRY, ECR_REPOSITORY
set -euo pipefail

IMAGE_TAG="${1:?Usage: deploy.sh <image-tag>}"
AWS_REGION="${AWS_REGION:?AWS_REGION must be set}"
ECR_REGISTRY="${ECR_REGISTRY:?ECR_REGISTRY must be set}"
ECR_REPOSITORY="${ECR_REPOSITORY:?ECR_REPOSITORY must be set}"

APP_DIR="${APP_DIR:-/home/ec2-user/app}"
CONTAINER_NAME="aws-deployment-demo"
HOST_PORT="${HOST_PORT:-80}"
CONTAINER_PORT="3000"
HEALTH_URL="http://127.0.0.1:${CONTAINER_PORT}/health"

FULL_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
CURRENT_FILE="${APP_DIR}/.current-image"
PREVIOUS_FILE="${APP_DIR}/.previous-image"

log() { echo "[deploy] $(date -u +%FT%TZ) $*"; }

cd "${APP_DIR}"

# Remember what is currently running so we can roll back if needed.
PREVIOUS=""
if [[ -f "${CURRENT_FILE}" ]]; then
  PREVIOUS="$(cat "${CURRENT_FILE}")"
fi

log "Deploying image: ${FULL_IMAGE} (previous: ${PREVIOUS:-none})"

# 1. Authenticate to ECR using the instance role — no stored credentials.
log "Authenticating to ECR registry ${ECR_REGISTRY}"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# 2. Pull the exact version CI built.
log "Pulling ${FULL_IMAGE}"
docker pull "${FULL_IMAGE}"

# 3. Stop and remove the previous container (brief downtime window — this is
#    NOT a zero-downtime strategy; see README "Rollback" and "Not implemented").
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  log "Stopping and removing previous container ${CONTAINER_NAME}"
  docker stop "${CONTAINER_NAME}" || true
  docker rm "${CONTAINER_NAME}" || true
fi

# 4. Start the new container.
log "Starting ${FULL_IMAGE} on host port ${HOST_PORT}"
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  --restart unless-stopped \
  "${FULL_IMAGE}"

# 5. Verify the new container is actually serving.
if ./health-check.sh "${HEALTH_URL}"; then
  log "Health check PASSED"
  echo "${PREVIOUS}" > "${PREVIOUS_FILE}"
  echo "${FULL_IMAGE}" > "${CURRENT_FILE}"
  # Clean up dangling layers only; tagged images (incl. previous) are kept
  # so manual rollback remains possible.
  docker image prune -f >/dev/null 2>&1 || true
  log "Deployment SUCCESS: ${FULL_IMAGE}"
  exit 0
fi

# 6. Health check failed — surface logs, stop the bad container.
log "Health check FAILED for ${FULL_IMAGE}, container logs (tail):"
docker logs --tail 50 "${CONTAINER_NAME}" 2>&1 || true

docker stop "${CONTAINER_NAME}" || true
docker rm "${CONTAINER_NAME}" || true

# 7. Attempt automatic rollback to the previously deployed image.
if [[ -n "${PREVIOUS}" && "${PREVIOUS}" != "${FULL_IMAGE}" ]]; then
  log "Attempting rollback to previous image: ${PREVIOUS}"
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    --restart unless-stopped \
    "${PREVIOUS}"
  if ./health-check.sh "${HEALTH_URL}"; then
    echo "${PREVIOUS}" > "${CURRENT_FILE}"
    log "Rollback SUCCESS — previous version is serving again."
  else
    log "Rollback FAILED — previous image did not come up healthy either."
    exit 2
  fi
else
  log "No previous image available to roll back to (first deployment?)."
fi

log "Deployment FAILED — new image did not pass the health check."
exit 1
