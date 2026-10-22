# Spike H0 — Inventario de glibc, CPU y binarios del host (#3)

> Código descartable. La decisión final se lleva a arch.md (§1, §2, §18), a `platforms.defaultMatrix` de `.claude/project.config.json` y al checkbox de roadmap.md con `/record-decision`, **cuando esté el inventario de los servidores reales**.

## Pregunta

¿Qué glibc, CPU y binarios del host tienen los servidores reales donde se va a usar ditto, para fijar la glibc mínima, los `min_version` y los defaults de `source`?

## Estado

| Entorno | Estado |
|---|---|
| macOS del usuario | Hecho (`results/hosts/macos-1.txt`) |
| Contenedores Docker (validación del script) | Hecho (`results/validation/`, `results/validation-pkgs/`) |
| Servidores Linux reales del usuario | **Pendiente (paso manual)**: ver [Ejecución en los servidores reales](#ejecución-en-los-servidores-reales) |

Sin el inventario real, la sección [Decisión propuesta](#decisión-propuesta-provisional) es **provisional**.

## Archivos

| Archivo | Qué hace |
|---|---|
| `inventory.sh` | Inventario de un host. POSIX `sh`, solo lectura, sin red. Escribe solo `<outdir>/<label>.txt` (TOML simple). |
| `consolidate.sh` | Genera en Markdown la tabla host × binario, las comprobaciones contra los umbrales de arch.md §1 y un resumen (glibc mínima, musl, AVX2). |
| `run.sh` | Driver reproducible: `local`, `docker`, `docker-pkgs`, `consolidate`. |
| `results/hosts/` | Inventario **real** (por ahora solo macOS). |
| `results/validation/`, `results/validation-pkgs/` | Salidas de contenedores. **No son inventario**: solo validan el script. |

### Qué registra `inventory.sh`

- `[host]`: `uname -s -m -r`, distro (`/etc/os-release`, leído con `sed`, sin `source`), versión de macOS y si están las Command Line Tools, libc (`getconf GNU_LIBC_VERSION` → `ldd --version` → `/lib/ld-musl-*`), modelo y número de CPUs, AVX2 (`/proc/cpuinfo` en x86_64, `sysctl hw.optional.avx2_0` en macOS; `n/a` en arm64), si corre en un contenedor.
- `[bin.<nombre>]` con `category`, `found`, `name`, `path`, `version` (normalizada) y `raw` (primera línea útil de la salida):
  - Categoría B, duros: `git`, `curl`, `wget`, `tar`, `unzip`. Blandos: `cc`, `ssh`. Base: `$SHELL`, `bash`, `zsh`, `gzip`, `xz` (estos dos últimos porque mise descarga `.tar.gz`/`.tar.xz`).
  - Seleccionables: `nvim`, `rg`, `fd`/`fdfind`, `fzf`, `lazygit`, `node`, `python3`, `go`.
  - Interferencia: `mise` (categoría A en ditto; uno del host importa para H0.1b) y `conda`.

### Garantías y anonimización

- Solo lectura: en Docker se ejecuta con `--read-only --network none` y usuario no root; solo se escribe en el volumen de salida.
- La etiqueta del host la da el usuario (`-n srv-a`); por defecto es `host-<cksum del hostname>`. Se valida (`[A-Za-z0-9._-]`, sin `.` inicial) para que no pueda salir del directorio de salida.
- En todos los valores se sustituye `$HOME` por `~`, el hostname por `<host>` y el usuario por `<user>`. No se registran IPs, `PATH` ni variables de entorno.
- Cada sonda tiene `timeout 10` si `timeout` funciona (busybox antiguo solo acepta `-t`; en ese caso se omite).
- En macOS sin Command Line Tools, `/usr/bin/{git,cc,python3,clang,gcc}` son stubs que abren un diálogo de instalación: no se ejecutan y se marcan como `macOS CLT stub`.

## Comandos ejecutados

```sh
cd spikes/h0-inventario
./run.sh local macos-1                  # macOS, /bin/sh (bash 3.2 en modo sh)
dash inventory.sh -n m -o /tmp/x        # misma salida que con /bin/sh (solo cambia la etiqueta)
./run.sh docker                         # ubuntu-18.04 ubuntu-22.04 alpine-3.20 rocky-8 debian-12, imágenes limpias
./run.sh docker-pkgs                    # ubuntu-18.04 debian-12 alpine-3.20 rocky-8, con las herramientas instaladas
./run.sh consolidate                    # tabla de results/hosts
./run.sh consolidate results/validation-pkgs
docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable /mnt/inventory.sh /mnt/run.sh /mnt/consolidate.sh
```

`shellcheck` 0.11.0 (vía Docker; no está instalado en el host): sin avisos. Hay dos `disable` justificados en el código (SC1003 al borrar una barra invertida literal con `tr`; SC2016 en los comandos de instalación que deben expandirse dentro del contenedor).

## Resultados: macOS del usuario (inventario real)

| Campo | macos-1 |
|---|---|
| os / arch | Darwin / arm64 (Apple M2 Pro, 10 CPUs) |
| macOS | 26.2, Command Line Tools instaladas |
| libc / AVX2 | darwin / n/a |
| `git` | 2.50.1 (Apple Git) |
| `curl` / `wget` | 8.7.1 / — |
| `tar` / `unzip` | bsdtar 3.5.3 / 6.00 |
| `cc` / `ssh` | Apple clang 17.0.0 / OpenSSH 10.0 |
| `$SHELL` / `bash` / `zsh` | zsh 5.9 / 3.2.57 / 5.9 |
| `gzip` / `xz` | Apple gzip 475 / 5.8.3 (Homebrew) |
| `nvim` / `rg` | 0.11.5 / 15.1.0 (Homebrew) |
| `fd` / `fzf` / `lazygit` | — / — / — |
| `node` / `python3` / `go` | 26.7.0 (Homebrew) / 3.9.6 (`/usr/bin`) / — |
| `mise` / `conda` | — / — |

Prerrequisitos duros y blandos: ok. `nvim` ≥ 0.11.2, `node` ≥ 18 y `python3` ≥ 3.9 en el host: sí (python3 justo en el límite: 3.9.6 de las CLT).

Archivo completo: `results/hosts/macos-1.txt`.

## Validación del script en contenedores (no es inventario)

Arquitecturas: el host Docker es arm64; las imágenes `ubuntu:22.04` y `alpine:3.20` estaban en caché como amd64 y corrieron emuladas, así que se cubren las dos ramas de detección (x86_64 y aarch64). **El `avx2 = no` de esas dos es un artefacto de la emulación**, no un dato.

`/bin/sh` en cada imagen: dash (Ubuntu, Debian), busybox ash (Alpine), bash en modo sh (Rocky). En todas el script termina con éxito, con raíz de solo lectura, sin red y como usuario no root.

### Imágenes limpias (`results/validation/`)

| | ubuntu-18.04 | ubuntu-22.04 | alpine-3.20 | rocky-8 | debian-12 |
|---|---|---|---|---|---|
| libc | glibc 2.27 | glibc 2.35 | musl 1.2.5 | glibc 2.28 | glibc 2.36 |
| arch | aarch64 | x86_64 (emulado) | x86_64 (emulado) | aarch64 | aarch64 |
| duros presentes | `tar` | `tar` | `tar`, `wget`, `unzip` (busybox) | `tar`, `curl` | `tar` |

Valida el camino `found = false`, la detección de musl vía `ldd` y las applets de busybox (`wget`/`gzip` no aceptan `--version`: el script descarta la línea `unrecognized option` y registra el banner `BusyBox v1.36.1`).

### Con las herramientas instaladas (`results/validation-pkgs/`)

Paquetes de cada distro instalados dentro del contenedor (con red solo en ese paso). Valida el parseo de versiones (GNU/BSD/busybox, `fdfind`, `ssh -V`, `unzip -v`, `go version`, `version=` de lazygit, avisos de jemalloc bajo QEMU).

| Campo | alpine-3.20 | debian-12 | rocky-8 | ubuntu-18.04 |
|---|---|---|---|---|
| libc | musl 1.2.5 | glibc 2.36 | glibc 2.28 | glibc 2.27 |
| `git` | 2.45.4 | 2.39.5 | 2.43.7 | **2.17.1** |
| `curl` / `wget` | 8.14.1 / busybox 1.36.1 | 7.88.1 / 1.21.3 | 7.61.1 / 1.19.5 | 7.58.0 / 1.19.4 |
| `tar` / `unzip` | busybox 1.36.1 / 6.00 | 1.34 / 6.00 | 1.30 / 6.00 | 1.29 / 6.00 |
| `cc` / `ssh` | 13.2.1 / 9.7 | 12.2.0 / 9.2 | 8.5.0 / 8.0 | 7.5.0 / 7.6 |
| `bash` / `zsh` | 5.2.26 / 5.9 | 5.2.15 / 5.9 | 4.4.20 / 5.5.1 | 4.4.20 / 5.4.2 |
| `nvim` | 0.10.0 | 0.7.2 | — | 0.2.2 |
| `rg` / `fd` / `fzf` | 14.1.0 / 10.0.0 / 0.52.0 | 13.0.0 / 8.6.0 (`fdfind`) / 0.38.0 | — | — |
| `lazygit` | 0.41.0 | — | — | — |
| `node` / `python3` / `go` | 20.15.1 / 3.12.13 / 1.22.10 | 18.20.4 / 3.11.2 / 1.19.8 | 10.24.0 / 3.6.8 / — | 8.10.0 / 3.6.9 / 1.10.4 |

`—` = no hay paquete en los repos base de esa distro (o la instalación falló: `golang` en rocky-8 se instaló en una ejecución y no en otra).

Aunque no es inventario real, esto anticipa lo que se verá en hosts antiguos:

- **Ubuntu 18.04 trae `git` 2.17.1 < 2.19** (el mínimo duro de arch.md §1). Si algún servidor real es 18.04 sin git actualizado, `up` fallaría.
- Ningún `nvim` de distro llega a 0.11.2: el default `ditto` de Neovim es correcto.
- `node` y `python3` de las distros con glibc < 2.31 no cumplen `node ≥ 18` / `python ≥ 3.9`.
- En Debian/Ubuntu, `fd` se llama `fdfind`: `resolve` (H1.4b) debe buscar los dos nombres.

## Ejecución en los servidores reales

Paso manual del usuario, en cada servidor Linux:

```sh
# 1. Copiar el script (no necesita nada más que /bin/sh y coreutils)
scp spikes/h0-inventario/inventory.sh <servidor>:/tmp/ditto-inventory.sh

# 2. Ejecutarlo con una etiqueta anónima (srv-a, srv-b, …); escribe solo en el directorio de salida
ssh <servidor> 'sh /tmp/ditto-inventory.sh -n srv-a -o /tmp/ditto-inv'

# 3. Traer el resultado al repo y limpiar el servidor
scp <servidor>:/tmp/ditto-inv/srv-a.txt spikes/h0-inventario/results/hosts/
ssh <servidor> 'rm -rf /tmp/ditto-inventory.sh /tmp/ditto-inv'
```

- Ejecutarlo con el **mismo usuario y shell de login** con el que se usará ditto (el `PATH` cambia qué binarios encuentra). Si se usa `sudo -u`, hacerlo con `-i`.
- Revisar cada `.txt` antes de commitearlo (los valores `raw` llevan rutas y versiones; no deberían llevar nada sensible, pero conviene un vistazo).
- Una vez estén todos:

```sh
cd spikes/h0-inventario
./run.sh consolidate > /tmp/inventario.md    # tabla host × binario + comprobaciones + resumen
```

y pegar la salida en la sección [Tabla consolidada](#tabla-consolidada) de este archivo.

### Servidores inventariados

| Etiqueta | Rol / notas (sin hostnames ni IPs) |
|---|---|
| macos-1 | Equipo macOS del usuario |
| srv-a | *pendiente* |
| … | |

## Tabla consolidada

*Pendiente del inventario real.* Plantilla (la genera `./run.sh consolidate`; filas resumidas):

| Campo | macos-1 | srv-a | srv-b | … |
|---|---|---|---|---|
| os / arch | Darwin / arm64 | | | |
| distro | macOS 26.2 | | | |
| libc | darwin | | | |
| AVX2 | n/a | | | |
| `git` (≥ 2.19, duro) | 2.50.1 | | | |
| `curl` / `wget` (duro, uno de los dos) | 8.7.1 / — | | | |
| `tar` (duro) | 3.5.3 | | | |
| `unzip` (duro) | 6.00 | | | |
| `cc` (blando) | 17.0.0 | | | |
| `ssh` (blando) | 10.0 | | | |
| `$SHELL` | zsh 5.9 | | | |
| `nvim` (≥ 0.11.2) | 0.11.5 | | | |
| `rg` | 15.1.0 | | | |
| `fd` / `fdfind` | — | | | |
| `fzf` | — | | | |
| `lazygit` | — | | | |
| `node` (≥ 18) | 26.7.0 | | | |
| `python3` (≥ 3.9) | 3.9.6 | | | |
| `go` | — | | | |
| `mise` / `conda` | — / — | | | |

## Decisión propuesta (provisional)

Aplicando el *Criterio de decisión* del issue a lo que hay (macOS real + lo que anticipan las imágenes). **No aplicar en arch.md hasta tener el inventario real**; entonces se rellenan los huecos y se lleva con `/record-decision`.

| Tema | Propuesta | Depende de |
|---|---|---|
| glibc mínima (arch.md §18) | La más baja del inventario. Si algún servidor es Ubuntu 18.04 / glibc 2.27 (o Rocky/RHEL 8, 2.28), es < 2.31 y **el fallback legacy de Neovim (§7) es obligatorio**, igual que el CLI de tree-sitter y los binarios de Mason (H0.5) | Servidores reales |
| musl | Si ningún servidor real es musl, Alpine queda como best-effort (fuera de la matriz por defecto) | Servidores reales |
| AVX2 | Si todos los x86_64 reales tienen AVX2, no hace falta elegir variantes `-baseline` (H0.2, OpenCode) por defecto; si alguno no, la detección de AVX2 de H1.2 es obligatoria | Servidores reales |
| Neovim `source` (§1) | Mantener `ditto` (min 0.11.2): ninguna distro trae ≥ 0.11.2 | Confirmado por las imágenes |
| rg / fd / fzf / lazygit `source` | `auto` si la mayoría de servidores los tienen en una versión que baste; por lo visto en las imágenes, en hosts antiguos no están en los repos base, así que es probable que acabe siendo `auto` con resolución casi siempre a ditto. `resolve` debe aceptar `fdfind` como alias de `fd` | Servidores reales + `min_version` por componente (pendiente de fijar) |
| node / python `source` | `auto` con node ≥ 18 y python ≥ 3.9; en hosts con glibc < 2.31 caerá a ditto | Servidores reales |
| `git` ≥ 2.19 (duro, §1/§2) | Si algún servidor real tiene git < 2.19 (Ubuntu 18.04 trae 2.17.1), decidir entre: (a) mantener duro y que el usuario lo actualice, (b) bajar el mínimo si lazy.nvim/Mason funcionan con 2.17, o (c) pasarlo a seleccionable con versión de ditto | Servidores reales; (b) requiere probarlo |
| Prerrequisitos ausentes | Cualquier duro que falte en algún servidor real se anota aquí y se revisa si pasa a blando | Servidores reales |
| `platforms.defaultMatrix` | Las imágenes que correspondan a las distros reales (más la de glibc más baja). Actual: `ubuntu-18.04`, `ubuntu-22.04`, `alpine-3.20` | Servidores reales |

## Pendientes

1. Ejecutar `inventory.sh` en cada servidor Linux real (comandos arriba) y dejar los `.txt` en `results/hosts/`.
2. `./run.sh consolidate` y pegar la tabla en [Tabla consolidada](#tabla-consolidada).
3. Cerrar la [Decisión propuesta](#decisión-propuesta-provisional) y llevarla con `/record-decision` a arch.md §1 (tablas), §2 (prerrequisitos), §18 (glibc mínima), a `platforms.defaultMatrix` y al checkbox de roadmap.md.
