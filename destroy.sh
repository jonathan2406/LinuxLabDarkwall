#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
Uso:
  sudo bash destroy.sh [--force]

Descripcion:
  Elimina completamente DARKWALL_LINUX_WARGAME del sistema:
  - usuarios dw0..dw29 (y sus homes)
  - /opt/darkwall_lab
  - /etc/ssh/sshd_config.d/darkwall_lab.conf
  - /usr/local/bin/dw24_reader
EOF
}

confirm_destroy() {
  local response=""
  printf "Esto eliminara todo el laboratorio y usuarios del lab. Continuar? [yes/NO]: "
  read -r response
  if [[ "${response}" != "yes" ]]; then
    die "Operacion cancelada por el usuario."
  fi
}

stop_lab_services() {
  local pid_file pid
  if [[ -d "${LAB_SERVICE_DIR}" ]]; then
    while IFS= read -r -d '' pid_file; do
      pid="$(cat "${pid_file}" 2>/dev/null || true)"
      if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
        kill "${pid}" >/dev/null 2>&1 || true
      fi
      rm -f "${pid_file}"
    done < <(find "${LAB_SERVICE_DIR}" -type f -name '*.pid' -print0)
  fi
}

remove_users() {
  local lvl user
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    user="$(level_user "${lvl}")"
    if id "${user}" >/dev/null 2>&1; then
      pkill -KILL -u "${user}" >/dev/null 2>&1 || true
      userdel -r "${user}" >/dev/null 2>&1 || userdel "${user}" >/dev/null 2>&1 || true
      log_ok "Usuario eliminado: ${user}"
    fi
  done
}

remove_paths() {
  if [[ "${LAB_BASE_DIR}" != /opt/darkwall_lab* ]]; then
    die "LAB_BASE_DIR no esperado: ${LAB_BASE_DIR}"
  fi
  rm -rf "${LAB_BASE_DIR}"
  rm -f /usr/local/bin/dw24_reader
}

remove_ssh_dropin() {
  rm -f "${LAB_SSHD_DROPIN}"
  restart_ssh
}

main() {
  load_config
  require_root

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ "${1:-}" != "--force" ]]; then
    confirm_destroy
  fi

  stop_lab_services
  remove_users
  remove_paths
  remove_ssh_dropin
  log_ok "Laboratorio eliminado completamente."
}

main "$@"
