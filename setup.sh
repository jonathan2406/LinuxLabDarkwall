#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

declare -A FLAGS=()
declare -A PASSWORDS=()

ensure_dependencies() {
  local manager
  manager="$(detect_package_manager)"
  if [[ "${manager}" == "unknown" ]]; then
    die "Distribucion no soportada automaticamente. Usa Debian-based o Arch."
  fi

  require_command awk
  require_command sed
  require_command find
  require_command grep
  require_command tar
  require_command gzip
  require_command useradd
  require_command chpasswd
  require_command systemctl

  ensure_package openssh-server
  ensure_package netcat
  ensure_package zip
  ensure_package unzip
  ensure_package net-tools
  ensure_package gcc

  require_command python3
  require_command unzip
  require_command ss
  require_command nc
}

init_lab_dirs() {
  ensure_dir "${LAB_BASE_DIR}" 755 root root
  ensure_dir "${LAB_DATA_DIR}" 755 root root
  ensure_dir "${LAB_META_DIR}" 700 root root
  ensure_dir "${LAB_PROGRESS_DIR}" 1777 root root
  ensure_dir "${LAB_SERVICE_DIR}" 755 root root
}

generate_credentials() {
  local lvl
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    FLAGS["${lvl}"]="$(generate_flag "${lvl}")"
  done

  PASSWORDS["0"]="${LAB_INITIAL_PASSWORD}"
  for lvl in $(seq 1 "${LAB_LAST_LEVEL}"); do
    PASSWORDS["${lvl}"]="${FLAGS[$((lvl - 1))]}"
  done
}

create_users() {
  local lvl user home
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    user="$(level_user "${lvl}")"
    home="/home/${user}"
    ensure_user "${user}" "${home}" "/bin/bash"
    set_user_password "${user}" "${PASSWORDS[${lvl}]}"
    ensure_dir "${home}" 750 "${user}" "${user}"
  done
}

write_flags_meta() {
  local meta_file="${LAB_META_DIR}/flags.csv"
  local hash_file="${LAB_META_DIR}/flag_hashes.csv"
  printf "level,user,flag,next_user,next_password\n" >"${meta_file}"
  printf "level,sha256\n" >"${hash_file}"

  local lvl user next_user next_password
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    user="$(level_user "${lvl}")"
    if (( lvl < LAB_LAST_LEVEL )); then
      next_user="$(level_user "$((lvl + 1))")"
      next_password="${PASSWORDS[$((lvl + 1))]}"
    else
      next_user="N/A"
      next_password="N/A"
    fi
    printf "%s,%s,%s,%s,%s\n" "${lvl}" "${user}" "${FLAGS[${lvl}]}" "${next_user}" "${next_password}" >>"${meta_file}"
    printf "%s,%s\n" "${lvl}" "$(printf "%s" "${FLAGS[${lvl}]}" | sha256sum | awk '{print $1}')" >>"${hash_file}"
  done

  chown root:root "${meta_file}"
  chmod 600 "${meta_file}"
  chown root:root "${hash_file}"
  chmod 644 "${hash_file}"
}

reset_home_content() {
  local user="$1"
  local home="/home/${user}"
  local lvl="$2"
  find "${home}" -mindepth 1 -maxdepth 1 ! -name '.bash_history' -exec rm -rf {} +
  ensure_dir "${home}/level$(printf "%02d" "${lvl}")" 750 "${user}" "${user}"
}

write_level_readme() {
  local user="$1"
  local lvl="$2"
  local objective="$3"
  local skills="$4"
  local hint="$5"
  local path="/home/${user}/README_LEVEL${lvl}.txt"

  local progression_msg
  if (( lvl < LAB_LAST_LEVEL )); then
    progression_msg="La flag de este nivel es la password del siguiente usuario.\nConecta usando: ssh $(level_user "$((lvl + 1))")@localhost -p ${LAB_SSH_PORT}"
  else
    progression_msg="Este es el nivel final del laboratorio. Documenta tu solve y revisa scoreboard.sh."
  fi

  cat >"${path}" <<EOF
DARKWALL_LINUX_WARGAME - LEVEL ${lvl}
User actual: ${user}

Objetivo:
${objective}

Skills:
${skills}

Hint:
${hint}

Regla de progresion:
${progression_msg}
EOF
  chown "${user}:${user}" "${path}"
  chmod 640 "${path}"
}

create_level_scripts_common() {
  local user="$1"
  local level="$2"
  local path="/home/${user}/level$(printf "%02d" "${level}")/check.sh"
  cat >"${path}" <<'EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
echo "Este nivel no usa check.sh en automatico. Sigue el README."
EOF
  chown "${user}:${user}" "${path}"
  chmod 750 "${path}"
}

provision_level() {
  local lvl="$1"
  local user
  user="$(level_user "${lvl}")"
  local home="/home/${user}"
  local level_dir="${home}/level$(printf "%02d" "${lvl}")"
  local flag="${FLAGS[${lvl}]}"

  reset_home_content "${user}" "${lvl}"
  create_level_scripts_common "${user}" "${lvl}"

  case "${lvl}" in
    0)
      ensure_dir "${level_dir}/start_here" 750 "${user}" "${user}"
      ensure_file "${level_dir}/start_here/note.txt" "Usa pwd, ls, cd y cat para encontrar la flag.\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/start_here/.flag.txt" "${flag}\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Navega por carpetas basicas y encuentra un archivo oculto." "pwd ls cd cat" "Explora ${level_dir}/start_here"
      ;;
    1)
      ensure_file "${level_dir}/.hidden_password" "${flag}\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/visible.txt" "No soy la flag.\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Encuentra la flag en un dotfile." "ls -la" "Los archivos ocultos empiezan con punto."
      ;;
    2)
      {
        printf "linea 1\nlinea 2\nlinea 3\n"
        printf "FLAG=%s\n" "${flag}"
      } >"${level_dir}/long_text.log"
      chown "${user}:${user}" "${level_dir}/long_text.log"
      chmod 640 "${level_dir}/long_text.log"
      write_level_readme "${user}" "${lvl}" "Usa herramientas de lectura para encontrar la linea correcta." "cat less head tail" "La flag aparece con prefijo FLAG=."
      ;;
    3)
      ensure_file "${level_dir}/TASK.txt" "Crea carpeta build y archivo build/token.txt con texto READY.\nLuego ejecuta ./check.sh\n" 640 "${user}" "${user}"
      cat >"${level_dir}/check.sh" <<EOF
#!/usr/bin/env bash
set -o errexit
if [[ -f "${level_dir}/build/token.txt" ]] && grep -qx 'READY' "${level_dir}/build/token.txt"; then
  echo "${flag}"
else
  echo "Falta build/token.txt con READY"
  exit 1
fi
EOF
      chown "${user}:${user}" "${level_dir}/check.sh"
      chmod 750 "${level_dir}/check.sh"
      write_level_readme "${user}" "${lvl}" "Practica touch y mkdir para validar una tarea." "touch mkdir" "Lee TASK.txt y luego ejecuta check.sh."
      ;;
    4)
      ensure_file "${level_dir}/a.txt" "DW\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/b.txt" "FLAG\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/c.txt" "{${flag}}\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/TASK.txt" "Copia/mueve archivos para crear result.txt y luego ./check.sh\n" 640 "${user}" "${user}"
      cat >"${level_dir}/check.sh" <<EOF
#!/usr/bin/env bash
set -o errexit
if [[ -f "${level_dir}/result.txt" ]]; then
  if grep -q "${flag}" "${level_dir}/result.txt"; then
    echo "${flag}"
    exit 0
  fi
fi
echo "No se detecto la cadena esperada en result.txt"
exit 1
EOF
      chown "${user}:${user}" "${level_dir}/check.sh"
      chmod 750 "${level_dir}/check.sh"
      write_level_readme "${user}" "${lvl}" "Usa cp y mv para preparar un archivo final." "cp mv" "Puedes concatenar y mover al destino final."
      ;;
    5)
      ensure_dir "${level_dir}/delete_me/empty_dir" 750 "${user}" "${user}"
      ensure_file "${level_dir}/delete_me/tmp1" "noise\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/delete_me/tmp2" "noise\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/SAFE_NOTE.txt" "Elimina tmp1 tmp2 y empty_dir; despues ejecuta check.sh\n" 640 "${user}" "${user}"
      cat >"${level_dir}/check.sh" <<EOF
#!/usr/bin/env bash
set -o errexit
if [[ ! -e "${level_dir}/delete_me/tmp1" && ! -e "${level_dir}/delete_me/tmp2" && ! -d "${level_dir}/delete_me/empty_dir" ]]; then
  echo "${flag}"
else
  echo "Aun faltan elementos por eliminar."
  exit 1
fi
EOF
      chown "${user}:${user}" "${level_dir}/check.sh"
      chmod 750 "${level_dir}/check.sh"
      write_level_readme "${user}" "${lvl}" "Practica rm/rmdir con criterio de seguridad." "rm rmdir" "Evita usar comodines peligrosos."
      ;;
    6)
      ensure_dir "${level_dir}/tree/a/b/c/d" 750 "${user}" "${user}"
      ensure_file "${level_dir}/tree/a/b/c/d/target.txt" "${flag}\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/tree/noise.txt" "nope\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Encuentra un archivo por busqueda." "find" "Busca por nombre target.txt."
      ;;
    7)
      ensure_dir "${level_dir}/docs" 750 "${user}" "${user}"
      ensure_file "${level_dir}/docs/a.log" "alpha\nbeta\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/docs/b.log" "id=${flag}\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/docs/c.log" "gamma\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Busca contenido recursivo en multiples archivos." "grep -r" "El patron podria ser id=."
      ;;
    8)
      ensure_dir "${level_dir}/sizes" 750 "${user}" "${user}"
      ensure_file "${level_dir}/sizes/small.txt" "tiny\n" 640 "${user}" "${user}"
      printf "%s" "${flag}" >"${level_dir}/sizes/exact.bin"
      chown "${user}:${user}" "${level_dir}/sizes/exact.bin"
      chmod 640 "${level_dir}/sizes/exact.bin"
      write_level_readme "${user}" "${lvl}" "Filtra por tamano para identificar archivo objetivo." "find -size" "Usa bytes exactos."
      ;;
    9)
      ensure_dir "${level_dir}/perm_lab" 750 "${user}" "${user}"
      ensure_file "${level_dir}/perm_lab/readme.txt" "Revisa ls -l para identificar archivo legible.\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/perm_lab/flag_readable.txt" "${flag}\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/perm_lab/flag_blocked.txt" "not_this\n" 000 root root
      write_level_readme "${user}" "${lvl}" "Interpreta permisos rwx y elige archivo correcto." "ls -l" "No todo archivo puede leerse."
      ;;
    10)
      ensure_file "${level_dir}/unlock.sh" "#!/usr/bin/env bash\necho '${flag}'\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Convierte un script en ejecutable y ejecútalo." "chmod numerico simbolico" "Primero revisa permisos con ls -l."
      ;;
    11)
      ensure_file "${level_dir}/owners.txt" "Usa ls -l para inspeccionar owner:group. La flag esta en owned_by_dw11.txt\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/owned_by_dw11.txt" "${flag}\n" 640 "${user}" "${user}"
      chown "${user}:${user}" "${level_dir}/owned_by_dw11.txt"
      write_level_readme "${user}" "${lvl}" "Reconoce ownership con chown/chgrp en contexto de laboratorio." "chown chgrp" "Compara owner y group en cada archivo."
      ;;
    12)
      ensure_file "${level_dir}/script.sh" "#!/usr/bin/env bash\nprintf '%s\n' '${flag}'\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Ejecuta scripts con shebang y bash." "./script.sh bash script.sh shebang" "Prueba ambas formas de ejecucion."
      ;;
    13)
      cat >"${level_dir}/generator.sh" <<EOF
#!/usr/bin/env bash
echo "stdout-noise"
echo "stderr-flag:${flag}" 1>&2
EOF
      chown "${user}:${user}" "${level_dir}/generator.sh"
      chmod 750 "${level_dir}/generator.sh"
      write_level_readme "${user}" "${lvl}" "Usa redireccion de salida y error para capturar la flag." "> >> 2> &>" "La flag se imprime por stderr."
      ;;
    14)
      ensure_file "${level_dir}/stream.txt" "x|ignore\nneedle:${flag}|ok\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Filtra texto con pipes para aislar la flag." "|" "Combina cat y grep."
      ;;
    15)
      ensure_file "${level_dir}/combined.log" "INFO a\nWARN b\nFLAG ${flag} END\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Encadena grep y pipes para extraer solo el token." "grep pipes" "Puedes cortar columnas."
      ;;
    16)
      ensure_file "${home}/.dw16_env" "DW16_PART1=${flag:0:12}\nDW16_PART2=${flag:12}\n" 640 "${user}" "${user}"
      ensure_line_in_file "${home}/.bashrc" 'DW16_PART1=' "source ~/.dw16_env"
      write_level_readme "${user}" "${lvl}" "Recolecta datos del entorno para reconstruir la flag." "whoami id uname -a env" "Mira variables DW16_PART*."
      ;;
    17)
      ensure_file "${level_dir}/process_note.txt" "Busca proceso con nombre dw17_worker y mata el correcto.\nDespues ejecuta check.sh\n" 640 "${user}" "${user}"
      cat >"${LAB_SERVICE_DIR}/dw17_worker.sh" <<EOF
#!/usr/bin/env bash
exec -a "dw17_worker_${flag}" sleep 99999
EOF
      chmod 755 "${LAB_SERVICE_DIR}/dw17_worker.sh"
      nohup "${LAB_SERVICE_DIR}/dw17_worker.sh" >/dev/null 2>&1 &
      cat >"${level_dir}/check.sh" <<EOF
#!/usr/bin/env bash
if pgrep -f "dw17_worker_${flag}" >/dev/null; then
  echo "El proceso sigue vivo."
  exit 1
fi
echo "${flag}"
EOF
      chown "${user}:${user}" "${level_dir}/check.sh"
      chmod 750 "${level_dir}/check.sh"
      write_level_readme "${user}" "${lvl}" "Gestiona procesos para liberar el resultado." "ps top kill" "Usa pgrep -f para localizarlo."
      ;;
    18)
      ensure_file "${level_dir}/network_note.txt" "Descubre el puerto local que escucha darkwall-l18 y conecta para ver la flag.\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Identifica puertos activos en localhost." "ss netstat" "Busca el servicio darkwall-l18."
      ;;
    19)
      ensure_file "${level_dir}/nc_note.txt" "Conecta con nc al puerto de nivel 19 en localhost.\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Usa netcat para hablar con un listener TCP." "nc" "nc 127.0.0.1 <puerto>."
      ;;
    20)
      ensure_file "${level_dir}/http_note.txt" "Descarga /flag20.txt desde el servidor local.\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Accede a un HTTP server local." "python3 -m http.server curl wget" "curl http://127.0.0.1:${LAB_HTTP_PORT}/flag20.txt"
      ;;
    21)
      ensure_file "${level_dir}/encoded.b64" "$(printf "%s" "${flag}" | base64 -w 0)\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Decodifica base64 para obtener la flag." "base64 -d" "base64 -d encoded.b64"
      ;;
    22)
      ensure_dir "${level_dir}/archives" 750 "${user}" "${user}"
      ensure_file "${level_dir}/archives/flag.txt" "${flag}\n" 640 "${user}" "${user}"
      tar -czf "${level_dir}/archives/pack.tar.gz" -C "${level_dir}/archives" flag.txt
      zip -q "${level_dir}/archives/pack.zip" "${level_dir}/archives/pack.tar.gz"
      rm -f "${level_dir}/archives/flag.txt" "${level_dir}/archives/pack.tar.gz"
      chown "${user}:${user}" "${level_dir}/archives/pack.zip"
      chmod 640 "${level_dir}/archives/pack.zip"
      write_level_readme "${user}" "${lvl}" "Extrae un archivo comprimido por capas." "tar gzip unzip" "Empieza por unzip."
      ;;
    23)
      ensure_file "${level_dir}/file with spaces [and] \$pecial!.txt" "${flag}\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Manipula nombres de archivo raros." "quoting escaping" "Usa comillas simples o tab completion."
      ;;
    24)
      ensure_file "${LAB_DATA_DIR}/level24_flag.txt" "${flag}\n" 640 root "${user}"
      cat >"${LAB_SERVICE_DIR}/dw24_reader.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  FILE *f = fopen("/opt/darkwall_lab/data/level24_flag.txt", "r");
  if (!f) {
    puts("No se pudo abrir la flag.");
    return 1;
  }
  char buf[128];
  if (fgets(buf, sizeof(buf), f) == NULL) {
    fclose(f);
    return 1;
  }
  fclose(f);
  printf("%s", buf);
  return 0;
}
EOF
      if command -v gcc >/dev/null 2>&1; then
        gcc "${LAB_SERVICE_DIR}/dw24_reader.c" -o /usr/local/bin/dw24_reader
        chown root:root /usr/local/bin/dw24_reader
        chmod 4755 /usr/local/bin/dw24_reader
      else
        ensure_file "/usr/local/bin/dw24_reader" "#!/usr/bin/env bash\ncat /opt/darkwall_lab/data/level24_flag.txt\n" 755 root root
      fi
      write_level_readme "${user}" "${lvl}" "Encuentra binario SUID y usalo de forma segura." "find -perm -4000" "find /usr/local/bin -perm -4000 2>/dev/null"
      ;;
    25)
      ensure_dir "${LAB_DATA_DIR}/cron_sim" 755 root root
      ensure_file "${LAB_DATA_DIR}/cron_sim/cron_task.sh" "#!/usr/bin/env bash\necho \"[cron] generated $(date +%s)\" >> /opt/darkwall_lab/data/cron_sim/cron.log\necho '${flag}' > /opt/darkwall_lab/data/cron_sim/out.flag\nchmod 644 /opt/darkwall_lab/data/cron_sim/out.flag\n" 755 root root
      ensure_file "${LAB_DATA_DIR}/cron_sim/cron.log" "[cron] darkwall simulation initialized\n" 644 root root
      bash "${LAB_DATA_DIR}/cron_sim/cron_task.sh"
      ln -sfn "${LAB_DATA_DIR}/cron_sim" "${level_dir}/cron_sim"
      chown -h "${user}:${user}" "${level_dir}/cron_sim"
      write_level_readme "${user}" "${lvl}" "Analiza simulacion de cron para hallar la salida programada." "cron scheduling" "Revisa cron.log y out.flag."
      ;;
    26)
      ensure_dir "${level_dir}/logs" 750 "${user}" "${user}"
      {
        local i
        for i in $(seq 1 500); do
          printf "2026-01-01 INFO event-%s\n" "${i}"
        done
        printf "2026-01-01 ALERT token=%s source=training\n" "${flag}"
      } >"${level_dir}/logs/huge.log"
      chown "${user}:${user}" "${level_dir}/logs/huge.log"
      chmod 640 "${level_dir}/logs/huge.log"
      write_level_readme "${user}" "${lvl}" "Extrae evento clave desde un log grande." "grep head tail" "Busca por token=."
      ;;
    27)
      ensure_dir "${level_dir}/maze/a/b/c" 700 root root
      ensure_dir "${level_dir}/maze/open" 711 "${user}" "${user}"
      ensure_file "${level_dir}/maze/open/flag.txt" "${flag}\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Resuelve un puzzle de traversal y permisos de directorio." "permisos en directorios" "Necesitas x para atravesar carpetas."
      ;;
    28)
      ensure_dir "${level_dir}/multi/a" 750 "${user}" "${user}"
      ensure_dir "${level_dir}/multi/b" 750 "${user}" "${user}"
      ensure_file "${level_dir}/multi/a/data1.txt" "noise 123\n" 640 "${user}" "${user}"
      ensure_file "${level_dir}/multi/b/target.log" "row1\nFLAG64 $(printf "%s" "${flag}" | base64 -w 0)\n" 640 "${user}" "${user}"
      write_level_readme "${user}" "${lvl}" "Combina find grep pipes y decodificacion para llegar a la flag." "find grep pipes base64" "Encuentra FLAG64 y decodifica."
      ;;
    29)
      ensure_file "${level_dir}/boss.txt" "Final boss: combina busqueda, permisos, ejecucion y red local.\n1) Encuentra final_helper.sh\n2) Ejecutalo y filtra salida\n3) Conecta al puerto final y combina resultados\n" 640 "${user}" "${user}"
      ensure_dir "${level_dir}/boss_zone" 750 "${user}" "${user}"
      ensure_file "${level_dir}/boss_zone/final_helper.sh" "#!/usr/bin/env bash\necho 'token_part=FINALPART'\n" 750 "${user}" "${user}"
      ensure_file "${LAB_DATA_DIR}/final_flag.txt" "${flag}\n" 640 root root
      write_level_readme "${user}" "${lvl}" "Reto final multi-step de estilo mini CTF." "navigation permissions network execution pipes search" "El resultado final esta en servicio local final."
      ;;
  esac

}

start_python_tcp_service() {
  local name="$1"
  local port="$2"
  local payload="$3"
  local server_py="${LAB_SERVICE_DIR}/${name}.py"
  local pid_file="${LAB_SERVICE_DIR}/${name}.pid"

  cat >"${server_py}" <<EOF
#!/usr/bin/env python3
import socket
import socketserver

PAYLOAD = ${payload@Q}
class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.sendall((PAYLOAD + "\\n").encode())

class Server(socketserver.TCPServer):
    allow_reuse_address = True

with Server(("127.0.0.1", ${port}), Handler) as s:
    s.serve_forever()
EOF
  chmod 755 "${server_py}"

  if [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" >/dev/null 2>&1; then
    kill "$(cat "${pid_file}")" >/dev/null 2>&1 || true
  fi

  nohup python3 "${server_py}" >/dev/null 2>&1 &
  echo $! >"${pid_file}"
}

start_http_service() {
  local web_root="${LAB_DATA_DIR}/http_level20"
  local pid_file="${LAB_SERVICE_DIR}/http_level20.pid"
  ensure_dir "${web_root}" 755 root root
  ensure_file "${web_root}/flag20.txt" "${FLAGS[20]}\n" 644 root root

  if [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" >/dev/null 2>&1; then
    kill "$(cat "${pid_file}")" >/dev/null 2>&1 || true
  fi

  nohup python3 -m http.server "${LAB_HTTP_PORT}" --bind 127.0.0.1 --directory "${web_root}" >/dev/null 2>&1 &
  echo $! >"${pid_file}"
}

configure_ssh() {
  ensure_ssh_dropin_enabled
  ensure_file "${LAB_SSHD_DROPIN}" "# Managed by DARKWALL_LINUX_WARGAME\nPort ${LAB_SSH_PORT}\nPasswordAuthentication yes\nKbdInteractiveAuthentication yes\nChallengeResponseAuthentication yes\nUsePAM yes\nPermitRootLogin no\nAllowUsers $(for i in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do printf '%s ' "$(level_user "$i")"; done)\n" 644 root root
  restart_ssh
}

provision_all_levels() {
  local lvl
  for lvl in $(seq "${LAB_FIRST_LEVEL}" "${LAB_LAST_LEVEL}"); do
    provision_level "${lvl}"
  done
}

start_services() {
  start_python_tcp_service "level18_service" 4018 "darkwall-l18 ${FLAGS[18]}"
  start_python_tcp_service "level19_service" "${LAB_LISTENER_PORT}" "${FLAGS[19]}"
  start_python_tcp_service "level29_service" 4029 "FINALPART ${FLAGS[29]}"
  start_http_service
}

main() {
  load_config
  require_root
  ensure_dependencies
  init_lab_dirs
  generate_credentials
  create_users
  write_flags_meta
  provision_all_levels
  start_services
  configure_ssh
  log_ok "Laboratorio ${LAB_NAME} provisionado."
  log_info "Credenciales iniciales -> usuario: $(level_user "${LAB_FIRST_LEVEL}") | password: ${LAB_INITIAL_PASSWORD}"
  log_info "Acceso: ssh $(level_user "${LAB_FIRST_LEVEL}")@localhost -p ${LAB_SSH_PORT}"
}

main "$@"
