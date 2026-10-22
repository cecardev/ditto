---
name: develop-story
description: Implementa una story de ditto a partir de su GitHub Issue — la lee con gh, valida dependencias, carga code standards y arquitectura, escribe código y tests en una rama, verifica (gofmt, vet, tests, cross-build) y abre un PR que cierra el issue. Usar cuando el usuario pide desarrollar/implementar un issue (ej. "develop-story 12", "#12").
argument-hint: "<número de issue>"
---

# Develop Story

Desarrolla la story del issue `$ARGUMENTS`. Toda interacción con GitHub se hace con **`gh`** (no el MCP de GitHub).

## Paso 0 — Configuración y precondiciones

1. Leer `.claude/project.config.json`: `project.*`, `docs.*`, `paths.spikes`, `branchPattern`, `labels.status`, `verify`.
2. `gh auth status`. Si falla, detener.
3. `git status --porcelain`. Si hay cambios sin commitear, detener y preguntar qué hacer con ellos (no descartarlos).

## Fase 1 — Leer el issue

```sh
gh issue view <N> --repo <repo> \
  --json number,title,body,state,labels,milestone,assignees,comments,url
```

- Si no existe o está cerrado, detener e informar.
- Extraer: hito (prefijo `[H…]`), tipo (`type:*`), área (`area:*`), objetivo, alcance y fuera de alcance, criterios de aceptación, plan técnico, tests, verificación manual, documentación y dependencias (`Depende de: #N`).
- Leer también los comentarios: pueden traer aclaraciones o cambios de alcance.
- Si falta algo crítico (criterios no verificables, alcance ambiguo), preguntar antes de seguir.

## Fase 2 — Dependencias

Para cada `Depende de: #M`: `gh issue view M --repo <repo> --json state,title`.

- Si alguna sigue abierta: informar, sugerir desarrollarla primero y **no continuar**, salvo que el usuario lo autorice explícitamente.
- Si el issue tiene `status:blocked`, preguntar si el bloqueo ya se resolvió.

## Fase 3 — Contexto del proyecto

Leer, en este orden:

1. `docs.codeStandards` **completo**. Es la fuente de verdad de cómo escribir el código. Si no existe, avisar y seguir las convenciones del código existente.
2. Las secciones de `docs.architecture` enlazadas en el issue, más §5 (módulos) y §16 (estructura).
3. La entrada del hito en `docs.roadmap` y la *Definición de "hecho"*.
4. El código existente del área (`internal/<area>/`) y sus tests, para reutilizar tipos y helpers antes de crear nuevos.

Si el issue contradice arch.md, señalarlo y preguntar cuál manda. No resolverlo en silencio.

## Fase 4 — Preparar el trabajo

1. Actualizar la rama base: `git switch <defaultBranch> && git pull --ff-only`.
2. Crear la rama: `branchPattern` con `{number}` y un `{slug}` corto del título (ej. `story/12-platform-detect`).
3. Marcar el issue: `gh issue edit <N> --repo <repo> --add-assignee @me --add-label status:in-progress`.
4. Para `size:M` o mayor, mostrar un plan breve (archivos, tipos, enfoque de tests) y esperar el OK antes de escribir código.

## Fase 5 — Implementar

### Modo feature / chore / bug

- Seguir **estrictamente** `docs.codeStandards`.
- Cubrir cada criterio de aceptación. Nada fuera del alcance del issue: si aparece trabajo extra, anotarlo para el resumen como story sugerida.
- Tests junto con el código, según la sección *Tests* del issue y los standards. Sin red, sin escribir fuera de `t.TempDir()`.
- Respetar los principios de arch.md: nada se escribe fuera de `.ditto/`, sin `XDG_*` global, `CGO_ENABLED=0`.

### Modo spike (`type:spike`)

- Código **descartable** solo en `paths.spikes` + `h0.<n>-<slug>/`, con un `run.sh` reproducible. No tocar `internal/` ni `cmd/`.
- Ejecutar en esta máquina lo que corresponda a macOS. Para Linux, lanzar el agente **`platform-tester`** con el `run.sh`, la matriz de los *Entornos* del issue (claves de `platforms.images`) y los prerrequisitos de host que asume el spike. Lo que no cubra Docker (servidores reales, hardware), dejarlo como comandos exactos para que el usuario los ejecute y pedirle la salida.
- Escribir `RESULTS.md`: entorno, comandos, salida relevante (incluida la tabla de `platform-tester`), respuesta a la pregunta y decisión según el *Criterio de decisión* del issue.
- Llevar la decisión a la documentación con el skill **`record-decision`** (pide confirmación antes de editar arch.md/roadmap.md).

## Fase 6 — Verificar

Si `verify.requiresGoMod` y no existe `go.mod` (antes de H1.1), saltar los comandos Go e indicarlo.

1. Ejecutar cada comando de `verify.commands`. Si falla, corregir y repetir.
2. Cross-build de cada target de `verify.crossBuild`:
   `CGO_ENABLED=0 GOOS=<os> GOARCH=<arch> go build ./...`
3. `verify.optional`: ejecutar solo si la herramienta está instalada; si no, indicarlo.
4. **Revisión con contexto limpio:** lanzar el agente **`standards-reviewer`** con el diff (`git diff <defaultBranch>...`), la ruta de `docs.codeStandards`, la de `docs.architecture` y los criterios de aceptación. Corregir los `ERROR` con fundamento y repetir la verificación; los `WARNING` se corrigen o se justifican en el PR.
5. **Linux:** si la *Verificación manual* del issue incluye Linux y ya existe `cmd/ditto`, lanzar **`platform-tester`** con el escenario del issue y `platforms.defaultMatrix`. Lo que no pueda cubrir queda como verificación manual pendiente.
6. Recorrer los criterios de aceptación uno por uno y anotar la evidencia de cada uno (test, comando o archivo:línea).

## Fase 7 — Documentación

- Actualizar las secciones que pide el issue.
- Si la implementación cambió una decisión de arquitectura, usar **`record-decision`** (y avisar en el PR).
- Marcar el checkbox del hito en roadmap.md **solo** si esta story completa el hito; consultar si hay otras stories abiertas del mismo hito: `gh issue list --repo <repo> --state open --search "[H<x.y>] in:title"`.

## Fase 8 — Commit y PR

1. Commits con Conventional Commits en español y el número de issue:
   `feat(platform): detectar libc y versión de glibc (#12)`.
   Tipos: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `spike`. Scope = área. Añadir la línea de atribución que indique el harness.
2. Mostrar el resumen de cambios y **pedir confirmación antes de `git push` y de abrir el PR**.
3. `git push -u origin <rama>`.
4. Crear el PR con el body en un archivo temporal del scratchpad:

```sh
gh pr create --repo <repo> --base <defaultBranch> --head <rama> \
  --title "<título del issue sin el prefijo de hito> (#<N>)" \
  --body-file <tmp>/pr.md
```

Body del PR:

```markdown
Closes #<N>

## Cambios
- …

## Criterios de aceptación
- [x] <criterio> — <evidencia>

## Verificación
- gofmt / vet / test: ✅
- Cross-build (4 targets): ✅
- Manual Linux/macOS: <hecho / pendiente / no aplica>

## Documentación
- <secciones actualizadas o "ninguna">
```

5. `gh issue edit <N> --repo <repo> --remove-label status:in-progress --add-label status:in-review`.
6. No cerrar el issue a mano: lo cierra el merge del PR (`Closes #N`).

## Fase 9 — Resumen

- URL del PR y del issue.
- Archivos creados/modificados.
- Resultado de la verificación (y lo que se saltó y por qué).
- Verificación manual pendiente para el usuario (Linux/macOS), con comandos.
- Trabajo fuera de alcance detectado → stories sugeridas (para `/create-story`).

## Agentes y skills utilizados

| Nombre | Tipo | Fase |
|---|---|---|
| `standards-reviewer` | agente | 6 — revisión del diff |
| `platform-tester` | agente | 5 (spikes) y 6 — matriz Linux en Docker |
| `record-decision` | skill | 5 (spikes) y 7 — decisiones de arquitectura |

## Manejo de errores

- `gh` sin red tras la Fase 1: seguir implementando y verificando en local. Al final, dejar listos los comandos `gh` pendientes (labels, PR).
- Tests que no se pueden arreglar sin salir del alcance: detener y explicar; no desactivar ni saltar tests.
