#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

IMAGE_REF="${IMAGE_REF:-unoserver-docker:local}"
SEVERITY="${SEVERITY:-MEDIUM,HIGH,CRITICAL}"
REPORTS_DIR="${REPORTS_DIR:-${REPO_ROOT}/reports/trivy}"

mkdir -p "${REPORTS_DIR}"
ts="$(date -u +%Y%m%d-%H%M%S)"
base="${REPORTS_DIR}/${ts}"

set +e
trivy image --severity "${SEVERITY}" --exit-code 1 "${IMAGE_REF}" | tee "${base}.txt"
trivy_status=${PIPESTATUS[0]}
set -e

if ! trivy image --severity "${SEVERITY}" --format json --output "${base}.json" "${IMAGE_REF}"; then
  echo "[trivy-task] JSON report generation failed (vulnerability gate status=${trivy_status})" >&2
  exit 2
fi

exit "${trivy_status}"
