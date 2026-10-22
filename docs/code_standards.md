# ditto — Code standards

**Estado:** borrador inicial. Se ajusta en H1.1 (esqueleto) y cuando una story lo requiera; los cambios se hacen en PR como cualquier otro.
**Aplica a:** todo el código de `cmd/`, `internal/`, `install.sh` y los wrappers generados. El código de `spikes/` es descartable y solo debe ser reproducible.

## 1. Idioma

- Identificadores, comentarios y mensajes de log: **inglés**.
- Mensajes al usuario (errores accionables, menú, `doctor`): **español**.
- Documentación, issues, PRs y commits: **español**.

## 2. Go

- Versión fijada en `go.mod`; `CGO_ENABLED=0` siempre (binario estático, arch.md §15).
- Formato con `gofmt`; `go vet` sin avisos. Cuando exista config de `golangci-lint`, sin avisos también.
- Estructura de arch.md §16. Todo el código de producto en `internal/`; `cmd/ditto` solo parsea flags y llama a `internal/`.
- Un paquete por responsabilidad de arch.md §5. Sin dependencias cíclicas; `platform` y `manifest` no importan paquetes de más arriba.

### Dependencias externas

- Preferir la biblioteca estándar. Cada dependencia nueva se justifica en el PR (qué resuelve y por qué no basta stdlib).
- Previstas: `charmbracelet/huh` (menú), una librería TOML. Nada que requiera CGO.

### Diseño

- Sin estado global mutable ni `init()` con efectos. Las dependencias se pasan explícitamente (structs con campos o argumentos).
- **Todo lo que toca el sistema es inyectable** para poder testearlo: ejecución de procesos (interfaz tipo `Runner`), entorno (`Getenv`/`LookPath`), sistema de archivos (raíz configurable) y reloj si hace falta.
- Interfaces pequeñas, definidas donde se consumen. Ejemplo de referencia: `Installer{Install, Link, Where, Prune}` (arch.md §5).
- `context.Context` como primer argumento en todo lo que ejecute procesos o use red.
- Funciones cortas y con nombre claro antes que comentarios. Comentar el *por qué*, no el *qué*. Doc comment en todo lo exportado.

### Errores

- Devolver errores, no `panic` (salvo invariantes imposibles). `os.Exit` solo en `main`.
- Envolver con contexto: `fmt.Errorf("install %s: %w", name, err)`. Comparar con `errors.Is`/`errors.As`.
- Los errores que ve el usuario son **accionables**: qué falló, por qué y qué hacer (URL, comando o ruta). Ej.: arch.md §7, paso 4.

### Salida y logs

- `stdout` solo para la salida útil del comando (p. ej. `ditto env` debe poder evaluarse con `eval`). Todo lo demás a `stderr`.
- Logs con `log/slog`; nivel debug con `DITTO_DEBUG=1`. Nunca loguear secretos ni el contenido de `.ditto/secrets`.

## 3. Principios de arch.md que el código debe respetar

- **Nada se escribe fuera de `.ditto/`.** Todas las rutas se derivan de `DITTO_ROOT`; prohibido construir rutas a `$HOME` para escribir.
- Ninguna variable `MISE_*` ni `XDG_*` se exporta a la subshell (arch.md §8). `XDG_*` solo dentro del wrapper de nvim.
- Ningún script remoto se ejecuta durante la instalación de herramientas (arch.md §14). Todo artefacto descargado se verifica con sha256.
- Sin llamadas de red en `ditto up` si todo coincide con el lockfile (arch.md §7).

## 4. Tests

- `go test -race ./...` en verde antes de abrir un PR.
- **Tests de tabla** con `t.Run` y nombres descriptivos.
- `t.TempDir()` para el sistema de archivos y `t.Setenv()` para el entorno. Ningún test escribe fuera de su `TempDir` ni lee el `$HOME` real.
- **Sin red** en los tests unitarios. Los procesos externos se simulan con el `Runner` inyectado o con **binarios falsos** (scripts que imprimen una versión) en un `PATH` temporal.
- Fixtures en `testdata/` (p. ej. salidas reales de `ldd --version` de distintas distros, `/etc/os-release`). Golden files con flag `-update`.
- Tests de integración (mise real, red) detrás del build tag `integration`; no corren por defecto.
- Cada bug corregido trae un test que lo reproduce.

## 5. Shell (`install.sh`, wrappers, `.host-sh`)

- POSIX `sh`, no bash. Deben funcionar con `dash` y con el `sh` de macOS.
- `set -eu`; comillas en todas las expansiones; sin `eval` de datos externos.
- `shellcheck` sin avisos.
- Los wrappers generados son mínimos: exportar variables y `exec`. La lógica vive en Go, que los genera.

## 6. Commits y PRs

- Conventional Commits en español con scope = área y número de issue: `feat(installer): bootstrap de mise con sha256 (#14)`.
- Una story = un PR que la cierra (`Closes #N`). PRs pequeños y revisables.
- El PR cumple la *Definición de "hecho"* de roadmap.md: código + tests, CI en verde, documentación actualizada y verificación manual en Linux y macOS cuando afecte a la plataforma.
