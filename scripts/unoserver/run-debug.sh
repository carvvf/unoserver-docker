#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${IMAGE_REF:-unoserver-docker:local}"
CONTAINER_NAME="${CONTAINER_NAME:-unoserver-docker-debug}"
HOST_BIND_ADDRESS="${HOST_BIND_ADDRESS:-127.0.0.1}"
HOST_PORT="${HOST_PORT:-2003}"
CONTAINER_PORT="${CONTAINER_PORT:-2003}"
DOCKER_NETWORK="${DOCKER_NETWORK:-bridge}"
CPU_LIMIT="${CPU_LIMIT:-2}"
MEMORY_LIMIT="${MEMORY_LIMIT:-1g}"
PIDS_LIMIT="${PIDS_LIMIT:-128}"
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

check_network_exists() {
  if ! docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1; then
    echo "[run-debug] Docker network not found: ${DOCKER_NETWORK}" >&2
    echo "[run-debug] Create it first or set DOCKER_NETWORK to an existing network." >&2
    exit 2
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
check_network_exists

echo "[run-debug] Starting ${CONTAINER_NAME} from ${IMAGE_REF}"
echo "[run-debug] Network: ${DOCKER_NETWORK}"
echo "[run-debug] Bind: ${HOST_BIND_ADDRESS}:${HOST_PORT}->${CONTAINER_PORT}/tcp"
echo "[run-debug] Limits: cpus=${CPU_LIMIT}, memory=${MEMORY_LIMIT}, pids=${PIDS_LIMIT}"
echo "[run-debug] Press Ctrl+C to stop and remove the container cleanly."

docker run \
  --name "${CONTAINER_NAME}" \
  --rm \
  --network "${DOCKER_NETWORK}" \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --read-only \
  --tmpfs /data \
  --tmpfs /tmp \
  --cpus "${CPU_LIMIT}" \
  --memory "${MEMORY_LIMIT}" \
  --pids-limit "${PIDS_LIMIT}" \
  -e HOME=/tmp \
  -p "${HOST_BIND_ADDRESS}:${HOST_PORT}:${CONTAINER_PORT}" \
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
