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
  ./check_progress.sh submit <FLAG>
  ./check_progress.sh status [usuario]
EOF
}

progress_file_for_user() {
  local user="$1"
  printf "%s/%s.solved" "${LAB_PROGRESS_DIR}" "${user}"
}

resolve_level_from_flag() {
  local flag="$1"
  local hash hash_file
  hash="$(printf "%s" "${flag}" | sha256sum | awk '{print $1}')"
  hash_file="${LAB_META_DIR}/flag_hashes.csv"
  [[ -f "${hash_file}" ]] || die "No existe ${hash_file}. Ejecuta setup.sh como root."

  awk -F',' -v h="${hash}" 'NR>1 && $2==h {print $1; exit}' "${hash_file}"
}

submit_flag() {
  local flag="$1"
  local user level next_level next_user pf
  user="$(whoami)"
  level="$(resolve_level_from_flag "${flag}")"
  [[ -n "${level}" ]] || die "Flag invalida."

  pf="$(progress_file_for_user "${user}")"
  touch "${pf}"
  chmod 666 "${pf}" >/dev/null 2>&1 || true

  if ! grep -qx "${level}" "${pf}"; then
    printf "%s\n" "${level}" >>"${pf}"
  fi

  next_level=$((level + 1))
  if (( next_level <= LAB_LAST_LEVEL )); then
    next_user="$(level_user "${next_level}")"
    log_ok "Flag valida para nivel ${level}. Siguiente usuario: ${next_user}"
    printf "Login esperado: ssh %s@localhost -p %s\n" "${next_user}" "${LAB_SSH_PORT}"
  else
    log_ok "Completaste el nivel final (${level})."
  fi
}

show_status() {
  local user="${1:-$(whoami)}"
  local pf
  pf="$(progress_file_for_user "${user}")"
  if [[ ! -f "${pf}" ]]; then
    printf "Usuario: %s | 0/%s niveles registrados\n" "${user}" "$((LAB_LAST_LEVEL + 1))"
    return 0
  fi

  local solved
  solved="$(sort -n "${pf}" | uniq | wc -l)"
  printf "Usuario: %s | %s/%s niveles registrados\n" "${user}" "${solved}" "$((LAB_LAST_LEVEL + 1))"
  printf "Niveles: %s\n" "$(sort -n "${pf}" | uniq | tr '\n' ' ')"
}

main() {
  load_config
  local cmd="${1:-}"
  case "${cmd}" in
    submit)
      [[ $# -eq 2 ]] || { usage; exit 1; }
      submit_flag "$2"
      ;;
    status)
      show_status "${2:-}"
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
