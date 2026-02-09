#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${IMAGE_REF:-unoserver-docker:local}"
CONTAINER_NAME="${CONTAINER_NAME:-unoserver-docker-debug}"
HOST_PORT="${HOST_PORT:-2003}"
CONTAINER_PORT="${CONTAINER_PORT:-2003}"
INTERRUPTED=0
DOCKER_PID=""

check_already_running() {
  if docker ps --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
    echo "[run-debug] Container already running: ${CONTAINER_NAME}" >&2
    echo "[run-debug] Use the task 'debug: spawn a shell' or stop it first." >&2
    exit 1
  fi

  mapfile -t running_from_image < <(docker ps --filter "ancestor=${IMAGE_REF}" --format '{{.Names}}')
  if [[ ${#running_from_image[@]} -gt 0 ]]; then
    echo "[run-debug] A container from ${IMAGE_REF} is already running:" >&2
    printf '  - %s\n' "${running_from_image[@]}" >&2
    echo "[run-debug] Stop it before starting another debug run." >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "${DOCKER_PID}" ]] && kill -0 "${DOCKER_PID}" >/dev/null 2>&1; then
    kill "${DOCKER_PID}" >/dev/null 2>&1 || true
  fi
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}

on_signal() {
  INTERRUPTED=1
  cleanup
}

trap cleanup EXIT
trap on_signal INT TERM HUP

check_already_running

echo "[run-debug] Starting ${CONTAINER_NAME} from ${IMAGE_REF}"
echo "[run-debug] Press Ctrl+C to stop and remove the container cleanly."

docker run \
  --name "${CONTAINER_NAME}" \
  --rm \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /data \
  --tmpfs /tmp \
  -e HOME=/tmp \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  "${IMAGE_REF}" &

DOCKER_PID=$!

set +e
wait "${DOCKER_PID}"
rc=$?
set -e

if [[ "${INTERRUPTED}" -eq 1 ]]; then
  exit 130
fi

exit "${rc}"
