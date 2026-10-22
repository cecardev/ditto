# Spike H0.2: aislamiento y variantes de OpenCode (#2)

**Pregunta:** ¿con qué variables se aísla por completo la configuración, los datos y las credenciales de OpenCode dentro de `.ditto/`, y qué variante del release necesita cada plataforma?

**Respuesta corta:**

- `OPENCODE_CONFIG_DIR` **no basta**. OpenCode calcula datos, estado, caché y logs **solo** con `XDG_*` (librería `xdg-basedir`) y crea esos directorios en `$HOME` al arrancar, incluso con `opencode --version`. Con `OPENCODE_CONFIG_DIR` solo, sigue escribiendo en `~/.config/opencode` (un `.gitignore`), `~/.local/share/opencode` (base de datos de sesiones, logs), `~/.local/state/opencode` (locks), `~/.cache/opencode` y `$TMPDIR/opencode`.
- Con `XDG_CONFIG_HOME`/`DATA`/`STATE`/`CACHE`, `OPENCODE_CONFIG_DIR` y `TMPDIR` aplicados **solo dentro del wrapper** ([wrapper.sh](wrapper.sh)), todo queda en `.ditto/`. Probado en macOS arm64 y en Linux (glibc 2.27, glibc 2.35 y musl; arm64 y amd64): **0 archivos** fuera de `.ditto/`.
- `auth.json` va a `$XDG_DATA_HOME/opencode/auth.json`, es decir `.ditto/data/opencode/auth.json` (modo 0600 según el código). El login real queda pendiente (ver *Pendientes*).
- Variantes: arm64 → normal; musl → `-musl`; x86_64 sin AVX2 → `-baseline` (combinable: `-baseline-musl`). En Alpine, las builds musl necesitan `libstdc++` y `libgcc` del host. glibc 2.27 funciona.
- Los procesos hijos (shell tool, MCPs locales, LSPs) heredan **todo** `process.env` de OpenCode, incluidos los `XDG_*` del wrapper.

## Entorno

| | |
|---|---|
| Host | macOS 26.2, Apple M2 Pro (arm64) |
| Docker | colima (VM aarch64, 4 CPU), Docker Engine 28.4 |
| amd64 | emulado con `qemu-x86_64` 7.0 (binfmt). **La CPU emulada no tiene AVX ni AVX2** (TCG 7.0 no los implementa; `ld.so --help` solo muestra `x86-64-v2`). Así que todo amd64 de este spike es "x86_64 sin AVX2" |
| OpenCode | v1.19.3 (2026-10-16), repo `anomalyco/opencode` (antes `sst/opencode`, que redirige) |
| Código revisado | tag `v1.19.3`: `packages/core/src/global.ts`, `packages/core/src/flag/flag.ts`, `packages/opencode/src/auth/index.ts`, `config/paths.ts`, `config/managed.ts`, `core/src/shell.ts`, `tool/shell.ts`, `mcp/index.ts`, `lsp/server.ts`, `install`, `script/build.ts` |

Investigación: el grafo de graphify del repo está vacío (aún no hay código de ditto). El código de OpenCode se leyó con grep sobre un clon temporal, fuera del repo.

## Cómo reproducir

```sh
cd spikes/h0.2-opencode
./run.sh fetch      # descarga los 7 assets CLI y verifica sha256 (SHA256SUMS)
./run.sh macos      # 3 escenarios en el host con HOME/TMPDIR falsos
./run.sh linux      # los mismos 3 escenarios en Docker: ubuntu 18.04/22.04, alpine 3.20 × arm64/amd64
./run.sh noavx2     # probe completo de la build x64 normal en la CPU sin AVX2
./run.sh variants   # matriz: cada variante × imagen × arquitectura (`--version`)
./run.sh tmpdir     # arranque con TMPDIR inexistente
```

- [SHA256SUMS](SHA256SUMS): el release **no publica** `checksums.txt`. Los sha256 salen del campo `digest` de la API de GitHub (`gh api repos/anomalyco/opencode/releases/tags/v1.19.3`), como prevé arch.md §14. `run.sh` borra el archivo si no coincide.
- [probe.sh](probe.sh) ejecuta, sin credenciales, `debug paths`, `mcp list`, `session list`, `models` (red: catálogo models.dev) y `serve` durante 8 s. Cada escenario usa un `HOME` y un `TMPDIR` "de sistema" falsos; después lista todo lo escrito en ellos, en `.ditto/` y, en Docker, en el resto del sistema de archivos del contenedor.
- [envdump.sh](envdump.sh) es un MCP local falso: OpenCode lo lanza con `mcp list` y guarda el entorno que recibe el proceso hijo.
- Escenarios: `none` (sin variables), `configdir` (solo `OPENCODE_CONFIG_DIR`, lo que tenía arch.md §8) y `wrapper` ([wrapper.sh](wrapper.sh)).

## Variables y rutas

Según el código (`global.ts`), todas las rutas se fijan **al importar el módulo** y se crean con `mkdir -p` en cada arranque:

| Ruta | Default | Qué guarda | Variable que la mueve |
|---|---|---|---|
| config | `$XDG_CONFIG_HOME/opencode` (`~/.config/opencode`) | `opencode.json[c]`, agentes, comandos, plugins (`node_modules`, `package.json`), `.gitignore` | `XDG_CONFIG_HOME`. `OPENCODE_CONFIG_DIR` añade un directorio de config más, pero **no** evita que se cree y se lea el de XDG |
| data | `$XDG_DATA_HOME/opencode` (`~/.local/share/opencode`) | `auth.json`, `mcp-auth.json`, `opencode.db` (sesiones, SQLite), `snapshot/`, `repos/`, `log/` | solo `XDG_DATA_HOME` (`OPENCODE_DB` mueve solo la base de datos) |
| state | `$XDG_STATE_HOME/opencode` | `locks/` | solo `XDG_STATE_HOME` |
| cache | `$XDG_CACHE_HOME/opencode` | `models.json`, `bin/` (LSPs que descarga OpenCode) | solo `XDG_CACHE_HOME` |
| tmp | `os.tmpdir()/opencode` (`$TMPDIR` o `/tmp`) | temporales | `TMPDIR` |
| home | `os.homedir()` (`$HOME`) | solo lectura (ver abajo) | `HOME` (no se toca) |

En macOS **no** se usa `~/Library`: `xdg-basedir` aplica las rutas XDG de Linux también en darwin.

Otras variables útiles para el wrapper: `OPENCODE_DISABLE_AUTOUPDATE=1` (sin comprobar versiones nuevas; ditto fija la versión en `mise.lock`), `OPENCODE_AUTH_CONTENT` (JSON de credenciales desde el entorno, sin archivo), `OPENCODE_DISABLE_LSP_DOWNLOAD`, `OPENCODE_DISABLE_CLAUDE_CODE` / `OPENCODE_DISABLE_EXTERNAL_SKILLS` (ver *Lecturas del host*).

### Resultado de los escenarios (sin login)

Archivos escritos fuera de `.ditto/` (en el `HOME` falso, en el `TMPDIR` falso o en el resto del contenedor):

| Plataforma | Variante | `none` | `configdir` | `wrapper` |
|---|---|---|---|---|
| macOS 26.2 arm64 (host) | darwin-arm64 | 18 rutas en `~/.config`, `~/.local/share`, `~/.local/state`, `~/.cache` + `$TMPDIR/opencode` | 17 (igual, sin `opencode.jsonc`; config en `.ditto/`) | **0** |
| Ubuntu 18.04 arm64 (glibc 2.27) | linux-arm64 | ídem | ídem | **0** |
| Ubuntu 18.04 amd64 sin AVX2 (glibc 2.27) | linux-x64-baseline | ídem | ídem | **0** |
| Ubuntu 22.04 arm64 (glibc 2.35) | linux-arm64 | ídem | ídem | **0** |
| Ubuntu 22.04 amd64 sin AVX2 (glibc 2.35) | linux-x64-baseline | ídem | ídem | **0** (\*) |
| Ubuntu 22.04 amd64 sin AVX2 | linux-x64 (normal) | ídem | ídem | **0** (\*) |
| Alpine 3.20 arm64 (musl) + libstdc++ | linux-arm64-musl | ídem | ídem | **0** |
| Alpine 3.20 amd64 sin AVX2 (musl) + libstdc++ | linux-x64-baseline-musl | ídem | ídem | **0** |

Todos los comandos salen con `exit=0` (`serve` con 143 porque se mata a los 8 s). En macOS, `run.sh macos` comprueba además que en el `$HOME` real no aparece ninguna ruta de OpenCode (`~/.config/opencode`, `~/.local/share/opencode`, `~/.local/state/opencode`, `~/.cache/opencode`, `~/.opencode`, `~/Library/...`, `$TMPDIR/opencode`): **sin cambios**.

(\*) En los 2 runs de Ubuntu 22.04 amd64 (no en los de 18.04 ni en Alpine) cambió la `mtime` del directorio `/tmp` del contenedor, pero no quedó ningún archivo en él. Puede ser un temporal que Bun crea y borra ignorando `TMPDIR`. No se pudo confirmar sin `strace` (no funciona bajo qemu-user). Queda para H0.4.

Con `wrapper`, lo que queda en `.ditto/` tras la prueba:

```
cache/opencode/{bin/, models.json}
config/opencode/.gitignore
data/opencode/{opencode.db, opencode.db-shm, opencode.db-wal, log/opencode.log, repos/}
state/opencode/locks/<hash>.lock
tmp/opencode/
```

`config/opencode` coincide con `OPENCODE_CONFIG_DIR` y con `$XDG_CONFIG_HOME/opencode`. OpenCode deduplica la lista de directorios de config, así que la config de los dotfiles va ahí.

### `auth.json` y credenciales

- `auth.json` = `Global.Path.data/auth.json` → `.ditto/data/opencode/auth.json`. Se escribe con modo `0600` (`auth/index.ts`, `writeJson(file, …, 0o600)`). Las credenciales OAuth de MCPs van a `mcp-auth.json`, en el mismo directorio y también 0600.
- `OPENCODE_AUTH_CONTENT` (JSON) sustituye la lectura de `auth.json`. Permite inyectar credenciales desde el entorno o desde `.ditto/secrets` sin escribirlas en disco (arch.md §13).
- Las API keys de los proveedores (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`…) se leen del entorno.
- Sin login, `opencode models` ya lista los modelos gratuitos de OpenCode Zen (`opencode/…-free`). La sesión real con un modelo **no** se ejecutó en este spike: ver *Pendientes*.

### Lecturas del host (no escrituras)

OpenCode **lee** del `$HOME` real aunque se aísle todo lo demás: `~/.opencode/` (directorio de config), `~/.claude/CLAUDE.md`, `~/.claude/skills/`, `~/.agents/skills/` y, si existe, la config gestionada del sistema (`/etc/opencode` en Linux; `/Library/Application Support/opencode` y el plist `ai.opencode.managed` en macOS). No escribe en ellos. Las lecturas de Claude Code se desactivan con `OPENCODE_DISABLE_CLAUDE_CODE=1` y las de skills externas con `OPENCODE_DISABLE_EXTERNAL_SKILLS=1`. No se proponen por defecto: no modifican el host y pueden ser útiles. Se documentan como riesgo de reproducibilidad.

### Procesos hijos

- El shell tool (`tool/shell.ts`), los MCPs locales (`mcp/index.ts`) y los LSPs (`lsp/server.ts`) se lanzan con `{...process.env, …}`. Heredan **todo** el entorno del wrapper. Evidencia (`mcp list`, escenario `wrapper`): el MCP recibe `XDG_CONFIG_HOME/DATA/STATE/CACHE=<ws>/.ditto/…`, `TMPDIR=<ws>/.ditto/tmp`, `OPENCODE_CONFIG_DIR`, `OPENCODE_DISABLE_AUTOUPDATE`, `DITTO_ORIG_*`, `OPENCODE=1` y `OPENCODE_PID`.
- Consecuencia: un `git` lanzado por el shell tool vería `XDG_CONFIG_HOME=.ditto/config` y perdería `~/.config/git/config`, igual que los hijos de nvim (arch.md §8).
- El shell tool usa la clave `shell` de la config si existe y, si no, `$SHELL` (`core/src/shell.ts`). Con una ruta absoluta a `.ditto/bin/.host-sh` (que restaura `DITTO_ORIG_*` y hace `exec "$SHELL" "$@"`), los comandos del agente verían el entorno real. Para shells sin nombre conocido OpenCode pasa `-c <cmd>`. **Hay que validarlo en H0.3** junto con el resto de `.host-sh`; aquí no se pudo comprobar sin una sesión con modelo.
- MCPs y LSPs heredan los `XDG_*` de `.ditto/`. Para ellos es deseable: `uv`/`uvx` cachean en `.ditto/cache/uv` y no en `~/.cache/uv`. `npx` usa `~/.npm` (no XDG): queda como escritura en `$HOME` para H0.4 (se movería con `npm_config_cache`).
- Los MCPs locales se buscan por el `PATH` heredado. El wrapper de OpenCode debe anteponer los runtimes de ditto (node, uv) a su `PATH`, igual que el de nvim, y nunca en la subshell.

### `TMPDIR` debe existir

`tmpdir-check.sh` arranca OpenCode con `TMPDIR` apuntando a un directorio inexistente:

| Variante | Plataforma | TMPDIR inexistente |
|---|---|---|
| darwin-arm64 | macOS (host) | arranca (crea el directorio) |
| linux-arm64 | Ubuntu 22.04 | arranca |
| linux-x64-baseline | Ubuntu 22.04 amd64 | **`Aborted (core dumped)`**. En el probe se quedó colgado en `debug paths` (100 % CPU, ignora SIGTERM) |
| linux-arm64-musl | Alpine 3.20 | arranca |
| linux-x64-baseline-musl | Alpine 3.20 amd64 | arranca |

→ ditto crea `.ditto/tmp` en `up` (o el wrapper hace `mkdir -p` antes del `exec`). No se depende de que OpenCode lo cree.

## Matriz de variantes (v1.19.3)

Assets CLI del release: `darwin-arm64`, `darwin-x64`, `darwin-x64-baseline` (`.zip`); `linux-arm64`, `linux-arm64-musl`, `linux-x64`, `linux-x64-baseline`, `linux-x64-musl`, `linux-x64-baseline-musl` (`.tar.gz`). No hay `darwin-*-musl` ni `linux-arm64-baseline`. Todos son un ejecutable de Bun (`bun build --compile`) de 145–196 MB.

`./run.sh variants` (`opencode --version`; amd64 = sin AVX2):

| Imagen | Plataforma | normal | `-baseline` | `-musl` | `-baseline-musl` |
|---|---|---|---|---|---|
| Ubuntu 18.04 (glibc 2.27) | amd64 | ✅ | ✅ | ❌ sin `ld-musl` | ❌ sin `ld-musl` |
| Ubuntu 18.04 (glibc 2.27) | arm64 | ✅ | — | ❌ sin `ld-musl` | — |
| Ubuntu 22.04 (glibc 2.35) | amd64 | ✅ | ✅ | ❌ | ❌ |
| Ubuntu 22.04 (glibc 2.35) | arm64 | ✅ | — | ❌ | — |
| Rocky 8 (glibc 2.28) | amd64 | ✅ | ✅ | ❌ | ❌ |
| Rocky 8 (glibc 2.28) | arm64 | ✅ | — | ❌ | — |
| Alpine 3.20 (musl) | amd64 | ❌ sin `ld-linux` | ❌ | ❌ `Error relocating … __vmi_class_type_info` (falta libstdc++) | ❌ ídem |
| Alpine 3.20 (musl) | arm64 | ❌ | — | ❌ ídem | — |
| Alpine 3.20 + `apk add libstdc++ libgcc` | amd64 | ❌ | ❌ | ✅ | ✅ |
| Alpine 3.20 + `apk add libstdc++ libgcc` | arm64 | ❌ | — | ✅ | — |
| macOS 26.2 (host) | arm64 | ✅ | — | — | — |

Observaciones:

- **glibc**: las builds glibc arrancan con 2.27 (Ubuntu 18.04) aunque el binario contiene cadenas `GLIBC_2.29`/`2.30` (probablemente símbolos opcionales; empíricamente arranca y el probe completo pasa). No se probó glibc < 2.27.
- **musl**: el binario enlaza dinámicamente `libstdc++.so.6` y `libgcc_s.so.1` (`ldd` en Alpine). En Alpine son prerrequisitos del host (`apk add libstdc++ libgcc`): ditto debe comprobarlos (`doctor`) y dar la instrucción. No los instala.
- **AVX2**: la build x64 **normal** también funcionó (`--version` y el probe completo) en la CPU emulada sin AVX/AVX2. Es decir, en estos caminos de código no ejecuta instrucciones AVX2. No demuestra que sea segura en una sesión real (JIT, SIMD de Bun). El instalador oficial (`install`) elige `-baseline` si no hay `avx2` en `/proc/cpuinfo` (o `hw.optional.avx2_0` en macOS) y se adopta la misma regla, conservadora. La build normal **con** AVX2 no se puede probar aquí (qemu 7.0 no emula AVX2): pendiente en un host x86_64 real.
- **macOS x64**: se aplica la misma regla de AVX2 (`darwin-x64-baseline`). En Rosetta, el instalador oficial elige arm64. No se probó (no hay Mac Intel).
- **Backend mise**: el registro aqua (`aqua:anomalyco/opencode`, alias `sst/opencode`) solo resuelve la variante normal (`opencode-{{.OS}}-{{.Arch}}`), sin `-baseline` ni `-musl`. Para elegir variante hace falta `github:anomalyco/opencode` con el asset explícito por plataforma. Validar la sintaxis exacta en H0.1.

### Regla de elección de variante (manifiesto)

```
os=darwin → arm64: darwin-arm64
           x86_64: darwin-x64        si AVX2, si no darwin-x64-baseline
os=linux  → sufijo libc  = "-musl" si libc=musl
            arm64:  linux-arm64<libc>
            x86_64: linux-x64<-baseline si no AVX2><libc>
```

Detección (ya prevista en `internal/platform`): libc por `ldd --version`/`/lib/ld-musl*`; AVX2 por `/proc/cpuinfo` (`flags`) o `sysctl hw.optional.avx2_0`.

## Dependencias de los MCPs

- OpenCode en sí no necesita ningún runtime (ejecutable autocontenido de Bun). Cuando instala plugins o LSPs desde npm usa su Bun embebido (`BUN_BE_BUN=1`).
- Un MCP `local` se lanza como `command[0]` buscado en el `PATH` heredado. Los MCPs típicos usan `npx` (Node; lo habitual en los servidores MCP oficiales es Node ≥ 18) o `uvx` (uv; el SDK MCP de Python pide Python ≥ 3.10). Los MCPs `remote` (URL) no necesitan runtime.
- **Inventario de los MCPs que usa el usuario: pendiente.** En esta máquina no hay config de OpenCode (`~/.config/opencode` no existe), así que no hay MCPs que inventariar.

## Pendientes (manual, usuario)

1. **Login real y `auth.json`** (necesita credenciales; no se pidieron ni se usaron):
   ```sh
   cd spikes/h0.2-opencode && ./run.sh fetch
   S=$PWD; W=$(mktemp -d); mkdir -p "$W/home" "$W/ws/.ditto/tmp"
   oc() { (cd "$W/ws" && env HOME="$W/home" DITTO_ROOT="$W/ws/.ditto" \
       DITTO_OPENCODE_BIN="$S/.work/bin/darwin-arm64/opencode" sh "$S/wrapper.sh" "$@"); }
   oc auth login                                 # elegir proveedor y completar el login
   ls -l "$W/ws/.ditto/data/opencode/auth.json"  # esperado: existe, -rw-------
   find "$W/home" -mindepth 1                    # esperado: vacío
   ```
   Repetir con `oc` (TUI): abrir una sesión corta con el proveedor, pedir que ejecute `env | grep -E 'XDG|DITTO'` con el shell tool, salir y volver a ejecutar los dos últimos comandos. Anotar también si aparece `~/.npm` o algo en el `$HOME` real. (Borrar `$W` al terminar: contiene credenciales.)
2. **Inventario de MCPs actuales**: en la máquina donde se usa OpenCode hoy, listar solo nombres y comandos, sin `environment` ni `headers`:
   ```sh
   jq -r '.mcp // {} | to_entries[] | "\(.key)\t\(.value.type)\t\((.value.command // [])[0:2] | join(" "))\t\(.value.url // "" | sub("\\?.*";""))"' ~/.config/opencode/opencode.json
   node --version; uv --version; python3 --version
   ```
3. **x86_64 real con AVX2** (build normal) y **x86_64 real sin AVX2** (`-baseline`; si no hay hardware, `qemu-system-x86_64 -cpu Westmere` con una ISO de Ubuntu): `grep -cw avx2 /proc/cpuinfo` y, con el wrapper, `opencode debug paths && opencode models && opencode serve` (Ctrl-C a los segundos), más una sesión TUI corta.
4. **Glibc mínima real** de los servidores (`ldd --version`) si alguno es < 2.27.
5. `/tmp` (mtime) en Ubuntu 22.04 amd64 y `~/.npm` de los MCPs con `npx`: revisar en H0.4 con `strace -f -e trace=file` en un host Linux real.

## Conclusión

Se cumple la primera rama del *criterio de decisión* solo en parte: no hay variables específicas suficientes. Se aplica la segunda: **`XDG_*` solo dentro del wrapper de OpenCode**, como con nvim, más `OPENCODE_CONFIG_DIR`, `TMPDIR` y `OPENCODE_DISABLE_AUTOUPDATE`. Con eso no escapa nada en las plataformas probadas. Los efectos en los hijos (`XDG_*` heredados) se resuelven con el mismo mecanismo `.host-sh` de §8, a validar en H0.3.

## Decisión propuesta

Texto para aplicar con `/record-decision` (no se ha editado arch.md ni roadmap.md).

### arch.md §6: fila de OpenCode

```markdown
| OpenCode | `github:anomalyco/opencode` (releases oficiales; `sst/opencode` redirige). aqua solo conoce la variante normal | Asset por plataforma: `darwin-arm64`, `darwin-x64[-baseline]`, `linux-arm64[-musl]`, `linux-x64[-baseline][-musl]`. Regla: libc musl → `-musl`; x86_64 sin AVX2 → `-baseline`. Sin `checksums.txt`: sha256 del `digest` de la API de GitHub. glibc ≥ 2.27 verificada. En Alpine requiere `libstdc++` y `libgcc` del host (`doctor` lo comprueba) |
```

El título de §6 conserva *(spike H0.1)* por los demás backends.

### arch.md §8: regla, tabla y wrapper

Regla (primer párrafo):

```markdown
Regla: **cada herramienta se configura con su variable específica cuando existe; `XDG_*` solo para Neovim y OpenCode**, que no tienen alternativa (LazyVim, lazy.nvim y Mason dependen de `stdpath()`; OpenCode calcula datos, estado y caché solo con `XDG_*` y crea esas rutas en `$HOME` en cada arranque, spike H0.2). En ambos casos, **solo dentro de su wrapper**.
```

Fila de la tabla:

```markdown
| OpenCode | `XDG_CONFIG_HOME`/`DATA`/`STATE`/`CACHE` → `.ditto/…` + `OPENCODE_CONFIG_DIR=.ditto/config/opencode` + `TMPDIR=.ditto/tmp` + `OPENCODE_DISABLE_AUTOUPDATE=1` (solo dentro del wrapper). Datos y `auth.json` en `.ditto/data/opencode/` |
```

Párrafo nuevo después del bloque del wrapper de Neovim:

```markdown
Wrapper de OpenCode: mismas `XDG_*` y `DITTO_ORIG_*` que el de nvim, más `OPENCODE_CONFIG_DIR`, `TMPDIR` y `OPENCODE_DISABLE_AUTOUPDATE=1`. `.ditto/tmp` debe existir antes del `exec` (la build x64 aborta si `TMPDIR` no existe). Los runtimes para MCPs (node, uv) se anteponen a su `PATH`, como en el de nvim. OpenCode pasa todo su entorno a sus hijos (shell tool, MCPs, LSPs). Su shell tool usa la clave `shell` de la config, que ditto fija a `$DITTO_ROOT/bin/.host-sh` para que los comandos del agente vean el XDG y el `PATH` reales. MCPs y LSPs conservan los `XDG_*` de `.ditto/` (sus cachés quedan dentro).
```

### arch.md §4: layout

Añadir `tmp/` a la línea de `data/ state/ cache/`:

```markdown
│   ├── data/  state/  cache/  tmp/  # XDG de nvim y OpenCode (plugins de lazy, Mason, sesiones y auth.json de OpenCode); TMPDIR de OpenCode
```

### arch.md §13: credenciales de OpenCode

```markdown
- Credenciales de OpenCode: `auth.json` (y `mcp-auth.json` para OAuth de MCPs) en `.ditto/data/opencode/`, con modo 0600. Se pierden al borrar el workspace (documentado). Alternativa sin archivo: `OPENCODE_AUTH_CONTENT` (JSON) o las variables del proveedor (`ANTHROPIC_API_KEY`…), desde el entorno o `.ditto/secrets`.
```

### arch.md §18: riesgo de OpenCode

```markdown
- **OpenCode**: rutas resueltas (spike H0.2): `XDG_*` solo en su wrapper. Quedan: (a) lee del `$HOME` real `~/.opencode/`, `~/.claude/CLAUDE.md` y `~/.claude/skills`, `~/.agents/skills` y `/etc/opencode` (sin escribir; se pueden desactivar con `OPENCODE_DISABLE_CLAUDE_CODE`/`OPENCODE_DISABLE_EXTERNAL_SKILLS`); (b) los hijos heredan los `XDG_*` del wrapper (shell tool → `.host-sh`, validar en H0.3); (c) `npx` de los MCPs escribe en `~/.npm` y hay un posible temporal en `/tmp` (H0.4); (d) build x64 normal sin probar en un host real con AVX2; la `-baseline` sin AVX2 solo se probó emulada; (e) inventario de MCPs del usuario y su runtime mínimo, pendiente (H3.1).
```

### roadmap.md

Marcar H0.2 solo cuando se cierren los pendientes 1 y 2 (login real e inventario de MCPs), o marcarlo ahora y llevar esos pendientes a H0.4 y H3.1.
