#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

BENCH_VERSION="${BENCH_VERSION:-v1.6.0}"
BENCH_REPO_URL="${BENCH_REPO_URL:-https://github.com/docker/docker-bench-security.git}"
BENCH_IMAGE="${BENCH_IMAGE:-local/docker-bench-security:${BENCH_VERSION#v}}"
DOCKER_BENCH_ARGS="${DOCKER_BENCH_ARGS:-}"
REPORTS_ROOT="${REPORTS_ROOT:-${REPO_ROOT}/reports/docker-bench}"

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
RUN_DIR="${REPORTS_ROOT}/${TIMESTAMP}"
STDOUT_LOG="${RUN_DIR}/docker-bench.stdout.log"
SUMMARY_FILE="${RUN_DIR}/summary.txt"

log() {
  printf '[docker-bench] %s\n' "$*"
}

ensure_bench_image() {
  if docker image inspect "${BENCH_IMAGE}" >/dev/null 2>&1; then
    log "Using cached tool image: ${BENCH_IMAGE}"
    return
  fi

  log "Building tool image ${BENCH_IMAGE} from ${BENCH_REPO_URL}@${BENCH_VERSION}"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  git clone --depth 1 --branch "${BENCH_VERSION}" "${BENCH_REPO_URL}" "${tmpdir}/src"
  docker build -t "${BENCH_IMAGE}" "${tmpdir}/src"

  trap - RETURN
  rm -rf "${tmpdir}"
}

optional_mounts() {
  local path
  for path in /usr/bin/containerd /usr/bin/runc /usr/lib/systemd /lib/systemd/system; do
    if [[ -e "${path}" ]]; then
      printf '%s\n' "${path}:${path}:ro"
    fi
  done
}

mkdir -p "${RUN_DIR}"

ensure_bench_image

run_args=(
  --rm
  --net host
  --pid host
  --userns host
  --cap-add audit_control
  --label docker_bench_security
  -v /etc:/etc:ro
  -v /var/lib:/var/lib:ro
  -v /var/run/docker.sock:/var/run/docker.sock:ro
  -v "${RUN_DIR}:/report"
)

while IFS= read -r mount_arg; do
  run_args+=(-v "${mount_arg}")
done < <(optional_mounts)

if [[ -n "${DOCKER_CONTENT_TRUST:-}" ]]; then
  run_args+=(-e "DOCKER_CONTENT_TRUST=${DOCKER_CONTENT_TRUST}")
fi

bench_args=(-b -l /report/docker-bench-security.log)
if [[ -n "${DOCKER_BENCH_ARGS}" ]]; then
  read -r -a extra_bench_args <<< "${DOCKER_BENCH_ARGS}"
  bench_args+=("${extra_bench_args[@]}")
fi

log "Report directory: ${RUN_DIR}"
log "Running args: ${bench_args[*]}"

set +e
docker run "${run_args[@]}" "${BENCH_IMAGE}" "${bench_args[@]}" | tee "${STDOUT_LOG}"
bench_rc=${PIPESTATUS[0]}
set -e

pass_count="$(grep -c '^\[PASS\]' "${STDOUT_LOG}" || true)"
warn_count="$(grep -c '^\[WARN\]' "${STDOUT_LOG}" || true)"
info_count="$(grep -c '^\[INFO\]' "${STDOUT_LOG}" || true)"
note_count="$(grep -c '^\[NOTE\]' "${STDOUT_LOG}" || true)"

checks_line="$(grep -E '^\[INFO\] Checks:' "${STDOUT_LOG}" | tail -1 || true)"
score_line="$(grep -E '^\[INFO\] Score:' "${STDOUT_LOG}" | tail -1 || true)"

{
  echo "Docker Bench Security summary"
  echo "UTC timestamp: ${TIMESTAMP}"
  echo "Tool image: ${BENCH_IMAGE}"
  echo "Tool version ref: ${BENCH_VERSION}"
  echo "Args: ${bench_args[*]}"
  echo "Exit code: ${bench_rc}"
  echo
  echo "Counts from stdout log:"
  echo "  PASS: ${pass_count}"
  echo "  WARN: ${warn_count}"
  echo "  INFO: ${info_count}"
  echo "  NOTE: ${note_count}"
  if [[ -n "${checks_line}" ]]; then
    echo "  ${checks_line}"
  fi
  if [[ -n "${score_line}" ]]; then
    echo "  ${score_line}"
  fi
  echo
  echo "Files:"
  echo "  ${STDOUT_LOG}"
  echo "  ${RUN_DIR}/docker-bench-security.log"
  echo "  ${RUN_DIR}/docker-bench-security.log.json"
} | tee "${SUMMARY_FILE}"

log "Summary: ${SUMMARY_FILE}"
exit "${bench_rc}"
