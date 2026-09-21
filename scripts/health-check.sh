#!/usr/bin/env bash
# Retries a GET request until the endpoint answers 2xx or attempts run out.
# Exit 0 = healthy, non-zero = unhealthy. Used by deploy.sh and rollback.sh.
#
# Usage: ./health-check.sh <url>
# Env:   ATTEMPTS (default 15), INTERVAL seconds (default 2)
set -euo pipefail

URL="${1:?Usage: health-check.sh <url>}"
ATTEMPTS="${ATTEMPTS:-15}"
INTERVAL="${INTERVAL:-2}"

for i in $(seq 1 "${ATTEMPTS}"); do
  if response=$(curl -fsS --max-time 5 "${URL}" 2>/dev/null); then
    echo "[health] healthy on attempt ${i}/${ATTEMPTS}: ${response}"
    exit 0
  fi
  echo "[health] attempt ${i}/${ATTEMPTS}: not ready yet..."
  sleep "${INTERVAL}"
done

echo "[health] FAILED after ${ATTEMPTS} attempts: ${URL}" >&2
exit 1
