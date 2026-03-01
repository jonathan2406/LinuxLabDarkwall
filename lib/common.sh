#!/usr/bin/env bash
# Shared helpers for DARKWALL_LINUX_WARGAME scripts.

set -o errexit
set -o nounset
set -o pipefail

COLOR_RESET="\033[0m"
COLOR_BLUE="\033[1;34m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"

log_info() {
  printf "%b[INFO]%b %s\n" "${COLOR_BLUE}" "${COLOR_RESET}" "$*"
}

log_ok() {
  printf "%b[OK]%b %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
}

log_warn() {
  printf "%b[WARN]%b %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$*"
}

log_error() {
  printf "%b[ERROR]%b %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$*" 1>&2
}

die() {
  log_error "$*"
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Este script debe ejecutarse como root (sudo)."
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    die "No se encontro el comando requerido: ${cmd}"
  fi
}

load_config() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local conf="${script_dir}/config/lab.conf"
  [[ -f "${conf}" ]] || die "No existe configuracion: ${conf}"
  # shellcheck source=/dev/null
  source "${conf}"
}

level_user() {
  local level="$1"
  printf "%s%s" "${LAB_USER_PREFIX}" "${level}"
}

ensure_dir() {
  local path="$1"
  local mode="$2"
  local owner="$3"
  local group="$4"
  mkdir -p "${path}"
  chown "${owner}:${group}" "${path}"
  chmod "${mode}" "${path}"
}

ensure_file() {
  local path="$1"
  local content="$2"
  local mode="$3"
  local owner="$4"
  local group="$5"
  # Interpret escaped newlines so callers can pass multiline content safely.
  printf "%b" "${content}" >"${path}"
  chown "${owner}:${group}" "${path}"
  chmod "${mode}" "${path}"
}

ensure_line_in_file() {
  local file="$1"
  local regex="$2"
  local line="$3"
  touch "${file}"
  if ! grep -Eq "${regex}" "${file}"; then
    printf "%s\n" "${line}" >>"${file}"
  fi
}

ensure_user() {
  local user="$1"
  local home="$2"
  local shell="$3"

  if id "${user}" >/dev/null 2>&1; then
    usermod -d "${home}" -s "${shell}" "${user}" >/dev/null 2>&1 || true
  else
    useradd -m -d "${home}" -s "${shell}" "${user}"
  fi
}

set_user_password() {
  local user="$1"
  local password="$2"
  printf "%s:%s\n" "${user}" "${password}" | chpasswd
}

generate_flag() {
  local level="$1"
  python3 - <<PY
import hashlib
seed = "${LAB_FLAG_SEED}"
level = "${level}"
raw = f"{seed}|level-{level}".encode()
print("DWFLAG{" + hashlib.sha256(raw).hexdigest()[:20] + "}")
PY
}

ssh_service_name() {
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    printf "ssh"
  else
    printf "sshd"
  fi
}

restart_ssh() {
  local service
  service="$(ssh_service_name)"
  systemctl daemon-reload
  systemctl enable "${service}" >/dev/null 2>&1 || true
  systemctl restart "${service}"
}

in_range() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] || return 1
  (( value >= LAB_FIRST_LEVEL && value <= LAB_LAST_LEVEL ))
}

ensure_apt_package() {
  local pkg="$1"
  if dpkg -s "${pkg}" >/dev/null 2>&1; then
    return 0
  fi
  log_info "Instalando dependencia: ${pkg}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y "${pkg}"
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf "apt"
    return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    printf "pacman"
    return 0
  fi
  printf "unknown"
}

ensure_pacman_package() {
  local pkg="$1"
  if pacman -Q "${pkg}" >/dev/null 2>&1; then
    return 0
  fi
  log_info "Instalando dependencia: ${pkg}"
  pacman -Sy --noconfirm --needed "${pkg}"
}

ensure_pacman_any_of() {
  local selected=""
  local candidate
  for candidate in "$@"; do
    if pacman -Q "${candidate}" >/dev/null 2>&1; then
      selected="${candidate}"
      break
    fi
    if pacman -Si "${candidate}" >/dev/null 2>&1; then
      selected="${candidate}"
      break
    fi
  done

  if [[ -z "${selected}" ]]; then
    die "No se encontro ningun paquete compatible en pacman: $*"
  fi

  ensure_pacman_package "${selected}"
}

ensure_package() {
  local logical_pkg="$1"
  local manager
  manager="$(detect_package_manager)"
  case "${manager}" in
    apt)
      case "${logical_pkg}" in
        openssh-server|netcat|zip|unzip|net-tools|gcc) ;;
        *)
          die "Paquete logico no soportado en apt: ${logical_pkg}"
          ;;
      esac
      case "${logical_pkg}" in
        openssh-server) ensure_apt_package "openssh-server" ;;
        netcat) ensure_apt_package "netcat-openbsd" ;;
        zip) ensure_apt_package "zip" ;;
        unzip) ensure_apt_package "unzip" ;;
        net-tools) ensure_apt_package "net-tools" ;;
        gcc) ensure_apt_package "gcc" ;;
      esac
      ;;
    pacman)
      case "${logical_pkg}" in
        openssh-server|netcat|zip|unzip|net-tools|gcc) ;;
        *)
          die "Paquete logico no soportado en pacman: ${logical_pkg}"
          ;;
      esac
      case "${logical_pkg}" in
        openssh-server) ensure_pacman_package "openssh" ;;
        netcat) ensure_pacman_any_of "openbsd-netcat" "gnu-netcat" ;;
        zip) ensure_pacman_package "zip" ;;
        unzip) ensure_pacman_package "unzip" ;;
        net-tools) ensure_pacman_package "net-tools" ;;
        gcc) ensure_pacman_package "gcc" ;;
      esac
      ;;
    *)
      die "No se detecto gestor soportado. Usa Debian/Ubuntu/Kali/Parrot o Arch."
      ;;
  esac
}

ensure_ssh_dropin_enabled() {
  local sshd_config="/etc/ssh/sshd_config"
  if [[ -f "${sshd_config}" ]]; then
    if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "${sshd_config}"; then
      ensure_line_in_file "${sshd_config}" '^Include /etc/ssh/sshd_config\.d/\*\.conf$' 'Include /etc/ssh/sshd_config.d/*.conf'
    fi
  fi
}

csv_escape() {
  local value="${1//\"/\"\"}"
  printf "\"%s\"" "${value}"
}
