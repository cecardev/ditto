# H0.4 — Escrituras fuera de `.ditto/`: resultados

**Issue:** #6 · **Fecha:** 2026-10-22 · **Base:** H0.1 (#1), H0.2 (#2) y H0.3 (#5), reutilizados sin modificarlos · **Estado:** sesión completa en verde en macOS arm64 y Ubuntu 22.04 arm64 (nativo) y amd64 (emulado, solo OpenCode). Con los mecanismos propuestos no escapa nada fuera de `.ditto/` salvo cuatro excepciones documentadas (ver *Clasificación*). Tras borrar el workspace no queda nada atribuible a ditto.

## Pregunta

En una sesión real con LazyVim + OpenCode, ¿qué se escribe fuera de `.ditto/`?

**Respuesta corta:** con los wrappers tal como los dejaron H0.2 y H0.3 escapan **dos** cosas evitables, y las dos se cierran con una variable en un wrapper:

1. `~/.npm/` (`_npx/`, `_logs/`, `_cacache/tmp/`, `_update-notifier-last-checked`): `npx` de los MCPs locales de OpenCode. Se evita con `npm_config_cache=$DITTO_ROOT/cache/npm` en el wrapper de OpenCode (y en el de nvim, para los paquetes npm de Mason).
2. `$TMPDIR/lazygit-<uid>/` (o `/tmp/lazygit-<uid>/` en Linux): lazygit, tanto suelto como desde LazyVim. Se evita con `TMPDIR=$DITTO_ROOT/tmp` en el wrapper de lazygit.

Lo demás que aparece fuera de `.ditto/` es trabajo del usuario en su proyecto (el archivo editado, el índice de git), temporales que se borran solos (sockets de nvim en `$XDG_RUNTIME_DIR`), una caché de OpenCode dentro de `<repo>/.git/` y el historial de un shell que el usuario abre a mano con su propio rc. Se documentan como excepciones (§18).

## Contenido del directorio

| Archivo | Para qué |
|---|---|
| `run.sh <dest> [full\|opencode]` | Instantánea → instalación → sesión A (wrappers actuales) → sesión B (mecanismos propuestos) → borrado del workspace, con una instantánea entre cada paso y sus diffs. Exige `DITTO_SPIKE_DISPOSABLE_HOME=1` (escribe fixtures en `$HOME`). |
| `lib.sh` | Carga `../h0.3-aislamiento-lazyvim/lib.sh` (que carga `../h0.1-mise-aislado/env.sh`). Añade: instantáneas (`h04_snap`, `h04_diff`), descargas fijadas con sha256 (Node.js; StyLua y registro de Mason para la verificación cruzada), OpenCode en la config de mise con el lock de H0.1, su wrapper con las variables de H0.2, la copia del starter con Mason activo y `h04_apply_proposed`. |
| `macos.sh <scratch>` | Driver macOS: `env -i`, `HOME`/`TMPDIR` desechables bajo una ruta corta, simula Terminal.app y barre el `$HOME` real en solo lectura. |
| `docker.sh <work> [arm64\|amd64] [full\|opencode]` | Driver Linux: Ubuntu 22.04, usuario no root limpio (`dev`, `HOME` vacío), `XDG_RUNTIME_DIR=/run/user/1000` como en un login con systemd, `strace` e `inotifywait`. |
| `lua/session.lua` | La parte de Neovim del guion, dentro del nvim real (TUI) en un pty. |
| `oc-session.sh` | La parte de OpenCode del guion, tecleada en la sesión. |
| `strace-writes.awk` | Extrae del `strace -f -y` las llamadas de escritura con éxito y las resuelve a rutas absolutas. |
| `starter/spike-h04.lua` | Sustituye a `spike-offline.lua` de H0.3 en la copia del starter: Mason activo con el registro fijado y sin instalaciones automáticas. |
| `fake-mcp/` | MCP local falso que OpenCode lanza con `npx` desde una carpeta local (sin descargar paquetes): guarda su entorno y sale. |

## Método

- **Nada se ejecuta con el `$HOME` real.** macOS: `env -i HOME=<scratch>/home TMPDIR=<scratch>/tmp PATH=/usr/bin:/bin:/usr/sbin:/sbin`, con `<scratch>` = `/tmp/h04` (ruta corta: H0.3, *Rutas largas*). El `$HOME` real y los directorios por usuario de macOS solo se leen (`find`). Linux: contenedor desechable con el usuario `dev`.
- **Fixtures del usuario** en el `HOME` desechable: `~/.gitconfig`, `~/.config/git/{config,ignore}`, `~/.bashrc` y `~/.zshrc` (este con `HISTFILE=$HOME/.zsh_history`, como es habitual). Proyecto: `<ws>/proj`, un repo git con un `opencode.json` que declara dos MCPs locales falsos (`sh` y `npx`) y deniega `bash`, `edit` y `webfetch` al agente.
- **Instantáneas:** por cada raíz, una línea `ruta  tipo  tamaño  mtime` (`find -xdev`, sin seguir enlaces), ordenada, más el sha256 del listado (`snap/<Sn>.hashes`). Se excluyen `.ditto/` y el directorio de resultados del spike. Raíces:
  - Linux: todo el sistema de archivos del contenedor (`/`, sin `/proc`, `/sys`, `/dev`).
  - macOS: `HOME` y `TMPDIR` desechables, el workspace fuera de `.ditto`, `/private/tmp`, `/private/var/tmp`, `DARWIN_USER_TEMP_DIR` y `DARWIN_USER_CACHE_DIR` (estos cuatro, compartidos con el resto del sistema, con profundidad 3).
- **Además, en Linux:** `strace -f -qq -y -e trace=file,fchdir,clone,clone3,fork,vfork` sobre toda la sesión (solo arm64: ptrace no funciona bajo qemu-user) e `inotifywait -m -r` sobre `/tmp`, `/var/tmp`, `$HOME` y `/run/user/1000` (ve también lo que se crea y se borra durante la sesión). `strace-writes.awk` une por pid las llamadas partidas (`<unfinished ...>` / `<... resumed>`), resuelve las rutas relativas con el dirfd o el cwd decodificados por `-y` y cuenta `open*` con escritura, `mkdir*`, `rename*`, `unlink*`, `rmdir`, `(sym)link*`, `truncate`, `utimensat`, `chmod`/`fchmodat(2)`, `chown`/`fchownat`, `mknod*` y `(l)setxattr`/`(l)removexattr`. **Límite:** la creación de sockets Unix (`bind`) no es una llamada de la clase `file`; esos sockets se ven en `inotifywait` y en su `unlink`.
- **Guion de la sesión** (en un pty, con el driver `lua/pty.lua` de H0.3), desde `.ditto/shell/session` (sustituto de `ditto up`):
  1. `nvim --headless '+Lazy! restore' +qa` (los plugins del `lazy-lock.json` de H0.3 más los dos de Mason).
  2. `nvim --headless '+Lazy! load mason.nvim' '+MasonInstall stylua@v2.6.0' +qa` (registro de Mason fijado a la release `2026-10-22-ill-fund`).
  3. `nvim` (TUI real) con `lua/session.lua`: editar `hello.lua`, formatearlo con conform + el `stylua` de Mason y guardarlo; `:!git status`; `:terminal`; terminal de Snacks; lazygit (`Snacks.lazygit`). Los dos terminales guardan su `env`.
  4. `oc-session.sh`: `opencode --version`, `debug paths`, `models` (catálogo de models.dev), `mcp list` (lanza los dos MCPs falsos), `serve` 8 s y `session list`. **Opt-in** (`H04_OC_RUN=1`, desactivado por defecto): una petición corta con `opencode run` y un modelo gratuito de OpenCode Zen (sin credenciales; hasta tres modelos hasta que uno responde). El `opencode.json` del proyecto deniega y desactiva todas las tools (`bash`, `edit`, `write`, `patch`, `webfetch`, `read`, `glob`, `grep`, `list`, `task`, `todo*`): el agente solo puede contestar texto.
  5. `opencode` (TUI) durante 20 s; se sale con ctrl+c.
  6. `lazygit` suelto; se sale con `q`.
  7. Un shell anidado abierto a mano (`"$SHELL" -i`), un comando y `exit`.
  8. `exit` de la subshell.
- **Fases:** A = wrappers de H0.2/H0.3 sin cambios; B = `h04_apply_proposed` (ver *Decisión propuesta*). `H04_PHASES=B` ejecuta solo B desde cero, para comprobar qué queda tras borrar el workspace con los mecanismos propuestos.
- **Integridad:** mise y herramientas como en H0.1 (sha256 embebido para mise, `install --locked` con el `mise.lock` de H0.1, OpenCode incluido); Node.js 22.23.4 con sha256 embebido (`SHASUMS256.txt` de nodejs.org); plugins por commit (`lazy-lock.json`, más `mason.nvim` v2.3.1 y `mason-lspconfig.nvim` v2.3.0 fijados por commit). Todo lo anterior se verifica **antes** de ejecutarlo. Mason, en cambio, no fija sha256 de lo que descarga (H0.5), así que su instalación se comprueba **a posteriori**: después de la sesión el spike descarga por su cuenta el zip de StyLua y el `registry.json.zip`, los verifica contra el sha256 del campo `digest` de la API de GitHub y compara el binario y el registro que instaló Mason (`*-mason-sha256 PASS` en todas las ejecuciones completas). Ojo: el `digest` y el artefacto vienen de la **misma fuente** (GitHub), así que esto detecta corrupción o un cambio de artefacto respecto al fijado, no un compromiso de la release. Mason ya había ejecutado StyLua (conform) antes de la comprobación.

Comandos:

```sh
# macOS (HOME/TMPDIR desechables bajo /tmp/h04)
sh spikes/h0.4-escrituras/macos.sh /tmp/h04                 # fases A y B
H04_PHASES=B sh spikes/h0.4-escrituras/macos.sh /tmp/h04    # solo mecanismos propuestos
# Linux (Docker)
sh spikes/h0.4-escrituras/docker.sh "$SCRATCH/u22-arm64" arm64 full
H04_PHASES=B sh spikes/h0.4-escrituras/docker.sh "$SCRATCH/u22-arm64-B" arm64 full
sh spikes/h0.4-escrituras/docker.sh "$SCRATCH/u22-amd64" amd64 opencode
```

## Entornos

| Entorno | Detalle | Ejecuciones |
|---|---|---|
| macOS arm64 | macOS 26.2 (Darwin 25.2), zsh 5.9 simulando Terminal.app (`TERM_PROGRAM=Apple_Terminal`, `TERM_SESSION_ID`) | A+B y solo B |
| Ubuntu 22.04 arm64 | Docker (colima, nativo), bash 5.1, usuario `dev` (uid 1000), `XDG_RUNTIME_DIR=/run/user/1000` | A+B y solo B, con `strace` e `inotifywait` |
| Ubuntu 22.04 amd64 | Docker, emulado con qemu-user (CPU sin AVX2 → OpenCode `linux-x64-baseline`), perfil `opencode` | A+B, con `inotifywait` |

Versiones: Neovim 0.12.6, lazygit 0.66.2, OpenCode 1.19.3, mise 2026.10.15, Node.js 22.23.4, StyLua v2.6.0.

## Resultados

Todas las ejecuciones: guion completo (`session-* PASS`), `Lazy! restore` y `MasonInstall` sin errores, StyLua instalado por Mason y usado por conform (`hello.lua` formateado). 0 FAIL salvo los falsos positivos del barrido del `$HOME` real descritos abajo.

Las ejecuciones de la primera ronda incluían la petición con `opencode run` (entonces activada por defecto): respondió `ok` con un modelo gratuito (`cat-jam-free` devolvió a veces `Unexpected server error`; el siguiente respondió) y no añadió ninguna ruta fuera de `.ditto/` distinta de las de la tabla. Tras pasarla a opt-in, la fase B se repitió **sin** la petición (`H04_OC_RUN=0`) en macOS arm64 y Ubuntu 22.04 arm64, con el mismo resultado (ver *Ronda 2*).

Cambios fuera de `.ditto/` por fase (sin contar el ruido de otros procesos en los directorios compartidos de macOS):

| | Instalación (S0→S1) | Sesión A, actual | Sesión B, propuesta | Tras borrar el workspace (solo B, S0→S9) |
|---|---|---|---|---|
| macOS arm64 | nada (solo el mtime del workspace) | `~/.npm/…`, `$TMPDIR/lazygit-<uid>`, `~/.zsh_history` y `~/.zsh_sessions/` (shell anidado), `<repo>/.git/{index,opencode}`, `hello.lua` | `~/.zsh_history` y `~/.zsh_sessions/` (shell anidado), `<repo>/.git/{index,opencode}`, `hello.lua` | `~/.zsh_history`, `~/.zsh_sessions/` |
| Ubuntu 22.04 arm64 | nada | `~/.npm/…`, `/tmp/lazygit-1000/`, `<repo>/.git/{index,opencode}`, `hello.lua`; sockets `/run/user/1000/nvim.<pid>.0` (creados y borrados) | `<repo>/.git/{index,opencode}`, `hello.lua`; sockets en `/run/user/1000` (creados y borrados) | **nada** (solo mtime de `/run/user/1000` y del padre del workspace) |
| Ubuntu 22.04 amd64 (OpenCode) | nada | `~/.npm/…` (incl. `_cacache/tmp/<uuid>`), `<repo>/.git/opencode`; `/tmp/qemu-open.*` (creados y borrados) | `<repo>/.git/opencode`; `/tmp/qemu-open.*` | — |

`strace` (Ubuntu 22.04 arm64) confirma la lista: sesión A, 28 rutas escritas fuera de `.ditto/` (todas de las filas de arriba); sesión B, 4 (`<repo>/.git/index.lock` → `index`, `<repo>/.git/opencode`, el `hello.lua~` temporal de nvim al guardar) y 7 en la ejecución solo-B (más el `unlink` de los sockets de nvim). Ningún `open`/`mkdir`/`rename`/`unlink` en `$HOME`, `/tmp` ni `/var/tmp` en la fase B.

Entorno de los hijos (fase B): `:terminal` y el terminal de Snacks ven el `TMPDIR` del host y **no** ven `npm_config_cache` (lo restaura `.host-sh`); el MCP lanzado con `npx` recibe `npm_config_cache=<ws>/.ditto/cache/npm` (fase A: `~/.npm`).

`$HOME` real del Mac (barrido de solo lectura): ninguna escritura atribuible a la sesión. El filtro por nombres dio falsos positivos por herramientas ajenas que escribían a la vez (otra instalación de npm actualizando su `~/.npm/_cacache`, un repo cuya ruta contiene `mason`): `macos.sh` solo cuenta las entradas de `_cacache` cuya clave nombra el paquete del spike, y `DITTO_SPIKE_REAL_HOME_EXCLUDE` / `DITTO_SPIKE_SNAP_PRUNE` permiten excluir el ruido de cada máquina.

### Red

Lo que el guion contacta **siempre**, también con `H04_OC_RUN=0`:

| Paso | Destino | Qué se envía |
|---|---|---|
| Instalación | `github.com` / `objects.githubusercontent.com` (mise, herramientas, OpenCode), `nodejs.org` (Node.js) | Descargas fijadas (sha256) |
| `Lazy! restore` | `github.com` | `git clone` de los plugins del lock |
| `MasonInstall` | `api.github.com` (versiones), `github.com` (registro y StyLua) | Descargas; Mason no envía datos del proyecto |
| `opencode models`, TUI, `serve` | `models.dev` (catálogo de modelos; `OPENCODE_DISABLE_AUTOUPDATE=1` evita la consulta de versiones) | Petición del catálogo |
| `npx` del MCP falso (fase A) | `registry.npmjs.org` (aviso de actualización de npm; en B se desactiva con `npm_config_update_notifier=false`) | Consulta de la versión de npm. El paquete del MCP es una carpeta local |
| Comprobación de Mason | `github.com`, `api.github.com` | Descargas |

No se capturó el tráfico (sin proxy): la tabla sale del código de H0.2 y de lo que muestran los logs. Que la TUI o `serve` no contacten otros hosts de OpenCode (`opencode.ai`) sin una petición **no está verificado**: queda en *Pendientes*.

Solo con `H04_OC_RUN=1`: `opencode run` envía a OpenCode Zen (`opencode.ai`) el prompt (`Responde solo con la palabra: ok`), el system prompt de OpenCode con datos del entorno (directorio de trabajo `<ws>/proj`, plataforma, fecha, que es un repo git y, según la versión, un listado de los archivos del proyecto de prueba: `README.md`, `opencode.json`, `hello.lua`) y el nombre de las tools disponibles (ninguna, con el `opencode.json` del spike). No se envía ningún archivo del usuario: el `HOME` y el proyecto son desechables.

### Ronda 2 (correcciones de la revisión, fase B, `H04_OC_RUN=0`)

Con todos los wrappers regenerados con la lista ampliada de `DITTO_ORIG_*`, `npm_config_update_notifier=false` y `mkdir -p "$TMPDIR"` antes del `exec` en lazygit y OpenCode, y sin `opencode run`:

| | Sesión B (S1→S2) | Tras borrar el workspace (S0→S9) |
|---|---|---|
| macOS arm64 | `~/.zsh_history` y `~/.zsh_sessions/` (shell anidado), `<repo>/.git/{index,opencode}`, `hello.lua`; mtime de directorios compartidos | `~/.zsh_history`, `~/.zsh_sessions/`; mtime de `/private/tmp`, `/private/var/tmp` y `DARWIN_USER_TEMP_DIR` (las entradas nuevas que hay en ellos son de otros procesos y de los `docker build` del spike) |
| Ubuntu 22.04 arm64 | `<repo>/.git/{index,opencode}`, `hello.lua`; sockets en `/run/user/1000` (creados y borrados) | **nada** (mtime de `/run/user/1000` y del padre del workspace) |

`strace` de la sesión B: 9 rutas, todas en `<repo>/` o el `unlink` de los sockets de nvim. Ni `~/.npm` ni `_update-notifier-last-checked` en ninguna de las dos. `:terminal` y el terminal de Snacks ven el `TMPDIR` del host y ninguna variable `npm_config_*`. `Lazy! restore`, `MasonInstall` y la verificación cruzada de Mason: sin errores, `PASS`.

## Clasificación de las rutas

| Ruta | Quién | Dónde | Clasificación | Mecanismo / decisión | Evidencia |
|---|---|---|---|---|---|
| `~/.npm/_npx/`, `_logs/`, `_cacache/tmp/`, `_update-notifier-last-checked` | `npx` de un MCP local de OpenCode | macOS, Linux | **Evitable** | `npm_config_cache=$DITTO_ROOT/cache/npm` en el wrapper de OpenCode. npm guarda sus logs y el aviso de actualización dentro de la caché, así que todo se mueve. Además `npm_config_update_notifier=false` (sin consulta a `registry.npmjs.org` ni marca de última comprobación) | A vs B en las tres plataformas; entorno del MCP |
| `~/.npm/…` desde Mason (paquetes npm: pyright, prettier…) | Mason (`npm install`) | macOS, Linux | **Evitable** (inferido) | La misma variable en el wrapper de nvim, guardada y restaurada como los `DITTO_ORIG_*` (los shells hijos no la ven). Validar con un paquete npm en H0.5 (#7) | Mismo mecanismo que npx; `:terminal`/Snacks sin la variable en B |
| `$TMPDIR/lazygit-<uid>/` (macOS) · `/tmp/lazygit-<uid>/` (Linux) | lazygit (suelto y `Snacks.lazygit`) | macOS, Linux | **Evitable** | `TMPDIR=$DITTO_ROOT/tmp` en el wrapper de lazygit, con `mkdir -p "$TMPDIR"` antes del `exec`. Los subdirectorios `lazygit-<n>` se borran al salir, pero el padre queda | A vs B; `inotifywait` |
| `/tmp/nvim.<user>/` | nvim (socket RPC) | macOS, Linux sin `XDG_RUNTIME_DIR` | **Cerrado** (H0.3) | El `TMPDIR` del wrapper de nvim ya lo deja en `.ditto/tmp/nvim.<user>/` (`stdpath("run")`) | `servername` en `*-nvim.json` (macOS) |
| `$XDG_RUNTIME_DIR/nvim.<pid>.0` (p. ej. `/run/user/1000`) | nvim (socket RPC) | Linux con login systemd | **Temporal aceptable** | Se crea al arrancar y se borra al salir (tmpfs por usuario, se limpia al cerrar sesión). No se toca `XDG_RUNTIME_DIR`: lo usan otros programas del host | `inotifywait` (CREATE/DELETE), `strace` (`unlinkat`) |
| `/tmp/qemu-open.XXXXXX` y el mtime de `/tmp` en Ubuntu 22.04 amd64 | **qemu-user** (emula lecturas de `/proc/self/*`), no OpenCode | Solo amd64 emulado | **Artefacto de la emulación** | Ninguno. Cierra el pendiente de H0.2: en arm64 nativo `strace` muestra que el Bun de OpenCode extrae sus librerías nativas (`.*.so`, `.*.node`) en `$TMPDIR` = `.ditto/tmp` | `inotifywait` (amd64), `strace` (arm64) |
| `~/.zsh_history` | Shell anidado abierto a mano (`zsh` dentro de la sesión) | macOS (zsh) | **Inevitable / del usuario** | El shell anidado carga el rc del usuario, que fija `HISTFILE` en `$HOME`: es su configuración y pasaría igual sin ditto. bash anidado hereda el `HISTFILE` exportado por la sesión y escribe en `.ditto/state/shell/` (Linux, ambas fases). Solo lo cubriría el hook de prompt de H0.1b (no recomendado: cambiaría el comportamiento del shell del usuario) | `history` en `results.txt` |
| `~/.zsh_sessions/` | `/etc/zshrc_Apple_Terminal` en el shell anidado | macOS (Terminal.app) | **Inevitable / del usuario** | Mismo caso: el shell anidado tiene el `ZDOTDIR` del usuario. La **subshell de ditto** guarda sus `.zsh_sessions` y su historial de Terminal.app en `.ditto/shell/zsh/` (`/etc/zshrc` se ejecuta con el `ZDOTDIR` de ditto): dentro de `.ditto`. Cierra el pendiente de H0.3 | `zsh-sessions` en `results.txt` |
| `<repo>/.git/opencode` | OpenCode (caché del id de proyecto: hash del commit raíz) | macOS, Linux | **Inevitable** (documentar) | Dentro del `.git` del proyecto, no versionado ni visible en `git status`; igual que sin ditto. Desaparece con el repo | Snapshots, `strace` |
| `<repo>/.git/index` (`index.lock` → `index`), `<repo>/hello.lua` y su `hello.lua~` temporal | git (lazygit, gitsigns, `git status`), nvim al guardar | macOS, Linux | **Trabajo del usuario** | Es el proyecto que se edita. El `~` es la copia de `writebackup` de nvim en el directorio del archivo (`backupdir` empieza por `.`) y se borra al terminar de guardar | `strace` (`unlinkat …hello.lua~`) |
| `.ditto/config/git` → `~/.config/git` | wrapper de nvim | macOS, Linux | **Excepción ya aceptada** (H0.3) | Borrar el workspace no toca la config real (`rm -rf` no sigue el enlace) | `git-symlink-target PASS` |
| `DARWIN_USER_TEMP_DIR`, `DARWIN_USER_CACHE_DIR` | — | macOS | **Nada atribuible** | En la instantánea no aparece nada de la sesión (solo `docker_cli_*`/`dockerfile*` del propio spike, por los `docker build` en paralelo). Nota: `mktemp` sin plantilla en macOS usa `_CS_DARWIN_USER_TEMP_DIR` **antes** que `TMPDIR` (`man mktemp`), así que los scripts que genere ditto deben usar siempre una plantilla en `$DITTO_ROOT/tmp` | Snapshots `dtmp`/`dcache` |
| mtime de `/private/tmp`, `/private/var/tmp` y `DARWIN_USER_TEMP_DIR` | Sin atribuir | macOS | **Pendiente** (probablemente ajeno) | Cambian sin que aparezca ninguna entrada nueva hasta profundidad 3; son directorios compartidos con todo el sistema (otros procesos escribían en `/private/tmp` a la vez). Atribuirlo exige `fs_usage` (root): ver *Pendientes* | Snapshots `ptmp`/`vtmp`/`dtmp` |

Nada en `~/.config`, `~/.local`, `~/.cache`, `~/Library`, `~/.bun`, `~/.opencode` ni `/var/tmp` en ninguna plataforma, con la TUI de OpenCode y `serve`, y también en la primera ronda, que incluía `opencode run`.

## Pendientes (manual)

1. **macOS: atribuir los cambios de mtime** de `/private/tmp`, `/private/var/tmp` y `DARWIN_USER_TEMP_DIR` (necesita root, no se ejecutó):
   ```sh
   # Terminal 1
   sudo fs_usage -w -f filesys nvim lazygit opencode node git stylua > /tmp/h04-fsusage.txt
   # Terminal 2
   sh spikes/h0.4-escrituras/macos.sh /tmp/h04
   # Después (Ctrl-C en la terminal 1):
   grep -E '/private/(var/)?tmp/|/var/folders/' /tmp/h04-fsusage.txt | grep -v '/tmp/h04/' | sort -u | head -50
   ```
   Esperado: nada fuera de `/tmp/h04/`.
2. **Terminal.app real** (aquí se simuló con `TERM_PROGRAM`/`TERM_SESSION_ID`): `H04_PHASES=B H04_KEEP_WS=1 sh spikes/h0.4-escrituras/macos.sh /tmp/h04` (deja el workspace montado); después, en una ventana de Terminal.app, `env -i HOME=/tmp/h04/home TMPDIR=/tmp/h04/tmp TERM="$TERM" TERM_PROGRAM="$TERM_PROGRAM" TERM_SESSION_ID="$TERM_SESSION_ID" SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin /tmp/h04/w/.ditto/shell/session`, abrir `nvim` y `lazygit`, salir, cerrar la ventana y comprobar `ls -a /tmp/h04/home /tmp/h04/w/.ditto/shell/zsh`. Esperado: nada nuevo en `/tmp/h04/home`.
3. **x86_64 real** (no emulado), con `strace` (en qemu-user no funciona): `sh spikes/h0.4-escrituras/run.sh /tmp/h04 opencode` dentro de un usuario o contenedor desechable, con `DITTO_SPIKE_DISPOSABLE_HOME=1 H04_STRACE=1 H04_INOTIFY="/tmp /var/tmp $HOME"`. Esperado: ningún `/tmp/qemu-open.*` y nada en `/tmp`.
4. **Peticiones al modelo (opt-in, las decide el usuario):**
   - Sin credenciales, con un modelo gratuito de OpenCode Zen (envía lo descrito en *Red*): `H04_OC_RUN=1 H04_PHASES=B sh spikes/h0.4-escrituras/macos.sh /tmp/h04` (o `H04_OC_RUN=1 H04_PHASES=B sh spikes/h0.4-escrituras/docker.sh <work> arm64 full`). Esperado: el mismo diff que sin la petición.
   - Con credenciales reales de un proveedor (no se pidieron ni se usaron): `H04_PHASES=B H04_KEEP_WS=1 sh spikes/h0.4-escrituras/macos.sh /tmp/h04`; después, desde la sesión (`env -i HOME=/tmp/h04/home TMPDIR=/tmp/h04/tmp TERM="$TERM" SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin /tmp/h04/w/.ditto/shell/session`), `touch /tmp/h04/marca; cd /tmp/h04/w/proj; opencode auth login`, una sesión TUI corta que use el shell tool (quitando `bash` de `permission` y `tools` en el `opencode.json` del proyecto) y `find /tmp/h04/home /tmp /private/var/tmp -newer /tmp/h04/marca 2>/dev/null | grep -v '^/tmp/h04/w/'`. Borrar `/tmp/h04` al terminar (contiene `auth.json`).
   - Comprobar qué hosts contactan la TUI y `serve` sin petición (con un proxy local o `nettop`/`lsof -i` durante la sesión).
5. **Servidores reales** del usuario (bash/zsh, `XDG_RUNTIME_DIR` de systemd, glibc de la distro): `run.sh` con `DITTO_SPIKE_DISPOSABLE_HOME=1` **solo** en un usuario desechable (escribe fixtures en `$HOME`).
6. **Mason con un paquete npm** (confirma `npm_config_cache` en el wrapper de nvim): parte de H0.5 (#7).

## Conclusión

Según el *Criterio de decisión* del issue, escapa algo, así que se aplica la segunda rama: por cada ruta, su mecanismo (§8) o su excepción (§18).

- **Mecanismos nuevos para §8:** `npm_config_cache=$DITTO_ROOT/cache/npm` y `npm_config_update_notifier=false` en los wrappers de OpenCode y de nvim, las dos en la lista de `DITTO_ORIG_*` de todos los wrappers (nvim las guarda; `.host-sh` y los demás las restauran); `TMPDIR=$DITTO_ROOT/tmp` en el wrapper de lazygit, y `mkdir -p "$TMPDIR"` antes del `exec` en los de lazygit y OpenCode. Con ellos, en Linux no queda nada fuera de `.ditto/` tras borrar el workspace, y en macOS solo lo que escribe el propio shell del usuario si abre uno a mano.
- **Excepciones para §18:** `<repo>/.git/opencode`; sockets de nvim en `$XDG_RUNTIME_DIR` (temporales); historial y `.zsh_sessions` de los shells anidados con el rc del usuario; el enlace `.ditto/config/git` (ya aceptado).
- **Cerrados:** `/tmp/nvim.<user>` (ya en `.ditto/tmp`); el mtime de `/tmp` en amd64 (qemu-user, no OpenCode); `.zsh_sessions` de la subshell de ditto (dentro de `.ditto/shell/zsh`).
- Se confirma §4 con dos líneas nuevas (`tmp/`, `shell/`) y `cache/npm`.

## Decisión propuesta

Texto para aplicar con `/record-decision` (no se ha editado arch.md ni roadmap.md). Supone ya aplicadas las propuestas de H0.2 (#2) y H0.3 (#5), que se citan donde coinciden.

### arch.md §4: layout

Sustituir las líneas de `config/` y `data/ state/ cache/` y añadir `tmp/` y `shell/`:

```markdown
│   ├── config/              # XDG_CONFIG_HOME de nvim y OpenCode; lazygit (CONFIG_DIR), ripgrep, fzf; config/git → enlace a la config de git del usuario (§8)
│   ├── data/  state/  cache/  # XDG de nvim y OpenCode (plugins de lazy, Mason, sesiones y auth.json de OpenCode); state/shell: historiales; cache/npm: caché de npm/npx (MCPs y Mason)
│   ├── tmp/                 # TMPDIR de nvim, lazygit y OpenCode (sockets, temporales, librerías nativas que extrae Bun)
│   ├── shell/               # lanzador y rc de la subshell (bash, zsh); en Terminal.app, también el .zsh_history y .zsh_sessions de la subshell
```

Y después del bloque, junto a la nota de `.gitignore`:

```markdown
Verificado en H0.4 (macOS arm64; Ubuntu 22.04 arm64 y amd64): una sesión con `Lazy! restore`, Mason, edición, `:terminal`, terminal de Snacks, lazygit y OpenCode (TUI, `serve`, MCPs con `npx` y, en una ronda, una petición a un modelo gratuito) no escribe nada fuera de `.ditto/` salvo las excepciones de §18, y borrar `<workspace>/.ditto` no deja nada atribuible a ditto.
```

### arch.md §8: tabla y reglas

Filas de la tabla (sustituyen a las de lazygit y OpenCode; añadir npm):

```markdown
| lazygit | `CONFIG_DIR=.ditto/config/lazygit` (también `state.yml`), `LG_CONFIG_FILE` solo si no viene definido y `TMPDIR=.ditto/tmp`, creado con `mkdir -p` antes del `exec` (si no, deja `lazygit-<uid>/` en el temporal del sistema) |
| OpenCode | `XDG_CONFIG_HOME`/`DATA`/`STATE`/`CACHE` → `.ditto/…` + `OPENCODE_CONFIG_DIR=.ditto/config/opencode` + `TMPDIR=.ditto/tmp` (creado con `mkdir -p` antes del `exec`) + `OPENCODE_DISABLE_AUTOUPDATE=1` + `npm_config_cache=.ditto/cache/npm` + `npm_config_update_notifier=false` (solo dentro del wrapper) |
| npm / npx (MCPs de OpenCode, paquetes npm de Mason) | `npm_config_cache=.ditto/cache/npm` y `npm_config_update_notifier=false` en los wrappers de OpenCode y de nvim; si no, `npx` escribe `~/.npm/{_npx,_logs,_cacache}` y consulta `registry.npmjs.org` para avisar de versiones. npm no usa `XDG_*` |
```

**Lista de `DITTO_ORIG_*`** (la que guarda el wrapper de nvim y restauran **todos** los demás wrappers —lazygit, rg, fd, fzf, tree-sitter, OpenCode— y `.host-sh`): `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME`, `PATH`, `GIT_CONFIG_GLOBAL`, `TMPDIR`, `npm_config_cache` y `npm_config_update_notifier`. Así ningún shell ni herramienta lanzada desde nvim ve los valores de ditto (validado: `:terminal` y el terminal de Snacks no ven `npm_config_cache`).

Wrapper de nvim, antes del `exec`:

```sh
export npm_config_cache="$DITTO_ROOT/cache/npm" npm_config_update_notifier=false   # paquetes npm de Mason
mkdir -p "$npm_config_cache"
```

Wrappers de lazygit y OpenCode, antes del `exec`:

```sh
mkdir -p "$TMPDIR"   # TMPDIR=$DITTO_ROOT/tmp; la build x64 de OpenCode aborta si no existe (H0.2)
```

Párrafo nuevo al final de la sección:

```markdown
**Temporales.** Todo wrapper que lanza algo que escribe temporales fija `TMPDIR=$DITTO_ROOT/tmp` (nvim, lazygit, OpenCode) y el directorio existe antes del `exec`; `.host-sh` y los wrappers devuelven el `TMPDIR` original a los shells hijos. `XDG_RUNTIME_DIR` no se toca: en Linux con login systemd nvim crea su socket en `$XDG_RUNTIME_DIR/nvim.<pid>.0` y lo borra al salir (temporal aceptado, §18). Los scripts que genera ditto (`install.sh`, wrappers) usan siempre una plantilla en `$DITTO_ROOT/tmp` (`mktemp -d "$DITTO_ROOT/tmp/x.XXXXXX"`): en macOS `mktemp` sin plantilla va a `DARWIN_USER_TEMP_DIR` aunque `TMPDIR` esté definido. Validado en H0.4.
```

### arch.md §18: riesgos abiertos

Sustituir las viñetas *Escrituras en el temporal del sistema* y *Shells anidados a mano* (propuestas en H0.3), y la parte (c) de la viñeta de OpenCode (H0.2), por:

```markdown
- **Escrituras fuera de `.ditto/`** (spike H0.4, macOS arm64 y Ubuntu 22.04): con los mecanismos de §8 solo quedan estas, documentadas como excepciones al principio "nada se escribe fuera de `.ditto/`":
  - `<repo>/.git/opencode`: OpenCode guarda el id del proyecto (hash del commit raíz) en el `.git` de cada repo en que se usa. No se versiona ni aparece en `git status`; pasa igual sin ditto.
  - Sockets de nvim en `$XDG_RUNTIME_DIR` (`/run/user/<uid>/nvim.<pid>.0`, Linux con systemd): se crean al arrancar y se borran al salir.
  - Shells anidados abiertos a mano dentro de la sesión: cargan el rc del usuario, así que zsh con `HISTFILE` propio escribe `~/.zsh_history` y, en Terminal.app, `~/.zsh_sessions/` (bash hereda el `HISTFILE` de la sesión y escribe en `.ditto/state/shell/`). Es la configuración del usuario y pasa igual sin ditto; solo el hook de prompt de H0.1b podría cambiarlo, y no se recomienda.
  - El enlace `.ditto/config/git` (§8): lo que escriban en su config global los git lanzados por nvim cae en la config real.
  - Archivos del proyecto que el usuario edita (incluidos el índice de git y el `archivo~` temporal de `writebackup` de nvim, que se borra al guardar).
- **Pendiente de H0.4:** atribuir en macOS los cambios de mtime de `/private/tmp`, `/private/var/tmp` y `DARWIN_USER_TEMP_DIR` (sin entradas nuevas visibles; directorios compartidos con el resto del sistema; necesita `fs_usage`), repetir en x86_64 real con `strace` (en amd64 emulado los únicos temporales en `/tmp` eran de qemu-user), y repetir con credenciales reales de un proveedor y el shell tool de OpenCode.
- **Paquetes npm de Mason**: `npm_config_cache` en el wrapper de nvim se dedujo del caso de `npx`; validar con un paquete npm real en H0.5.
```

### roadmap.md

Marcar H0.4 cuando se apliquen §4, §8 y §18. Los pendientes 1–5 no cambian la decisión (como mucho añaden excepciones de §18): pueden quedar como verificación de H1.x o de los servidores reales de Fase 0.
