#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${IMAGE_REF:-unoserver-docker:local}"
CONTAINER_NAME="${CONTAINER_NAME:-}"
PREFERRED_SHELL="${PREFERRED_SHELL:-/bin/bash}"

select_container() {
  if [[ -n "${CONTAINER_NAME}" ]]; then
    if docker ps --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
      printf '%s\n' "${CONTAINER_NAME}"
      return
    fi
    echo "[spawn-shell] Container not running: ${CONTAINER_NAME}" >&2
    exit 1
  fi

  mapfile -t matches < <(docker ps --filter "ancestor=${IMAGE_REF}" --format '{{.Names}}')

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "[spawn-shell] No running container found for image ${IMAGE_REF}" >&2
    exit 1
  fi

  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "[spawn-shell] Multiple running containers found for image ${IMAGE_REF}:" >&2
    printf '  - %s\n' "${matches[@]}" >&2
    echo "[spawn-shell] Set CONTAINER_NAME to choose one." >&2
    exit 2
  fi

  printf '%s\n' "${matches[0]}"
}

container="$(select_container)"

if docker exec "${container}" test -x "${PREFERRED_SHELL}" >/dev/null 2>&1; then
  shell_path="${PREFERRED_SHELL}"
elif docker exec "${container}" test -x /bin/sh >/dev/null 2>&1; then
  shell_path="/bin/sh"
else
  echo "[spawn-shell] No usable shell found in container ${container}" >&2
  exit 3
fi

echo "[spawn-shell] Attaching to ${container} using ${shell_path}"
exec docker exec -it "${container}" "${shell_path}"
