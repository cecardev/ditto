# ditto — Roadmap

Fases e hitos para llegar de la propuesta ([project.md](project.md)) a la herramienta descrita en [arch.md](arch.md) (arquitectura híbrida: mise instala, LazyVim + Mason gestionan Neovim, ditto orquesta). Cada hito tiene criterio de aceptación verificable.

## Fase 0 — Spikes de validación (2–4 días, código descartable)

Objetivo: eliminar incógnitas antes de escribir el producto. **H0.1 va primero**: su resultado confirma o descarta la mitad del diseño.

- [ ] **H0.1 mise aislado.** Con todos los `MISE_*` apuntando a un `.ditto/` temporal (incluido `MISE_GLOBAL_CONFIG_FILE`), instalar Neovim, rg, fd, fzf, lazygit, tree-sitter CLI y OpenCode. Probar la variante legacy de Neovim en un host con glibc 2.27, `mise link` sin red, `mise.lock` con checksums por plataforma y que nada se escriba fuera de `.ditto/`. **Criterio de decisión:** si pasa, se adopta mise; si no, se documenta qué falla y se evalúa aqua o un provider propio solo para ese caso.
- [ ] **H0.2 OpenCode.** Variables de configuración (`OPENCODE_CONFIG_DIR`…), dónde escribe datos y `auth.json`, variantes de release (`-baseline`, `-musl`) y requisitos de libc/CPU, dependencias de los MCPs actuales.
- [ ] **H0.3 Aislamiento con LazyVim.** Prototipo de wrappers + `.host-sh` + subshell sin `XDG_*` global. Verificar que `git`, `ssh` y `nvme` no cambian, incluso desde `:terminal`, `:!git`, el terminal de Snacks y lazygit integrado. Probar la fusión de extras en `lazyvim.json`.
- [ ] **H0.4 Escrituras fuera de `.ditto/`.** Comparar el árbol de `$HOME` antes/después de una sesión con LazyVim + OpenCode; listar qué escapa.
- [ ] **H0.5 Mason en hosts antiguos.** Precalentar Mason en headless (comando exacto) y verificar que los LSPs principales funcionan con la glibc mínima y con los runtimes de mise solo en el `PATH` del wrapper.
- [ ] Registrar `ldd --version` y CPU (AVX2) de los servidores reales del usuario.

**Salida:** decisiones finales anotadas en arch.md (adopción de mise, glibc mínima, variables de OpenCode, estrategia de aislamiento) y actualización de §18 (riesgos).

## Fase 1 — MVP (la experiencia central de project.md §10)

Objetivo: copiar un binario, ejecutarlo, elegir componentes y obtener una shell con LazyVim y OpenCode configurados sin modificar el host.

- [ ] **H1.1 Esqueleto.** `go mod`, estructura de arch.md §16, CLI con `ditto`/`up`/`run`/`env`. CI de build y tests en cada push (`.github/workflows/ci.yml`).
- [ ] **H1.2 Platform.** OS, arquitectura, libc, versión de glibc y flags de CPU (AVX2), con tests de tabla sobre fixtures.
- [ ] **H1.3 Installer (mise).** Bootstrap de mise en versión fijada con sha256 embebido; aislamiento de `MISE_*`; `Install`/`Where`/`Link`/`Prune`.
- [ ] **H1.4 Manifest de componentes.** `components.toml` con núcleo, herramientas y lenguajes; reglas de variante por plataforma; dependencias; generación de `.ditto/mise/config.toml`.
- [ ] **H1.5 Menú de setup + perfil.** Formulario con `huh` (fallback numerado), resolución de dependencias, perfil en `.ditto/state.toml`, `ditto setup`. **Aceptación:** funciona sin TTY con `--yes`/`--tools=…` y no vuelve a preguntar en el segundo `up`.
- [ ] **H1.6 Env + launcher.** Wrappers por herramienta con variables específicas, `.host-sh`, subshell bash/zsh (PATH antepuesto después del rc del usuario), `ditto env`, `DITTO_ACTIVE`.
- [ ] **H1.7 Config mínima.** LazyVim starter embebido (checker desactivado, `vim.o.shell` → `.host-sh`) y config de OpenCode aplicados en `.ditto/config`; extras del perfil fusionados en `lazyvim.json`; `Lazy! restore` headless en el primer arranque.
- [ ] **H1.8 Build y release automáticos.** *(requisito)*
  - `.goreleaser.yaml`: targets `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`, `CGO_ENABLED=0`, `checksums.txt`.
  - `.github/workflows/release.yml`: se dispara en `push` de tags `v*`, ejecuta tests y GoReleaser, y adjunta binarios y checksums a la GitHub Release. Permisos mínimos (`contents: write`); acciones fijadas por versión.
  - Verificar con un tag de prueba (`v0.0.1-rc1`) que los 4 binarios aparecen en la release.
- [ ] **H1.9 `install.sh`.** Detecta `uname`, descarga el binario de la última release, verifica sha256, lo coloca en el workspace.

**Criterio de aceptación del MVP:** en un host limpio, `curl … | sh && ./ditto` → menú → `nvim` (LazyVim con plugins restaurados), `opencode`, `rg` funcionando en < 3 min; `nvme list` sigue siendo el del host; `git` dentro de `:terminal` usa la configuración real del usuario; al salir de la subshell y borrar el workspace, no queda nada en el sistema.

## Fase 2 — Robustez y reproducibilidad

- [ ] **H2.1 Dotfiles por git.** `--dotfiles <url>`, clon/actualización en `.ditto/dotfiles`, starter de LazyVim propio, perfil compartido `ditto.toml`, `mise.lock` + `lazy-lock.json` + `lazyvim.json` versionados.
- [ ] **H2.2 `up` reproducible.** Instalación exacta desde `mise.lock`, sin red si ya está todo instalado. Test con red caída.
- [ ] **H2.3 `update` con fallback.** Latest → versión del lockfile → `mise link` (usuario/host) → error accionable (arch.md §7). Escribe el nuevo `mise.lock` en el clon de dotfiles. Tests con asset ausente y checksum inválido.
- [ ] **H2.4 Fallback de glibc para Neovim.** Oficial → legacy → host (≥ 0.11.2) → usuario → error.
- [ ] **H2.5 Modo offline.** `--from`/`.ditto/downloads` vía `mise link`, proxy, `ditto bundle` (misma plataforma, incluye lazy + Mason).
- [ ] **H2.6 Mason precalentado.** Instalación headless de los LSPs de los extras seleccionados durante `up`.
- [ ] **H2.7 `doctor` y `rollback`.** Prerrequisitos, plataforma, secretos, estado de LazyVim/Mason, recordatorio de Nerd Font; `rollback` vía historial del lockfile.
- [ ] **H2.8 E2E en CI.** Contenedor Ubuntu 20.04 + runner macOS validando el flujo completo con `--yes`.

## Fase 3 — Ecosistema

- [ ] **H3.1 MCPs de OpenCode.** Runtimes Node/uv vía mise, configuración de MCPs en los dotfiles.
- [ ] **H3.2 Secretos.** Lectura de `.ditto/secrets` (0600) y reenvío opcional por SSH; avisos en `doctor`.
- [ ] **H3.3 Herramientas opcionales.** tmux/Zellij y otras como componentes del menú.
- [ ] **H3.4 Caché compartida opt-in** (`DITTO_CACHE` → `MISE_CACHE_DIR` común entre workspaces).
- [ ] **H3.5 Treesitter sin `cc`.** Evaluar parsers precompilados por plataforma en la release de ditto.

## Orden y dependencias

```
Fase 0 (H0.1 primero) ──► H1.1 ─► H1.2 ─► H1.3 ─► H1.4 ─► H1.5 ─► H1.6 ─► H1.7
                            │                                              │
                            └─► H1.8 (release) ─► H1.9 ───────────────────┴─► MVP
MVP ──► Fase 2 (H2.1 → H2.2 → H2.3/H2.4/H2.5/H2.6 en paralelo → H2.7 → H2.8) ──► Fase 3
```

H1.8 puede empezar justo después de H1.1: conviene tener el pipeline de release funcionando desde el primer binario para validar la distribución temprano.

## Definición de "hecho" por hito

Código + tests, CI en verde, documentación actualizada (arch.md si cambia una decisión) y verificación manual en al menos un host Linux y uno macOS cuando afecte a la plataforma.
