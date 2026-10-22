# H0.1 — mise aislado en `.ditto/`: resultados

**Issue:** #1 · **Fecha:** 2026-10-21 · **Estado:** pruebas 2–8 en verde en macOS arm64 y en la matriz Linux de Docker, con dos componentes sin build para musl (ver *Conclusión*).

## Pregunta

¿Puede mise, en una versión fijada y con todos sus `MISE_*` apuntando a `.ditto/`, instalar el núcleo de ditto en Linux (incluida glibc 2.27) y macOS sin escribir nada fuera de `.ditto/`?

**Respuesta corta:** sí, con tres matices:

1. Las `MISE_*` **no bastan**. El cliente sigstore de mise (verificación de *attestations*) guarda una caché TUF en `~/Library/Caches/dev.sigstore.sigstore-rust` (macOS) o `~/.cache/sigstore-rust` (Linux), y no respeta `MISE_CACHE_DIR`. Por eso, **solo en el proceso de mise**, también se redirigen `HOME`, `XDG_*` y `TMPDIR` a `.ditto/mise/home`.
2. El CLI de **tree-sitter** de upstream (aqua/GitHub) exige **glibc ≥ 2.39** desde la 0.26, así que falla incluso en Ubuntu 22.04. El de **conda-forge** (`conda:tree-sitter-cli`) sí funciona en glibc 2.27.
3. En **musl** (Alpine) no existe build de Neovim ni de tree-sitter CLI. Las versiones de `apk` tampoco cumplen los requisitos (ver *Riesgos*).

## Contenido del directorio

| Archivo | Para qué |
|---|---|
| `env.sh` | Librería POSIX reutilizable: versión y sha256 de mise, `ditto_mise_paths <dir>` (solo rutas `DITTO_*`), `ditto_mise <args>` (aplica el aislamiento por invocación en un subshell), `ditto_mise_env <dir>` (exporta las `MISE_*` en el shell actual), `ditto_mise_bootstrap`, `ditto_mise_unexport`, detección de plataforma/libc/AVX2 y `ditto_write_config` (genera `config.toml` por host). **Pensada para H0.1b (#4) y #5.** |
| `run.sh <dest> [all\|online\|offline]` | Pruebas 1–8 sobre `<dest>/.ditto`. Imprime líneas `RESULT <id> <PASS\|FAIL\|INFO\|SKIP> …`. |
| `gen-lock.sh <scratch> [out]` | Regenera `mise.lock` (6 plataformas, variantes de OpenCode). |
| `mise.lock` | Lockfile compartido generado con `gen-lock.sh`. |
| `docker.sh <imagen> <arch> <workdir>` | Driver Linux: fase *online* y después fase *offline* con `--network none` sobre el mismo volumen. |
| `macos.sh <scratch>` | Driver macOS: `HOME` y `TMPDIR` desechables, mise del host simulado y barrido completo del `$HOME` real. |

### Reutilización en #4 (H0.1b) y #5

```sh
. spikes/h0.1-mise-aislado/env.sh
ditto_mise_paths "$PWD/.ditto"      # DITTO_DIR, DITTO_MISE_BIN/CONFIG/LOCK; no exporta MISE_*
ditto_mise_bootstrap                # descarga + sha256
ditto_write_config "$DITTO_MISE_CONFIG"
cp spikes/h0.1-mise-aislado/mise.lock "$DITTO_MISE_LOCK"
ditto_mise install --locked         # MISE_* + HOME/XDG/TMPDIR solo en este proceso
ditto_mise which nvim               # ruta absoluta para el wrapper
```

Reglas:

- **Las `MISE_*` se limitan al proceso de mise; nunca al shell del usuario** (arch.md §8). `ditto_mise` las aplica en cada invocación dentro de un subshell (`( … exec mise "$@" )`), así que el shell que la llama no queda con ninguna `MISE_*` ni con `HOME`/`XDG_*` cambiados. Es la forma recomendada.
- `ditto_mise_env` exporta las `MISE_*` en el shell actual. Úsala solo dentro de un script o un subshell (`( ditto_mise_env …; otro-comando )`) cuando otra herramienta deba heredarlas, nunca en la sesión interactiva. Para limpiar un shell: `ditto_mise_unexport`.
- Antes de exportar, el aislamiento hace **`unset` de toda `MISE_*` heredada del host** (`MISE_DATA_DIR`, `MISE_ENV`, `MISE_SHIMS_DIR`…). Solo conserva `MISE_GITHUB_TOKEN` (y `GITHUB_TOKEN`, que no es `MISE_*`) y los diagnósticos que no escriben nada (`MISE_LOG_HTTP`, `MISE_DEBUG`, `MISE_TRACE`, `MISE_VERBOSE`, `MISE_LOG_LEVEL`, `MISE_OFFLINE`). Los nombres salen de `env | sed -n 's/^\(MISE_[A-Za-z0-9_]*\)=.*/\1/p'`: un valor multilínea solo puede añadir nombres falsos (y válidos, así que el `unset` es inocuo), nunca ocultar uno real. `docker.sh` lo comprueba exportando `MISE_DATA_DIR`, `MISE_CACHE_DIR`, `MISE_ENV` y `MISE_SHIMS_DIR` del "host" en los contenedores.
- Para la sesión de H0.1b (`mise en`/`exec`), parte de `ditto_mise`: el proceso hijo hereda las `MISE_*` de mise, y #4 debe comprobar cuáles llegan a la subshell.

## Versión de mise fijada

**mise `2026.10.15`** (publicada el 2026-10-19). No se fija la `2026.10.17` porque salió el mismo día del spike: mise publica casi a diario y conviene dejar unos días de margen.

| Asset | sha256 |
|---|---|
| `mise-v2026.10.15-linux-x64-musl` | `5daa5f70c1588bb27ffecb275b46dbafcab0f6fc93a893138ba4d8cae6074b60` |
| `mise-v2026.10.15-linux-arm64-musl` | `823b94a7425c4781d475357cb2064bfafddc13cf66b7f2927b65d96f49bbe73c` |
| `mise-v2026.10.15-macos-arm64` | `826c4833fa7437a63f6027b86bc10c8b61b1163dc793c03ecde92f68ad167890` |
| `mise-v2026.10.15-macos-x64` | `ea45cc6e787d412deb8e069eec57875c71863e33a36acf69dd59791c27c9c073` |
| `mise-v2026.10.15-linux-x64` (glibc, no usado) | `e3b186d4c70627f27037be615becaf4acfb30e41fb6a1819486717dc94e4e2a9` |
| `mise-v2026.10.15-linux-arm64` (glibc, no usado) | `3abbaac305a465ef038eb4ea07b961c037a8b639108005e43f8e2c00a8f67c11` |

Origen: `SHASUMS256.txt` de la release. Se embeben en `env.sh`, como hará ditto: así una descarga manipulada no puede sustituir también el hash esperado.

En Linux se usa siempre el build **`-musl`** (estático). Funciona en glibc 2.27, 2.28, 2.35 y 2.36 y en Alpine, con un solo asset por arquitectura. El build glibc también arranca en Ubuntu 18.04 (comprobado), pero no aporta nada.

## Aislamiento: variables y mecanismo

`_ditto_mise_isolate` (env.sh; la usan `ditto_mise` y `ditto_mise_env`) exporta, **solo para el proceso de mise**, tras borrar las `MISE_*` heredadas:

| Variable | Valor | Motivo |
|---|---|---|
| `MISE_DATA_DIR` | `.ditto/mise` | `installs/`, `downloads/`, `plugins/`, `shims/` |
| `MISE_CACHE_DIR` | `.ditto/mise/cache` | |
| `MISE_STATE_DIR` | `.ditto/mise/state` | confianza, `incomplete-installs` |
| `MISE_TMP_DIR` | `.ditto/mise/tmp` | |
| `MISE_CONFIG_DIR` | `.ditto/mise` | |
| `MISE_GLOBAL_CONFIG_FILE` | `.ditto/mise/config.toml` | única config global; desactiva `config.override.toml` |
| `MISE_GLOBAL_CONFIG_ROOT` | `.ditto/mise` | `config_root` de la global (por defecto `$HOME`) |
| `MISE_SYSTEM_CONFIG_DIR`, `MISE_SYSTEM_DATA_DIR` | `.ditto/mise/system` | no leer `/etc/mise` ni `/usr/local/share/mise` |
| `MISE_SYSTEM_CONFIG_FILE` | `.ditto/mise/system/config.toml` (no existe) | |
| `MISE_CEILING_PATHS` | `.ditto` | no sube a buscar `mise.toml`/`.tool-versions`/`.miserc.toml` del workspace |
| `MISE_IGNORED_CONFIG_PATHS` | `<HOME real>/.config/mise` | defensa adicional |
| `MISE_TRUSTED_CONFIG_PATHS` | `.ditto/mise` | confianza por ruta: sin prompt ni escritura de estado fuera |
| `MISE_YES=1`, `MISE_AUTO_INSTALL=0`, `MISE_NOT_FOUND_AUTO_INSTALL=0` | | no interactivo |
| `MISE_DISABLE_UPDATE_WARNING=1`, `MISE_SELF_UPDATE_AUTO=0` | | sin comprobación de versión de mise |
| `MISE_USE_VERSIONS_HOST_TRACK=0` | | **telemetría**: por defecto mise envía tool+versión+OS a mise-versions.jdx.dev tras cada instalación |
| `MISE_EXPERIMENTAL=1` | | backend `conda` |
| `MISE_LOCKFILE=1` | | mantiene `mise.lock` existente |

Además, `ditto_mise` ejecuta mise con `cwd=.ditto/mise` y, **solo en su entorno**, `HOME=.ditto/mise/home`, `XDG_{CACHE,CONFIG,DATA,STATE}_HOME` bajo ella y `TMPDIR=.ditto/mise/tmp`. Con `DITTO_MISE_ISOLATE_HOME=0` se desactiva para reproducir la fuga.

Descargas propias (bootstrap de mise, prueba 5): solo URLs `https://`. Con curl se usa `--proto '=https' --tlsv1.2`; con GNU wget, `--https-only` (si `wget --help` lo anuncia). busybox wget (Alpine) no tiene esa opción, así que ahí solo protegen la comprobación de la URL y el sha256.

El lockfile vive junto a la config global (`.ditto/mise/mise.lock`) y se genera con **`mise lock --global`**: un `mise lock` normal responde *"No tools configured to lock in this project"*.

## Backend por componente

| Componente | Backend | Versión | Resultado |
|---|---|---|---|
| Neovim (glibc ≥ 2.31, macOS) | `aqua:neovim/neovim` | 0.12.6 | OK |
| Neovim legacy (glibc < 2.31) | `github:neovim/neovim-releases` | 0.12.5 | OK en glibc 2.27 (Ubuntu 18.04, amd64 y arm64) y 2.28 (Rocky 8 arm64). Va una versión por detrás del oficial. Sin build para macOS |
| Neovim en musl | — | — | No hay build. `source=host/path` |
| ripgrep | `github:BurntSushi/ripgrep` | 15.2.0 | OK. **No `aqua:`**: el registro de aqua elige el asset `aarch64-unknown-linux-gnu` también en musl, y no arranca en Alpine arm64 |
| fd | `aqua:sharkdp/fd` | 10.5.0 | OK (aqua elige `-musl` en musl) |
| fzf | `aqua:junegunn/fzf` | 0.74.5 | OK (Go estático) |
| lazygit | `aqua:jesseduffield/lazygit` | 0.66.2 | OK (Go estático) |
| tree-sitter CLI | **`conda:tree-sitter-cli`** (conda-forge) | 0.27.1 | OK en glibc 2.27+ y macOS. El lock incluye `conda_deps` (libgcc, libgomp, `_openmp_mutex`) con sha256. **No `aqua:`/`github:`**: ver *tree-sitter y glibc* |
| tree-sitter en musl | — | — | conda-forge no publica builds musl. `source=host/path` |
| OpenCode | `github:anomalyco/opencode` | 1.19.3 | OK. El backend `github:` elige `-musl` por sí solo en musl. `aqua:anomalyco/opencode` no lo hace (instala el build glibc en Alpine) |
| OpenCode `-baseline` | mismo, con `platforms.linux-x64 = { asset_pattern = "opencode-linux-x64-baseline[-musl].tar.gz" }` | 1.19.3 | OK. Lo genera `ditto_write_config` si x86_64 no tiene AVX2 (caso del amd64 emulado) |

**Variante por plataforma:** las opciones por plataforma de mise (`platforms.<os>-<arch>.*`) no distinguen libc ni CPU. ditto debe elegir la variante (glibc legacy, musl, baseline) al **generar** `config.toml` en cada host, como hace `ditto_write_config`. En `mise.lock` las opciones forman parte de la entrada: un mismo lock guarda a la vez la entrada normal y la `-baseline` de OpenCode (comprobado). Las claves de plataforma del lock incluyen `linux-x64-musl` y `linux-arm64-musl`.

### tree-sitter y glibc

glibc máxima requerida por el binario Linux de upstream (`strings | grep GLIBC_`), confirmada al ejecutarlo:

| Versión | x64 | arm64 |
|---|---|---|
| 0.25.3 – 0.25.10 | 2.34 | 2.29 |
| 0.26.1 – 0.27.1 (también `tree-sitter-cli-linux-x64.zip`) | **2.39** | **2.39** |

En Ubuntu 22.04 arm64: `version 'GLIBC_2.39' not found`. En Ubuntu 18.04, el 0.25.10 de GitHub tampoco arranca (`GLIBC_2.28`/`2.29`). `conda:tree-sitter-cli@0.27.1` arranca en todas las glibc probadas.

## Resultados por plataforma

Pruebas de `run.sh` (numeración del issue): T1 bootstrap + sha256 · T2 directorios y config cargada · T3 instalación desde config + lock y ejecución de cada binario · T4 Neovim legacy · T5 descarga manual + `mise link` sin red · T6 `install --locked` sin red, 0 peticiones HTTP · T7 nada fuera de `.ditto/` · T8 mise del host.

| Plataforma | Cómo | libc | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| macOS arm64 (Darwin 25.2) | host, `macos.sh` | — | ✅ | ✅ | ✅ 7/7 | n/a | ✅ | ✅ | ✅ (+ `$HOME` real) | ✅ | 31 PASS |
| Ubuntu 18.04 amd64 | Docker, emulado | glibc 2.27 | ✅ | ✅ | ✅ 7/7 | ✅ legacy 0.12.5; oficial falla (`GLIBC_2.28`) | ✅ | ✅ | ✅ | ✅ | 30 PASS |
| Ubuntu 18.04 arm64 | Docker, nativo | glibc 2.27 | ✅ | ✅ | ✅ 7/7 | ✅ legacy; oficial falla (`GLIBC_2.29`) | ✅ | ✅ | ✅ | ✅ | 30 PASS |
| Ubuntu 22.04 amd64 | Docker, emulado (sin AVX2 → OpenCode baseline) | glibc 2.35 | ✅ | ✅ | ✅ 7/7 | n/a | ✅ | ✅ | ✅ | ✅ | 30 PASS |
| Ubuntu 22.04 arm64 | Docker, nativo | glibc 2.35 | ✅ | ✅ | ✅ 7/7 | n/a | ✅ | ✅ | ✅ | ✅ | 30 PASS |
| Alpine 3.20 amd64 | Docker, emulado | musl | ✅ | ✅ | ✅ 5/7 (nvim y tree-sitter SKIP) | n/a | ✅ | ✅ | ✅ | ✅ | 26 PASS, 4 SKIP |
| Alpine 3.20 arm64 | Docker, nativo | musl | ✅ | ✅ | ✅ 5/7 (ídem) | n/a | ✅ | ✅ | ✅ | ✅ | 26 PASS, 4 SKIP |
| Rocky 8 arm64 (extra) | Docker, nativo | glibc 2.28 | ✅ | ✅ | ✅ 7/7 | ✅ legacy; oficial falla (`GLIBC_2.29`) | ✅ | ✅ | ✅ | ✅ | 0 FAIL |
| Debian 12 arm64 (extra) | Docker, nativo | glibc 2.36 | ✅ | ✅ | ✅ 7/7 | n/a | ✅ | ✅ | ✅ | ✅ | 0 FAIL |

Comandos:

```sh
# macOS (HOME/TMPDIR desechables; nada en el $HOME real)
DITTO_SPIKE_WATCH_EXCLUDE='<ruido ajeno en /tmp, si lo hay>' sh spikes/h0.1-mise-aislado/macos.sh "$SCRATCH/mac"
# Linux (online + offline --network none). Los contenedores corren como root:
# en un host Linux, <workdir> queda con archivos de root (borrar con
# `docker run --rm -v <workdir>:/w alpine rm -rf /w/ws` o sudo).
sh spikes/h0.1-mise-aislado/docker.sh ubuntu-18.04 amd64 "$SCRATCH/u18-amd64"
sh spikes/h0.1-mise-aislado/docker.sh alpine-3.20 arm64 "$SCRATCH/alpine-arm64"
# Lock (requiere red y la API de GitHub)
sh spikes/h0.1-mise-aislado/gen-lock.sh "$SCRATCH/lock"
```

Detalle de cada prueba:

- **T1:** `ditto_mise_bootstrap` descarga el asset, compara con el sha256 embebido y solo entonces lo mueve a `.ditto/mise/bin/mise`. `mise --version` = `2026.10.15`.
- **T2:** en `mise doctor` todos los `dirs` (cache, config, data, shims, state) quedan bajo `.ditto/mise`. `mise config ls` muestra solo `.ditto/mise/config.toml`.
- **T3:** instalación de los 7 componentes en ~2,5 s en macOS (~9 s en amd64 emulado). Cada binario se ejecuta (`--version`) con `HOME`/`XDG_*` dentro de `.ditto/smoke-home`, para no confundir las escrituras de las herramientas (H0.2/H0.4) con las de mise.
- **T4:** en glibc < 2.31 la config generada usa `github:neovim/neovim-releases`. Además se instala el oficial para demostrar que falla.
- **T5:** se descarga a mano el tarball de ripgrep de la URL del lock y se verifica contra su `checksum`. En la fase offline, `mise link -f github:BurntSushi/ripgrep@15.2.0-path <dir>` y `mise where` devuelven `installs/github-burnt-sushi-ripgrep/15.2.0-path` (enlace al directorio), y el `rg` enlazado arranca. Sin peticiones HTTP.
- **T6:** `mise.lock` con checksums para `linux-x64`, `linux-arm64`, `linux-x64-musl`, `linux-arm64-musl`, `macos-x64` y `macos-arm64` (48 entradas de plataforma con `checksum`, más 12 paquetes conda de dependencias; la legacy de Neovim no tiene macOS). Cada ejecución es una reinstalación desde el lock en un `.ditto/` limpio, y `install --locked` no reescribe el lock. Con la red cortada (`--network none` en Linux; proxy muerto `127.0.0.1:9` en macOS) y `MISE_LOG_HTTP=1`, `install --locked` y `which` terminan bien con **0 peticiones**.
- **T7:** `find $HOME <ruta real de /tmp> $TMPDIR -newer <marker>` antes/después de cada fase: vacío en todas las plataformas. Exclusiones: las propias raíces vigiladas, todo lo que está bajo `<dest>/` (comparación literal de prefijo) y, **solo si `DITTO_SPIKE_HOST_MISE=1`**, el fixture del mise del host (`~/.config/mise`, `~/.local/share/mise`, `~/.local/bin/mise` y sus padres), que T8 verifica por hash. El ruido ajeno se pasa por entorno (`DITTO_SPIKE_WATCH_EXCLUDE`, sin valor por defecto); en el Mac de desarrollo solo hizo falta excluir el directorio de tareas del agente que ejecutaba el spike (`/private/tmp/claude-501/…/tasks`).
  **Alcance en macOS:** además, `macos.sh` barre **todo** el `$HOME` real (`find "$HOME" -newer <marker>`, saltando lo que no se puede leer por TCC). Cualquier ruta que contenga mise, sigstore, aqua, conda, nvim, neovim, opencode, lazygit, tree-sitter, ripgrep o fzf es FAIL; resultado: ninguna. El resto se lista para revisión manual en `<scratch>/real-home-new.txt`. En la última ejecución hubo 11 rutas, todas de procesos ajenos activos a la vez: `.vscode-server`, `.colima/_lima/…/diffdisk` (la VM de Docker), `.hermes/…` y una base de datos de `apps/open-notebook`. Exclusiones extra por entorno: `DITTO_SPIKE_REAL_HOME_EXCLUDE`. *Control positivo:* con `DITTO_MISE_ISOLATE_HOME=0` y tree-sitter por `aqua:` (sin lock), T7 sí detecta `~/Library/Caches/dev.sigstore.sigstore-rust/…` (macOS) y `/root/.cache/sigstore-rust/tuf/…` (Ubuntu 22.04). Con aislamiento, esa caché queda en `.ditto/mise/home/.cache/sigstore-rust`. Con lock (checksum + provenance ya registrados) no se repite la verificación y no hay fuga ni sin aislar `HOME`.
- **T8:** antes del marker se crean un `~/.local/bin/mise`, un `~/.config/mise/config.toml` (con `[tools]` fzf 0.50.0, `[env]` con marcador y `[settings]`) y un `<workspace>/mise.toml` (fd 9.0.0 y otro marcador). Con y sin aislamiento de `HOME`, el mise aislado no los lista en `config ls`, no exporta los marcadores en `mise env` y no muestra esas versiones en `ls`. El hash de `~/.config/mise` y `~/.local/share/mise` no cambia. En Docker, además, los contenedores arrancan con `MISE_DATA_DIR`, `MISE_CACHE_DIR`, `MISE_ENV` y `MISE_SHIMS_DIR` del "host" exportados; T2 y T7 siguen en verde porque el aislamiento las borra.

### Hallazgos adicionales

- **mise sin aislar escribe en `$HOME` incluso con `--version`:** crea `~/.local/state/mise/incomplete-installs/.migrated` y `~/Library/Caches/mise/latest-version.releases-v1`, y consulta la última versión por red. Ocurrió aquí con el primer `mise --version` del spike, antes de aislarlo (ver *Pendientes*).
- **Alpine:** el build `-musl` de OpenCode enlaza dinámicamente `libstdc++.so.6` y `libgcc_s.so.1`. Sin `apk add libstdc++ libgcc` falla (`Error loading shared library libstdc++.so.6`). `docker.sh` los instala; `DITTO_SPIKE_ALPINE_BARE=1` reproduce el fallo.
- **Alpine, versiones de `apk`:** 3.20 → neovim 0.10.0, tree-sitter-cli 0.22.5; 3.21 → 0.10.4 / 0.24.4; 3.22 → 0.11.1 / 0.25.10. Ninguna cumple Neovim ≥ 0.11.2.
- **Tamaño de `.ditto/`** (Ubuntu 22.04 amd64): ~500 MB en total; `installs/` 265 MB, `cache/` 82 MB (archivos descargados). `mise prune`/limpiar caché es tarea de `update`.
- **Rutas para wrappers:** `mise which <bin>` da la ruta absoluta dentro de `installs/<tool>/<versión>/…`; la estructura interna varía por backend (`nvim-linux-x86_64/bin/nvim`, `.mise-bins/tree-sitter` en conda…). ditto debe usar `which`, no construir la ruta.
- mise crea `.ditto/mise/shims/` al instalar aunque no se usen. Está dentro de `.ditto/`, así que no es un problema.

## Pendientes (no cubiertos aquí)

- [ ] **x86_64 real con AVX2**: el amd64 de Docker es emulado y no expone AVX2, así que solo se ejecutó el build `-baseline` de OpenCode. Comprobar el build normal en un servidor real:
  `sh spikes/h0.1-mise-aislado/run.sh /tmp/ditto-h01 all`. `DITTO_SPIKE_HOST_MISE=1` escribe un mise falso en `$HOME`: `run.sh` lo rechaza salvo con `DITTO_SPIKE_DISPOSABLE_HOME=1` o un `HOME` bajo `<dest>`.
- [ ] **macOS x64 (Intel):** sin hardware. Mismo comando con `macos.sh`.
- [ ] **Servidores reales** del usuario (glibc, CPU, red/proxy): `sh run.sh <dir> online` y después `sh run.sh <dir> offline` con la red cortada (o `DITTO_SPIKE_OFFLINE=proxy`).
- [ ] **Limpieza en el `$HOME` del Mac de desarrollo**, de la primera prueba sin aislar (2026-10-21 21:13; no hay mise del host instalado): `rm -rf ~/.local/state/mise ~/Library/Caches/mise`.
- [ ] Llevar la decisión a arch.md y roadmap.md con `/record-decision` (no se editan en esta story).

## Conclusión

Según el *Criterio de decisión* del issue, las pruebas 2–8 **pasan** en todas las plataformas probadas → **se adopta mise**, con estas condiciones:

- aislamiento = `MISE_*` + `HOME`/`XDG_*`/`TMPDIR` solo en el proceso mise + `cwd=.ditto/mise`;
- tree-sitter CLI desde conda-forge;
- ripgrep y OpenCode con el backend `github:`;
- variante (legacy/musl/baseline) elegida por ditto al generar `config.toml`.

Fallo parcial (anotado como riesgo, sin provider propio): **musl no tiene Neovim ni tree-sitter CLI** desde ningún backend de mise. En Alpine el stack de Neovim solo es posible con `source=path:` (binario aportado). El resto (rg, fd, fzf, lazygit, OpenCode) sí funciona. No se evalúa aqua ni un provider propio: el problema es que upstream no publica builds musl, no del gestor.

## Decisión propuesta (texto para arch.md, vía `/record-decision`)

### §2 Decisiones clave — fila "Obtención de binarios"

> | Obtención de binarios | **mise `2026.10.15`** (fijado; sha256 por asset embebido en ditto; build `-musl` estático en Linux), totalmente aislado en `.ditto/mise/`: se borran las `MISE_*` heredadas del host (salvo `MISE_GITHUB_TOKEN`) y se fijan `MISE_DATA_DIR`, `MISE_CACHE_DIR`, `MISE_STATE_DIR`, `MISE_TMP_DIR`, `MISE_CONFIG_DIR`, `MISE_GLOBAL_CONFIG_FILE`, `MISE_GLOBAL_CONFIG_ROOT`, `MISE_SYSTEM_CONFIG_{DIR,FILE}`, `MISE_SYSTEM_DATA_DIR`, `MISE_CEILING_PATHS`, `MISE_TRUSTED_CONFIG_PATHS`, sin telemetría (`MISE_USE_VERSIONS_HOST_TRACK=0`) ni avisos de actualización; además `HOME`/`XDG_*`/`TMPDIR` → `.ditto/mise/home` **solo en el proceso de mise** (la caché TUF de sigstore ignora `MISE_CACHE_DIR`) y `cwd=.ditto/mise`. Lock con `mise lock --global` en `.ditto/mise/mise.lock`. Validado en H0.1 (macOS arm64; Ubuntu 18.04/22.04, Rocky 8, Debian 12, Alpine 3.20) |

### §6 Backends (sustituye la tabla y quita *(spike H0.1)*)

> ## 6. Backends
>
> Aplican a la categoría A y a los seleccionables cuando se resuelven con origen ditto. Validados en H0.1. Las opciones por plataforma de mise (`platforms.<os>-<arch>`) no distinguen libc ni CPU: **ditto elige la variante al generar `config.toml`** en cada host. El `mise.lock` compartido guarda una entrada por combinación de opciones y tiene claves `linux-*-musl`.
>
> | Componente | Backend mise | Notas |
> |---|---|---|
> | Neovim | `aqua:neovim/neovim`; `github:neovim/neovim-releases` si glibc < 2.31 | El oficial 0.12.6 exige `GLIBC_2.28` (x64) / `2.29` (arm64). El legacy funciona en 2.27 y suele ir una versión por detrás. Sin build musl → `source=host\|path`. LazyVim exige ≥ 0.11.2 |
> | ripgrep | `github:BurntSushi/ripgrep` | `aqua:` elige el build gnu en linux-arm64 incluso en musl |
> | fd, fzf, lazygit | `aqua:` | fd: aqua elige `-musl` en musl; fzf/lazygit son Go estático |
> | tree-sitter CLI | `conda:tree-sitter-cli` (conda-forge) | Upstream (aqua/github) exige glibc ≥ 2.39 desde 0.26 (2.34 en x64 para 0.25.x). conda-forge funciona en 2.27; el lock fija también sus dependencias conda. Sin build musl → `source=host\|path`. Requiere `MISE_EXPERIMENTAL=1` |
> | OpenCode | `github:anomalyco/opencode` | `github:` elige `-musl` en musl (`aqua:` no). Sin AVX2 → ditto añade `platforms.linux-x64.asset_pattern = "opencode-linux-x64-baseline[-musl].tar.gz"`. En musl necesita `libstdc++` y `libgcc` del host |
> | Node, Go, Python/uv | `core:node`, `core:go`, `core:python` / `aqua:astral-sh/uv` | Sin validar en H0.1. Solo si `auto` no encuentra uno válido en el host o `source=ditto`. Para Mason y MCPs; no visibles en la subshell (§8) |

### §18 Riesgos abiertos (añadir / sustituir)

> - **Dependencia de mise**: versión fijada (`2026.10.15`; publica casi a diario) y actualización deliberada. Cada subida repite `spikes/h0.1-mise-aislado/run.sh` en la matriz, porque el aislamiento depende de comportamientos no documentados (p. ej. la caché TUF de sigstore fuera de `MISE_CACHE_DIR`). La interfaz `Installer` permite reemplazarlo.
> - **musl (Alpine)**: no hay build de Neovim ni del CLI de tree-sitter en ningún backend, y los de `apk` no llegan (Alpine 3.22: nvim 0.11.1 < 0.11.2). En musl el stack de Neovim solo funciona con `source=path:`; OpenCode `-musl` necesita `libstdc++`/`libgcc` del host. Decidir si Alpine queda soportado solo para las herramientas CLI.
> - **tree-sitter CLI desde conda-forge**: depende de un segundo origen (`conda.anaconda.org`) y del sysroot que use conda-forge. Si sube su glibc mínima o deja de publicar, queda `path:` (o compilar con `cargo:`, que exige Rust y `cc`).
> - **Glibc mínima real**: el oficial de Neovim pide 2.28/2.29; el legacy, el CLI de tree-sitter (conda) y mise (musl) funcionan en 2.27. Sigue pendiente la glibc de los binarios que descarga **Mason** (H0.5) y el inventario de servidores.
> - **CPU sin AVX2**: el build normal de OpenCode no se pudo ejecutar (el amd64 emulado no tiene AVX2); el `-baseline` sí. Validar en x86_64 real.
> - **Lockfile por variante**: el lock solo contiene las variantes con las que se generó. `ditto update` debe regenerarlo con todas las configs posibles (normal, baseline glibc, baseline musl) y `mise lock` sin token topa con el límite de 60 req/h de la API de GitHub: aceptar `GITHUB_TOKEN`/`MISE_GITHUB_TOKEN` del entorno (nunca guardarlo).
> - **Telemetría de mise**: por defecto envía herramienta, versión y OS a mise-versions.jdx.dev tras cada instalación; ditto lo desactiva (`MISE_USE_VERSIONS_HOST_TRACK=0`) y debe vigilar nuevas opciones de este tipo al subir de versión.

### Ajustes menores sugeridos en otras secciones

- **§4 Layout:** dentro de `.ditto/mise/` aparecen también `home/` (HOME del proceso mise), `tmp/`, `downloads/`, `shims/` (no usados) y `system/` (vacío). `mise.lock` está junto a `config.toml` porque es el lock de la config global.
- **§5 `internal/installer`:** la lista de variables de §2 más `HOME`/`XDG_*`/`TMPDIR` solo en el proceso mise; `Where` = `mise which <bin>` (la estructura de `installs/` varía por backend); `Link` = `mise link -f <tool>@<ver>-path <dir>` (comprobado sin red).
- **§7 Fallback de glibc:** el paso 2 (legacy en 2.27) queda validado; el umbral 2.31 es conservador (el oficial pide 2.28 en x64 y 2.29 en arm64).
