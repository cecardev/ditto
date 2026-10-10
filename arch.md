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

La división es **por capa, no por herramienta**: ditto nunca descarga binarios con un mecanismo propio en paralelo a mise. Lo que mise no cubre directamente (binario del host, binario aportado por el usuario) se registra *dentro* de mise con `mise link`, para que haya un único store y un único lockfile.

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
| Configuración | Wrapper por herramienta; preferir variables específicas de cada app; **no** se exportan `XDG_*` en la subshell (§8) |
| Dotfiles | Repo git configurable (`--dotfiles <url>`); embed mínimo (LazyVim starter + config OpenCode) como valor por defecto |
| Prerrequisitos | `git` ≥ 2.19 (lazy.nvim/LazyVim), `curl` o `wget` + `unzip` + `tar` (Mason), compilador C `cc` (parsers de nvim-treesitter). `ditto doctor` los verifica |
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

En tiempo de ejecución **mise no participa**: los wrappers apuntan directamente a la ruta de instalación (obtenida con `mise where` al generar los wrappers). Ni `mise activate` ni shims de mise en la subshell.

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
│   └── state.toml           # perfil seleccionado, dotfiles url, preferencias locales
├── proyecto-a/
└── proyecto-b/
```

`.ditto/` no se versiona (se añade a `.gitignore` si el workspace es un repo).

## 5. Módulos (paquetes Go)

- **`internal/platform`** — GOOS/GOARCH; libc (glibc vs musl vía `ldd --version`/`/lib/ld-musl*`), versión de glibc, versión de macOS y **flags de CPU** (AVX2, para elegir variantes `-baseline`).
- **`internal/manifest`** — catálogo embebido de **componentes**: herramienta mise (backend + nombre), variantes por plataforma (p. ej. Neovim oficial → `neovim-releases` legacy; OpenCode normal → `-baseline` → `-musl`), dependencias entre componentes, extras de LazyVim asociados y forma del wrapper.
- **`internal/setup`** — menú de selección y perfil (§10).
- **`internal/installer`** — interfaz mínima `Installer{Install, Link, Where, Prune}` con **una sola** implementación sobre mise. Bootstrap de mise: descarga la versión fijada desde su release y verifica el sha256 embebido en ditto. Aísla mise: `MISE_DATA_DIR`, `MISE_CACHE_DIR`, `MISE_STATE_DIR`, `MISE_CONFIG_DIR`, `MISE_GLOBAL_CONFIG_FILE` (y config de confianza) apuntando a `.ditto/mise/`, para no interferir con un mise del host. Ninguna `MISE_*` se exporta a la subshell.
- **`internal/config`** — clona/actualiza el repo de dotfiles; aplica el starter de LazyVim y la config de OpenCode; fusiona los extras del perfil en `lazyvim.json`; fallback a configs embebidas (`go:embed`).
- **`internal/env`** — genera wrappers por herramienta y `.host-sh` (§8); `PATH` con `.ditto/bin` primero; `DITTO_ACTIVE=1`, `DITTO_ROOT`.
- **`internal/launcher`** — `syscall.Exec` del `$SHELL` del usuario con rcfile/`ZDOTDIR` temporal; ejecución de un comando suelto; salida de `ditto env`.
- **`cmd/ditto`** — subcomandos:

| Comando | Función |
|---|---|
| `ditto` / `ditto up` | Primer uso: menú de setup. Luego instala lo que falte **según el lockfile** (sin red si ya está todo) y abre la subshell |
| `ditto setup` | Vuelve a abrir el menú de componentes |
| `ditto run -- <cmd>` | Ejecuta un comando dentro del entorno |
| `ditto env` | Imprime las variables para `eval "$(ditto env)"` (tmux, scripts) |
| `ditto doctor` | Plataforma, glibc, CPU, prerrequisitos, secretos faltantes, estado de LazyVim/Mason |
| `ditto update` | Resuelve latest con fallback y escribe el nuevo `mise.lock` en el clon de dotfiles (el usuario hace commit) |
| `ditto rollback` | Restaura el `mise.lock` anterior (historial git del repo de dotfiles) y reinstala |
| `ditto bundle` | Empaqueta `.ditto/` para copiarlo a otro host de la misma plataforma |

Limpieza de versiones no referenciadas: `mise prune` (invocado por `update`, `rollback` y `setup`).

## 6. Backends previstos *(spike H0.1)*

| Componente | Backend mise (tentativo) | Notas |
|---|---|---|
| Neovim | `aqua:neovim/neovim` / `github:neovim/neovim-releases` | Variante legacy si glibc < 2.31. LazyVim exige ≥ 0.11.2 |
| ripgrep, fd, fzf, lazygit | `aqua:` | Builds estáticos/musl en Linux |
| tree-sitter CLI | `aqua:tree-sitter/tree-sitter` | ≥ 0.25 para nvim-treesitter (rama `main`). Verificar glibc |
| OpenCode | `github:` (releases oficiales) | Variantes normal / `-baseline` / `-musl` |
| Node, Go, Python/uv | `core:node`, `core:go`, `core:python` / `aqua:astral-sh/uv` | Solo para Mason y MCPs; no visibles en la subshell (§8) |

## 7. Política de versiones

- **`ditto up` es reproducible**: instala exactamente lo del `mise.lock` (versión + checksum por plataforma). Si todo está instalado, no hace ninguna llamada de red (evita el límite de 60 req/h de la API de GitHub).
- **`ditto update`** resuelve latest para cada componente, en orden:
  1. Última versión con asset para la plataforma y checksum válido.
  2. Si falla (sin red, sin asset, libc/CPU incompatible) → se conserva la versión del lockfile.
  3. Si no hay ninguna → binario aportado por el usuario o del host, registrado con `mise link`.
  4. Si tampoco → error accionable: URL exacta a descargar y dónde colocar el archivo.
- **Neovim se fija junto con `lazy-lock.json`**: se actualizan juntos (`ditto update` + `:Lazy update` en una máquina, commit de ambos lockfiles), nunca uno sin el otro.

### Fallback de glibc (Neovim)

1. Build oficial (glibc ≥ 2.31).
2. Build *legacy* de `neovim/neovim-releases` (glibc 2.27, best-effort).
3. `nvim` del host vía `mise link`, **solo si es ≥ 0.11.2** (requisito de LazyVim; en la práctica raro en hosts antiguos).
4. Binario aportado por el usuario (`mise link`).
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
export PATH="$DITTO_ROOT/mise/installs/node/<ver>/bin:…:$PATH"   # runtimes para Mason, solo aquí
exec "$DITTO_ROOT/mise/installs/neovim/<ver>/bin/nvim" "$@"
```

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
├── internal/{platform,manifest,setup,installer,config,env,launcher}/
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
