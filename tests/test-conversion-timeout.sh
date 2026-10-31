#!/usr/bin/env bash
# Checks what the service does when a conversion hangs: past the timeout the container exits,
# so that its restart policy brings up a clean one.
#
# entrypoint.sh recognizes the timeout from a line unoserver logs, and the image takes the
# newest unoserver of its major version on each build. If a release changes that line, the
# service would stay up and report healthy while unable to convert, and only this test notices.
#
# Starts its own throwaway container, with no network. LibreOffice is suspended to make the
# hang certain: how long a real document takes is not something a test can rely on.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_REF="${IMAGE_REF:-unoserver-docker:local}"
FIXTURE="${FIXTURE:-${REPO_ROOT}/fixtures/office/sample.docx}"
CONVERSION_TIMEOUT_S=3
START_TIMEOUT_S=120
EXIT_TIMEOUT_S=30
CONTAINER="unoserver-timeout-test-$$"

CONVERT='
import sys
import xmlrpc.client

payload = xmlrpc.client.Binary(sys.stdin.buffer.read())
result = xmlrpc.client.ServerProxy("http://127.0.0.1:2003", allow_none=True).convert(
    None, payload, None, "pdf"
)
sys.exit(0 if bytes(result.data[:4]) == b"%PDF" else 1)
'

fail() {
  echo "[timeout-test] FAIL: $*" >&2
  echo "[timeout-test] Last container logs:" >&2
  docker logs --tail 20 "${CONTAINER}" >&2 2>&1 || true
  exit 1
}

cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

state() {
  docker inspect -f '{{.State.Status}}' "${CONTAINER}"
}

docker run -d --name "${CONTAINER}" --network none \
  --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges:true \
  -e HOME=/tmp -e UNOSERVER_CONVERSION_TIMEOUT="${CONVERSION_TIMEOUT_S}" \
  "${IMAGE_REF}" >/dev/null

deadline=$((SECONDS + START_TIMEOUT_S))
until docker logs "${CONTAINER}" 2>&1 | grep -q 'Started\.'; do
  [[ "$(state)" == "running" ]] || fail "the service did not start."
  ((SECONDS < deadline)) || fail "the service did not start within ${START_TIMEOUT_S}s."
  sleep 1
done

# The timeout must not touch a conversion that finishes in time.
docker exec -i "${CONTAINER}" python3 -c "${CONVERT}" < "${FIXTURE}" \
  || fail "a normal conversion failed."
[[ "$(state)" == "running" ]] || fail "the service exited after a normal conversion."
echo "[timeout-test] A normal conversion succeeds and the service stays up." >&2

soffice_pid="$(docker exec "${CONTAINER}" pgrep -f '/program/soffice\.bin' | head -n 1)"
[[ -n "${soffice_pid}" ]] || fail "soffice.bin was not found."
docker exec "${CONTAINER}" kill -STOP "${soffice_pid}"

# Never answered: the point is what happens to the service while this waits.
docker exec -i "${CONTAINER}" python3 -c "${CONVERT}" < "${FIXTURE}" >/dev/null 2>&1 &
client_pid=$!

deadline=$((SECONDS + EXIT_TIMEOUT_S))
while [[ "$(state)" == "running" ]]; do
  if ((SECONDS >= deadline)); then
    kill "${client_pid}" 2>/dev/null || true
    fail "the service was still up ${EXIT_TIMEOUT_S}s after a conversion hung."
  fi
  sleep 1
done
wait "${client_pid}" 2>/dev/null || true

exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${CONTAINER}")"
[[ "${exit_code}" == "1" ]] || fail "the service exited with status ${exit_code}, not 1."
docker logs "${CONTAINER}" 2>&1 | grep -q 'exiting so that the service restarts' \
  || fail "the service exited for another reason than the conversion timeout."

echo "[timeout-test] PASS: a hung conversion makes the service exit with status 1." >&2
