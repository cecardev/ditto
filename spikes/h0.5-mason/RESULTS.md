# H0.5 — Precalentado de Mason y LSPs en hosts antiguos: resultados

**Issue:** #7 · **Fecha:** 2026-10-22 · **Base:** H0.3 (#5, `spikes/h0.3-aislamiento-lazyvim/`) sobre H0.1 (#1) · **Estado:** comando validado. Los 4 LSPs arrancan y responden en macOS arm64, Ubuntu 22.04 arm64 y Rocky 8 arm64 (glibc 2.28). En glibc 2.27 fallan los LSPs que necesitan Node en arm64 (no existe Node ≥ 18 para esa combinación) y `stylua` en todas las arquitecturas. En amd64 emulado (qemu), Go y Python fallan por la emulación, no por glibc (ver *Matriz*).

## Pregunta

¿Con qué comando exacto se precalienta Mason en modo headless, y funcionan los LSPs principales en el host con la glibc mínima cuando los runtimes de mise solo están en el `PATH` del wrapper de nvim?

**Respuesta corta:**

1. **Comando:** `nvim --headless "+Lazy! restore" +qa` (H0.3) y después `nvim --headless "+luafile <prewarm.lua>"`, ambos con el wrapper de nvim y `.ditto/bin` en el `PATH`. `prewarm.lua` (embebido en ditto) instala **y espera** los parsers de nvim-treesitter, el binario de blink.cmp y los paquetes de Mason que LazyVim instalaría con los extras activos. Sale con 0 o 1. Tarda 20–35 s en arm64 nativo y en macOS, y menos de 1 s si ya está todo instalado. **`:MasonInstall` solo no basta:** la lista sale de los extras, y LazyVim lanza sus propias instalaciones asíncronas al cargar Mason. `:MasonInstall` en headless se salta los paquetes que ya se están instalando, en vez de esperarlos.
2. **Runtimes solo en el wrapper:** funciona. Mason y los LSPs usan el node, python y go de mise. La subshell, `:!` y `:terminal` siguen viendo los del host, o ninguno. Hay que añadir al wrapper las cachés de npm, pip y Go y algunas variables más: sin ellas, Mason escribe en `~/.npm`, `~/go/pkg/mod`, `~/Library/Caches/go-build`…
3. **glibc:** en 2.28 arranca todo menos `stylua` (su build `-gnu` pide 2.34). En 2.27 x86_64, Node necesita el build no oficial `glibc-217` (el oficial pide 2.28). En 2.27 arm64 no hay ningún Node ≥ 18, así que pyright y vtsls no se pueden instalar. basedpyright falla en 2.27 en las dos arquitecturas: pip no encuentra wheel de `nodejs-wheel-binaries` para glibc 2.17 e intenta compilarlo. lua_ls, gopls (se compila en el host), ruff, los parsers y blink.cmp piden glibc ≤ 2.17.
4. **Todo queda en `.ditto/data/nvim/mason`.** La excepción está en macOS: el toolchain de Go y gopls escriben su telemetría local y el índice de goimports en `~/Library/…`, y no hay ninguna variable que lo cambie (ver *Aislamiento*).
5. **Integridad:** Mason no verifica nada. Su registro no lleva checksums y el `checksums.txt` que descarga no se comprueba. Fijar el registro (validado) fija las versiones. La integridad depende de cada gestor: Go usa `sum.golang.org`, npm el `integrity` del registro y pip los hashes del índice. Los binarios de GitHub solo tienen TLS. Ver *Descargas e integridad* y la propuesta para §14.

## Contenido del directorio

| Archivo | Para qué |
|---|---|
| `lib.sh` | Librería sobre `../h0.3-aislamiento-lazyvim/lib.sh`, sin modificarla: versiones de los runtimes, `h05_write_mise_config` (subconjunto de H0.3 + node/go/python y el flavour `glibc-217` de Node si hace falta), `h05_write_lock` (lock de H0.1 + el de runtimes), `h05_install_tools`, `h05_runtime_path` (`mise which` → `H03_RUNTIME_PATH`), `h05_write_wrappers` (wrappers de H0.3 + cachés en el wrapper de nvim + `XDG_CACHE_HOME` para tree-sitter) |
| `mise.lock` | Lock de los runtimes: node 24.22.1, go 1.27.3 y python 3.13.16 para 6 plataformas, más la entrada `glibc-217` de Node para linux-x64. Todas con sha256 |
| `starter/` | Copia del starter de H0.3 **sin** `spike-offline.lua`, con los extras `lang.go`, `lang.python` y `lang.typescript`, el registro de Mason fijado (`lua/plugins/ditto.lua`) y `lazy-lock.json` regenerado (33 plugins: + `mason.nvim` y `mason-lspconfig.nvim`) |
| `lua/prewarm.lua` | El precalentado: parsers, blink.cmp y Mason, esperando a que terminen. Informe JSON (`H05_REPORT`) |
| `lua/lsp-check.lua` | Abre `main.{lua,py,go,ts}` en LazyVim (headless, a través del wrapper) y espera a que el cliente LSP esté `initialized` y responda a `textDocument/documentSymbol` |
| `lua/rt-probe.lua` | Lo que ven los hijos de nvim: `node`/`python3`/`go` por `'shell'` (`.host-sh`) y por lista de argumentos, y la config y las cachés de npm, pip y go |
| `run.sh <dest> [test\|lock\|mise-lock\|mise-lock-217]` | Prueba completa (`RESULT <id> <estado> …`), regeneración de `lazy-lock.json`, del `mise.lock` de runtimes y de la entrada `glibc-217` (solo Linux x86_64) |
| `macos.sh <scratch> [modo]` | Driver macOS: `env -i`, `HOME`/`TMPDIR` desechables y barrido del `$HOME` real |
| `docker.sh <work> [arm64\|amd64] [ubuntu-18.04\|ubuntu-22.04\|rocky-8] [modo]` | Driver Linux: contenedor desechable, solo se copian los logs. `--clean` borra las imágenes `ditto-h05-*` |

## Método

- **Nada se ejecuta con el `$HOME` real.** `macos.sh` lanza `run.sh` con `env -i HOME=<scratch>/home TMPDIR=<scratch>/tmp PATH=/usr/bin:/bin:/usr/sbin:/sbin`. En Linux todo corre dentro del contenedor (`HOME=/root`). Las comprobaciones de binarios usan otro `HOME` dentro de `<dest>/driver`.
- **Fixtures** (en el `HOME` desechable): `~/.bashrc` antepone `~/hostbin` al `PATH`, con un `node` y un `python3` falsos "del host". También `~/.config/pip/pip.conf` (`timeout = 61`), `~/.config/go/env` (y en macOS `~/Library/Application Support/go/env`) con `GOPRIVATE=spike.example.invalid` y `~/.npmrc` (`fetch-retries=7`). Son marcadores inocuos: solo cambian lo que informa `config`.
- **Contextos:** `ditto_run` es como ditto lanzaría el precalentado: entorno del usuario + `.ditto/bin` primero. `in_session` es el usuario escribiendo `nvim` dentro de la subshell (bashrc de sesión de H0.3). Las pruebas de LSP y de runtimes corren con `in_session`.
- **Escrituras fuera de `.ditto`:** `find -newer <marker>` sobre `$HOME`, `$TMPDIR`, `/tmp` y `/var/tmp` (fuera de `<dest>`), desde antes de instalar hasta después de los LSPs. En macOS, además, barrido de todo el `$HOME` real (`macos.sh`).
- **Control (T10):** un segundo `.ditto` con el wrapper de H0.3 + runtimes, **sin** las variables de caché, que instala un paquete npm (`prettier`), uno de GitHub (`ruff`) y uno de Go (`goimports`).
- **Plataformas:** macOS arm64 en el host. Ubuntu 18.04 (glibc 2.27) y 22.04 en arm64 nativo y amd64 emulado. Rocky 8 arm64 (glibc 2.28) como proxy de la glibc mínima del inventario, que no existe todavía (#3 pendiente). Imagen = base + `ca-certificates curl git unzip xz gcc libc` (categoría B; `cc` para los parsers). Sin node, python ni go del sistema.

Comandos:

```sh
# macOS (HOME/TMPDIR desechables). <scratch> corto: /tmp/h05
DITTO_SPIKE_WATCH_EXCLUDE='<ruido de otros procesos en /tmp>' \
DITTO_SPIKE_REAL_HOME_EXCLUDE='<ruido de otras apps en ~>' \
  sh spikes/h0.5-mason/macos.sh /tmp/h05
# Linux
sh spikes/h0.5-mason/docker.sh /tmp/h05d/u18-arm64 arm64 ubuntu-18.04
sh spikes/h0.5-mason/docker.sh /tmp/h05d/u18-amd64 amd64 ubuntu-18.04
sh spikes/h0.5-mason/docker.sh /tmp/h05d/u22-arm64 arm64 ubuntu-22.04
sh spikes/h0.5-mason/docker.sh /tmp/h05d/u22-amd64 amd64 ubuntu-22.04
sh spikes/h0.5-mason/docker.sh /tmp/h05d/rocky8 arm64 rocky-8
sh spikes/h0.5-mason/docker.sh --clean
# Regenerar los locks (red)
sh spikes/h0.5-mason/macos.sh /tmp/h05l lock          # starter/lazy-lock.json
sh spikes/h0.5-mason/macos.sh /tmp/h05l mise-lock     # mise.lock (6 plataformas)
sh spikes/h0.5-mason/docker.sh /tmp/h05d/l amd64 ubuntu-18.04 mise-lock-217   # + entrada glibc-217
```

Variables: `H05_CONTROL` (1), `H05_BASEDPYRIGHT` (1), `H05_LSP_TIMEOUT` (ms por LSP; 120000, o 240000 en Docker), `H05_NODE_FLAVOR` (fuerza el flavour), `H05_MASON_REGISTRY=latest` (registro sin fijar), `GOMAXPROCS` (se pasa al contenedor).

## Comando de precalentado

```sh
# Lo ejecuta ditto (Go) con el entorno del usuario, PATH=.ditto/bin:$PATH y DITTO_ROOT:
nvim --headless "+Lazy! restore" +qa                  # H0.3: plugins en el commit del lock
nvim --headless "+luafile <prewarm.lua embebido en ditto>"   # exit 0 = todo instalado
```

Qué hace `prewarm.lua` (`lua/prewarm.lua`), en este orden:

1. **Parsers:** `require("lazy").load` de nvim-treesitter y `require("nvim-treesitter").install(LazyVim.opts("nvim-treesitter").ensure_installed):wait()`. Con los tres extras son 29 lenguajes: los 23 de LazyVim + `go`, `gomod`, `gowork`, `gosum`, `ninja` y `rst`. Al cargar nvim-treesitter, LazyVim lanza su propia instalación de la misma lista. A veces las dos chocan en el directorio de descarga (`Could not rename temp: ENOTEMPTY`, visto en macOS y Linux), así que los que faltan se reintentan una vez. Con el reintento, 0 fallos.
2. **blink.cmp:** `require("blink.cmp.fuzzy.download").ensure_downloaded(cb)` hasta que la implementación sea `rust`. Al cargar el plugin, su `setup` lanza la misma descarga; una llamada concurrente lee el archivo de versión a medio escribir y cae a Lua, así que se reintenta.
3. **Mason:** la lista se calcula con las mismas reglas que `lazyvim/plugins/lsp/init.lua`: `ensure_installed` de mason.nvim + los servidores de `nvim-lspconfig` con `enabled ~= false`, `mason ~= false` y paquete en `mason-lspconfig` + `ensure_installed` de mason-lspconfig. Se cargan mason.nvim, mason-lspconfig y nvim-lspconfig (que arrancan las instalaciones de LazyVim) y se refresca el registro. Después se instala lo que no esté instalado ni instalándose, y se espera a que no quede nada pendiente. Lo que LazyVim lanzó y no terminó instalado se reintenta una vez, para registrar el error. El script sale con `cquit 1` si falta algo.

Lista resultante con `lang.go` + `lang.python` + `lang.typescript` (LazyVim `9997009`): `gofumpt goimports golangci-lint gopls lua-language-server pyright ruff shfmt stylua vtsls`, más `basedpyright` si `vim.g.lazyvim_python_lsp = "basedpyright"` (comprobado: el mismo comando añade solo ese paquete en 5 s). **No existe el extra `lang.lua`**: lua_ls y stylua vienen del núcleo de LazyVim.

Observaciones:

- **`Lazy! sync` y `Lazy! restore` ya disparan instalaciones** de Mason y de parsers, que se cortan al salir: *"Neovim is exiting while packages are still installing"*. Son inofensivas, porque `prewarm.lua` las rehace, pero demuestran que `+qa` no espera.
- Una segunda ejecución tarda menos de 1 s y no instala nada (`T3-prewarm-again`).
- Se validaron dos invocaciones separadas; no se probó juntar `+Lazy! restore` y `+luafile` en una sola.
- Proxy: Mason, nvim-treesitter (`curl`), npm, pip y go heredan `HTTPS_PROXY`/`NO_PROXY` del entorno (el wrapper no los toca). `curl` lee además `~/.curlrc` del usuario. blink.cmp pasa `HTTPS_PROXY` a `curl` con `--proxy`.
- Dominios que hay que permitir: `github.com` y sus redirecciones de assets, `raw.githubusercontent.com` (esquemas de configuración de lua_ls, pyright y vtsls), `api.mason-registry.dev` (versiones de PyPI), `registry.npmjs.org`, `pypi.org` + `files.pythonhosted.org`, `proxy.golang.org` + `sum.golang.org`, `nodejs.org` (cabeceras de node-gyp) y, para mise, `nodejs.org`/`unofficial-builds.nodejs.org`, `dl.google.com` y `github.com` (python-build-standalone). Con el registro fijado, **ninguna** llamada a `api.github.com`.

## Runtimes (mise, solo en el `PATH` del wrapper)

| Runtime | Backend | Versión | glibc del binario | Notas |
|---|---|---|---|---|
| Node | `core:node` | 24.22.1 (LTS) | oficial: **2.28**; `glibc-217` (no oficial): 2.17 | En glibc < 2.28 x86_64, ditto genera `[settings.node] flavor = "glibc-217"` + `mirror_url = "https://unofficial-builds.nodejs.org/download/release/"`. **arm64 con glibc < 2.28: no hay build** (unofficial-builds solo publica `linux-x64-glibc-217`) |
| Python | `core:python` (python-build-standalone, `compile = false`) | 3.13.16 | 2.17 | El lock marca `provenance = "github-attestations"` |
| Go | `core:go` | 1.27.3 | estático | `GOTOOLCHAIN=local` en el wrapper: nunca descarga otro toolchain |

- Comprobado en 18.04 amd64: el Node oficial falla en la instalación (`version 'GLIBC_2.28' not found`) y el `glibc-217` arranca (`v24.22.1`).
- **`mise lock` multiplataforma no sirve para el flavour:** generado desde macOS (`--platform linux-x64`), la entrada `glibc-217` sale como compilación desde fuentes (`install = "source"`, sin checksum). Generada en Linux x86_64 (`run.sh … mise-lock-217`), sale con la URL del binario y su sha256. El lock guarda una entrada por combinación de opciones (`[tools.node.options]`), igual que la variante `-baseline` de OpenCode en H0.1.
- sha256 de la entrada `glibc-217` contrastado a mano con el `SHASUMS256.txt` de unofficial-builds (`422ddeec…c570`). Ese archivo no va firmado con GPG, a diferencia del oficial.
- `uv` no hace falta: Mason instala los paquetes pypi con `python3 -m venv` + `pip`.

## Matriz LSP × plataforma

T6 = el LSP se adjunta al buffer, se inicializa y responde a `documentSymbol` (2 símbolos en cada archivo de prueba). Tiempo hasta `initialized` en la primera apertura.

| Plataforma | glibc | lua_ls 3.19.2 | pyright 1.1.414 (npm) | basedpyright 1.40.2 (pip) | gopls v0.23.0 (go) | vtsls 0.3.0 (npm) | stylua 2.6.0 | Total |
|---|---|---|---|---|---|---|---|---|
| macOS arm64 (host, Darwin 25.2) | — | ✅ 0,3 s | ✅ 0,3 s | ✅ 0,4 s | ✅ 0,3 s | ✅ 0,4 s | ✅ | 33 PASS, 1 FAIL (T9: telemetría de Go, ver *Aislamiento*) |
| Ubuntu 22.04 arm64 (nativo) | 2.35 | ✅ 0,07 s | ✅ 0,1 s | ✅ 0,2 s | ✅ 0,05 s | ✅ 0,2 s | ✅ | **34 PASS, 0 FAIL** |
| Rocky 8 arm64 (nativo) | 2.28 | ✅ 0,07 s | ✅ 0,1 s | ✅ 0,2 s | ✅ 0,06 s | ✅ 0,2 s | ❌ `GLIBC_2.30`… | 33 PASS, 1 FAIL (stylua) |
| Ubuntu 18.04 arm64 (nativo) | 2.27 | ✅ 0,07 s | ❌ sin Node | ❌ pip intenta compilar `nodejs-wheel-binaries` (no hay wheel para glibc 2.17 en aarch64) | ✅ 0,07 s | ❌ sin Node | ❌ `GLIBC_2.28`… | 19 PASS, 10 FAIL |
| Ubuntu 18.04 amd64 (emulado) | 2.27 | ✅ 0,8 s | ✅ 2,2 s (Node `glibc-217`) | ❌ pip intenta compilar `nodejs-wheel-binaries` (sin wheel para glibc 2.17); en la primera ejecución, `python3` SIGSEGV (qemu) | ⚠️ `go install` aborta: *"found bad pointer in Go heap"* (qemu) | ✅ 2,2 s | ❌ `GLIBC_2.28`…; ✅ con `--target=linux_x64` (musl) | 23 PASS, 6 FAIL |
| Ubuntu 22.04 amd64 (emulado) | 2.35 | ✅ 0,9 s | ✅ 2,1 s | ✅ 2,9 s | ⚠️ `go install` aborta (SIGSEGV en el runtime de Go, qemu) | ✅ 2,3 s | ✅ | 27 PASS, 4 FAIL (todo por los paquetes Go) |

Leyenda: ❌ = no funciona en esa glibc. ⚠️ = fallo de la emulación qemu de amd64 sobre arm64, no de glibc. gopls se compila en el host y enlaza su propia glibc, y basedpyright se ve en 22.04 y Rocky 8. En hardware x86_64 real queda pendiente.

### glibc requerida por paquete (Linux; máximo `GLIBC_x.y` referenciado por sus ELF)

| Paquete | Origen en Mason | x86_64 | arm64 | Mínima práctica |
|---|---|---|---|---|
| lua-language-server | GitHub release (`-linux-x64` / `-linux-arm64`) | 2.17 | 2.17 | 2.17 |
| gopls, gofumpt, goimports | `go install` en el host | según host / estático | según host (2.17 en 2.27; 2.34 si se compila en 2.35) | la del host: se compila allí |
| golangci-lint, shfmt | GitHub release (Go estático) | — | — | ninguna |
| ruff | GitHub release (x64: **musl**; arm64: gnu) | estático | 2.17 | 2.17 |
| pyright, vtsls | npm (JS) | — | — | **la de Node**: 2.28 oficial, 2.17 con `glibc-217` (solo x64) |
| basedpyright | pypi (incluye Node en el wheel `nodejs-wheel-binaries`) | — | 2.28 | 2.28 (en 2.27 aarch64 pip intenta compilarlo y falla) |
| stylua | GitHub release `-gnu` | 2.34 | 2.34 | **2.34**. x64: `MasonInstall --target=linux_x64 stylua` instala el build musl (comprobado en 18.04). arm64: upstream publica `stylua-linux-aarch64-musl.zip`, pero el registro de Mason no lo mapea |
| blink.cmp (`.so` de la release) | GitHub release del tag | 2.17 | 2.17 | 2.17 |
| Parsers de nvim-treesitter | compilados en el host con `tree-sitter build` + `cc` | 2.14 | 2.17 | la del host |
| python-build-standalone | mise | 2.17 | 2.17 | 2.17 |

## Tiempos y tamaños

| Plataforma | `install --locked` (H0.3 + runtimes) | `Lazy! restore` | prewarm (parsers / blink / Mason) | `.ditto` total |
|---|---|---|---|---|
| macOS arm64 | 11 s | 8–14 s | **29 s** (6,6 / 0,5 / 21,6) | 2,5 GB |
| Ubuntu 22.04 arm64 | 8 s | 11 s | **24 s** (5,2 / 3,0 / 15,1) | 2,4 GB |
| Rocky 8 arm64 | 7 s | 12 s | **20–35 s** (2,1–4,7 / 3,0 / 14,7–26,8) | 2,4 GB |
| Ubuntu 18.04 arm64 | 7 s | 22–27 s | 25 s (con fallos) | 1,6 GB |
| Ubuntu 18.04 amd64 (emulado) | 21 s | 54 s | 52 s (con fallos) | 1,4 GB |
| Ubuntu 22.04 amd64 (emulado) | 17 s | 35 s | 53 s (parsers 30 s; Go falla por qemu) | — |

Desglose (22.04 arm64; macOS es casi igual):

| Directorio | MB |
|---|---|
| `data/nvim/mason` | 492, de ellos **basedpyright 292** (incluye Node), pyright 37, gopls 38, golangci-lint 37, vtsls 29, ruff 20, lua_ls 11, stylua 9, goimports 8, gofumpt 4, shfmt 3 |
| `cache/go` (`GOCACHE` + `GOMODCACHE` de los `go install`) | 594 (629 en macOS) |
| `cache/pip` · `cache/npm` | 71 · 29 |
| `mise/installs` (H0.3 + runtimes) | 653: node 204, go 276, python 89 |
| `data/nvim/lazy` (33 plugins) | 121 |
| `data/nvim/site` (29 parsers) | 9 |
| blink.cmp `target/` | 1 |

`cache/go` es el mayor desperdicio: solo sirve para recompilar. `ditto` puede vaciarlo tras el precalentado (`go clean -cache -modcache` con las mismas variables) o no fijar `GOCACHE` persistente para los `go install` de Mason. Sin basedpyright, Mason ocupa unos 200 MB.

## Aislamiento

### Runtimes: quién ve qué (T7)

| Contexto | `node` | `python3` | `go` |
|---|---|---|---|
| Shell del host | `~/hostbin/node` (fixture) | `~/hostbin/python3` | — |
| Subshell de ditto | igual que el host ✅ | igual ✅ | igual ✅ |
| `:!` / `system()` con string (`.host-sh`) | igual que el host ✅ (sin `mason/bin` ni runtimes) | igual ✅ | igual ✅ |
| Hijo con lista de argumentos (Mason, LSPs) | `.ditto/mise/installs/node/24.22.1/bin/node` ✅ | `.ditto/mise/installs/python/3.13.16/bin/python3` ✅ | `.ditto/mise/installs/go/1.27.3/bin/go` ✅ |

En 18.04 arm64, sin Node de mise, el hijo con lista de argumentos **cae en el `node` del host** (`~/hostbin/node`): el `PATH` del wrapper es runtimes + `PATH` del usuario. Si el host tiene un Node antiguo, Mason lo usaría. ditto debería detectarlo (`doctor`) o no anteponer nada y avisar.

### Cachés y estado de npm, pip y Go (T8, T9, T10)

Sin variables (control T10), los paquetes de Mason escriben fuera de `.ditto` en todas las plataformas: `~/.npm/_cacache`, `~/.npm/_logs`, `~/.npm/_update-notifier-last-checked`, `~/go/pkg/mod` (≈ 5 300 archivos) y `~/go/pkg/sumdb`. En macOS, además, `~/Library/Caches/go-build`, `~/Library/Caches/pip` y `~/Library/Caches/node-gyp`. En Linux, pip y go-build caen en `XDG_CACHE_HOME`, que dentro de nvim es `.ditto/cache`.

Variables que el wrapper de nvim exporta (guardadas en `DITTO_ORIG_*` y restauradas por `.host-sh` y los demás wrappers, como en H0.3), validadas con T9 = 0 escrituras fuera en Linux:

| Variable | Valor | Motivo |
|---|---|---|
| `npm_config_cache` | `.ditto/cache/npm` | caché y `_logs` de npm |
| `npm_config_devdir` | `.ditto/cache/node-gyp` | cabeceras de node-gyp (macOS: `~/Library/Caches/node-gyp`). npm 11 avisa *"Unknown env config devdir. This will stop working in the next major version"* |
| `PIP_CACHE_DIR` | `.ditto/cache/pip` | macOS: `~/Library/Caches/pip` |
| `GOPATH` | `.ditto/data/go` | `~/go` (`pkg/sumdb`) |
| `GOMODCACHE` · `GOCACHE` | `.ditto/cache/go/{mod,build}` | `~/go/pkg/mod`; macOS `~/Library/Caches/go-build` |
| `GOTOOLCHAIN` | `local` | sin descargas de toolchain fuera del lock |
| `GOPLSCACHE` · `GOLANGCI_LINT_CACHE` | `.ditto/cache/{gopls,golangci-lint}` | macOS: `~/Library/Caches/{gopls,golangci-lint}` (nvim-lint ejecuta golangci-lint al abrir un `.go`) |
| `GOENV` (solo Linux, si el usuario no lo tiene) | `${XDG_CONFIG_HOME original:-~/.config}/go/env` | `go env -w` del usuario (GOPROXY, GOPRIVATE): con `XDG_CONFIG_HOME=.ditto/config` se perdería. Validado: `GOPRIVATE` visible |
| enlace `.ditto/config/pip` → `${XDG_CONFIG_HOME original:-~/.config}/pip` | (como `.ditto/config/git` en H0.3) | pip en Linux lee `$XDG_CONFIG_HOME/pip/pip.conf`: sin el enlace se pierden `index-url`, `proxy` y `trusted-host`. Validado: `timeout=61` visible a través del enlace. En macOS, pip lee `~/.config/pip/pip.conf` directamente |
| wrapper de `tree-sitter`: `XDG_CACHE_HOME=.ditto/cache` | | nvim-treesitter ejecuta `tree-sitter build`, que deja un lock en `$XDG_CACHE_HOME/tree-sitter`, y el wrapper de H0.3 restaura el XDG del host (`~/.cache/tree-sitter/lock` en Linux y macOS) |

`~/.npmrc` se sigue leyendo, porque depende de `HOME` y no de XDG (validado: `fetch-retries=7`). En `:!` todas estas variables vuelven a estar sin definir (T8-shell-caches).

**Consecuencia:** gopls, lanzado por nvim, también usa el `GOMODCACHE` de `.ditto` para los proyectos del usuario. Descarga allí sus dependencias en vez de reutilizar `~/go/pkg/mod`. Cuesta disco, pero no se escribe fuera.

**Residuo en macOS (no evitable con variables):** el toolchain de Go (`go install` de Mason) y gopls usan `os.UserConfigDir()`/`os.UserCacheDir()`. En darwin son `~/Library/Application Support` y `~/Library/Caches`, y no dependen de XDG. Escriben `~/Library/Application Support/go/telemetry/local/*.count` (telemetría local en modo por defecto `local`: no se sube) y `~/Library/Caches/goimports/index-*` (índice de módulos de gopls). `GOTELEMETRY=off` y `GOTELEMETRYDIR` como variables **no** tienen efecto (comprobado), y `x/tools/internal/modindex` no admite override. En Linux ambos caen en `XDG_*` → `.ditto`. Opciones (decisión pendiente):

1. Aceptarlo como excepción documentada en macOS (16 archivos, solo telemetría local e índice).
2. Lanzar `go` y gopls con un `HOME` propio en macOS. Rompe módulos privados: `git` pierde `~/.gitconfig` y las credenciales.
3. `go telemetry off`: escribe el modo en `~/Library/Application Support/go/telemetry/mode` y cambia la preferencia del usuario para su propio Go, así que no es aceptable sin su consentimiento.

`$HOME` real del Mac: el barrido completo no encontró nada de nvim, Mason, npm, pip, go ni mise. Las rutas nuevas eran de procesos ajenos (otras apps del usuario, Docker buildx).

## Descargas e integridad

| Artefacto | Origen | ¿Versión fijada? | Verificación de integridad |
|---|---|---|---|
| Runtimes (node, go, python) | mise | sí, `mise.lock` | **sha256 por plataforma** en `mise.lock` (+ attestations de GitHub en python) |
| Registro de Mason | `github.com/mason-org/mason-registry/releases/download/<tag>/registry.json.zip` | **sí, si se fija** `registries = { "github:mason-org/mason-registry@<tag>" }` (validado: `2026-10-22-ill-fund`, sin llamadas a `api.github.com`). Por defecto, "latest" vía API de GitHub (límite de 60 req/h) | **ninguna**: descarga también `checksums.txt` y lo guarda en `info.json`, pero no lo compara con el zip (`mason-registry/sources/github.lua`) |
| Paquetes de Mason desde GitHub (lua_ls, stylua, ruff, shfmt, golangci-lint) | GitHub releases | sí: la entrada del registro fija la versión (`pkg:github/LuaLS/lua-language-server@3.19.2`) | **ninguna**: el registro no tiene campos de checksum (0 de 601 paquetes) y Mason no verifica los assets. Solo TLS |
| Paquetes npm (pyright, vtsls) | registry.npmjs.org | el paquete raíz sí (`pkg:npm/pyright@1.1.414`); **sus dependencias no** (npm resuelve sin lockfile) | `integrity` (sha512) de los metadatos del registro npm (mismo origen) |
| Paquetes pypi (basedpyright) | PyPI | el raíz sí; las dependencias no | sha256 del fragmento de URL del índice, que pip compara (mismo origen) |
| Paquetes Go (gopls, gofumpt, goimports) | proxy.golang.org | sí (`@v0.23.0` + `go.sum` del módulo) | **`sum.golang.org`** (checksum database con log de transparencia) + `go.sum`. La mejor de todas |
| Parsers de nvim-treesitter | `github.com/<repo>/archive/<commit>.tar.gz` | sí: commit de `parsers.lua` en el commit de nvim-treesitter fijado por `lazy-lock.json` | **ninguna** sobre el tarball (contenido direccionado por commit, pero GitHub no garantiza que el tarball sea estable byte a byte). Se compila en local |
| Binario de blink.cmp | `github.com/saghen/blink.cmp/releases/download/v1.10.2/<triple>.so` | sí: el commit del lock es el tag `v1.10.2` | sha256 contra un `.sha256` **de la misma release**: protege de corrupción, no de una release manipulada |
| Cabeceras de node-gyp | nodejs.org | según la versión de Node | `SHASUMS256.txt` de nodejs.org |

## Hallazgos

- **`:MasonInstall` headless** (`mason/api/command.lua`) bloquea y sale con `1cq` si algo falla, pero **se salta los paquetes que ya se están instalando** sin esperarlos. Con LazyVim siempre hay alguno, porque `config` de mason.nvim lanza `ensure_installed` en cuanto se carga. Por eso el precalentado espera sobre el estado del registro.
- **Carreras de LazyVim en el primer arranque:** al cargar nvim-treesitter y blink.cmp, LazyVim y el plugin lanzan sus descargas asíncronas. Una segunda petición concurrente de lo mismo puede fallar (parsers: `ENOTEMPTY`; blink: cae a Lua). Un reintento lo resuelve en todas las plataformas.
- **stylua:** el registro mapea `linux_x64_gnu` y `linux_arm64_gnu` al build `-gnu` (glibc 2.34) y deja el musl solo para `linux_x64` sin libc. `:MasonInstall --force --target=linux_x64 stylua` instala el musl en x86_64 (comprobado en 18.04). En arm64 no hay alternativa en Mason. Opción para ditto: instalar stylua con mise (`github:JohnnyMorganz/StyLua`, asset `-musl`, sha256 en `mise.lock`) y sacarlo de Mason.
- **Emulación amd64 (qemu sobre arm64):** el `go` de mise aborta de forma no determinista durante `go install` (*"found bad pointer in Go heap"*, *"unexpected fault address"*) y el `python3` de un venv murió una vez con SIGSEGV. Con `GOMAXPROCS=1` (`GOMAXPROCS=1 sh docker.sh …`) sigue fallando (*"sweep increased allocation count"*). En arm64 nativo, con la misma glibc 2.27, ambos funcionan. No es un problema de glibc, pero impide validar los paquetes Go (gopls, gofumpt, goimports) en amd64 con esta máquina.
- **Telemetría y "update notifier":** npm crea `_update-notifier-last-checked` (en su caché, ya dentro de `.ditto`). Go deja contadores locales (ver *Aislamiento*). En `mason.log` (nivel DEBUG) no aparece ninguna petición que no sea de descarga.
- **mason-lspconfig** entra en el lock solo porque se activó Mason. El starter de ditto lleva los dos plugins en `lazy-lock.json`.
- **`pip config debug`** muestra que en Linux pip lee `.ditto/config/pip/pip.conf` (el enlace) y en macOS `~/.config/pip/pip.conf`.
- `T7` en Rocky 8 necesitó `diffutils` (`cmp`) en la imagen: no viene en `rockylinux:8`. No afecta a ditto.

## Reutilización en H2.6

```sh
H05_DIR=spikes/h0.5-mason
. "$H05_DIR/lib.sh"                       # carga H0.3 y H0.1 sin modificarlos
h05_paths "$WS/.ditto"
h05_install_tools                         # mise (sha256) + H0.3 tools + node/go/python (lock con sha256)
h05_write_wrappers                        # wrapper de nvim con runtimes + cachés; tree-sitter con XDG_CACHE_HOME
h03_write_session
h03_install_starter "$H05_DIR/starter"
PATH="$DITTO_ROOT/bin:$PATH" nvim --headless "+Lazy! restore" +qa
PATH="$DITTO_ROOT/bin:$PATH" nvim --headless "+luafile $H05_DIR/lua/prewarm.lua"
```

- `lua/prewarm.lua` es el prototipo del script que ditto embebe (`go:embed`) y ejecuta en `setup`/`up`. El informe JSON (`H05_REPORT`) tiene pasos, tiempos, paquetes, fallos y registro, y sirve para `ditto doctor`.
- `lua/lsp-check.lua` es una base para un `ditto doctor --lsp`.
- `H05_WRAPPER=bare` reproduce el control sin cachés.

## Pendientes

- [ ] **x86_64 real con glibc 2.27** (sin emulación): gopls, gofumpt y goimports. Comando: `sh spikes/h0.5-mason/run.sh /tmp/h05 test` con `DITTO_SPIKE_DISPOSABLE_HOME=1` **solo en un usuario o contenedor desechable**: escribe fixtures en `$HOME`. Esperado: Go igual que en arm64 nativo. basedpyright ya se sabe que falla en 2.27 (`nodejs-wheel-binaries`).
- [ ] **Glibc mínima real del inventario** (#3): repetir en el servidor más antiguo. Rocky 8 (2.28) y Ubuntu 18.04 (2.27) son proxies.
- [ ] **Ubuntu 22.04 amd64** en hardware real (aquí, emulado: ver la fila de la matriz).
- [ ] **macOS x64 (Intel):** sin hardware. `sh spikes/h0.5-mason/macos.sh /tmp/h05`.
- [ ] **Proxy corporativo real** (`HTTPS_PROXY` + `pip.conf` con `index-url` privado + `GOPROXY` privado): aquí solo se validó que la config del usuario llega a los procesos de Mason, con marcadores inocuos.
- [ ] **blink.cmp sin descarga** (propuesta de §14): poner el `.so` verificado por ditto en `lazy/blink.cmp/target/release/` sin archivo `version` y `fuzzy.prebuilt_binaries.download = false`. El código (`fuzzy/download/init.lua`, línea 27) acepta una biblioteca colocada a mano; no se ha probado.
- [ ] Decidir el residuo de Go en macOS (ver *Aislamiento*, opciones 1–3).
- [ ] Llevar la decisión a arch.md y roadmap.md con `/record-decision` (en esta story no se editan).

## Conclusión

Según el *Criterio de decisión* del issue:

- **El comando es fiable** (0 fallos en macOS, Ubuntu 22.04 arm64 y Rocky 8 arm64; idempotente) **y los LSPs arrancan** → se anota en §9 el comando y la glibc mínima por LSP.
- **Algunos LSPs fallan por glibc** → se documentan la alternativa o la limitación en §18:
  - Node (pyright, vtsls, basedpyright) en glibc < 2.28: build `glibc-217` en x86_64. **Sin alternativa en arm64.**
  - stylua (`-gnu`, glibc 2.34): build musl (`--target=linux_x64` en Mason, o mise en cualquier arquitectura).
  - lua_ls, gopls, ruff, parsers y blink.cmp: glibc 2.17, sin problema.

## Decisión propuesta (texto para arch.md, vía `/record-decision`)

### §9 LazyVim — sustituye las viñetas "Primer arranque headless" y "Mason"

> - **Primer arranque headless** (lo ejecuta ditto con el entorno del usuario, `.ditto/bin` primero en el `PATH` y `DITTO_ROOT`), validado en H0.5:
>   1. `nvim --headless "+Lazy! restore" +qa`: plugins en el commit de `lazy-lock.json` (H0.3).
>   2. `nvim --headless "+luafile <prewarm.lua embebido>"`: instala **y espera** (a) los parsers de `ensure_installed` de nvim-treesitter, (b) el binario de blink.cmp y (c) los paquetes de Mason que LazyVim instalaría con los extras activos. La lista se calcula como `lazyvim/plugins/lsp/init.lua`: `ensure_installed` de mason.nvim + servidores de nvim-lspconfig con `enabled ~= false`, `mason ~= false` y paquete en mason-lspconfig. Reintenta una vez lo que choque con las instalaciones asíncronas de LazyVim y sale con 0/1. Con Go + Python + TS: unos 25 s en arm64 nativo y macOS, menos de 1 s si ya está hecho. `:MasonInstall` solo no sirve: en headless se salta los paquetes que LazyVim ya está instalando.
> - **Mason**: instala en `.ditto/data/nvim/mason` (validado). El starter fija el registro: `registries = { "github:mason-org/mason-registry@<tag>" }`. Así quedan fijas las versiones de todos los paquetes y no hay llamadas a la API de GitHub; `ditto update` mueve el tag. Los paquetes npm/go/pip usan los runtimes de mise (`core:node` 24 LTS, `core:go`, `core:python` precompilado) expuestos solo en el `PATH` del wrapper de nvim. La subshell, `:!` y `:terminal` siguen viendo los del host (validado). glibc mínima por paquete (Linux): lua_ls, ruff, gopls (se compila en el host), parsers y blink.cmp 2.17. pyright, vtsls y basedpyright, la de Node: 2.28, o 2.17 con el build `glibc-217` en x86_64. stylua `-gnu` 2.34, o su build musl.
> - **Runtimes y glibc**: si el host tiene glibc < 2.28 en x86_64, ditto genera `[settings.node] flavor = "glibc-217"` y `mirror_url = "https://unofficial-builds.nodejs.org/download/release/"`. La entrada del lock para ese flavour se genera en Linux x86_64 (`mise lock` desde otra plataforma la deja como compilación desde fuentes, sin checksum). En arm64 con glibc < 2.28 no hay Node: ditto no instala los paquetes de Mason que lo necesitan y `doctor` lo explica.

### §8 Aislamiento — añadir tras el wrapper de Neovim

> **Mason y sus hijos** (validado en H0.5). El wrapper de nvim exporta además, guardando y restaurando los originales como el resto de `DITTO_ORIG_*`: `npm_config_cache=.ditto/cache/npm`, `npm_config_devdir=.ditto/cache/node-gyp`, `PIP_CACHE_DIR=.ditto/cache/pip`, `GOPATH=.ditto/data/go`, `GOMODCACHE=.ditto/cache/go/mod`, `GOCACHE=.ditto/cache/go/build`, `GOPLSCACHE=.ditto/cache/gopls`, `GOLANGCI_LINT_CACHE=.ditto/cache/golangci-lint` y `GOTOOLCHAIN=local`. En Linux añade `GOENV=${XDG_CONFIG_HOME original:-~/.config}/go/env` (si el usuario no lo define) y el enlace `.ditto/config/pip` → `${XDG_CONFIG_HOME original:-~/.config}/pip`, igual que `.ditto/config/git`, para que `go env -w` y `pip.conf` (índices, proxy) sigan valiendo. El wrapper de `tree-sitter` fija `XDG_CACHE_HOME=.ditto/cache` (su lock). `~/.npmrc` y `HTTPS_PROXY`/`NO_PROXY` llegan sin cambios. Sin estas variables, Mason escribe en `~/.npm`, `~/go` y `~/Library/Caches`.
> **Excepción en macOS** *(decisión pendiente)*: el toolchain de Go y gopls escriben telemetría local (`~/Library/Application Support/go/telemetry`) y el índice de goimports (`~/Library/Caches/goimports`) en rutas de `os.UserConfigDir`/`UserCacheDir`, sin variable que las mueva.

### §14 Seguridad de la cadena de suministro — añadir

> - **Lo que descargan los plugins** no pasa por `mise.lock`. Validado en H0.5:
>   - **Mason**: no verifica nada (su registro no lleva checksums y el `checksums.txt` que descarga no se comprueba). Se mitiga fijando el registro a un tag (versiones exactas). La integridad queda en manos de cada gestor: Go con `sum.golang.org`, npm con el `integrity` del registro y pip con los hashes del índice. Las releases de GitHub (lua_ls, stylua, ruff, shfmt, golangci-lint) solo tienen TLS.
>   - **Parsers de nvim-treesitter**: tarball de GitHub en el commit fijado por `lazy-lock.json`, sin hash, compilado en local.
>   - **blink.cmp**: `.so` de la release del tag fijado, comparado con un `.sha256` de la misma release.
> - **Propuesta** *(H2.6)*: los binarios precompilados que hoy trae Mason desde GitHub (lua_ls, stylua, ruff, shfmt, golangci-lint) pasan a mise (aqua/github, con sha256 en `mise.lock` y la variante musl donde haga falta) con `mason = false`. Mason se queda solo con lo que se instala con npm/pip/go, cuya integridad verifica el propio gestor. Para blink.cmp, ditto descarga el `.so` con sha256 embebido y desactiva la descarga del plugin (`fuzzy.prebuilt_binaries.download = false`; sin validar).

### §18 Riesgos abiertos — sustituir "Glibc mínima real" y añadir

> - **Glibc mínima real**: el oficial de Neovim pide 2.28/2.29; el legacy, tree-sitter (conda), mise (musl), lua_ls, ruff, gopls, los parsers y blink.cmp funcionan en 2.27 (H0.1, H0.5). **Node ≥ 18 oficial pide 2.28.** En x86_64 hay build `glibc-217` no oficial (sin firma GPG). En **arm64 con glibc < 2.28 no hay Node**, así que no hay pyright ni vtsls; basedpyright pide 2.28 en las dos arquitecturas (su wheel `nodejs-wheel-binaries`). **stylua `-gnu` pide 2.34** (musl como alternativa). Pendiente: inventario de servidores (#3) y x86_64 real (aquí, emulado).
> - **Mason sin verificación de integridad** y dependencias npm/pip resueltas en cada instalación (sin lockfile): dos máquinas con el mismo tag del registro pueden tener dependencias transitivas distintas. Ver §14.
> - **Carreras del primer arranque**: LazyVim lanza instalaciones asíncronas de Mason, parsers y blink.cmp al cargar los plugins, y `+qa` las corta (*"Neovim is exiting while packages are still installing"*). El precalentado espera y reintenta. Si LazyVim cambia esa lógica, hay que revisar `prewarm.lua` al subir el lock.
> - **Tamaño**: Mason (Go + Python + TS) ≈ 0,5 GB, de ellos basedpyright ≈ 0,3 GB, más ≈ 0,6 GB de caché de Go tras compilar gopls y compañía. `.ditto` total ≈ 2,4 GB. ditto debería vaciar `cache/go` tras el precalentado.
> - **macOS y Go**: telemetría local y el índice de goimports fuera de `.ditto` (§8).
> - **npm `devdir`**: npm 11 avisa de que `npm_config_devdir` dejará de funcionar en la próxima versión mayor. Buscar la variable propia de node-gyp al subir Node.
