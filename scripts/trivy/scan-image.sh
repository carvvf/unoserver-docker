#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REPO_TARGET="${REPO_TARGET:-${REPO_ROOT}}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-${REPO_ROOT}/Dockerfile.custom}"
IMAGE_FILTER="${IMAGE_FILTER:-*unoserver-docker*}"
IMAGE_LABEL_SELECTOR="${IMAGE_LABEL_SELECTOR:-org.opencontainers.image.title=unoserver-docker}"
IMAGE_REF="${IMAGE_REF:-}"
SEVERITY="${SEVERITY:-UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL}"
FAIL_SEVERITY="${FAIL_SEVERITY:-HIGH,CRITICAL}"
REPORTS_DIR="${REPORTS_DIR:-${REPO_ROOT}/reports/trivy}"
FS_SKIP_DIRS="${FS_SKIP_DIRS:-${REPORTS_DIR}}"
TRIVY_CLEAN_ARGS="${TRIVY_CLEAN_ARGS:---scan-cache}"

mkdir -p "${REPORTS_DIR}"
ts="$(date -u +%Y%m%d-%H%M%S)"
base="${REPORTS_DIR}/${ts}"

sanitize_label() {
  echo "${1//[^a-zA-Z0-9_.-]/_}"
}

is_tagged_image_ref() {
  local ref="$1"
  [[ "${ref}" == *:* && "${ref}" != sha256:* && "${ref}" != *@sha256:* ]]
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
  local scan_status=0

  echo "[trivy-task] Running ${mode} scan for ${name}" >&2

  if ! trivy "${mode}" --severity "${SEVERITY}" "$@" | tee "${text_report}"; then
    echo "[trivy-task] Text report generation failed for ${name}" >&2
    return 2
  fi

  if ! trivy "${mode}" --severity "${SEVERITY}" --format json --output "${json_report}" "$@"; then
    echo "[trivy-task] JSON report generation failed for ${name}" >&2
    return 2
  fi

  set +e
  trivy "${mode}" --severity "${FAIL_SEVERITY}" --exit-code 1 --quiet "$@" >/dev/null
  scan_status=$?
  set -e

  return "${scan_status}"
}

overall_status=0

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
  echo "[trivy-task] Dockerfile not found: ${DOCKERFILE_PATH}" >&2
  exit 2
fi

echo "[trivy-task] Cleaning Trivy cache (${TRIVY_CLEAN_ARGS})" >&2
declare -a trivy_clean_args=()
IFS=' ' read -r -a trivy_clean_args <<< "${TRIVY_CLEAN_ARGS}"
if ! trivy clean "${trivy_clean_args[@]}"; then
  echo "[trivy-task] Cache cleanup failed" >&2
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
declare -a discovered_image_refs=()

if [[ -n "${IMAGE_REF}" ]]; then
  image_refs=("${IMAGE_REF}")
else
  if [[ -n "${IMAGE_LABEL_SELECTOR}" ]]; then
    while IFS= read -r image_id; do
      if [[ -n "${image_id}" ]]; then
        discovered_image_refs+=("${image_id}")
      fi
    done < <(docker image ls --filter "label=${IMAGE_LABEL_SELECTOR}" --format '{{.ID}}' | sort -u)
  fi

  if [[ -n "${IMAGE_FILTER}" ]]; then
    while IFS= read -r ref; do
      if [[ "${ref}" == ${IMAGE_FILTER} ]] && [[ "${ref}" != "<none>:<none>" ]]; then
        discovered_image_refs+=("${ref}")
      fi
    done < <(docker image ls --format '{{.Repository}}:{{.Tag}}' | sort -u)
  fi

  if [[ ${#discovered_image_refs[@]} -gt 0 ]]; then
    declare -A image_id_to_ref=()
    declare -a ordered_image_ids=()

    for candidate in "${discovered_image_refs[@]}"; do
      [[ -z "${candidate}" ]] && continue

      resolved_id="$(docker image inspect --format '{{.Id}}' "${candidate}" 2>/dev/null || true)"
      [[ -z "${resolved_id}" ]] && continue

      if [[ -z "${image_id_to_ref["${resolved_id}"]+x}" ]]; then
        image_id_to_ref["${resolved_id}"]="${candidate}"
        ordered_image_ids+=("${resolved_id}")
        continue
      fi

      existing_ref="${image_id_to_ref["${resolved_id}"]}"
      if is_tagged_image_ref "${candidate}" && ! is_tagged_image_ref "${existing_ref}"; then
        image_id_to_ref["${resolved_id}"]="${candidate}"
      fi
    done

    for resolved_id in "${ordered_image_ids[@]}"; do
      image_refs+=("${image_id_to_ref["${resolved_id}"]}")
    done
  fi
fi

if [[ ${#image_refs[@]} -eq 0 ]]; then
  echo "[trivy-task] No local images match selectors: IMAGE_LABEL_SELECTOR='${IMAGE_LABEL_SELECTOR}', IMAGE_FILTER='${IMAGE_FILTER}'" >&2
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
