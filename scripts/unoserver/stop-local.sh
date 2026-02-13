#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-unoserver-docker-debug}"

if docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "[stop-local] Stopped and removed ${CONTAINER_NAME}"
else
  echo "[stop-local] No container named ${CONTAINER_NAME} is running."
fi
