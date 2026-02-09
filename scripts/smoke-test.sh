#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-unoserver-docker:local}"
NETWORK_NAME="unoserver-smoke-net"
SERVER_NAME="unoserver-smoke-server"
WORK_DIR="$(mktemp -d)"

cleanup() {
  docker rm -f "${SERVER_NAME}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "[smoke] Building image ${IMAGE_TAG}..."
docker build -t "${IMAGE_TAG}" .

chmod 0777 "${WORK_DIR}"
cat > "${WORK_DIR}/input.txt" <<'TXT'
unoserver-docker smoke test
TXT

echo "[smoke] Creating network ${NETWORK_NAME}..."
docker network create "${NETWORK_NAME}" >/dev/null

echo "[smoke] Starting unoserver container ${SERVER_NAME}..."
docker run -d --rm --name "${SERVER_NAME}" --network "${NETWORK_NAME}" "${IMAGE_TAG}" >/dev/null

echo "[smoke] Converting /data/input.txt -> /data/output.pdf..."
converted=0
for i in $(seq 1 30); do
  if docker run --rm \
    --network "${NETWORK_NAME}" \
    -v "${WORK_DIR}:/data" \
    --entrypoint unoconvert \
    "${IMAGE_TAG}" \
    --host "${SERVER_NAME}" \
    --port 2003 \
    --host-location remote \
    /data/input.txt /data/output.pdf >/dev/null 2>&1; then
    converted=1
    break
  fi
  sleep 1
done

if [[ "${converted}" -ne 1 ]]; then
  echo "[smoke] Conversion failed after retries. Container logs:" >&2
  docker logs "${SERVER_NAME}" >&2 || true
  exit 1
fi

if [[ ! -s "${WORK_DIR}/output.pdf" ]]; then
  echo "[smoke] output.pdf missing or empty." >&2
  exit 1
fi

if [[ "$(head -c 4 "${WORK_DIR}/output.pdf")" != "%PDF" ]]; then
  echo "[smoke] output.pdf is not a valid PDF header." >&2
  exit 1
fi

echo "[smoke] OK: output.pdf generated and valid (${WORK_DIR}/output.pdf)."
