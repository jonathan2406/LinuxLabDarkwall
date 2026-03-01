#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

stop_services() {
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

clean_lab_state() {
  if [[ "${LAB_BASE_DIR}" != /opt/darkwall_lab* ]]; then
    die "LAB_BASE_DIR no esperado: ${LAB_BASE_DIR}"
  fi

  find "${LAB_DATA_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  find "${LAB_META_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  find "${LAB_SERVICE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  find "${LAB_PROGRESS_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

clean_user_homes() {
  local lvl user home
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    user="$(level_user "${lvl}")"
    home="/home/${user}"
    if [[ -d "${home}" ]]; then
      find "${home}" -mindepth 1 -maxdepth 1 ! -name '.bash_history' -exec rm -rf {} +
      chown "${user}:${user}" "${home}" >/dev/null 2>&1 || true
      chmod 750 "${home}" >/dev/null 2>&1 || true
    fi
  done
}

main() {
  load_config
  require_root

  ensure_dir "${LAB_BASE_DIR}" 755 root root
  ensure_dir "${LAB_DATA_DIR}" 755 root root
  ensure_dir "${LAB_META_DIR}" 700 root root
  ensure_dir "${LAB_PROGRESS_DIR}" 1777 root root
  ensure_dir "${LAB_SERVICE_DIR}" 755 root root

  stop_services
  clean_lab_state
  clean_user_homes

  log_info "Reconstruyendo laboratorio desde setup.sh..."
  "${SCRIPT_DIR}/setup.sh"
  log_ok "Reset completado."
}

main "$@"
