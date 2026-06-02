#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PROFILE_NAME="${APPARMOR_PROFILE:-docker-unoserver}"
PROFILE_SOURCE="${APPARMOR_PROFILE_SOURCE:-${REPO_ROOT}/security/apparmor/${PROFILE_NAME}}"
APPARMOR_DIR="${APPARMOR_DIR:-/etc/apparmor.d}"
PROFILE_DEST="${APPARMOR_PROFILE_DEST:-${APPARMOR_DIR}/${PROFILE_NAME}}"
DISABLE_DIR="${APPARMOR_DISABLE_DIR:-${APPARMOR_DIR}/disable}"

log() {
  printf '[apparmor] %s\n' "$*"
}

die() {
  printf '[apparmor] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $0 <enable|disable|reload|remove|status|check|run-opts>

Environment:
  APPARMOR_PROFILE        Profile name. Default: docker-unoserver
  APPARMOR_PROFILE_SOURCE Source profile path.
                           Default: ${REPO_ROOT}/security/apparmor/\${APPARMOR_PROFILE}
  APPARMOR_DIR            Host AppArmor profile directory. Default: /etc/apparmor.d

Actions:
  enable    Install the repository profile and load it in enforce mode.
  disable   Unload the profile and mark it disabled under /etc/apparmor.d/disable.
  reload    Replace the loaded profile from the installed destination.
  remove    Disable the profile and remove the installed host copy.
  status    Show whether the profile is loaded and where it is installed.
  check     Parse the source profile without loading it into the kernel.
  run-opts  Print the Docker flag needed to use the profile.
EOF
}

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "This action requires root privileges and sudo is not available."
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_profile_source() {
  [[ -f "${PROFILE_SOURCE}" ]] || die "Profile source not found: ${PROFILE_SOURCE}"
}

check_apparmor_available() {
  if [[ -r /sys/module/apparmor/parameters/enabled ]]; then
    if ! grep -qi '^Y' /sys/module/apparmor/parameters/enabled; then
      die "AppArmor kernel module is present but not enabled."
    fi
  elif [[ ! -d /sys/kernel/security/apparmor ]]; then
    die "AppArmor does not appear to be available on this host."
  fi
}

check_profile() {
  require_command apparmor_parser
  require_profile_source
  apparmor_parser -Q -T -K "${PROFILE_SOURCE}"
  log "Profile syntax is valid: ${PROFILE_SOURCE}"
}

profile_loaded() {
  local profiles_file="/sys/kernel/security/apparmor/profiles"
  local status_output
  local status_rc=0

  if [[ -e "${profiles_file}" ]] \
    && { grep -Fxq "${PROFILE_NAME} (enforce)" "${profiles_file}" 2>/dev/null \
      || grep -Fxq "${PROFILE_NAME} (complain)" "${profiles_file}" 2>/dev/null; }; then
    return 0
  fi

  if [[ -e "${profiles_file}" ]] && ! head -n 1 "${profiles_file}" >/dev/null 2>&1; then
    return 2
  fi

  if command -v apparmor_status >/dev/null 2>&1; then
    status_output="$(apparmor_status 2>&1)" || status_rc=$?
    if grep -Fxq "   ${PROFILE_NAME}" <<< "${status_output}"; then
      return 0
    fi
    if [[ "${status_rc}" -ne 0 ]] && grep -Fqi 'not have enough privilege' <<< "${status_output}"; then
      return 2
    fi
  fi

  return 1
}

enable_profile() {
  require_command apparmor_parser
  require_profile_source
  check_apparmor_available

  as_root install -d -m 0755 "${APPARMOR_DIR}"
  as_root install -m 0644 "${PROFILE_SOURCE}" "${PROFILE_DEST}"
  as_root rm -f "${DISABLE_DIR}/${PROFILE_NAME}"
  as_root apparmor_parser -r -W "${PROFILE_DEST}"

  log "Enabled ${PROFILE_NAME} from ${PROFILE_DEST}"
  log "Use: docker run --security-opt apparmor=${PROFILE_NAME} ..."
}

reload_profile() {
  require_command apparmor_parser
  check_apparmor_available
  [[ -f "${PROFILE_DEST}" ]] || die "Installed profile not found: ${PROFILE_DEST}"

  as_root rm -f "${DISABLE_DIR}/${PROFILE_NAME}"
  as_root apparmor_parser -r -W "${PROFILE_DEST}"
  log "Reloaded ${PROFILE_NAME} from ${PROFILE_DEST}"
}

disable_profile() {
  require_command apparmor_parser
  check_apparmor_available

  if [[ -f "${PROFILE_DEST}" ]]; then
    as_root install -d -m 0755 "${DISABLE_DIR}"
    as_root ln -sfn "${PROFILE_DEST}" "${DISABLE_DIR}/${PROFILE_NAME}"
    as_root apparmor_parser -R "${PROFILE_DEST}" || true
    log "Disabled ${PROFILE_NAME}"
  else
    log "Profile is not installed: ${PROFILE_DEST}"
  fi
}

remove_profile() {
  disable_profile
  as_root rm -f "${DISABLE_DIR}/${PROFILE_NAME}" "${PROFILE_DEST}"
  log "Removed installed profile ${PROFILE_DEST}"
}

status_profile() {
  local loaded_rc

  log "Profile name: ${PROFILE_NAME}"
  log "Source: ${PROFILE_SOURCE}"
  log "Installed path: ${PROFILE_DEST}"

  if [[ -f "${PROFILE_DEST}" ]]; then
    log "Installed: yes"
  else
    log "Installed: no"
  fi

  if [[ -L "${DISABLE_DIR}/${PROFILE_NAME}" ]]; then
    log "Disabled marker: yes"
  else
    log "Disabled marker: no"
  fi

  set +e
  profile_loaded
  loaded_rc=$?
  set -e

  case "${loaded_rc}" in
    0)
      log "Kernel status: loaded"
      ;;
    1)
      log "Kernel status: not loaded"
      ;;
    2)
      log "Kernel status: unknown (insufficient privileges to read AppArmor profile set)"
      ;;
  esac
}

run_opts() {
  printf '%s\n' "--security-opt apparmor=${PROFILE_NAME}"
}

action="${1:-}"

case "${action}" in
  enable)
    enable_profile
    ;;
  disable)
    disable_profile
    ;;
  reload)
    reload_profile
    ;;
  remove)
    remove_profile
    ;;
  status)
    status_profile
    ;;
  check)
    check_profile
    ;;
  run-opts)
    run_opts
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
