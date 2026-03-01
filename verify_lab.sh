#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

errors=0

check_file() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    log_error "Falta: ${path}"
    errors=$((errors + 1))
  else
    log_ok "Existe: ${path}"
  fi
}

check_user() {
  local user="$1"
  local home="/home/${user}"
  if ! id "${user}" >/dev/null 2>&1; then
    log_error "Usuario no encontrado: ${user}"
    errors=$((errors + 1))
    return
  fi
  log_ok "Usuario OK: ${user}"
  check_file "${home}"
}

check_users() {
  local lvl
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    check_user "$(level_user "${lvl}")"
  done
}

check_chain() {
  local csv="${LAB_META_DIR}/flags.csv"
  check_file "${csv}"
  [[ -f "${csv}" ]] || return

  local rows expected
  rows="$(awk 'NR>1{count++} END{print count+0}' "${csv}")"
  expected=$((LAB_LAST_LEVEL - LAB_FIRST_LEVEL + 1))
  if [[ "${rows}" -ne "${expected}" ]]; then
    log_error "flags.csv tiene ${rows} filas, se esperaban ${expected}"
    errors=$((errors + 1))
  else
    log_ok "flags.csv filas esperadas: ${rows}"
  fi
}

check_ssh() {
  check_file "${LAB_SSHD_DROPIN}"
  if ss -ltn | grep -q ":${LAB_SSH_PORT}"; then
    log_ok "SSHD escucha en puerto ${LAB_SSH_PORT}"
  else
    log_error "No se detecta SSH en puerto ${LAB_SSH_PORT}"
    errors=$((errors + 1))
  fi
}

check_services() {
  local pid_file pid
  for pid_file in "${LAB_SERVICE_DIR}/level18_service.pid" "${LAB_SERVICE_DIR}/level19_service.pid" "${LAB_SERVICE_DIR}/level29_service.pid" "${LAB_SERVICE_DIR}/http_level20.pid"; do
    check_file "${pid_file}"
    if [[ -f "${pid_file}" ]]; then
      pid="$(cat "${pid_file}" 2>/dev/null || true)"
      if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
        log_ok "Servicio activo PID ${pid} (${pid_file})"
      else
        log_error "Servicio caido (${pid_file})"
        errors=$((errors + 1))
      fi
    fi
  done
}

check_level_artifacts() {
  local lvl user level_dir readme
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    user="$(level_user "${lvl}")"
    level_dir="/home/${user}/level$(printf "%02d" "${lvl}")"
    readme="/home/${user}/README_LEVEL${lvl}.txt"
    check_file "${level_dir}"
    check_file "${readme}"
  done
}

main() {
  load_config
  check_file "${LAB_BASE_DIR}"
  check_file "${LAB_DATA_DIR}"
  check_file "${LAB_META_DIR}"
  check_file "${LAB_PROGRESS_DIR}"
  check_file "${LAB_META_DIR}/flag_hashes.csv"
  check_users
  check_chain
  check_ssh
  check_services
  check_level_artifacts

  if (( errors > 0 )); then
    log_error "Verificacion finalizo con ${errors} error(es)."
    exit 1
  fi

  log_ok "Verificacion completa: laboratorio consistente."
}

main "$@"
