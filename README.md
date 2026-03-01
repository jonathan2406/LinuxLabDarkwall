# DARKWALL_LINUX_WARGAME

Laboratorio local tipo OverTheWire/Bandit para entrenamiento Linux en CTF y pentesting.

## Caracteristicas principales

- 30 niveles progresivos (`0` a `29`), cada uno con usuario dedicado (`dw0..dw29`).
- Progresion por SSH local: la flag del nivel `N` es la password de `dw(N+1)`.
- Provisioning idempotente y seguro con `setup.sh`.
- Scripts operativos incluidos: `reset.sh`, `scoreboard.sh`, `check_progress.sh`, `verify_lab.sh`.
- Compatible con Debian/Kali/Parrot/Ubuntu y Arch Linux.

## Requisitos

- Sistema Debian-based o Arch Linux.
- Privilegios `root` o `sudo`.
- Herramientas base Linux + `python3`.
- Dependencias instaladas automaticamente segun distro:
  - Debian/Kali/Parrot/Ubuntu: `openssh-server`, `netcat-openbsd`, `zip`, `unzip`, `net-tools`, `gcc`
  - Arch: `openssh`, `openbsd-netcat` (o `gnu-netcat` si aplica), `zip`, `unzip`, `net-tools`, `gcc`

## Estructura del proyecto

- `setup.sh`: provision completa del laboratorio.
- `reset.sh`: reconstruccion segura del entorno del lab.
- `destroy.sh`: desinstalacion completa del laboratorio.
- `scoreboard.sh`: tablero de progreso por usuario.
- `check_progress.sh`: envio/consulta de progreso por flag.
- `verify_lab.sh`: verificacion de consistencia del laboratorio.
- `config/lab.conf`: configuracion central.
- `config/levels.csv`: manifiesto de niveles.
- `lib/common.sh`: funciones reutilizables e idempotentes.
- `levels/`: documentacion pedagógica `level00.md .. level29.md`.

## Instalacion y arranque

Desde la raiz del proyecto:

```bash
sudo bash setup.sh
```

Acceso inicial:

```bash
ssh dw0@localhost -p 2222
```

Password inicial por defecto:

```text
DARKWALL_START
```

## Progresion de niveles

1. Inicia sesion como `dwN`.
2. Resuelve el reto del nivel.
3. Obtiene la flag.
4. Usa esa flag como password de `dw(N+1)`:

```bash
ssh dw1@localhost -p 2222
```

## Seguimiento de avance

Registrar una flag:

```bash
bash check_progress.sh submit 'DWFLAG{...}'
```

Ver estado del usuario actual:

```bash
bash check_progress.sh status
```

Ver scoreboard global:

```bash
bash scoreboard.sh
```

## Verificacion automatica

```bash
bash verify_lab.sh
```

Esta verificacion comprueba usuarios, artefactos de niveles, servicios locales y escucha SSH en el puerto del laboratorio.

## Reset seguro

```bash
sudo bash reset.sh
```

`reset.sh` solo limpia y reconstruye rutas bajo `/opt/darkwall_lab` y contenido de niveles en `/home/dw*`, sin operaciones destructivas fuera del alcance del laboratorio.

## Desinstalacion completa

Para eliminar completamente el laboratorio (usuarios `dw*`, datos y configuracion SSH del lab):

```bash
sudo bash destroy.sh
```

Modo no interactivo (sin confirmacion):

```bash
sudo bash destroy.sh --force
```

## Seguridad y buenas practicas

- Diseñado para ejecutarse en VM de entrenamiento.
- Servicios expuestos solo en `127.0.0.1`.
- Incluye demo SUID controlada para fines didacticos.
- No modifica configuraciones no relacionadas con el laboratorio.

## Niveles incluidos (0-29)

1. Basic Navigation
2. Hidden Files
3. File Reading Tools
4. File Creation
5. Copy and Move
6. Deletion
7. Searching Files
8. Searching Content
9. File Size Filtering
10. Permissions Basics
11. chmod
12. Ownership
13. Execution
14. Redirection
15. Pipes
16. Combining grep + pipes
17. Environment
18. Processes
19. Networking Basics
20. Netcat
21. Local Server
22. Encoded Data
23. Archives
24. Weird Filenames
25. SUID Concept
26. Cron Simulation
27. Log Analysis Simulation
28. Permission Puzzle
29. Multi-step Challenge
30. Mini CTF Final Boss

## Nota para instructores

Las flags y la cadena de passwords se generan automaticamente y se almacenan en:

- `/opt/darkwall_lab/meta/flags.csv` (solo root)
- `/opt/darkwall_lab/meta/flag_hashes.csv` (hashes para validacion de progreso)
