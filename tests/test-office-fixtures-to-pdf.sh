#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONTAINER_NAME="${CONTAINER_NAME:-unoserver-docker-debug}"
CONTAINER_PORT="${CONTAINER_PORT:-2003}"
API_PROTOCOL="${API_PROTOCOL:-http}"
FIXTURES_DIR="${FIXTURES_DIR:-${REPO_ROOT}/fixtures/office}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/tests/out}"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
REPORT_FILE="${OUT_DIR}/conversion-${TIMESTAMP}.report.txt"

SUPPORTED_REGEX='\.(doc|docx|xls|xlsx|ppt|pptx|odt|ods|odp)$'

mkdir -p "${OUT_DIR}"

if [[ ! -d "${FIXTURES_DIR}" ]]; then
  echo "[tests] Fixtures directory not found: ${FIXTURES_DIR}" >&2
  exit 4
fi

if ! docker ps --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
  echo "[tests] Required running container not found: ${CONTAINER_NAME}" >&2
  echo "[tests] Start it first (e.g. VS Code task: debug: run unoserver-docker)." >&2
  echo "[tests] This test does not start or modify containers; it only validates a live endpoint." >&2
  exit 5
fi

mapfile -t PORT_BINDINGS < <(docker port "${CONTAINER_NAME}" "${CONTAINER_PORT}/tcp" 2>/dev/null || true)
if [[ ${#PORT_BINDINGS[@]} -eq 0 ]]; then
  echo "[tests] Container ${CONTAINER_NAME} is running but port ${CONTAINER_PORT}/tcp is not published." >&2
  echo "[tests] Start the container with an explicit port mapping (e.g. -p 2003:2003)." >&2
  exit 6
fi

PORT_MAPPING="${PORT_BINDINGS[0]}"
if [[ ! "${PORT_MAPPING}" =~ :([0-9]+)$ ]]; then
  echo "[tests] Unable to parse published port mapping: ${PORT_MAPPING}" >&2
  exit 6
fi

ENDPOINT_PORT="${BASH_REMATCH[1]}"
ENDPOINT_HOST="${PORT_MAPPING%:*}"
ENDPOINT_HOST="${ENDPOINT_HOST#[}"
ENDPOINT_HOST="${ENDPOINT_HOST%]}"
if [[ "${ENDPOINT_HOST}" == "0.0.0.0" || "${ENDPOINT_HOST}" == "::" || -z "${ENDPOINT_HOST}" ]]; then
  ENDPOINT_HOST="127.0.0.1"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[tests] python3 is required on the host to execute API-based conversion tests." >&2
  exit 7
fi

ABS_FIXTURES_DIR="$(realpath "${FIXTURES_DIR}")"
ABS_OUT_DIR="$(realpath "${OUT_DIR}")"

mapfile -t FILES < <(find "${ABS_FIXTURES_DIR}" -maxdepth 1 -type f | sort)

total=0
supported=0
passed=0
failed=0
skipped=0

{
  echo "Office fixture conversion report"
  echo "UTC timestamp: ${TIMESTAMP}"
  echo "Target container: ${CONTAINER_NAME}"
  echo "Endpoint: ${API_PROTOCOL}://${ENDPOINT_HOST}:${ENDPOINT_PORT}"
  echo "Transfer mode: remote binary upload/download (stdin/stdout)"
  echo "Client mode: host-python-xmlrpc"
  echo "Fixtures: ${ABS_FIXTURES_DIR}"
  echo "Output: ${ABS_OUT_DIR}"
  echo
} > "${REPORT_FILE}"

for file_path in "${FILES[@]}"; do
  file_name="$(basename "${file_path}")"
  lower_name="$(printf '%s' "${file_name}" | tr '[:upper:]' '[:lower:]')"
  total=$((total + 1))

  if [[ ! "${lower_name}" =~ ${SUPPORTED_REGEX} ]]; then
    skipped=$((skipped + 1))
    echo "[SKIP] ${file_name} (unsupported extension)" | tee -a "${REPORT_FILE}" >/dev/null
    continue
  fi

  supported=$((supported + 1))
  tmp_pdf="${ABS_OUT_DIR}/${file_name}.tmp.pdf"
  final_pdf="${ABS_OUT_DIR}/${file_name}.pdf"
  conversion_log="$(mktemp)"
  rm -f "${tmp_pdf}" "${final_pdf}"

  set +e
  python3 - "${API_PROTOCOL}" "${ENDPOINT_HOST}" "${ENDPOINT_PORT}" "${file_path}" "${tmp_pdf}" > /dev/null 2> "${conversion_log}" <<'PY'
import sys
import xmlrpc.client

protocol, host, port, in_path, out_path = sys.argv[1:]
url = f"{protocol}://{host}:{port}"

with open(in_path, "rb") as in_fh:
    payload = in_fh.read()

proxy = xmlrpc.client.ServerProxy(url, allow_none=True)
info = proxy.info()
result = proxy.convert(
    None,
    xmlrpc.client.Binary(payload),
    None,
    "pdf",
    None,
    [],
    True,
    None,
)

if result is None:
    raise RuntimeError("The endpoint returned no PDF payload.")

with open(out_path, "wb") as out_fh:
    out_fh.write(result.data)

print(f"Connected to API version: {info.get('api', 'unknown')}", file=sys.stderr)
print(f"Received bytes: {len(result.data)}", file=sys.stderr)
PY
  rc=$?
  set -e
  conversion_output="$(cat "${conversion_log}")"
  rm -f "${conversion_log}"

  if [[ ${rc} -eq 0 && -s "${tmp_pdf}" ]]; then
    mv "${tmp_pdf}" "${final_pdf}"
    if [[ "$(head -c 4 "${final_pdf}")" == "%PDF" ]]; then
      passed=$((passed + 1))
      {
        echo "[PASS] ${file_name} -> $(basename "${final_pdf}")"
        [[ -n "${conversion_output}" ]] && printf '%s\n' "${conversion_output}" | sed 's/^/  /'
        echo
      } >> "${REPORT_FILE}"
      continue
    fi
    rm -f "${final_pdf}"
    failed=$((failed + 1))
    {
      echo "[FAIL] ${file_name} (invalid PDF header)"
      [[ -n "${conversion_output}" ]] && printf '%s\n' "${conversion_output}" | sed 's/^/  /'
      echo
    } >> "${REPORT_FILE}"
    continue
  fi

  rm -f "${tmp_pdf}" "${final_pdf}"
  failed=$((failed + 1))
  {
    echo "[FAIL] ${file_name} (converter exit code: ${rc})"
    [[ -n "${conversion_output}" ]] && printf '%s\n' "${conversion_output}" | sed 's/^/  /'
    echo
  } >> "${REPORT_FILE}"
done

{
  echo "Summary:"
  echo "  Total files scanned: ${total}"
  echo "  Supported fixtures: ${supported}"
  echo "  Passed conversions: ${passed}"
  echo "  Failed conversions: ${failed}"
  echo "  Skipped files: ${skipped}"
} | tee -a "${REPORT_FILE}"

echo "[tests] Report: ${REPORT_FILE}"
echo "[tests] Output directory: ${ABS_OUT_DIR}"

if [[ ${failed} -gt 0 ]]; then
  exit 1
fi
