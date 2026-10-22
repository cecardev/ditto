# H0.1b — ¿Puede mise llevar la sesión de ditto? (opción A vs B): resultados

**Issue:** #4 · **Fecha:** 2026-10-21 · **Depende de:** H0.1 (#1, `spikes/h0.1-mise-aislado/`) · **mise:** `2026.10.15`

## Pregunta

¿Puede mise, por sí solo (`mise en` / `mise exec` / `mise env` + `[env]`), lanzar y gestionar la sesión de ditto sin interferir con el host ni romper el aislamiento por herramienta?

**Respuesta corta: no → opción B.** Fallan tres verificaciones de los puntos 4 y 5 del issue, en macOS y en Linux, con bash y con zsh:

1. **El rc del usuario reordena el `PATH` después de `mise en`.** `mise en` calcula el entorno y *después* arranca el shell, que carga `.bashrc`/`.zshrc`. Con conda o con un rc que reconstruye `PATH`, `.ditto/bin` deja de ir primero y `rg`/`nvim` resuelven al de conda o al de `~/bin`. mise no tiene ningún punto de enganche posterior al rc.
2. **Un mise del host activado en el rc deshace la sesión.** `mise en` deja en el hijo `__MISE_DIFF` (el diff que aplicó). El `hook-env` del mise del host lo lee en el primer prompt y lo revierte: desaparecen `DITTO_ACTIVE`, `DITTO_ROOT` y `.ditto/bin` del `PATH`.
3. **Variables de mise en los procesos del host.** Con el `[env]` mínimo del issue, `mise en` y `mise exec` pasan al hijo las 21 `MISE_*` del aislamiento de H0.1, más `__MISE_DIFF` (`MISE_DATA_DIR`, `MISE_GLOBAL_CONFIG_FILE`, `MISE_IGNORED_CONFIG_PATHS`…). Cualquier `mise` del host lanzado desde la subshell usaría el store y la config de ditto. Además, `mise en <workspace>` carga el `mise.toml` del workspace del usuario aunque `MISE_CEILING_PATHS` apunte a `.ditto`. Se puede mitigar casi todo (`VAR = false` en `[env]` y `MISE_OVERRIDE_*_FILENAMES`), pero **`__MISE_DIFF` no se puede quitar**.

El aislamiento por herramienta (XDG solo en nvim, `.host-sh`, wrappers que restauran el entorno) **no depende de A o B**: funciona igual con las dos, porque vive en los wrappers de `.ditto/bin`. La sesión propia de ditto (B: `--rcfile` en bash, `ZDOTDIR` en zsh y hook de prompt) pasa todas las verificaciones de interferencia en las cinco plataformas probadas.

## Contenido del directorio

| Archivo | Para qué |
|---|---|
| `lib.sh` | Librería POSIX. Carga `../h0.1-mise-aislado/env.sh` **sin modificarlo** y añade: wrappers sh (`nvim`, `lazygit`, `rg`, `.host-sh` y `.probe`), la config de sesión de A (`mise-raw.toml`, `mise-clean.toml`), `spike_mise_session` y los rc de B (`bashrc`, `zsh/.zshenv`, `zsh/.zshrc`, `path.sh`). |
| `session.sh <ditto_dir> <modo> [shell]` | Sustituto de `ditto up`/`env`/`run` en los dos diseños: `up-a`, `up-a-raw`, `up-a-rc` (híbrido), `up-b`, `env-a`, `env-b`, `run-a`, `run-a-raw`, `run-b`. |
| `run.sh <dest>` | Pruebas T1–T7. `<dest>` es un directorio propio del spike (vacío o de una ejecución anterior, marcado con `.h01b-spike`; si no, aborta): el workspace es `<dest>/ws`, `.ditto` es `<dest>/ws/.ditto` y `TMPDIR=<dest>/tmp`. Aborta si `$HOME` no está bajo `<dest>` y no hay `DITTO_SPIKE_DISPOSABLE_HOME=1` (lo exportan `docker.sh` y `macos.sh`). Imprime `RESULT <id> <PASS\|FAIL\|INFO\|SKIP> …`. No escribe en `$HOME`: cada escenario tiene su HOME bajo `<dest>/homes/`. |
| `nvim-check.lua` | Lo que ven nvim y sus hijos (`:!`, `system()` con lista, `:terminal`, lazygit). |
| `docker.sh <imagen> <arch> <workdir>` | Driver Linux: imagen con bash, zsh, git y cliente ssh, y un `~/.ssh/config` de prueba en el home de passwd (`/root`). |
| `macos.sh <scratch>` | Driver macOS: `HOME`/`TMPDIR` desechables, `env -i` y barrido completo del `$HOME` real al terminar. |

Reutilización de H0.1: `ditto_mise_paths`, `ditto_mise_bootstrap`, `ditto_mise` (instalación, `which`), `_ditto_mise_isolate` (dentro de `spike_mise_session`) y `ditto_nvim_tool`, más el `mise.lock` compartido. `spike_mise_session` es una copia adaptada de `ditto_mise`: sustituye la config global por la de sesión, conserva el `HOME` real (el hijo es el shell del usuario y un `HOME` redirigido lo rompería) y no exporta los `DITTO_*` internos del spike. `env.sh` no se ha tocado.

## Montaje

**Común (T2).** `ditto_mise install --locked` con un subconjunto de la config de H0.1 (Neovim con su variante por glibc, ripgrep y lazygit) y el `mise.lock` de H0.1 (checksums verificados por mise). Los wrappers son scripts sh que exportan variables y hacen `exec` a la ruta de `mise which`:

- `nvim`: guarda `XDG_*` y `GIT_CONFIG_GLOBAL` en `DITTO_ORIG_*` (distinguiendo «sin definir» de «vacía»), exporta `XDG_*` → `.ditto/{config,data,state,cache}` y `GIT_CONFIG_GLOBAL` si existe `${XDG_CONFIG_HOME:-~/.config}/git/config` (arch.md §8). Su `init.lua` fija `vim.o.shell = .ditto/bin/.host-sh`.
- `lazygit`, `rg`, `.host-sh` y `.probe` empiezan con el mismo bloque de restauración (`DITTO_ORIG_*` → valor original o `unset`, y `PATH` original). Después exportan su variable propia (`LG_CONFIG_FILE`, `RIPGREP_CONFIG_PATH`) o ejecutan `$SHELL` (`.host-sh`). `.probe` es solo del spike: ejecuta `"$@"` tras el bloque para ver lo que recibe lazygit y el `git` que lanza.

**Opción A.** Config de sesión **sin `[tools]`**, cargada como config global (`MISE_GLOBAL_CONFIG_FILE`); con `[tools]`, los `bin/` de cada herramienta (y los runtimes) entrarían en el `PATH` de la subshell junto a los wrappers, en contra de §8.

```toml
[env]
DITTO_ACTIVE = "1"
DITTO_ROOT = "<ws>/.ditto"
_.path = ["<ws>/.ditto/bin"]
# solo en "clean": cada MISE_* del aislamiento a false (mise la quita del hijo)
MISE_DATA_DIR = false   # … (23 variables: las 21 del aislamiento y las 2 MISE_OVERRIDE_*)
```

- `up-a-raw`: `mise en -s "<shell> -i" <ws>` con el `[env]` mínimo del issue.
- `up-a`: lo mismo con la config `clean`, más `MISE_OVERRIDE_CONFIG_FILENAMES=ditto-none.toml` y `MISE_OVERRIDE_TOOL_VERSIONS_FILENAMES=ditto-none` para que no cargue `mise.toml`/`.tool-versions` del workspace. Es la mejor versión de A que se encontró.
- `up-a-rc` (híbrido): `mise en`, pero con el shell arrancado con los rc de B.
- `env-a`: `eval "$(mise env -s <shell>)"` en el shell del usuario (equivalente a `ditto env`).
- `run-a`: `mise exec -- <cmd>` (equivalente a `ditto run`).

**Opción B** (arch.md §12, prototipo en sh):

- bash: `exec bash --rcfile .ditto/session/bashrc -i`. El rcfile carga `~/.bashrc` y después `path.sh`, que exporta `DITTO_ACTIVE`/`DITTO_ROOT`, quita `.ditto/bin` de donde esté y lo antepone. Además añade `__ditto_path` **al final** de `PROMPT_COMMAND`.
- zsh: `ZDOTDIR=.ditto/session/zsh` con `DITTO_ORIG_ZDOTDIR`. `.zshenv` carga el del usuario (y si este cambia `ZDOTDIR`, lo recuerda y vuelve a poner el de ditto). `.zshrc` restaura `ZDOTDIR`, carga el `.zshrc` del usuario y después `path.sh`, y añade `__ditto_path` a `precmd_functions`.
- `env-b`: imprime los tres `export`. `run-b`: `PATH=.ditto/bin:$PATH DITTO_ACTIVE=1 DITTO_ROOT=… exec <cmd>`.

**Escenarios (T4)**, cada uno con su HOME:

| Escenario | rc del usuario (bash y zsh) |
|---|---|
| `clean` | solo un marcador `DITTO_SPIKE_RC_LOADED=1` |
| `conda` (**simulado**) | bloque `conda initialize` simulado: `CONDA_PREFIX`… y `PATH="$HOME/miniconda3/bin:$HOME/miniconda3/condabin:$PATH"`, con `rg`, `nvim` y `python` falsos en `miniconda3/bin` |
| `pathreset` | `export PATH="$HOME/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"` (reconstruye el `PATH`), con un `rg` falso en `~/bin` |
| `hostmise` | `eval "$(~/.local/bin/mise activate <shell>)"`: un mise del host (mismo binario, sin aislar) con `~/.config/mise/config.toml` que define `[env] HOST_MISE_MARKER` y `_.path` hacia un directorio con un `rg` falso |
| `hostmiseaggr` | igual, con `[settings] activate_aggressive = true`: `hook-env` antepone sus rutas en cada prompt |

En todos hay además un `<ws>/mise.toml` del usuario con `[env] WS_MARKER` y un `~/.config/git/config` con `user.name = ditto-fixture-xdg-git` (en la ruta XDG, para que el aislamiento de XDG de nvim lo pueda ocultar).

**Cómo se ejecuta cada caso.** Se simula al usuario escribiendo `ditto` en su shell: `env -i HOME=<home> SHELL=<shell> PATH=<base> "$shell" -i -c 'exec sh session.sh …'`. La subshell es interactiva (`-i`) y lee las órdenes por stdin, así que carga el rc y ejecuta `PROMPT_COMMAND`/`precmd` antes de cada línea. Tras dos prompts vacíos, `check.sh` imprime `PATH[0]`, `command -v rg`, las `MISE_*`/`__MISE_*`, `XDG_*` y `DITTO_*`, la vista del mise del host (`config ls`, `data dir`) y, si `nvim` es el wrapper, el resultado de `nvim-check.lua`. Cada caso se compara con `base`, el mismo shell interactivo sin ditto: «nuevo» significa «que no estaba sin ditto».

## Resultados

### Plataformas

| Plataforma | Cómo | Shells | git | Resultado de B (`up-b`) |
|---|---|---|---|---|
| macOS arm64 (Darwin 25.2) | host, `macos.sh` (`HOME`/`TMPDIR` desechables) | bash 3.2.57, zsh 5.9 | 2.50.1 | todo PASS |
| Ubuntu 22.04 arm64 | Docker, nativo | bash 5.1.16, zsh 5.8.1 | 2.34.1 | todo PASS (incl. ssh) |
| Ubuntu 22.04 amd64 | Docker, emulado | ídem | 2.34.1 | todo PASS (incl. ssh) |
| Ubuntu 18.04 arm64 (glibc 2.27) | Docker, nativo | bash 4.4.20, zsh 5.4.2 | 2.17.1 | todo PASS salvo `GIT_CONFIG_GLOBAL` (ver T5) |
| Ubuntu 18.04 amd64 (glibc 2.27) | Docker, emulado | ídem | 2.17.1 | todo PASS salvo `GIT_CONFIG_GLOBAL` |

Los resultados de A son idénticos en las cinco plataformas y en los dos shells.

### T1 — Bootstrap: `mise generate bootstrap`

`mise generate bootstrap` es un alias obsoleto de **`mise generate install-script`** (aviso: *se eliminará en mise 2027.9.0*). Se generó con `-V 2026.10.15 --localize` y se ejecutó con `--version`.

| Comprobación | Resultado |
|---|---|
| Instala la versión fijada | ✅ en todas las plataformas; el binario coincide byte a byte con el asset de la release (`macos-arm64`; en Linux glibc, el asset **glibc** `linux-<arch>`, no el `-musl`) |
| Verificación | ✅ lleva embebidos los sha256 de los **tarballs** de la versión fijada (`.tar.gz` y `.tar.zst`, 8 plataformas). Un archivo manipulado con el nombre esperado (`MISE_TARBALL_URL=file://…`) se rechaza: `mise: checksum mismatch …` |
| Origen | primero `mise.jdx.dev` y, si falla, GitHub Releases; el checksum nunca viene del mirror |
| Shell | **bash** (`#!/usr/bin/env bash`, `local`, `exec -a`), no POSIX sh. En Alpine (sin bash) no funciona |
| Aislamiento | `--localize` solo exporta 7 variables (`MISE_DATA_DIR`, `CONFIG_DIR`, `CACHE_DIR`, `STATE_DIR`, `INSTALL_PATH`, `TRUSTED_CONFIG_PATHS`, `IGNORED_CONFIG_PATHS`) y hace `exec` de mise. No borra las `MISE_*` del host ni fija `MISE_GLOBAL_CONFIG_FILE`, `MISE_SYSTEM_*`, `MISE_CEILING_PATHS`, la telemetría ni `HOME`/`XDG_*` (caché de sigstore). Es decir, no cubre el aislamiento de H0.1 |
| Ubicación | El proyecto es el directorio padre del script (`<proyecto>/bin/mise` → datos en `<proyecto>/.mise`). Ponerlo en `.ditto/bin/mise` sombrearía el `mise` del host |
| Escrituras fuera | descarga en `mktemp -d`: `$TMPDIR` o `/tmp` en Linux, y en macOS el temporal por usuario (`getconf DARWIN_USER_TEMP_DIR`, `/var/folders/…/T`), **ignorando `TMPDIR`**. Si la verificación falla, **no lo borra**: en las primeras ejecuciones quedó `tmp.XXXX/mise-v2026.10.15-<os>-<arch>.tar.gz` en `/tmp` (Linux) y en `DARWIN_USER_TEMP_DIR` (macOS). Ahora `run.sh` antepone, solo en esas llamadas, un shim de `mktemp` que convierte `mktemp -d` en `mktemp -d "$TMPDIR/tmp.XXXXXX"` (`TMPDIR=<dest>/tmp`), registra lo que queda (`T1-install-script-tmp`) y lo borra |

**Conclusión T1:** sirve para que un repo lleve su propio `bin/mise`, pero no sustituye a `install.sh` (que instala **ditto**, no mise) ni al bootstrap de ditto, que ya embebe el sha256 del binario y aplica el aislamiento completo de H0.1. Fila «Repetición parcial» → **no se adopta**.

### T3 — Sesión: `mise en` / `mise exec` / `mise env` frente a §12

| Requisito (§12 y `ditto env`) | A: mise | B: ditto |
|---|---|---|
| Subshell bash y zsh con el rc del usuario | ✅ `mise en -s "<shell> -i"` | ✅ |
| `.ditto/bin` primero **después** del rc | ❌ `mise en` no tiene enganche posterior al rc (T4) | ✅ |
| `DITTO_ACTIVE` y `DITTO_ROOT` | ✅ vía `[env]`, salvo con un mise del host activado (T4) | ✅ |
| Restaurar `ZDOTDIR` en shells anidadas | — (no lo usa) | ✅ |
| `ditto env` (`eval`, tmux) | ⚠️ `mise env` funciona, pero con la config `clean` emite 23 `unset MISE_*` (una por cada `VAR = false`), que borrarían las `MISE_*` propias del usuario en su shell. Con la `raw` no las emite. Aporta solo tres `export` | ✅ tres `export` |
| `ditto run -- cmd` | ❌ `mise exec` pasa al hijo las 21 `MISE_*` del aislamiento más `__MISE_DIFF` (`raw`; el spike las cuenta como 22) o solo `__MISE_DIFF` (`clean`) | ✅ 0 `MISE_*` |
| No anidar | igual en A y B: depende de `DITTO_ACTIVE` | |

### T4 — Interferencia con el host

Fallos por lanzador × escenario (iguales en macOS y Linux, bash y zsh). El escenario conda es **simulado** (ver *Montaje*):

| Lanzador | clean | conda (simulado) | pathreset | hostmise | hostmiseaggr |
|---|---|---|---|---|---|
| `up-a-raw` (`mise en`, `[env]` mínimo) | ❌ 21 `MISE_*` + `__MISE_DIFF` en la subshell; carga `<ws>/mise.toml` | — | — | — | — |
| `up-a` (`mise en`, config `clean`) | ❌ `__MISE_DIFF` | ❌ `PATH[0]` = `miniconda3/bin`, `rg` de conda; `__MISE_DIFF` | ❌ `PATH[0]` = `~/bin`, `rg` falso; `__MISE_DIFF` | ❌ el mise del host revierte el diff: sin `DITTO_ACTIVE`/`DITTO_ROOT`, `rg` del host | ❌ ídem |
| `up-a-rc` (híbrido) | ❌ `__MISE_DIFF` | ❌ `__MISE_DIFF` | ❌ `__MISE_DIFF` | ✅ | ✅ |
| `env-a` (`eval "$(mise env)"`) | ✅ | ✅ | ✅ | ✅ | ❌ `PATH[0]` = rutas del mise del host |
| `env-b` (tres `export`) | ✅ | ✅ | ✅ | ✅ | ❌ ídem |
| **`up-b`** (rcfile/ZDOTDIR + hook) | ✅ | ✅ | ✅ | ✅ | ✅ |

En `hostmise*`, con `up-b` el mise del host sigue intacto. `mise config ls` lista su `~/.config/mise/config.toml` (no el de ditto), su data dir es el suyo, y su `[env]` (`HOST_MISE_MARKER`) y su `_.path` siguen aplicándose, detrás de `.ditto/bin`. `<ws>/mise.toml` se carga exactamente igual que sin ditto (lo carga el mise del host, no ditto).

Lecturas:

- El **híbrido** `up-a-rc` solo pasa porque el rc de ditto rehace todo lo que hizo `mise en`. En `hostmise*` pasa porque el mise del host revierte el diff de ditto y después el rc de ditto lo vuelve a aplicar. mise no aporta nada y deja `__MISE_DIFF`.
- **El hook de prompt de B es necesario**: con `activate_aggressive = true`, el `hook-env` del host antepone sus rutas en cada prompt. `env-b`/`env-a` (sin hook) pierden el primer puesto; `up-b`, cuyo hook va después del de mise en `PROMPT_COMMAND`/`precmd_functions`, lo mantiene. Con el `activate` por defecto, `hook-env` no desplaza lo que se antepone después.
- `ditto env` no puede garantizar el orden frente a un hook agresivo, salvo que también imprima el hook (`eval` de una función + `PROMPT_COMMAND`/`precmd`).

### T5 — Aislamiento por herramienta (igual en A y B)

Medido dentro de las sesiones `up-*` en las que `nvim` resuelve al wrapper. En `up-a` con conda/pathreset, `nvim` resolvía al falso del escenario y no hubo medida.

| Comprobación | Resultado |
|---|---|
| `XDG_*` en la subshell | ✅ ninguna nueva respecto a `base`, en A y B |
| Dentro de nvim | ✅ `XDG_CONFIG_HOME=.ditto/config`, `stdpath("data")=.ditto/data/nvim`, `shell=.ditto/bin/.host-sh` |
| `:!` / `system("…")` (pasa por `.host-sh`) | ✅ sin `XDG_*`; `git config --global user.name` = el del usuario |
| `:terminal` | ✅ sin `XDG_*`; git ve la config real |
| `system({"git", …})` (argv directo, como gitsigns) | ✅ con git ≥ 2.32 gracias a `GIT_CONFIG_GLOBAL`. ❌ **en Ubuntu 18.04 (git 2.17.1)**: git ignora `GIT_CONFIG_GLOBAL` (existe desde git 2.32) y, con `XDG_CONFIG_HOME` de nvim, no encuentra `~/.config/git/config`. Control: sin `GIT_CONFIG_GLOBAL`, git no ve nada en ninguna plataforma |
| Alternativa: `.ditto/config/git/config` con `[include] path = ~/.config/git/config` | ✅ en todas, incluida git 2.17.1. git lo lee junto a `~/.gitconfig`, mientras que `GIT_CONFIG_GLOBAL` sustituye a `~/.gitconfig`. (`git config --global` necesita `--includes` para seguirlo; `commit`, `log`… lo siguen siempre) |
| lazygit desde nvim | ✅ resuelve a `.ditto/bin/lazygit`; `lazygit -cd` = `~/.config/lazygit` (no `.ditto/config`); el proceso y su `git` no ven `XDG_*` ni `GIT_CONFIG_GLOBAL`, y git ve la config real |
| ssh desde `:!`, `:terminal` y bajo lazygit (Docker) | ✅ `ssh -G ditto-fixture` → `user ditto-fixture-ssh`. ssh lee `~/.ssh/config` del **home de passwd**, no de `$HOME`, así que ni `XDG_*` ni un `HOME` distinto lo afectan. En macOS se desactivó (`SPIKE_SSH_FIXTURE`): ahí no hay fixture y leería el `~/.ssh/config` real. Una primera versión del spike lo ejecutó una vez en el Mac (`ssh -G`, solo lectura, sin conexión) |
| `MISE_*`/`[env]` en procesos del host | A: ❌ (T3/T4). B: ✅ solo `DITTO_ACTIVE` y `DITTO_ROOT`, que son las previstas |

### T6 — Tabla «Solapamiento con mise», confirmada con `2026.10.15`

| Función de ditto | ¿Lo cubre mise? (comprobado) | Estado tras H0.1b |
|---|---|---|
| Descarga, checksums, lockfile, versiones, `prune`, `link` | Sí (H0.1: `install --locked`, `lock --global`, `link`; `prune --help`) | **Delegado** |
| `install.sh` + bootstrap de mise con sha256 | Parcial: `generate install-script` (bash, sha256 embebido, aislamiento parcial; T1) | **No se adopta**: el bootstrap es de ditto (sha256 embebido, H0.1); `install.sh` instala ditto |
| Subshell (`ditto up`) | `mise en` existe, pero no puede ir después del rc y deja `__MISE_DIFF` (T3/T4) | **Valor propio** (B) |
| `ditto env` / `ditto run` | `mise env` / `mise exec` existen; `exec` filtra `MISE_*`/`__MISE_DIFF` al hijo y `env` sin hook no resiste un `activate_aggressive` | **Valor propio** (B): tres `export` / `exec` con `PATH` |
| `PATH` y variables de la sesión | `[env]`, `_.path`, `_.file` funcionan (`mise env` los aplica, T6) | **Valor propio**: son dos variables y un directorio; no compensa una config de mise para ello |
| Secretos (`.ditto/secrets`) | `[env]` con archivos sops/age (`sops.rops = true`: implementación interna, sin binario sops) y `mise exec --secrets` (*experimental*). No probado | Solapamiento posible; fuera de la sesión de mise no aporta. Decidir en H2 |
| Wrappers por binario | `generate tool-stub`: el stub es `#!/usr/bin/env -S mise tool-stub` + TOML (`url`; al descargar, también checksum, tamaño y `bin`). Ejecuta mise en **cada** invocación y necesita `mise` en `PATH`. La ayuda de `2026.10.15` no documenta variables por herramienta | **Valor propio** |
| `doctor` | `mise doctor` cubre mise (dirs, config, avisos); no prerrequisitos, LazyVim ni Mason | ditto añade lo suyo y puede incluir la salida de `mise doctor` |
| Variante por glibc / musl / AVX2 | Parcial (H0.1): `platforms.<os>-<arch>` no distingue libc ni CPU | Valor propio: ditto genera `config.toml` por host |
| Configuración aislada por herramienta | No: `[env]` es global a la sesión. `mise exec --allow-env/--deny-env` filtra el entorno heredado (deja `PATH`, `HOME`, `USER`, `SHELL`, `TERM`, `COLORTERM`, `LANG`), pero no fija variables por herramienta | **Valor propio** |
| Menú, perfil, `ditto.toml` | No | Valor propio |
| LazyVim (starter, extras, `Lazy! restore`, Mason) | No | Valor propio |
| Dotfiles por git | No | Valor propio |
| `bundle` offline | No | Valor propio |
| Binario único autocontenido | No | Valor propio |

### Lo que mise no puede hacer (alcance exacto de lo que construye ditto)

1. **Bootstrap de mise**: descarga del asset fijado con sha256 embebido en ditto (build `-musl` en Linux) y aislamiento completo por proceso (las `MISE_*` de H0.1 + `HOME`/`XDG_*`/`TMPDIR` → `.ditto/mise/home`, `cwd=.ditto/mise`). `generate install-script` no lo cubre (T1).
2. **`install.sh`** de ditto (descarga de ditto + sha256).
3. **Generar `.ditto/mise/config.toml`** por host con la variante (glibc legacy, musl, baseline) y el lock (H0.1).
4. **Wrappers** sh en `.ditto/bin`, con variables propias de cada herramienta y el bloque común que restaura `DITTO_ORIG_*`; **`.host-sh`** para `vim.o.shell`; y la config de git para nvim (`[include]` en `.ditto/config/git/config`, porque `GIT_CONFIG_GLOBAL` no existe antes de git 2.32).
5. **Subshell**: `bash --rcfile` / `ZDOTDIR` (zsh) que cargan el rc del usuario, después anteponen `.ditto/bin` (sin duplicados) y registran un hook de prompt al final (`PROMPT_COMMAND` / `precmd_functions`) que lo mantiene primero. También restauran `ZDOTDIR` y respetan un `.zshenv` que lo cambie, y exportan `DITTO_ACTIVE`/`DITTO_ROOT`. Ninguna `MISE_*`.
6. **`ditto env`**: los `export` (y, opcionalmente, el hook) para `eval`. **`ditto run`**: `exec` con `PATH` y `DITTO_*`.
7. Menú, perfil, LazyVim/Mason, dotfiles, `bundle`, `doctor` (prerrequisitos de la categoría B), secretos.

mise se queda con lo que hace bien y se usa **solo durante la instalación**: `install --locked`, `lock --global`, `link`, `which`/`where`, `prune` y `doctor` (como parte del de ditto).

### T7 — Escrituras fuera de `<dest>`

- `find $HOME /tmp $TMPDIR -newer <marker>`: vacío en todas las plataformas, salvo dos casos que se anotan aparte:
  - `install-script` deja su `mktemp -d` cuando falla la verificación (prueba de manipulación). Con el shim de `mktemp` queda en `<dest>/tmp`, y `T1-install-script-outside` exige que no aparezca nada fuera de `<dest>`, incluido `DARWIN_USER_TEMP_DIR` en macOS (que ahora forma parte del barrido de T7). Ver *Pendientes* para los restos de las primeras ejecuciones.
  - nvim crea `$TMPDIR/nvim.<usuario>/` para sus temporales (`/tmp/nvim.<usuario>` si no hay `TMPDIR`). Las sesiones reciben ahora `TMPDIR=<dest>/tmp`, y `T7-nvim-tmp` exige PASS. En el producto, el `TMPDIR` de la sesión es el del usuario: dónde escribe nvim sus temporales se decide en H0.4.
- En la ejecución final en macOS (tras la ronda de revisión), `T7-outside` pasa con `$HOME`, `/tmp`, el `TMPDIR` del llamador y `DARWIN_USER_TEMP_DIR` vigilados. El ruido de otros procesos en `/tmp` se excluye con `DITTO_SPIKE_WATCH_EXCLUDE` (sin valor por defecto).
- macOS, barrido completo del `$HOME` real (`macos.sh`): ninguna ruta de mise, shells ni herramientas. El resto (vscode-server, colima, procesos de otros agentes) es actividad ajena de la máquina.

### Comandos

```sh
# macOS (HOME/TMPDIR desechables; nada en el $HOME real; <dest> = $SCRATCH/mac/dest)
DITTO_SPIKE_WATCH_EXCLUDE='<ruido ajeno en /tmp, si lo hay>' sh spikes/h0.1b-mise-sesion/macos.sh "$SCRATCH/mac"
# Linux (nativo arm64 y emulado amd64)
sh spikes/h0.1b-mise-sesion/docker.sh ubuntu-22.04 arm64 "$SCRATCH/u22-arm64"
sh spikes/h0.1b-mise-sesion/docker.sh ubuntu-22.04 amd64 "$SCRATCH/u22-amd64"
sh spikes/h0.1b-mise-sesion/docker.sh ubuntu-18.04 arm64 "$SCRATCH/u18-arm64"
sh spikes/h0.1b-mise-sesion/docker.sh ubuntu-18.04 amd64 "$SCRATCH/u18-amd64"
```

Totales (`SUMMARY`; los FAIL son los esperados: variantes A, `env-*` con `hostmiseaggr` y `GIT_CONFIG_GLOBAL` en git 2.17). Con el código final (ronda de revisión: shim de `mktemp`, `TMPDIR=<dest>/tmp`, `<dest>/ws`, guarda de `HOME`, `set -eu` en los wrappers): macOS arm64 685 PASS / 46 FAIL; Ubuntu 22.04 arm64 751 PASS / 46 FAIL. Ubuntu 22.04 amd64 (749 / 46) y Ubuntu 18.04 arm64/amd64 (727 / 68) son de la versión anterior del spike. Esos cambios no alteran las pruebas de sesión, y su resultado era idéntico al de las otras plataformas.

## Hallazgos adicionales

- **`mise en <dir>` ignora `MISE_CEILING_PATHS`** para el propio `<dir>`: carga `<dir>/mise.toml`. `MISE_IGNORED_CONFIG_PATHS=<ws>` lo evita, pero también ignora la config de sesión (está bajo `<ws>/.ditto`). `MISE_OVERRIDE_CONFIG_FILENAMES` y `MISE_OVERRIDE_TOOL_VERSIONS_FILENAMES` sí funcionan.
- **`[env]` con `VAR = false`** quita la variable del entorno del hijo (`mise en`/`exec`) y en `mise env` se convierte en `unset VAR`. No afecta a los ajustes del propio proceso de mise. Las claves duplicadas rompen la config (`duplicate key`) y mise deja de cargarla.
- **`__MISE_DIFF`** lo añade siempre `mise en`/`exec` y no se puede quitar con `[env]`. Es lo que permite a un `mise activate` del host revertir la sesión.
- **`mise env`** no emite `__MISE_DIFF` y, por eso, convive con un mise del host no agresivo.
- **`mise exec --deny-env`/`--allow-env`** (sandbox) filtra el entorno heredado; no es útil para una sesión de usuario.
- El rc de bash solo se carga en shells **no login** (`~/.bashrc`): una subshell de ditto lo es. En macOS, Terminal abre shells login (`~/.bash_profile`, `/etc/zprofile` con `path_helper`), pero la subshell de ditto no pasa por ellos.

## Pendientes (no cubiertos aquí)

- [ ] **conda real** (aquí simulado con el `PATH` y las `CONDA_*` que deja `conda activate base`): en un servidor con conda, `sh spikes/h0.1b-mise-sesion/run.sh /tmp/ditto-h01b`. Atención: ejecutar solo con un `HOME` desechable o en un usuario de pruebas, porque los binarios descargados se ejecutan con ese `HOME`.
- [ ] **x86_64 real** y **servidores reales** del usuario (rc reales, `mise activate` real, direnv/pyenv): mismo comando.
- [ ] **macOS x64**: `sh spikes/h0.1b-mise-sesion/macos.sh <scratch>`.
- [ ] **Alpine/musl**: `install-script` exige bash; el resto de la sesión B es sh/bash/zsh y no depende de libc. No se ejecutó (sin Neovim en musl, H0.1).
- [ ] **Shells login, fish y `mise activate --shims`**: no se probaron. `--shims` antepone una ruta una sola vez en el rc, el mismo patrón que `conda`/`pathreset`.
- [ ] **`ditto env` en tmux** con un hook agresivo del host: definir si `ditto env` imprime también el hook.
- [ ] **Limpieza en el Mac de desarrollo** (fuera de `$HOME`): las pruebas de manipulación de `install-script` dejaron directorios `tmp.XXXX/` con un tarball falso de ~180 bytes (`mise-v2026.10.15-macos-arm64.tar.gz`, contiene un script que solo hace `echo tampered`) en el temporal por usuario. No se borraron desde el spike. Para listarlos y borrarlos: `ls -d "$(getconf DARWIN_USER_TEMP_DIR)"tmp.*/mise-v2026.10.15-macos-arm64.tar.gz` y, tras revisarlos, `rm -r` de esos `tmp.*`. macOS también los purga solo.
- [ ] **H0.1 (T7) tampoco vigilaba `DARWIN_USER_TEMP_DIR`** en macOS: lo que se escriba con `mktemp` sin plantilla no aparecía en su barrido.
- [ ] **Para H1.6**: (1) en bash ≥ 5.1 `PROMPT_COMMAND` puede ser un array. El prototipo lo trata como cadena: con un array, la asignación modifica solo el elemento 0, así que el hook de ditto no quedaría el último. Si es un array, hay que hacer `PROMPT_COMMAND+=(__ditto_path)`. (2) `ditto env` (y los rc generados) deben escapar las rutas para el shell. El prototipo (`spike_env_b`) las envuelve en comillas simples, y una ruta con `'` lo rompe.
- [ ] Llevar la decisión a arch.md y roadmap.md con `/record-decision` (no se editan en esta story).

## Decisión propuesta

**Opción B: sesión propia de ditto; mise solo instala.** Según el *Criterio de decisión* del issue, fallan las verificaciones 4.1 (mise del host), 4.2 (conda), 4.3 (rc que reordena `PATH`) y 5.3 (`MISE_*`/`__MISE_DIFF` en los procesos del host). La lista de *Lo que mise no puede hacer* es el alcance de H1.6.

Texto propuesto para `/record-decision`:

### arch.md §1 — «Solapamiento con mise» (sustituye el título, la frase inicial, la tabla, la conclusión y la «Decisión pendiente»)

> ### Solapamiento con mise *(validado en H0.1b)*
>
> Comparación de lo que este documento asigna a ditto con lo que trae mise `2026.10.15`, comprobada en H0.1b (`spikes/h0.1b-mise-sesion/`).
>
> | Función de ditto | ¿Lo cubre mise? | Decisión |
> |---|---|---|
> | Descarga, checksums, lockfile, versiones, `prune`, `link` | Sí, es su núcleo | Delegado |
> | `install.sh` + bootstrap de mise con sha256 | Parcial: `mise generate install-script` (antes `generate bootstrap`) es bash, solo fija 7 `MISE_*` y no cubre el aislamiento de §2 | Propio: el bootstrap lo hace ditto (sha256 embebido); `install.sh` instala ditto |
> | Subshell con el entorno (`ditto up`) | `mise en` existe, pero aplica el entorno **antes** del rc del usuario (conda o un rc que reconstruye `PATH` desplazan `.ditto/bin`) y deja `__MISE_DIFF`, que un `mise activate` del host revierte | **Propio** (§12) |
> | `ditto env` / `ditto run -- cmd` | `mise env` / `mise exec` existen; `exec` pasa al hijo las `MISE_*` del aislamiento (o `__MISE_DIFF`) | Propio: `export` / `exec` con `PATH` |
> | `PATH` y variables de la sesión | `[env]`, `_.path`, `_.file` | Propio: `DITTO_ACTIVE`, `DITTO_ROOT` y `.ditto/bin` |
> | Secretos (`.ditto/secrets`) | Parcial: `[env]` admite archivos sops/age; `exec --secrets` es experimental | Propio; revisar en H2 |
> | Wrappers por binario con `exec` | Parcial: `mise generate tool-stub` ejecuta mise en cada llamada (necesita `mise` en `PATH`) y no documenta variables por herramienta | Propio |
> | `doctor` | Parcial: `mise doctor` cubre mise | ditto añade prerrequisitos, LazyVim y Mason |
> | Variante por glibc / musl / AVX2 | Parcial: opciones por `os-arch`, sin libc ni CPU | Propio (genera `config.toml` por host) |
> | Configuración aislada por herramienta | No: `[env]` es global a la sesión | Propio |
> | Menú, perfil, LazyVim, dotfiles, `bundle`, binario único | No | Propio |
>
> **Decisión (H0.1b): opción B.** mise solo instala (`install --locked`, `lock`, `link`, `which`, `prune`) y nunca participa en la sesión. ditto controla la subshell, `ditto env` y `ditto run` (§12). La opción A (`mise en`/`exec`/`env` con `[env]`) se descartó porque falló en macOS y Linux, con bash y con zsh: (1) conda o un rc que reconstruye `PATH` desplazan `.ditto/bin`, porque mise no puede actuar después del rc; (2) un `mise activate` del host revierte la sesión a través de `__MISE_DIFF`; (3) las `MISE_*` del aislamiento y `__MISE_DIFF` llegan a los procesos del host, y `mise en <ws>` carga el `mise.toml` del workspace del usuario.

### arch.md §2 — fila «Sesión en tiempo de ejecución»

> | Sesión en tiempo de ejecución | **Propia de ditto** (H0.1b, opción B): subshell con `--rcfile` (bash) / `ZDOTDIR` (zsh) que carga el rc del usuario y después antepone `.ditto/bin`, más un hook de prompt que lo mantiene primero; `ditto env` y `ditto run` sin mise. mise solo instala (§1, *Solapamiento con mise*) |

### arch.md §3 — párrafo bajo el diagrama (sustituye el actual)

> En tiempo de ejecución **mise no participa** (decidido en H0.1b): los wrappers apuntan directamente a la ruta absoluta resuelta (`mise which` si el origen es ditto, la ruta del host si es host). Ni `mise activate`, ni `mise en`/`exec`/`env`, ni shims de mise en la subshell, y ninguna `MISE_*` en su entorno. Un mise del host activado en el rc del usuario sigue funcionando dentro de la subshell con su propia config, detrás de `.ditto/bin`.

### arch.md §12 — Sesión y shell (sustituye la sección)

> ## 12. Sesión y shell
>
> Validado en H0.1b (macOS arm64; Ubuntu 18.04 y 22.04, arm64 y amd64; bash 3.2–5.1, zsh 5.4–5.9), con conda, un rc que reconstruye `PATH` y un `mise activate` del host (también con `activate_aggressive`).
>
> - **Subshell** (`ditto up`): `syscall.Exec` de `$SHELL` interactivo.
>   - **bash**: `bash --rcfile .ditto/session/bashrc -i`. El rcfile carga `~/.bashrc` y **después** exporta `DITTO_ACTIVE=1` y `DITTO_ROOT`, y antepone `.ditto/bin` al `PATH` quitando duplicados.
>   - **zsh**: `ZDOTDIR=.ditto/session/zsh` y `DITTO_ORIG_ZDOTDIR=<original>`. Su `.zshenv` carga el del usuario y, si este cambia `ZDOTDIR`, lo toma como original y vuelve a poner el de ditto. Su `.zshrc` restaura `ZDOTDIR` (para shells anidadas), carga el `.zshrc` del usuario y después hace lo mismo que bash.
>   - **Hook de prompt**: `__ditto_path` se añade **al final** de `PROMPT_COMMAND` (bash) / `precmd_functions` (zsh) y vuelve a poner `.ditto/bin` primero si algo lo desplazó. Es necesario: un `mise activate` del host con `activate_aggressive` (y herramientas similares) antepone sus rutas en cada prompt.
>   - No se exporta ninguna `MISE_*` ni `XDG_*`. Las del usuario (incluido un mise del host) pasan intactas.
> - **`ditto env`**: imprime los `export` de `DITTO_ACTIVE`, `DITTO_ROOT` y `PATH` para `eval "$(ditto env)"` (tmux, scripts). Sin hook no puede garantizar el orden frente a un hook agresivo del host: `ditto env --hook` puede imprimir también la función y su registro.
> - **`ditto run -- cmd`**: `exec` de `cmd` con `PATH=.ditto/bin:$PATH`, `DITTO_ACTIVE` y `DITTO_ROOT`; sin `MISE_*`.
> - `DITTO_ACTIVE=1` evita anidar: `ditto` dentro de ditto informa y no abre otra subshell.

### roadmap.md — nota de alcance de H1.6 (sustituye la nota en cursiva)

> *(Alcance fijado por H0.1b: opción B, sesión propia de ditto. mise no participa en tiempo de ejecución.)* Wrappers por herramienta con variables específicas, bloque común que restaura `DITTO_ORIG_*` y `exec` a la ruta absoluta resuelta (mise o host; sin wrapper si es del host y no necesita config); `.host-sh`; config de git para nvim con `[include]` (no basta con `GIT_CONFIG_GLOBAL`, que exige git ≥ 2.32); subshell bash (`--rcfile`) y zsh (`ZDOTDIR`) con el rc del usuario primero, `.ditto/bin` antepuesto después y hook de prompt; `ditto env`; `ditto run`; `DITTO_ACTIVE`. **Aceptación:** con conda, un rc que reconstruye `PATH` y un `mise activate` del host (también agresivo) en el rc, `command -v rg` es `.ditto/bin/rg` tras varios prompts, la subshell no tiene ninguna `MISE_*` nueva y el mise del host sigue viendo solo su config.

### Ajustes sugeridos en otras secciones (no los pide el issue; para `/record-decision` o H0.3)

- **§8, procesos hijos de Neovim:** `GIT_CONFIG_GLOBAL` solo existe desde **git 2.32** (Ubuntu 18.04 trae 2.17.1, y el prerrequisito actual es git ≥ 2.19). Además, cuando existe, sustituye a `~/.gitconfig`. Propuesta: el wrapper de nvim **no** exporta `GIT_CONFIG_GLOBAL`. ditto escribe en su lugar `.ditto/config/git/config` con `[include] path = ~/.config/git/config` (o `$XDG_CONFIG_HOME/git/config` original), que git lee junto a `~/.gitconfig` en cualquier versión. Validado en git 2.17.1, 2.34.1 y 2.50.1.
- **§8 / H0.4:** nvim escribe sus temporales en `$TMPDIR/nvim.<usuario>` (o `/tmp/nvim.<usuario>`). Valorar `TMPDIR=.ditto/tmp` **solo** en el wrapper de nvim (restaurado en `.host-sh`).
- **§18 Riesgos:** los hooks de prompt de terceros que reordenan `PATH` (mise agresivo, direnv, pyenv) dependen de que el hook de ditto se registre el último; un rc que añada su hook *después* de cargar (p. ej. desde `precmd` diferido) podría ganarle.
