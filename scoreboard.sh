#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

print_header() {
  printf "%-8s %-10s %-10s %s\n" "USUARIO" "SOLVED" "PERCENT" "ULTIMO_NIVEL"
}

user_progress() {
  local user="$1"
  local file="${LAB_PROGRESS_DIR}/${user}.solved"
  if [[ ! -f "${file}" ]]; then
    printf "0|-"
    return 0
  fi

  local solved last
  solved="$(sort -n "${file}" | uniq | wc -l)"
  last="$(sort -n "${file}" | uniq | tail -n 1)"
  printf "%s|%s" "${solved}" "${last}"
}

print_scoreboard() {
  local total_levels=$((LAB_LAST_LEVEL + 1))
  local lvl user solved last percent data
  print_header
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    user="$(level_user "${lvl}")"
    data="$(user_progress "${user}")"
    solved="${data%%|*}"
    last="${data##*|}"
    percent=$(( solved * 100 / total_levels ))
    printf "%-8s %-10s %-9s%% %s\n" "${user}" "${solved}/${total_levels}" "${percent}" "${last}"
  done
}

main() {
  load_config
  if [[ ! -d "${LAB_PROGRESS_DIR}" ]]; then
    die "No existe ${LAB_PROGRESS_DIR}. Ejecuta setup.sh."
  fi
  print_scoreboard
}

main "$@"
