# H0.3 — Aislamiento de LazyVim con wrappers y `.host-sh`: resultados

**Issue:** #5 · **Fecha:** 2026-10-21 · **Base:** H0.1 (#1, `spikes/h0.1-mise-aislado/`) · **Estado:** casos 2–6 en verde con el mecanismo propuesto en macOS arm64 (zsh y bash), Ubuntu 22.04 (bash y zsh; arm64 nativo y amd64 emulado) y Ubuntu 18.04 arm64 (extra; lazygit no arranca con su git 2.17). 0 FAIL en todas.

## Pregunta

¿Funcionan los wrappers por herramienta + `.host-sh` + una subshell sin `XDG_*` global para aislar LazyVim, sin que `git`, `ssh` ni `nvme` cambien de comportamiento en ningún proceso hijo de Neovim?

**Respuesta corta:** sí, con un cambio respecto a arch.md §8:

1. Todo lo que pasa por un shell (`:terminal`, `:!`, `system()` con string, terminal de Snacks) y lazygit integrado ve **exactamente** el entorno del host: `.host-sh` y el wrapper de lazygit restauran los `DITTO_ORIG_*`.
2. Lo que Neovim lanza **con lista de argumentos** (gitsigns, lazy.nvim, `vim.system`) hereda el `XDG_CONFIG_HOME` de Neovim, así que `git` deja de leer `$XDG_CONFIG_HOME/git/{config,ignore,attributes}`. La solución de arch.md (`GIT_CONFIG_GLOBAL=~/.config/git/config`) **falla**: sustituye a `~/.gitconfig` en vez de sumarse (se pierden `user.name`, alias…), no recupera el ignore global y, si el usuario tiene `XDG_CONFIG_HOME` propio, apunta al archivo equivocado. La alternativa de #4 (`[include]` en `.ditto/config/git/config`) recupera la config pero no el ignore global. **Lo que funciona en todos los casos es un enlace simbólico `.ditto/config/git` → `${XDG_CONFIG_HOME original:-~/.config}/git`**, que crea el wrapper de nvim en cada arranque: mismos valores, mismo ignore, misma precedencia; solo cambia la ruta que imprime `--show-origin`.
3. Orden de extras: **no importa**. LazyVim (`lazyvim.plugins.xtras`) deduplica y ordena los extras de `lazyvim.json` por prioridad y nombre. La regla de fusión es la unión.

## Contenido del directorio

| Archivo | Para qué |
|---|---|
| `lib.sh` | Librería POSIX reutilizable (fuente de `../h0.1-mise-aislado/env.sh`, sin modificarlo): instala las herramientas con el mise aislado y el lock de H0.1, genera los wrappers (`nvim`, `lazygit`, `rg`, `fd`, `fzf`, `tree-sitter`, `.host-sh`), el lanzador de sesión y los rc de bash/zsh, y copia el starter + `lazy.nvim` fijado. **Pensada para #6 y #7** (ver *Reutilización*). |
| `starter/` | Starter de LazyVim (`LazyVim/starter@803bc18`) con `checker`/`change_detection`/`rocks` desactivados, `vim.o.shell = $DITTO_ROOT/bin/.host-sh`, `lazyvim.json` del "repo de dotfiles" y `lazy-lock.json` (32 plugins). `lua/plugins/spike-offline.lua` desactiva solo para este spike Mason, la instalación de parsers y la descarga del binario de blink.cmp (ver *Descargas*). |
| `lua/merge-extras.lua` | Prototipo de la fusión de extras (`nvim --clean -l`). En producción, Go. |
| `lua/pty.lua` | Driver de pseudoterminal sin TTY real (`nvim -l` + `jobstart({pty=true})`): lanza un programa con un entorno exacto (`clear_env`), le escribe líneas y espera archivos. Reutilizable. |
| `lua/probe.lua` | Se ejecuta dentro del nvim bajo prueba: recorre los casos (`:terminal`, `:!`, `system()`, lista de argumentos, terminal de Snacks, lazygit vía `Snacks.lazygit`, gitsigns) y escribe un JSON. |
| `lua/extras-order.lua` | Vuelca el orden de importación (`spec.modules`), los extras leídos y los `vim.notify` del arranque. |
| `probe.sh` | Lo que "ve el usuario" en un contexto: `git config --show-origin --list`, `git config --list`, `git check-ignore -v`, `ssh -G spike-host`, `command -v nvme`, `command -v ditto-rt` y las variables relevantes. |
| `run.sh <dest> [test\|lock]` | Prueba completa (o regenera `starter/lazy-lock.json`). Exige `DITTO_SPIKE_DISPOSABLE_HOME=1`: escribe los fixtures del usuario en `$HOME`. |
| `macos.sh <scratch>` | Driver macOS: `HOME`/`TMPDIR` desechables, `env -i`, y barrido del `$HOME` real al final. |
| `docker.sh <work> [arm64\|amd64] [imagen]` | Driver Linux: contenedor desechable (`HOME=/root`), resultados copiados con `docker cp`. |

## Método

- **Nada se ejecuta con el `$HOME` real.** `macos.sh` lanza `run.sh` con `env -i HOME=<scratch>/home TMPDIR=<scratch>/tmp PATH=/usr/bin:/bin:/usr/sbin:/sbin`. Las herramientas del propio spike (driver de pty, fusión de extras, `nvim --version`) usan además otro `HOME`/`XDG_*`/`TMPDIR` dentro de `<dest>/driver`. En Linux todo corre en un contenedor desechable.
- **Fixtures del usuario** (en el `$HOME` desechable, sin datos reales): `~/.gitconfig` (`user.name`, alias, `init.defaultBranch`), `~/.config/git/{config,ignore}`, `~/.xdg-config/git/{config,ignore}` (para el escenario B), `~/.ssh/config` con `Host spike-host`, `~/hostbin/nvme` (binario "del host" que el rc del usuario antepone al `PATH`, como haría conda), `~/.bashrc`, `~/.zshrc` (con `HISTFILE=~/.zsh_history`), `~/.zdot/{.zshenv,.zshrc}`.
- **Escenarios del host:** **A** sin `XDG_*` ni `ZDOTDIR`; **B** con `XDG_CONFIG_HOME=~/.xdg-config` y `ZDOTDIR=~/.zdot` exportados.
- **Línea base:** el shell interactivo normal del usuario (sin ditto) dentro de un pty ejecuta `probe.sh`. Cada contexto se compara byte a byte con ella.
- **Sesión:** `.ditto/shell/session` (sustituto de `ditto up`) dentro de un pty; en ella se ejecuta `probe.sh` y después `nvim --headless "+lua dofile('lua/probe.lua')"`. Los casos interactivos (`:terminal`, terminal de Snacks, lazygit) se automatizan escribiendo en su pty con `chansend`; lazygit ejecuta `probe.sh` mediante un *custom command* (`<ctrl+x>`) definido en `.ditto/config/lazygit/config.yml`.
- **Runtime simulado:** el wrapper de nvim antepone `.ditto/spike/runtime/bin` (con un marcador `ditto-rt`) al `PATH`, como haría con los runtimes de mise para Mason. Se comprueba que los shells hijos no lo ven y los procesos con lista de argumentos sí.
- **Modos de git para los hijos con lista de argumentos** (`H03_GIT_MODES`): `none`, `global` (arch.md §8 tal cual), `include` (propuesta de #4) y `symlink` (propuesto). Los tres primeros son controles: sus fallos esperados salen como `XFAIL`.
- **macOS y ssh:** `ssh` resuelve `~` con `getpwuid()`, no con `$HOME`, así que con un `HOME` desechable leería el `~/.ssh/config` real. En macOS `probe.sh` usa `ssh -F "$HOME/.ssh/config" -G`; en Linux (`HOME=/root`, igual que `pw_dir`) se usa `ssh -G` sin más.

Comandos:

```sh
# macOS (HOME/TMPDIR desechables). $SCRATCH corto, p. ej. /tmp/s (ver "Rutas largas").
DITTO_SPIKE_REAL_HOME_EXCLUDE='<regex de procesos ajenos que escriben a la vez>' \
  sh spikes/h0.3-aislamiento-lazyvim/macos.sh $SCRATCH/h03/mac
# Linux
sh spikes/h0.3-aislamiento-lazyvim/docker.sh "$SCRATCH/u22-arm64" arm64 ubuntu-22.04
sh spikes/h0.3-aislamiento-lazyvim/docker.sh "$SCRATCH/u22-amd64" amd64 ubuntu-22.04
sh spikes/h0.3-aislamiento-lazyvim/docker.sh "$SCRATCH/u18-arm64" arm64 ubuntu-18.04
# Regenerar el lazy-lock.json del starter (red)
sh spikes/h0.3-aislamiento-lazyvim/macos.sh $SCRATCH/h03/lock lock
```

Variables: `H03_SHELLS` (por defecto `zsh bash` en macOS, `bash zsh` en Docker), `H03_SCENARIOS` (`A B`), `H03_GIT_MODES` (`none global include symlink`).

## Resultados por caso

Numeración del issue. Con el modo `symlink` (propuesto), en **todas** las combinaciones escenario × shell × plataforma:

| Caso | Contexto | Resultado |
|---|---|---|
| 2 | `nvim --headless "+Lazy! restore" +qa` (entorno del usuario + `.ditto/bin` en `PATH`) | ✅ 32 plugins exactamente en el commit de `lazy-lock.json`; el lock no cambia |
| 3 | Subshell bash (`--rcfile`) y zsh (`ZDOTDIR` temporal) | ✅ ningún `XDG_*` ni `MISE_*` añadido (A: ninguno; B: solo el del usuario); rc del usuario cargado; `PATH` = `.ditto/bin` y después lo que añade el rc; zsh: `ZDOTDIR` restaurado (A: sin definir; B: `~/.zdot`), `.zshenv` y `.zshrc` del usuario leídos desde su `ZDOTDIR` |
| 4 | Sesión (antes de nvim) | ✅ idéntico al host |
| 4 | `:terminal` | ✅ idéntico (incl. `XDG_*`, `ZDOTDIR`, `GIT_CONFIG*`; sin el `PATH` de runtimes) |
| 4 | `:!git …` | ✅ idéntico |
| 4 | `system()` con string | ✅ idéntico |
| 4 | Terminal de Snacks | ✅ idéntico |
| 4 | lazygit integrado (`Snacks.lazygit`) | ✅ idéntico; `LG_CONFIG_FILE` = config de ditto + tema de Snacks |
| 4 | Lista de argumentos (`vim.system`, mismo mecanismo que gitsigns y lazy.nvim) | ✅ equivalente: mismos valores, mismo ignore global, mismo orden; `--show-origin`/`check-ignore -v` muestran la ruta `.ditto/config/git/…`. Ve el `PATH` de runtimes (a propósito) |
| 4 | gitsigns real (adjunto al repo, `vim.b.gitsigns_head = main`) | ✅ |
| 5 | Fusión de extras + orden de importación | ✅ mismo `spec.modules` con las dos listas invertidas; ningún aviso de orden. Control: un extra importado a mano después de `plugins` sí produce el aviso |
| 6 | `HISTFILE` y similares | ✅ historial de la sesión en `.ditto/state/shell/<shell>_history`; nada nuevo en `$HOME` tras todas las sesiones (control: el shell del host sin ditto escribe `~/.zsh_history` y `~/.bash_history`) |
| — | `.host-sh -c '<cmd>' arg0 arg1` (forma de la clave `shell` de OpenCode, #2) | ✅ entorno restaurado, `$0`/`$1` pasan intactos |

### Hijos con lista de argumentos según el mecanismo de git

| Modo | Escenario A (sin `XDG_*`) | Escenario B (`XDG_CONFIG_HOME` propio) |
|---|---|---|
| `none` | ❌ falta `~/.config/git/config` (email, alias) y el ignore global | ❌ falta `~/.xdg-config/git/config` y el ignore |
| `global` (arch.md §8) | ❌ se **pierde `~/.gitconfig`** (`user.name`, alias, `init.defaultBranch`) y el ignore global | ❌ lee `~/.config/git/config` (el archivo equivocado), pierde `~/.gitconfig` y el ignore |
| `include` (#4) | ⚠️ config equivalente (+ una línea `include.path`), **pierde el ignore global** (`core.excludesFile` por defecto = `$XDG_CONFIG_HOME/git/ignore`) | ⚠️ ídem |
| `symlink` (propuesto) | ✅ equivalente (solo cambia la ruta de origen) | ✅ equivalente |

Los contextos que pasan por shell dan ✅ en los cuatro modos: `.host-sh` restaura `XDG_*` y deshace `GIT_CONFIG_GLOBAL`.

## Resultados por plataforma

| Plataforma | Shells | git / ssh | Resultado (4 modos × 2 escenarios × 2 shells) |
|---|---|---|---|
| macOS arm64 (Darwin 25.2), host con `HOME` desechable | zsh 5.9, bash 3.2 | 2.50.1 / OpenSSH 10.0p2 | 159 PASS, 0 FAIL, 24 XFAIL (controles) |
| Ubuntu 22.04 arm64 (Docker, nativo) | bash 5.1, zsh 5.8 | 2.34.1 / OpenSSH 8.9p1 | 159 PASS, 0 FAIL, 24 XFAIL |
| Ubuntu 22.04 amd64 (Docker, emulado) | bash 5.1, zsh 5.8 | 2.34.1 / OpenSSH 8.9p1 | 159 PASS, 0 FAIL, 24 XFAIL |
| Ubuntu 18.04 arm64 (Docker, extra: Neovim legacy 0.12.5, git 2.17 sin `GIT_CONFIG_GLOBAL`) | bash 4.4, zsh 5.4 | 2.17.1 / OpenSSH 7.6p1 | 143 PASS, 0 FAIL, 24 XFAIL, 16 SKIP (lazygit) |

Tras la ronda de revisión (`set -eu` en los wrappers, enlace con `ln -sfn` y protección de los fixtures) se volvieron a ejecutar macOS y Ubuntu 22.04 arm64, con el mismo resultado. Las filas de Ubuntu 22.04 amd64 y 18.04 son de la ejecución anterior.

En Ubuntu 18.04 el caso lazygit se omite (`SKIP`): **lazygit 0.66 se niega a arrancar con git < 2.32** (*"Git version must be at least 2.32.0"*), así que tampoco funciona en Ubuntu 20.04 (git 2.25). No es un problema de aislamiento; el enlace `.ditto/config/git` sí funciona con git 2.17 (el modo `global` equivale allí a `none`, porque git 2.17 ignora `GIT_CONFIG_GLOBAL`).

`$HOME` real del Mac: el barrido completo (`find ~ -newer <marker>`) no encontró nada relacionado con nvim, lazygit, mise, historiales, git ni ssh. Las rutas nuevas eran de procesos ajenos concurrentes (editores, otros agentes, cachés de herramientas) y de la caché de Docker que generan los `docker build` del propio spike.

## Hallazgos

### lazygit necesita `CONFIG_DIR`, no solo `LG_CONFIG_FILE`

`LG_CONFIG_FILE` solo cambia los archivos de configuración. `state.yml` (y la config por defecto) van al *config dir* de lazygit, que sin más es `~/.config/lazygit` en Linux y `~/Library/Application Support/lazygit` en macOS (comprobado con `lazygit -cd`). El wrapper fija `CONFIG_DIR=$DITTO_ROOT/config/lazygit` y `state.yml` queda ahí.

Además, `Snacks.lazygit` ejecuta `lazygit -cd`, toma `<config dir>/config.yml` y **fija `vim.env.LG_CONFIG_FILE = "<config>,<tema>"`** en el proceso de nvim. El wrapper solo pone `LG_CONFIG_FILE` si no viene ya definido; si lo forzara, se perdería el tema. Ese `LG_CONFIG_FILE` queda en el entorno de nvim (lo heredan también los hijos de `:terminal`): es la config de ditto más el tema, así que no rompe nada.

Config de lazygit recomendada para ditto: `update.method: never` (por defecto consulta GitHub cada 14 días), `git.autoFetch: false` y `disableStartupPopups: true`.

### `TMPDIR` dentro del wrapper de nvim

nvim crea su socket RPC en `$TMPDIR/nvim.<usuario>/…` (o `/tmp/nvim.<usuario>/…`), visto en ambas plataformas. El wrapper fija `TMPDIR=$DITTO_ROOT/tmp` (guardado y restaurado como el resto de `DITTO_ORIG_*`) y ese directorio desaparece del temporal del sistema. Sigue apareciendo `lazygit-<uid>` en `$TMPDIR` o `/tmp`, porque lazygit recibe el `TMPDIR` restaurado. Queda para H0.4 (#6) decidir si se fija también en el wrapper de lazygit.

### Rutas largas

- `vim.loader` (activado por lazy.nvim) guarda cada `.lua` compilado en `stdpath("cache")/luac/` con **la ruta completa codificada en el nombre del archivo** (`/` → `%2f`). Con un `DITTO_ROOT` largo el nombre supera `NAME_MAX` (255) y Neovim falla al cargar archivos del runtime (`ENAMETOOLONG … editorconfig.luac`); lazy.nvim termina con *"Too many rounds of missing plugins"*. El archivo más profundo del árbol (`mise/installs/aqua-neovim-neovim/0.12.6/nvim-macos-arm64/share/nvim/runtime/pack/dist/opt/nvim.difftool/plugin/difftool.lua`) ocupa 153 caracteres codificados, así que `len(DITTO_ROOT) + 2 × nº de "/"` debe quedar por debajo de ~100 (unos 70–80 caracteres reales). Reproducido con el scratch de 120 caracteres de esta sesión.
- El socket RPC debe caber en `sun_path` (104 bytes en macOS): con un `TMPDIR` largo nvim no arranca su servidor (`server_start: Failed to start server: invalid argument`).
- `run.sh` rechaza `<dest>` o `$TMPDIR` de más de 60 caracteres. `ditto doctor`/`up` debería avisar.

### Otros

- **LazyVim escribe `lazyvim.json`** al arrancar (`news`, migraciones de versión, extras renombrados): visto en la prueba (`"news": {"NEWS.md": …}`). Si `.ditto/config/nvim` fuera un enlace al clon de dotfiles, ensuciaría el repo. LazyVim acepta `vim.g.lazyvim_json` para usar otra ruta.
- **`Lazy! restore` necesita `.ditto/bin` en el `PATH`**: sin él, nvim-treesitter (`main`) se queja de que falta el CLI de tree-sitter. En Docker también avisa de que falta `cc` (prerrequisito de categoría B; aquí no se instala porque no se compilan parsers).
- **Hijos con lista de argumentos**: además de git, cualquier herramienta que lea `XDG_CONFIG_HOME` y que nvim lance directamente ve `.ditto/config` (p. ej. `pip` lanzado por Mason lee `$XDG_CONFIG_HOME/pip/pip.conf` en Linux, `gh`…). Para git lo resuelve el enlace; para Mason (H0.5, #7) hay que comprobar proxies/índices privados. También ven el `PATH` de runtimes, a propósito (Mason los necesita): un runtime que trae un binario con el mismo nombre que uno del host lo sombrea solo para esos procesos.
- **zsh de macOS**: `/etc/zshrc` fija `HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history` antes de nuestro `.zshrc` (con `ZDOTDIR` = el de ditto, así que queda dentro de `.ditto`) y el rc de ditto lo sobrescribe después. En Terminal.app, `/etc/zshrc_Apple_Terminal` guarda sesiones en `${ZDOTDIR:-$HOME}/.zsh_sessions` al salir, ya con el `ZDOTDIR` del usuario: no probado (exige Terminal.app).
- **Shells anidados a mano**: un `zsh`/`bash` que el usuario abra dentro de la sesión carga su rc normal, que puede volver a poner `HISTFILE` en `$HOME`. `:terminal` y Snacks no tienen ese problema porque `.host-sh` sin argumentos reabre la sesión con el rc de ditto. Cubrirlo exigiría el hook de prompt que propone #4 (H0.1b); no validado aquí.

## Descargas e integridad

- mise y las herramientas: igual que H0.1 (sha256 embebido para mise; `install --locked` con `mise.lock`, sha256 por asset).
- lazy.nvim y los plugins: `git clone` fijado al **commit** de `lazy-lock.json` (integridad por hash de commit de git, SHA-1; no sha256). `h03_install_starter` clona lazy.nvim y hace `checkout` del commit del lock antes del primer arranque; `T2-lazy-restore` comprueba los 32 commits.
- Desactivado solo en el spike (`starter/lua/plugins/spike-offline.lua`) porque baja artefactos sin sha256 ni commit fijado: parsers de nvim-treesitter (tarballs), registro y paquetes de Mason, y el binario precompilado de blink.cmp (`fuzzy.implementation = "lua"`). Es trabajo de H0.5 (#7).
- Imágenes Docker por etiqueta (`ubuntu:22.04`, `ubuntu:18.04`, `koalaman/shellcheck:stable`) y paquetes de apt (firmados por la distro): solo infraestructura de prueba.

## Reutilización en #6 y #7

```sh
H03_DIR=spikes/h0.3-aislamiento-lazyvim
. "$H03_DIR/lib.sh"                 # carga también ../h0.1-mise-aislado/env.sh (sin modificarlo)
h03_paths "$WS/.ditto"              # DITTO_ROOT + rutas de H0.1; no exporta MISE_*
h03_install_tools                   # mise (sha256) + install --locked: nvim, rg, fd, fzf, lazygit, tree-sitter
h03_write_wrappers                  # .ditto/bin/{nvim,lazygit,rg,fd,fzf,tree-sitter,.host-sh}
h03_write_session                   # .ditto/shell/{session,bashrc,zsh/.zshenv,zsh/.zshrc}
h03_install_starter                 # starter/ -> .ditto/config/nvim + lazy.nvim en el commit del lock
nvim --clean -l "$H03_DIR/lua/merge-extras.lua" in.json out.json lazyvim.plugins.extras.lang.go …
```

- **Variables:** `H03_GIT_MODE` (`symlink` por defecto), `H03_RUNTIME_PATH` (entradas extra de `PATH` solo para nvim: **#7 debe apuntarla a los `bin/` de node/go/python de mise**), `H03_SAVED_VARS` (lo que el wrapper de nvim guarda y el resto restaura).
- **Wrappers sueltos:** `h03_write_nvim_wrapper <nvim>` y `h03_write_tool_wrapper <nombre> <bin> 'VAR=valor'…` (p. ej. un wrapper de `opencode` con `OPENCODE_CONFIG_DIR`, que restaura los `DITTO_ORIG_*` como los demás). `.host-sh` acepta `-c <cmd> [args]` (la clave `shell` de OpenCode de #2).
- **Mason (#7):** borrar `starter/lua/plugins/spike-offline.lua` (o la entrada de Mason) y regenerar el lock con `run.sh <dest> lock`. Ejecutar el precalentado con el wrapper y `.ditto/bin` en el `PATH`, como hace `ditto_run` en `run.sh`.
- **Sesión y escrituras (#6):** `lua/pty.lua` lanza la sesión con un entorno exacto y teclea comandos; `run.sh` ya separa escrituras en `$HOME` (`T6-outside-home`) y en el temporal (`T6-outside-tmp`). Usar rutas cortas (ver *Rutas largas*).
- **Casos interactivos:** `lua/probe.lua` muestra cómo automatizar `:terminal`, Snacks y lazygit con `chansend` en headless.

Qué usar, por pieza:

| Pieza | Función / archivo | Notas |
|---|---|---|
| Rutas | `h03_paths <dir>` (`lib.sh`) | Exporta `DITTO_ROOT` y las rutas de H0.1 |
| Instalación | `h03_install_tools`, `h03_write_mise_config <file>`, `h03_tool <bin>` (`lib.sh`) | Usa `env.sh` y `mise.lock` de H0.1 |
| Wrapper de nvim | `h03_write_nvim_wrapper <abs-nvim>` (`lib.sh`) | `H03_GIT_MODE`, `H03_RUNTIME_PATH`; `XDG_*`, `TMPDIR`, enlace `.ditto/config/git` |
| Otros wrappers | `h03_write_tool_wrapper <nombre> <bin> 'VAR=valor'…`, `h03_write_wrappers` (`lib.sh`) | Restauran `DITTO_ORIG_*`; todos con `set -eu` |
| `.host-sh` | `h03_write_host_sh` (`lib.sh`) | Sin args → sesión; `-c <cmd>` → `$SHELL` |
| Sesión y rc | `h03_write_session` (`lib.sh`) → `.ditto/shell/{session,bashrc,zsh/.zshenv,zsh/.zshrc}` | |
| Starter | `starter/`, `h03_install_starter [dir]` (`lib.sh`) | Falla si `lazy-lock.json` no fija lazy.nvim (salvo `H03_ALLOW_UNPINNED_LAZY=1`, solo para `run.sh … lock`) |
| Extras | `lua/merge-extras.lua` | `nvim --clean -l merge-extras.lua <in> <out> <extra>…` |
| pty headless | `lua/pty.lua`; `pty`/`helper_nvim` en `run.sh` | Entorno exacto por archivo `KEY=VALUE` |
| Sondas | `probe.sh`, `lua/probe.lua`, `lua/extras-order.lua` | |
| Fixtures y entornos | `make_fixtures`, `write_env`, `run_env`, `ditto_run`, `cmp_ctx` (`run.sh`) | `make_fixtures` se niega a escribir si ya existe algún archivo del usuario |
| Drivers | `macos.sh`, `docker.sh` | HOME desechable; Docker borra el `/root/.bashrc` de la imagen |

## Pendientes

- [ ] **TTY real** (opcional, confirma lo automatizado): en una terminal, `sh spikes/h0.3-aislamiento-lazyvim/macos.sh $SCRATCH/h03/tty` deja montado el workspace en `$SCRATCH/h03/tty/run/ws`; después `env -i HOME=$SCRATCH/h03/tty/home TMPDIR=$SCRATCH/h03/tty/tmp TERM="$TERM" SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin $SCRATCH/h03/tty/run/ws/.ditto/shell/session`, abrir `nvim`, y en `:terminal`, `<leader>gg` (lazygit) y `<C-/>` (terminal de Snacks) ejecutar `git config --show-origin --list | head` y `ssh -F ~/.ssh/config -G spike-host | head -3`. Debe coincidir con lo mismo fuera de ditto.
- [ ] **Servidores reales** del usuario (bash, glibc, git de la distro): `sh spikes/h0.3-aislamiento-lazyvim/run.sh /tmp/h03 test` con `DITTO_SPIKE_DISPOSABLE_HOME=1` **solo dentro de un usuario/contenedor desechable**: escribe fixtures en `$HOME`.
- [ ] Terminal.app (`.zsh_sessions`) y shells anidados a mano: ver *Otros*.
- [ ] Llevar la decisión a arch.md y roadmap.md con `/record-decision` (no se editan en esta story).

## Conclusión

Según el *Criterio de decisión* del issue, los casos de 4 que pasan por shell (y lazygit) **coinciden con el host** con la estrategia de §8 tal cual. Los procesos que nvim lanza con lista de argumentos (gitsigns, lazy.nvim) **fallan** con el mecanismo de §8 (`GIT_CONFIG_GLOBAL`) y también con `[include]`; el mecanismo alternativo validado es el enlace `.ditto/config/git`. Se confirma la estrategia de §8 con ese cambio, más `CONFIG_DIR` para lazygit y `TMPDIR` dentro del wrapper de nvim. Regla de fusión de extras: unión (el orden lo fija LazyVim).

## Decisión propuesta (texto para arch.md, vía `/record-decision`)

### §8 Aislamiento de entorno (sustituye la sección)

> ## 8. Aislamiento de entorno
>
> Regla: **cada herramienta se configura con su variable específica cuando existe; `XDG_*` solo para Neovim**, que no tiene alternativa (LazyVim, lazy.nvim y Mason dependen de `stdpath()`). Validado en H0.3 (macOS arm64 zsh/bash; Ubuntu 22.04 bash/zsh).
>
> | Herramienta | Mecanismo |
> |---|---|
> | nvim | `XDG_CONFIG_HOME`/`DATA`/`STATE`/`CACHE` → `.ditto/…` y `TMPDIR` → `.ditto/tmp` (solo dentro del wrapper) |
> | lazygit | `CONFIG_DIR=.ditto/config/lazygit` (también `state.yml`) y `LG_CONFIG_FILE` solo si no viene definido (Snacks.lazygit añade su tema) |
> | OpenCode | `OPENCODE_CONFIG_DIR` (+ ruta de datos/`auth.json` *(spike H0.2)*) |
> | ripgrep | `RIPGREP_CONFIG_PATH` |
> | fzf | `FZF_DEFAULT_OPTS_FILE` |
>
> La subshell **no** exporta `XDG_*` ni `MISE_*` (§12). Wrapper de Neovim (generado por ditto, POSIX sh):
>
> ```sh
> # .ditto/bin/nvim
> set -eu
> if [ "${DITTO_NVIM-}" != 1 ]; then        # guardar solo una vez (nvim anidado como hijo directo)
>   # por cada VAR de XDG_{CONFIG,DATA,STATE,CACHE}_HOME, PATH, TMPDIR, GIT_CONFIG_GLOBAL:
>   if [ -n "${VAR+x}" ]; then export DITTO_ORIG_VAR="$VAR"; fi   # ausente = no estaba definida
>   export DITTO_NVIM=1
>   export PATH="$DITTO_ROOT/mise/installs/node/<ver>/bin:…:$PATH"  # runtimes para Mason, solo aquí
> fi
> export XDG_CONFIG_HOME="$DITTO_ROOT/config" XDG_DATA_HOME="$DITTO_ROOT/data" \
>        XDG_STATE_HOME="$DITTO_ROOT/state"   XDG_CACHE_HOME="$DITTO_ROOT/cache"
> # git lanzado directamente por nvim: .ditto/config/git -> git del usuario
> _g="${DITTO_ORIG_XDG_CONFIG_HOME:-$HOME/.config}/git" _l="$XDG_CONFIG_HOME/git"
> if [ -e "$_l" ] && [ ! -L "$_l" ]; then
>   echo "ditto: $_l is not a symlink; left untouched" >&2      # nunca se toca algo que no es nuestro
> elif [ -d "$_g" ]; then
>   [ "$(readlink "$_l" 2>/dev/null || true)" = "$_g" ] || ln -sfn "$_g" "$_l"   # -n: reemplaza el enlace, no entra en él (GNU y BSD)
> elif [ -L "$_l" ]; then
>   rm -f "$_l"                                                  # sin git del usuario: se quita el enlace (solo enlaces)
> fi
> export TMPDIR="$DITTO_ROOT/tmp"; mkdir -p "$TMPDIR"
> exec "<AbsPath resuelto de nvim>" "$@"
> ```
>
> El aislamiento de esta sección se aplica igual sea cual sea el origen del binario: un `lazygit` del host también recibe `CONFIG_DIR`.
>
> **Procesos hijos de Neovim:**
>
> - La config de LazyVim fija `vim.o.shell = $DITTO_ROOT/bin/.host-sh` (si existe). `.host-sh` restaura los `DITTO_ORIG_*` (una variable sin `DITTO_ORIG_` se deja sin definir) y quita `DITTO_NVIM`; con argumentos hace `exec "$SHELL" "$@"` (`:!`, `system()` con string, y la clave `shell` de OpenCode con `-c <cmd>`), y sin argumentos reabre el shell de sesión con el rc de ditto (`:terminal`, terminal de Snacks). Validado: idéntico al host (`git config --show-origin --list`, `git check-ignore`, `ssh -G`, `command -v`).
> - **Todo wrapper de ditto restaura los `DITTO_ORIG_*` antes de lanzar su herramienta**: lazygit abierto desde LazyVim (`Snacks.lazygit`) ve el git del usuario. Validado.
> - **Procesos que nvim lanza con lista de argumentos** (gitsigns, lazy.nvim, `vim.system`, Mason) heredan el entorno de nvim. Para git, el enlace `.ditto/config/git` → `${XDG_CONFIG_HOME original:-~/.config}/git` hace que lea los mismos archivos (config, `ignore`, `attributes`, `credentials`) con la misma precedencia, en cualquier versión de git; solo cambia la ruta que muestra `--show-origin`. **Descartados:** `GIT_CONFIG_GLOBAL` (sustituye a `~/.gitconfig` en vez de sumarse, no recupera el ignore global, apunta al archivo equivocado con `XDG_CONFIG_HOME` propio y no existe antes de git 2.32) e `[include]` en `.ditto/config/git/config` (recupera la config pero no el `core.excludesFile` por defecto). Estos procesos sí ven el `PATH` de runtimes, a propósito.
>   **Excepción explícita a "nada se escribe fuera de `.ditto/`":** `.ditto/config/git` apunta a la configuración real del host, así que lo que esos procesos git escriban en su config global (`git config --global`, `credential-store` en `$XDG_CONFIG_HOME/git/credentials`) cae en los archivos del usuario, igual que si usara git sin ditto. ditto no escribe ahí por sí mismo; solo crea el enlace dentro de `.ditto/`.
> - El rc de la sesión (§12) apunta `HISTFILE`, `LESSHISTFILE`, `NODE_REPL_HISTORY` y `PYTHON_HISTORY` a `.ditto/state/`. Validado: ningún historial en `$HOME`.

### §9 LazyVim (sustituye las viñetas de extras y primer arranque)

> - **Starter** en el repo de dotfiles: `init.lua`, `lua/config/*`, `lua/plugins/*`, `lazy-lock.json`, `lazyvim.json`. ditto embebe un starter mínimo como valor por defecto (LazyVim/starter con `checker`, `change_detection` y `rocks` desactivados y `vim.o.shell = $DITTO_ROOT/bin/.host-sh`).
> - **Extras de lenguaje** (Python, Go, TS, Rust…) se activan desde el menú de setup (§10). **Regla de fusión:** unión; los extras del `lazyvim.json` del repo conservan su posición, los de ditto se añaden detrás en el orden del menú, sin duplicados, y el resto de claves (`version`, `install_version`, `news`) se conserva. **El orden no importa:** LazyVim (`lazyvim.plugins.xtras`) deduplica e importa los extras ordenados por su prioridad y por nombre, siempre entre `lazyvim.plugins` y `plugins`; validado en H0.3 (mismo orden de importación con las listas invertidas, sin aviso). Los extras se activan solo vía `lazyvim.json`, nunca con un `{ import = … }` en `lazy.lua` (eso sí rompe el orden y LazyVim avisa).
> - LazyVim **reescribe `lazyvim.json`** (noticias, migraciones, extras renombrados): ditto lo genera en `.ditto/config/nvim/` (copia, no enlace al clon de dotfiles) en cada `up`.
> - **Actualizaciones controladas**: `checker` y updates automáticos de lazy desactivados; la versión de plugins la fija `lazy-lock.json`. ditto clona lazy.nvim en el commit del lock antes del primer arranque.
> - **Primer arranque headless**: `nvim --headless "+Lazy! restore" +qa` con el wrapper y `.ditto/bin` en el `PATH` (nvim-treesitter busca el CLI de tree-sitter); deja cada plugin en el commit del lock y no modifica el lock (validado en H0.3). Precalentado de Mason: comando exacto *(spike H0.5)*.

(Las viñetas de Mason, Treesitter y Nerd Font no cambian.)

### §12 Sesión y shell (sustituye la primera viñeta)

> - **Subshell** (`ditto up`): `syscall.Exec` de `$SHELL` con el rc de ditto, que carga primero el rc del usuario y **después** antepone `.ditto/bin` al `PATH` (una sola vez), para que conda/pyenv/rc no lo desplacen. Validado en H0.3:
>   - bash: `bash --rcfile .ditto/shell/bashrc -i`; el rcfile hace `. ~/.bashrc`.
>   - zsh: `ZDOTDIR=.ditto/shell/zsh` y `DITTO_ORIG_ZDOTDIR` con el valor del usuario (ausente si no estaba definido). El `.zshenv` de ditto ejecuta el `.zshenv` del usuario con su `ZDOTDIR` (que puede cambiarlo) y vuelve a apuntar `ZDOTDIR` a ditto; el `.zshrc` de ditto **restaura el `ZDOTDIR` del usuario** (o lo deja sin definir), carga su `.zshrc` y aplica el `PATH` y los historiales. Las shells anidadas ven el `ZDOTDIR` original.
>   - Otros shells: `.ditto/bin` en el `PATH` y `exec $SHELL -i`.
>   - No se exporta ningún `XDG_*` ni `MISE_*`; `HISTFILE` y similares → `.ditto/state/` (§8).
>   - `:terminal` y el terminal de Snacks reabren este mismo shell de sesión a través de `.host-sh`.
>   - Mantener `.ditto/bin` primero ante cambios posteriores del `PATH` (activar entornos, direnv) es el hook de prompt de H0.1b *(no validado en H0.3)*.

### §18 Riesgos abiertos (sustituir las viñetas de herencia de variables y orden de extras; añadir)

> - **Herencia de variables en hijos de Neovim**: resuelta en H0.3 (§8). Queda: los procesos que nvim lanza con lista de argumentos ven `XDG_CONFIG_HOME=.ditto/config` y el `PATH` de runtimes; git está cubierto con el enlace `.ditto/config/git`, pero otras herramientas que lean `XDG_CONFIG_HOME` (p. ej. `pip` de Mason con `pip.conf`, `gh`) no. `--show-origin` muestra la ruta de `.ditto/config/git`.
> - **Longitud de la ruta del workspace**: `vim.loader` codifica la ruta completa de cada `.lua` en un nombre de archivo (`NAME_MAX` 255) y Neovim falla con `ENAMETOOLONG` si `DITTO_ROOT` es largo (≈ más de 70–80 caracteres); el socket RPC en `TMPDIR` debe caber en `sun_path` (104 bytes en macOS). `ditto up`/`doctor` deben avisar.
> - **Escrituras en el temporal del sistema**: lazygit crea `lazygit-<uid>` en `$TMPDIR`/`/tmp` (nvim ya no, con `TMPDIR` en el wrapper). Medir en H0.4.
> - **Shells anidados a mano** dentro de la sesión cargan el rc del usuario y pueden escribir su historial en `$HOME` (zsh con `HISTFILE` propio); en Terminal.app, `.zsh_sessions`. Pendiente de H0.4 y del hook de prompt de H0.1b.
> - **lazygit exige git ≥ 2.32** (0.66): no arranca en Ubuntu 18.04/20.04 con el git de la distro. `ditto doctor` debe avisar; fijar una versión de lazygit más antigua para esos hosts o aceptar que falte.
> - **Integridad de plugins**: lazy.nvim fija plugins por commit de git (SHA-1), no por sha256. Los parsers de nvim-treesitter, el registro de Mason y el binario de blink.cmp se descargan sin sha256 fijado: decidir en H0.5.
