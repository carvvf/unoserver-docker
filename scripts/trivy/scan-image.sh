#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REPO_TARGET="${REPO_TARGET:-${REPO_ROOT}}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-${REPO_ROOT}/Dockerfile}"
IMAGE_FILTER="${IMAGE_FILTER:-*unoserver-docker*}"
IMAGE_REF="${IMAGE_REF:-}"
SEVERITY="${SEVERITY:-MEDIUM,HIGH,CRITICAL}"
REPORTS_DIR="${REPORTS_DIR:-${REPO_ROOT}/reports/trivy}"
FS_SKIP_DIRS="${FS_SKIP_DIRS:-${REPORTS_DIR}}"

mkdir -p "${REPORTS_DIR}"
ts="$(date -u +%Y%m%d-%H%M%S)"
base="${REPORTS_DIR}/${ts}"

sanitize_label() {
  echo "${1//[^a-zA-Z0-9_.-]/_}"
}

merge_status() {
  local candidate="$1"

  if (( candidate > overall_status )); then
    overall_status="${candidate}"
  fi
}

run_scan() {
  local name="$1"
  local mode="$2"
  shift 2

  local text_report="${base}.${name}.txt"
  local json_report="${base}.${name}.json"
  local scan_status

  echo "[trivy-task] Running ${mode} scan for ${name}" >&2

  set +e
  trivy "${mode}" --severity "${SEVERITY}" --exit-code 1 "$@" | tee "${text_report}"
  scan_status=${PIPESTATUS[0]}
  set -e

  if ! trivy "${mode}" --severity "${SEVERITY}" --format json --output "${json_report}" "$@"; then
    echo "[trivy-task] JSON report generation failed for ${name} (gate status=${scan_status})" >&2
    return 2
  fi

  return "${scan_status}"
}

overall_status=0

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
  echo "[trivy-task] Dockerfile not found: ${DOCKERFILE_PATH}" >&2
  exit 2
fi

declare -a fs_skip_args=()
IFS=',' read -r -a raw_fs_skip_dirs <<< "${FS_SKIP_DIRS}"
for skip_dir in "${raw_fs_skip_dirs[@]}"; do
  if [[ -n "${skip_dir}" ]]; then
    fs_skip_args+=(--skip-dirs "${skip_dir}")
  fi
done

if run_scan "repo-fs" fs "${fs_skip_args[@]}" "${REPO_TARGET}"; then
  :
else
  merge_status "$?"
fi

if run_scan "dockerfile-config" config "${DOCKERFILE_PATH}"; then
  :
else
  merge_status "$?"
fi

declare -a image_refs=()

if [[ -n "${IMAGE_REF}" ]]; then
  image_refs=("${IMAGE_REF}")
else
  while IFS= read -r ref; do
    if [[ "${ref}" == ${IMAGE_FILTER} ]]; then
      image_refs+=("${ref}")
    fi
  done < <(docker image ls --format '{{.Repository}}:{{.Tag}}' | sort -u)
fi

if [[ ${#image_refs[@]} -eq 0 ]]; then
  echo "[trivy-task] No local images match filter: ${IMAGE_FILTER}" >&2
  exit 2
fi

for image in "${image_refs[@]}"; do
  label="image-$(sanitize_label "${image}")"
  if run_scan "${label}" image "${image}"; then
    :
  else
    merge_status "$?"
  fi
done

echo "[trivy-task] Reports generated under ${REPORTS_DIR}" >&2

exit "${overall_status}"
