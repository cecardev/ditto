# ditto — Arquitectura

**Estado:** provisional hasta cerrar la Fase 0 (spikes). Las decisiones marcadas con *(spike)* dependen de su resultado.
**Lenguaje:** Go · **Plataformas:** Linux (x86_64, arm64) y macOS (arm64, x86_64)
**Documentos relacionados:** [project.md](project.md) (propuesta original) · [roadmap.md](roadmap.md) (fases e hitos)

## 1. Qué es ditto

Un único binario Go que, ejecutado en cualquier servidor Linux o equipo macOS, prepara un entorno de desarrollo personal (Neovim con **LazyVim**, OpenCode, ripgrep, fd, fzf, lazygit, LSPs…) **dentro del workspace actual** y abre una subshell con ese entorno activo. El host no se modifica: los comandos del sistema (`nvme`, etc.) siguen siendo los originales y, al borrar la carpeta del workspace, no queda nada.

Principios: plug & play · no invasivo · ejecución nativa (sin Docker) · host-first · reproducible por defecto · mínima interacción (se pregunta una vez y nunca más).

### Arquitectura híbrida: división por capa

ditto **no es un gestor de paquetes**. Delega la obtención de binarios en [mise](https://mise.jdx.dev) y se concentra en lo que ninguna herramienta existente empaqueta:

| Capa | Responsable | Qué hace |
|---|---|---|
| **Que el binario exista** | **mise** (solo durante la instalación) | Descarga, verificación de checksums, lockfile, versiones, limpieza (`prune`), runtimes (Node, Go, Python/uv) |
| **Neovim como IDE** | **LazyVim + lazy.nvim + Mason** | Plugins, LSPs, formatters, linters |
| **Qué instalar y cómo se ejecuta** | **ditto** | Detección de plataforma y elección de variante, menú de setup, wrappers con configuración aislada, subshell / `ditto env`, dotfiles, `doctor`, `bundle` |

La división es **por capa, no por herramienta**: ditto nunca descarga binarios con un mecanismo propio en paralelo a mise. Un binario aportado por el usuario se registra *dentro* de mise con `mise link`, para que haya un único store y un único lockfile. Los binarios del host **no** pasan por mise: se referencian por ruta absoluta (ver *Origen de los binarios*), así el lockfile no depende de lo que tenga cada servidor.

### Solapamiento con mise *(spike H0.1b)*

Comparación de lo que este documento asigna a ditto con lo que mise trae de serie. Hecha sin verificar la documentación actual de mise; H0.1b la confirma con la versión fijada.

| Función de ditto | ¿Lo cubre mise? | Estado |
|---|---|---|
| Descarga, checksums, lockfile, versiones, `prune`, `link` | Sí, es su núcleo | Ya delegado |
| `install.sh` + bootstrap de mise con sha256 | Sí: `mise generate bootstrap` genera un script que instala mise localmente | Repetición parcial |
| Subshell con el entorno (`ditto up`) | Sí: `mise en` | **Repetición** |
| `ditto env` / `ditto run -- cmd` | Sí: `mise env` / `mise exec` | **Repetición** |
| `PATH` y variables de la sesión | Sí: `[env]`, `_.path`, `_.file` en `mise.toml` | **Repetición** |
| Secretos (`.ditto/secrets`) | Parcial: `[env]` admite archivos cifrados con sops/age | Solapamiento posible |
| Wrappers por binario con `exec` | Parcial: `mise generate tool-stub` | Solapamiento parcial |
| `doctor` | Parcial: `mise doctor` cubre mise, no prerrequisitos ni LazyVim/Mason | ditto añade lo suyo |
| Variante por glibc / musl / AVX2 | Parcial: elige por OS/arch y admite opciones por plataforma; no detecta AVX2 ni versión de glibc | Valor propio (fino) |
| Configuración aislada **por herramienta** (XDG solo en nvim, `.host-sh`, config de git/ssh) | No: `[env]` aplica a toda la sesión | **Valor propio** |
| Menú de setup, perfil, `ditto.toml` compartido | No | **Valor propio** |
| LazyVim: starter, fusión de extras, `Lazy! restore`, precalentado de Mason | No | **Valor propio** |
| Dotfiles por git | No | Valor propio |
| `bundle` offline | No | Valor propio |
| Binario único autocontenido | No: mise necesita su config aparte | Valor propio |

**Conclusión:** la capa de instalación está bien delegada. La capa de **sesión** (`up`/`env`/`run`, `PATH`, variables) reimplementa lo que mise ya ofrece. Se hizo a propósito (§3: mise no participa en tiempo de ejecución, para no chocar con un mise o conda del host), pero es código propio que mantener.

**Decisión pendiente (H0.1b):**

- **A. Sesión delegada en mise** *(preferida)*: ditto genera `mise.toml` (`[env]`, `_.path` hacia los wrappers) y lanza `mise en` / `mise exec` / `mise env`. ditto se reduce a lo que mise no hace: menú y perfil, variantes de plataforma, wrappers con aislamiento por herramienta, LazyVim/Mason, dotfiles, `bundle`.
- **B. Diseño actual**: mise solo instala; ditto controla la sesión. Más código, control total y sin posible interferencia con un mise del host.

Se elige A salvo que H0.1b muestre que `mise en` + `[env]` interfiere con el host (mise, conda, rc del usuario) o impide el aislamiento por herramienta.

### Origen de los binarios

Todo binario que ditto conoce pertenece a **una sola** de tres categorías, declarada en el manifiesto (`category`):

**A. Gestionados por ditto** (`managed`) — siempre en `.ditto/` vía mise, aunque el host ya los tenga.

| Binario | Motivo |
|---|---|
| `mise` | Motor de instalación interno (versión fijada, sha256 embebido) |
| tree-sitter CLI | nvim-treesitter (`main`) exige ≥ 0.25; casi ningún host lo trae |

**B. Requeridos del host** (`host`) — ditto nunca los instala ni crea wrappers con su nombre (validado por test sobre el manifiesto).

| Tipo | Binarios | Quién los usa | Si faltan |
|---|---|---|---|
| Prerrequisito duro (`required = "hard"`) | `git` ≥ 2.19, `curl` o `wget`, `tar`, `unzip` | lazy.nvim, Mason, `install.sh` | `up`/`doctor` fallan con mensaje accionable |
| Prerrequisito blando (`required = "soft"`) | `cc`, `ssh` | parsers de treesitter, dotfiles privados | aviso; funcionalidad degradada, no bloquea |
| Base del sistema | `$SHELL` (bash/zsh), coreutils, `ldd`, `uname` | launcher, platform | error |
| Passthrough | `nvme`, diagnóstico y **todo lo que no está en el manifiesto** | el usuario | — |

**C. Seleccionables** (`selectable`) — el origen se elige por componente con `source`:

| `source` | Comportamiento |
|---|---|
| `ditto` | Se instala con mise en la versión del `mise.lock` |
| `host` | Se usa el del host; si no existe o no cumple `min_version` → error claro |
| `auto` | Host si cumple `min_version`; si no, ditto |
| `path:<ruta>` | Binario aportado por el usuario (offline), registrado con `mise link` |

| Componente | Default | `min_version` (host) | Por qué |
|---|---|---|---|
| Neovim | `ditto` | 0.11.2 | Ligado a `lazy-lock.json`; requisito de LazyVim |
| OpenCode | `ditto` | — | Ligado a su config y MCPs |
| ripgrep, fd, fzf, lazygit | `auto` | por componente | Las versiones del host suelen bastar; ahorra descarga |
| Runtimes (node, python/uv, go) | `auto` | node ≥ 18, python ≥ 3.9 | Solo para Mason/MCPs; nunca visibles en la subshell (§8) |

El resultado de resolver cada componente (origen, ruta absoluta, versión, motivo) lo calcula `internal/resolve` (§5) y se guarda en `.ditto/state.toml`.

## 2. Decisiones clave

| Tema | Decisión |
|---|---|
| Nombre | `ditto`; directorio gestionado `.ditto/` en la raíz del workspace |
| Ubicación | Todo dentro de `<workspace>/.ditto/`. Borrar la carpeta no deja nada. Caché compartida solo como opt-in futuro (`DITTO_CACHE` → `MISE_CACHE_DIR` común) |
| Obtención de binarios | **mise**, en una versión fijada, totalmente aislado en `.ditto/mise/` *(spike H0.1)* |
| Distribución de Neovim | **LazyVim** (starter en el repo de dotfiles; uno mínimo embebido por defecto) |
| LSPs / formatters / linters | **Mason**, gestionado por los extras de LazyVim, con datos en `.ditto/data` |
| Versiones | Reproducible por defecto: `up` instala exactamente lo del lockfile; `update` resuelve latest con fallback (§7) |
| Lockfile | `mise.lock` + `lazy-lock.json` + `lazyvim.json`, **versionados en el repo de dotfiles** para que todos los servidores converjan |
| Selección de componentes | Menú interactivo en el primer setup; perfil persistido (§10) |
| Sesión en tiempo de ejecución | Pendiente de H0.1b: delegada en mise (`mise en`/`exec`/`env`, preferida) o propia de ditto (§1, *Solapamiento con mise*) |
| Origen por componente | Tres categorías: gestionado por ditto / requerido del host / seleccionable con `source = ditto\|host\|auto\|path` (§1, *Origen de los binarios*) |
| Configuración | Wrapper por herramienta; preferir variables específicas de cada app; **no** se exportan `XDG_*` en la subshell (§8) |
| Dotfiles | Repo git configurable (`--dotfiles <url>`); embed mínimo (LazyVim starter + config OpenCode) como valor por defecto |
| Prerrequisitos | Categoría B: duros `git` ≥ 2.19, `curl` o `wget`, `unzip`, `tar`; blandos `cc` (treesitter) y `ssh`. `ditto doctor` los verifica |
| Secretos | Nunca embebidos ni versionados |
| Distribución | Binario por plataforma publicado por GitHub Actions + GoReleaser en cada release |

## 3. Vista general

```
laptop ── scp / install.sh ──► servidor / macOS
                                   │
                          ditto (Go, binario estático)
 ┌──────────┬───────────┬──────────┬───────────┬──────────┬────────────┐
 │ platform │ manifest  │ setup    │ installer │ config   │ env +      │
 │ os/arch/ │ componen- │ menú +   │ (mise)    │ dotfiles │ launcher   │
 │ libc/cpu │ tes y     │ perfil   │           │ LazyVim  │ wrappers + │
 │          │ variantes │          │           │ OpenCode │ subshell   │
 └──────────┴───────────┴──────────┴─────┬─────┴──────────┴────────────┘
                                         │ (solo en instalación)
                              mise install / link / prune
                                         │
                    subshell con PATH=.ditto/bin:$PATH
                       │            │            │
                     nvim       opencode     rg/fd/fzf/lazygit
               (LazyVim+Mason)  (wrapper)      + host CLI (nvme…)
```

En tiempo de ejecución **mise no participa**: los wrappers apuntan directamente a la ruta absoluta resuelta (`mise where` si el origen es ditto, la ruta del host si es host). Ni `mise activate` ni shims de mise en la subshell. *(Provisional: si H0.1b adopta la opción A de "Solapamiento con mise", la sesión la lanza `mise en` y este párrafo cambia.)*

## 4. Layout en disco

```
<workspace>/
├── .ditto/
│   ├── bin/                 # wrappers que entran en PATH (+ .host-sh, ver §8)
│   ├── mise/
│   │   ├── bin/mise         # binario de mise (versión fijada, sha256 verificado)
│   │   ├── config.toml      # generado por ditto a partir del perfil + plataforma
│   │   ├── mise.lock        # copia/enlace del lockfile del repo de dotfiles
│   │   ├── installs/  cache/  state/
│   ├── downloads/           # binarios aportados por el usuario (offline), registrados con `mise link`
│   ├── config/              # XDG_CONFIG_HOME de nvim; configs de otras herramientas
│   ├── data/  state/  cache/  # XDG de nvim: plugins de lazy, paquetes de Mason
│   ├── dotfiles/            # clon del repo de dotfiles (si se configura)
│   ├── secrets              # opcional, 0600
│   └── state.toml           # perfil (componentes + source), resolución (origen/ruta/versión), dotfiles url
├── proyecto-a/
└── proyecto-b/
```

`.ditto/` no se versiona (se añade a `.gitignore` si el workspace es un repo).

## 5. Módulos (paquetes Go)

- **`internal/platform`** — GOOS/GOARCH; libc (glibc vs musl vía `ldd --version`/`/lib/ld-musl*`), versión de glibc, versión de macOS y **flags de CPU** (AVX2, para elegir variantes `-baseline`).
- **`internal/manifest`** — catálogo embebido de **componentes**: categoría (`managed`/`host`/`selectable`), orígenes permitidos y default, `min_version` + cómo leer la versión del host (`version_cmd`, `version_regex`), herramienta mise (backend + nombre), variantes por plataforma (p. ej. Neovim oficial → `neovim-releases` legacy; OpenCode normal → `-baseline` → `-musl`), dependencias entre componentes, extras de LazyVim asociados y forma del wrapper. Ejemplo:

  ```toml
  [components.rg]
  category      = "selectable"
  sources       = ["ditto", "host", "auto", "path"]
  default       = "auto"
  min_version   = "13.0.0"
  version_cmd   = ["--version"]
  version_regex = 'ripgrep (\d+\.\d+\.\d+)'
  mise          = { backend = "aqua:BurntSushi/ripgrep" }
  wrapper       = { env = { RIPGREP_CONFIG_PATH = "{config}/ripgrep/rc" } }

  [components.git]
  category      = "host"
  required      = "hard"
  min_version   = "2.19.0"
  version_cmd   = ["--version"]
  version_regex = 'git version (\d+\.\d+\.\d+)'
  hint          = "Instala git ≥ 2.19 con el gestor de paquetes del sistema"
  ```
- **`internal/setup`** — menú de selección y perfil (§10).
- **`internal/resolve`** — decide el origen de cada componente. Entrada: manifiesto + `Platform` + perfil. Busca en el host con `exec.LookPath` sobre un `PATH` **sin** `.ditto/bin` (para no encontrarse a sí mismo), ejecuta `version_cmd` y compara con `min_version`. Salida: `[]Resolved{Name, Source, AbsPath, Version, Reason}` persistida en `state.toml`. La consumen `installer` (solo `Source=ditto` entra en `config.toml` de mise; `path` → `mise link`), `env` (wrappers con `exec <AbsPath>`) y `doctor`. En cada `up` se revalida sin red que la ruta del host siga existiendo con la misma versión; si cambió, se re-resuelve (`auto` puede pasar a ditto) y se informa.
- **`internal/installer`** — interfaz mínima `Installer{Install, Link, Where, Prune}` con **una sola** implementación sobre mise. Solo recibe componentes con origen ditto o `path`. Bootstrap de mise: descarga la versión fijada desde su release y verifica el sha256 embebido en ditto. Aísla mise: `MISE_DATA_DIR`, `MISE_CACHE_DIR`, `MISE_STATE_DIR`, `MISE_CONFIG_DIR`, `MISE_GLOBAL_CONFIG_FILE` (y config de confianza) apuntando a `.ditto/mise/`, para no interferir con un mise del host. Ninguna `MISE_*` se exporta a la subshell.
- **`internal/config`** — clona/actualiza el repo de dotfiles; aplica el starter de LazyVim y la config de OpenCode; fusiona los extras del perfil en `lazyvim.json`; fallback a configs embebidas (`go:embed`).
- **`internal/env`** — genera wrappers por herramienta y `.host-sh` (§8); `PATH` con `.ditto/bin` primero; `DITTO_ACTIVE=1`, `DITTO_ROOT`. Con origen host, el wrapper solo se genera si la herramienta necesita config aislada (lazygit → `LG_CONFIG_FILE`, rg → `RIPGREP_CONFIG_PATH`…); si no, no hay wrapper y se resuelve por el `PATH` normal.
- **`internal/launcher`** — `syscall.Exec` del `$SHELL` del usuario con rcfile/`ZDOTDIR` temporal; ejecución de un comando suelto; salida de `ditto env`.
- **`cmd/ditto`** — subcomandos:

| Comando | Función |
|---|---|
| `ditto` / `ditto up` | Primer uso: menú de setup. Luego instala lo que falte **según el lockfile** (sin red si ya está todo) y abre la subshell |
| `ditto setup` | Vuelve a abrir el menú de componentes |
| `ditto run -- <cmd>` | Ejecuta un comando dentro del entorno |
| `ditto env` | Imprime las variables para `eval "$(ditto env)"` (tmux, scripts) |
| `ditto doctor` | Plataforma, glibc, CPU; tabla por categoría (componente, origen, ruta, versión, estado); secretos faltantes, estado de LazyVim/Mason |
| `ditto update` | Resuelve latest con fallback y escribe el nuevo `mise.lock` en el clon de dotfiles (el usuario hace commit) |
| `ditto rollback` | Restaura el `mise.lock` anterior (historial git del repo de dotfiles) y reinstala |
| `ditto bundle` | Empaqueta `.ditto/` para copiarlo a otro host de la misma plataforma |

Limpieza de versiones no referenciadas: `mise prune` (invocado por `update`, `rollback` y `setup`).

## 6. Backends previstos *(spike H0.1)*

Aplican a la categoría A y a los seleccionables cuando se resuelven con origen ditto.

| Componente | Backend mise (tentativo) | Notas |
|---|---|---|
| Neovim | `aqua:neovim/neovim` / `github:neovim/neovim-releases` | Variante legacy si glibc < 2.31. LazyVim exige ≥ 0.11.2 |
| ripgrep, fd, fzf, lazygit | `aqua:` | Builds estáticos/musl en Linux |
| tree-sitter CLI | `aqua:tree-sitter/tree-sitter` | ≥ 0.25 para nvim-treesitter (rama `main`). Verificar glibc |
| OpenCode | `github:` (releases oficiales) | Variantes normal / `-baseline` / `-musl` |
| Node, Go, Python/uv | `core:node`, `core:go`, `core:python` / `aqua:astral-sh/uv` | Solo si `auto` no encuentra uno válido en el host o `source=ditto`. Para Mason y MCPs; no visibles en la subshell (§8) |

## 7. Política de versiones

- **`ditto up` es reproducible**: instala exactamente lo del `mise.lock` (versión + checksum por plataforma). Si todo está instalado, no hace ninguna llamada de red (evita el límite de 60 req/h de la API de GitHub).
- **`ditto update`** resuelve latest para cada componente con origen ditto, en orden:
  1. Última versión con asset para la plataforma y checksum válido.
  2. Si falla (sin red, sin asset, libc/CPU incompatible) → se conserva la versión del lockfile.
  3. Si no hay ninguna → con `source=auto`, se usa el del host si cumple `min_version`; con `source=ditto`, error que sugiere `--source <tool>=host` o `path:<ruta>`.
  4. Si tampoco → error accionable: URL exacta a descargar y dónde colocar el archivo (`path:` / `.ditto/downloads`, registrado con `mise link`).
- Los componentes con origen host no se actualizan: su versión es la del sistema y solo se revalida contra `min_version`.
- **Neovim se fija junto con `lazy-lock.json`**: se actualizan juntos (`ditto update` + `:Lazy update` en una máquina, commit de ambos lockfiles), nunca uno sin el otro.

### Fallback de glibc (Neovim)

1. Build oficial (glibc ≥ 2.31).
2. Build *legacy* de `neovim/neovim-releases` (glibc 2.27, best-effort).
3. `nvim` del host (`source=auto` o `host`, por ruta absoluta), **solo si es ≥ 0.11.2** (requisito de LazyVim; en la práctica raro en hosts antiguos).
4. Binario aportado por el usuario (`source=path:<ruta>`, registrado con `mise link`).
5. Error con instrucciones.

(El AppImage no resuelve el problema: sigue usando la glibc del host.)

## 8. Aislamiento de entorno

Regla: **cada herramienta se configura con su variable específica cuando existe; `XDG_*` solo para Neovim**, que no tiene alternativa (LazyVim, lazy.nvim y Mason dependen de `stdpath()`).

| Herramienta | Mecanismo |
|---|---|
| nvim | `XDG_CONFIG_HOME`/`DATA`/`STATE`/`CACHE` → `.ditto/…` (solo dentro del wrapper) |
| lazygit | `LG_CONFIG_FILE` |
| OpenCode | `OPENCODE_CONFIG_DIR` (+ ruta de datos/`auth.json` *(spike H0.2)*) |
| ripgrep | `RIPGREP_CONFIG_PATH` |
| fzf | `FZF_DEFAULT_OPTS_FILE` |

La subshell **no** exporta `XDG_*`. Wrapper de Neovim:

```sh
# .ditto/bin/nvim
export DITTO_ORIG_XDG_CONFIG_HOME="${XDG_CONFIG_HOME-}"   # (ídem DATA/STATE/CACHE)
export XDG_CONFIG_HOME="$DITTO_ROOT/config" XDG_DATA_HOME="$DITTO_ROOT/data" \
       XDG_STATE_HOME="$DITTO_ROOT/state"   XDG_CACHE_HOME="$DITTO_ROOT/cache"
export PATH="$DITTO_ROOT/mise/installs/node/<ver>/bin:…:$PATH"   # runtimes para Mason, solo aquí (si su origen es ditto)
exec "<AbsPath resuelto de nvim>" "$@"                            # ruta de mise o del host
```

El aislamiento de esta sección se aplica igual sea cual sea el origen del binario: un `lazygit` del host también recibe `LG_CONFIG_FILE`.

**Procesos hijos de Neovim** (`:terminal`, `:!git`, terminal de Snacks, lazygit integrado):

- La config de LazyVim fija `vim.o.shell = "$DITTO_ROOT/bin/.host-sh"`, un mini-wrapper que restaura los `DITTO_ORIG_XDG_*` (y el `PATH` sin runtimes) antes de ejecutar `$SHELL`. Cubre `:terminal`, `:!` y `system()` con string.
- **Todo wrapper de ditto restaura los `DITTO_ORIG_*` antes de lanzar su herramienta**, así lazygit abierto desde LazyVim no hereda el XDG de nvim y su `git` ve la configuración real.
- Para procesos que nvim lanza directamente con lista de argumentos (p. ej. gitsigns → `git`): si existe `~/.config/git/config`, el wrapper de nvim exporta `GIT_CONFIG_GLOBAL` con esa ruta.
- Además se apunta `HISTFILE` (y similares) a `.ditto/` para no escribir en `$HOME`.

Validación de todo lo anterior: spike H0.3.

## 9. LazyVim

- **Starter** en el repo de dotfiles: `init.lua`, `lua/config/*`, `lua/plugins/*`, `lazy-lock.json`, `lazyvim.json`. ditto embebe un starter mínimo como valor por defecto.
- **Extras de lenguaje** (Python, Go, TS, Rust…) se activan desde el menú de setup (§10): ditto los fusiona en `lazyvim.json` (unión con los del repo) y añade el runtime que Mason necesite. Orden de importación de extras *(spike H0.3)*.
- **Actualizaciones controladas**: `checker` y updates automáticos de lazy desactivados; la versión de plugins la fija `lazy-lock.json`.
- **Primer arranque headless**: `nvim --headless "+Lazy! restore" +qa` y precalentado de Mason (comando exacto *(spike H0.5)*), para que la primera apertura sea inmediata.
- **Mason**: instala LSPs/formatters/linters en `.ditto/data/nvim/mason`. Los que son paquetes npm/go/pip usan los runtimes de mise expuestos solo en el `PATH` del wrapper de nvim, para no sombrear los del host.
- **Treesitter**: nvim-treesitter (`main`) necesita el CLI de tree-sitter (componente del núcleo) y `cc` (prerrequisito). Opción futura: parsers precompilados por plataforma en la release de ditto.
- **Nerd Font**: va en la terminal **local** del usuario; no es responsabilidad de ditto (`doctor` lo recuerda).

## 10. Menú de setup

**Cuándo:** solo en el primer `ditto up` y solo si hay TTY. `ditto setup` lo reabre. Sin TTY, o con `--yes` / `--tools=…`, se usa el perfil guardado o el default sin preguntar.

**Implementación:** formulario multiselección con `charmbracelet/huh` (Go puro, sin CGO, funciona por SSH); fallback a prompt numerado simple.

| Grupo | Componentes | Notas |
|---|---|---|
| **Núcleo** (fijo) | Neovim + LazyVim, rg, fd, tree-sitter CLI, verificación de git | Requisitos de LazyVim |
| **Herramientas** | fzf, lazygit, OpenCode (luego tmux/Zellij) | |
| **Lenguajes** | Python, Go, TypeScript, Rust, C/C++, Lua, Bash… | Cada uno activa su extra de LazyVim + runtime para Mason (Python → uv/python, TS → node, Go → go) |
| **MCPs de OpenCode** | Runtimes Node/uv | Solo si OpenCode está seleccionado |

- **Modelo**: cada componente del manifiesto declara variante por plataforma, dependencias (extra TS → node) y wrapper. El menú resuelve dependencias y muestra el tamaño estimado de descarga.
- **Paso "Origen de cada herramienta"** (opcional, plegado por defecto): para cada seleccionable muestra lo detectado y lo que instalaría ditto, p. ej. `rg: host 14.1.0 ✓ / ditto 14.1.1`, con el default preseleccionado. Los de la categoría B aparecen solo como lista de verificación (✓ / ✗ con su `hint`).
- **Sin menú**: `--source rg=host,nvim=ditto`; en `ditto.toml` compartido, sección `[sources]`.
- **Persistencia**: perfil en `.ditto/state.toml`. Opcionalmente `ditto.toml` en el repo de dotfiles como **perfil compartido**: los demás servidores lo usan sin preguntar y el menú lo muestra preseleccionado.
- **Efecto**: se regenera `.ditto/mise/config.toml` solo con lo seleccionado, se crean/eliminan wrappers y se fusionan extras en `lazyvim.json`. Lo desmarcado se libera con `mise prune`.

## 11. Modo sin internet

En orden de preferencia:

1. Instalación ya presente en `.ditto/` (`up` no necesita red si coincide con el lockfile).
2. Proxy: se respeta `HTTPS_PROXY`/`NO_PROXY` (también para mise y Mason).
3. Binarios aportados por el usuario en `.ditto/downloads/` o con `--from <dir>`, registrados con `mise link` y validados contra el `mise.lock` del repo de dotfiles (si está disponible).
4. `ditto bundle`: empaqueta `.ditto/` completo (mise, installs, plugins de lazy y paquetes de Mason) en una máquina **de la misma plataforma** con red, para copiarlo al destino.

## 12. Sesión y shell

- **Subshell** (`ditto up`): `syscall.Exec` de `$SHELL` con rcfile (bash) o `ZDOTDIR` temporal en `.ditto/` (zsh). Se carga primero el rc del usuario y **después** se antepone `.ditto/bin` al `PATH`, para que conda/pyenv/rc no lo desplacen. El `ZDOTDIR` original se restaura para shells anidadas.
- **`ditto env`**: alternativa sin subshell, componible con tmux (`eval "$(ditto env)"` en un panel) y scripts.
- `DITTO_ACTIVE=1` evita anidar: `ditto` dentro de ditto informa y no abre otra subshell.

## 13. Secretos

- Nunca en el binario, en los dotfiles ni en lockfiles.
- Se leen del entorno o de `.ditto/secrets` (modo 0600, fuera de git); opción futura de reenvío desde la máquina local por SSH (`SendEnv`/`SetEnv`).
- Credenciales de OpenCode (`auth.json`) quedan en `.ditto/` y se pierden al borrar el workspace (documentado).
- Repos de dotfiles privados: requieren agent forwarding SSH o token; `doctor` lo detecta.
- `ditto doctor` informa qué credenciales faltan sin bloquear las herramientas que no las necesitan.

## 14. Seguridad de la cadena de suministro

- HTTPS únicamente; sha256 para cada artefacto (mise/aqua, archivo de checksums del proyecto o `digest` de la API de GitHub), fijado en `mise.lock`.
- El binario de mise se verifica contra un sha256 embebido en ditto.
- Ningún script remoto se ejecuta durante la instalación de herramientas. **Excepción explícita**: el `install.sh` de bootstrap (`curl … | sh`), mínimo y auditable, que verifica el sha256 del binario de ditto. Alternativa sin script: `scp` del binario.
- Firmas (cosign/attestations) y SBOM: fuera de alcance para una herramienta personal.

## 15. Distribución de ditto

- **Build y release automáticos** con GitHub Actions + GoReleaser: al publicar un tag `v*` se compilan los 4 binarios (`linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`), se generan `checksums.txt` y se adjuntan a la GitHub Release.
- **Bootstrap:** `install.sh` detecta `uname -s/-m`, descarga el binario correcto, verifica su sha256 y lo deja en el workspace.
- `CGO_ENABLED=0` para binario estático en Linux (sin dependencia de glibc).

## 16. Estructura del repositorio

```
ditto/
├── cmd/ditto/
├── internal/{platform,manifest,setup,resolve,installer,config,env,launcher}/
├── manifest/components.toml   # catálogo de componentes y variantes (go:embed)
├── embed/                     # LazyVim starter mínimo + config OpenCode por defecto
├── install.sh
├── .goreleaser.yaml
├── .github/workflows/{ci.yml,release.yml}
├── arch.md  roadmap.md  project.md
```

## 17. Fuera de alcance (por ahora)

GUI, daemon, contenedores, sincronización distribuida, gestor complejo de proyectos, gestor de paquetes propio (lo cubre mise), gestión de LSPs propia (la cubre Mason), firmas/SBOM, tmux/Zellij (componentes opcionales más adelante).

## 18. Riesgos abiertos

- **Dependencia de mise**: cambios de comportamiento o de backends entre versiones → versión fijada y actualización deliberada; la interfaz `Installer` permite reemplazarlo.
- **Glibc mínima real** de los servidores objetivo (pendiente: `ldd --version` en cada uno), incluida la de los binarios que descarga **Mason** y la del CLI de tree-sitter.
- **OpenCode**: ruta de datos/credenciales, variantes de libc/CPU y dependencias de los MCPs.
- **Herencia de variables** en procesos hijos de Neovim (§8), pendiente de validar con LazyVim + lazygit + `:terminal`.
- **Store por workspace vs. `~/.ditto`**: con varios workspaces se duplican 1–2 GB. Se mantiene por workspace si en los servidores se comparte el usuario de sistema; si no, reconsiderar `~/.ditto` como default.
- **Orden de extras de LazyVim** al fusionar `lazyvim.json` con los del repo de dotfiles.
- **Binarios del host que cambian entre sesiones** (actualización del sistema, otro `PATH`): mitigado con la revalidación de `resolve` en cada `up`; con `source=host` puede romper una sesión que antes funcionaba. Además, `version_cmd`/`version_regex` deben cubrir formatos de salida distintos (BSD vs GNU, builds de distro).
