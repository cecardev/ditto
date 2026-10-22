---
name: generate-stories
description: Lee arch.md, roadmap.md y project.md, inspecciona el estado real del repo y de los GitHub Issues, y sugiere las siguientes stories a crear. Usar cuando el usuario quiere saber qué sigue, planificar el backlog o generar issues a partir del roadmap.
argument-hint: "[fase|hito]  ej. 0, 1, H1.3"
---

# Generate Stories

Sugiere las próximas stories de ditto a partir de la documentación y del estado actual. **No crea nada sin confirmación.**

**Uso:** `/generate-stories [fase|hito]`

- Sin argumento: la fase activa (la más baja con hitos sin cerrar) y lo que se pueda paralelizar.
- `0`..`3`: solo esa fase.
- `H1.3`: solo ese hito (útil para dividirlo en varias stories).

Toda interacción con GitHub se hace con **`gh`**. No usar el MCP de GitHub.

## Paso 0 — Configuración

1. Leer `.claude/project.config.json`. Si no existe, detener: *"Falta `.claude/project.config.json` (ver `.claude/README.md`)."*
2. Extraer `project.repo`, `docs.*`, `milestones`, `labels`, `paths.spikes`.
3. `gh auth status`. Si falla, detener: *"gh no está autenticado. Ejecuta `gh auth login`."*

## Paso 1 — Leer la documentación

- `docs.roadmap` **completo**: fases, hitos (`H<fase>.<n>`), criterios de aceptación, checkboxes y la sección *Orden y dependencias*.
- `docs.architecture` **completo**: decisiones vigentes y todo lo marcado como provisional (*(spike …)*, "Pendiente", "Decisión pendiente") — son bloqueos o insumos de spikes.
- `docs.proposal` solo como contexto (es histórico; si contradice a arch.md, manda arch.md).
- `docs.codeStandards` si existe, para que las stories propuestas sean coherentes con él.

## Paso 2 — Estado real del repo

Recolectar evidencia, no suposiciones:

- `git log --oneline -30` y `git status`.
- ¿Existe `go.mod`? Paquetes presentes bajo `internal/` y `cmd/` vs. los de arch.md §16.
- Tests existentes (`*_test.go`), `.github/workflows/`, `.goreleaser.yaml`, `install.sh`, `manifest/components.toml`, `embed/`.
- Contenido de `paths.spikes` (spikes hechos y sus `RESULTS.md`).
- Inconsistencias: hito marcado `[x]` sin código, o código existente con hito `[ ]`.

## Paso 3 — Issues existentes

```sh
gh issue list --repo <repo> --state all --limit 300 \
  --json number,title,state,labels,milestone,body
```

Mapear cada issue a su hito por el prefijo del título `[H1.3]` o la línea `Hito:` del body. Extraer dependencias de las líneas `Depende de: #N`.

## Paso 4 — Calcular qué sigue

Un hito es **candidato** si:

1. No tiene issue abierto ni cerrado que lo cubra completo (un hito puede estar repartido en varios issues; comparar su alcance con los criterios del roadmap).
2. Sus predecesores según *Orden y dependencias* están cerrados **o** tienen issue abierto (en ese caso, la nueva story declara `Depende de:`).
3. No depende de una decisión pendiente en arch.md. Si depende, proponer antes el spike correspondiente o marcar la story como `status:blocked`.

Reglas:

- Fase 0 antes que Fase 1, salvo lo que el roadmap declare paralelizable (p. ej. H1.8 tras H1.1).
- **Tamaño máximo L.** Si un hito supera L, dividirlo en stories verticales verificables (cada una con sus propios criterios de aceptación y tests). Ej.: H1.6 → wrappers / `.host-sh` / subshell bash / subshell zsh / `ditto env`.
- Tipo: `type:spike` para Fase 0 o cualquier incógnita; `type:feature` para código del producto; `type:chore` para CI/release/tooling; `type:docs` para cambios solo de documentación.
- Área: el paquete de arch.md §5 que toca (`area:*` del config). Una story debería tocar un área principal.
- Prioridad: `alta` si está en el camino crítico al MVP o desbloquea otras; `media` si no bloquea; `baja` si es Fase 3 o mejora.
- Tamaño: `XS` 1-2 h · `S` medio día · `M` 1 día · `L` 2-3 días.
- Si se detectan inconsistencias o huecos en la documentación, proponer una story `type:docs` en lugar de inventar diseño.

## Paso 5 — Presentar propuestas

```
ESTADO
- Fase activa: <N> — <milestone>
- Hitos cerrados: <lista> · con issue abierto: <lista> · sin issue: <lista>
- Decisiones pendientes que bloquean: <lista con sección de arch.md>
- Inconsistencias detectadas: <lista o "ninguna">

PROPUESTAS
1. [H0.1] Spike: mise aislado en .ditto/
   type:spike · area:installer · priority:alta · size:M · Fase 0
   Depende de: ninguna
   Por qué ahora: <1 línea>
   Criterios (resumen): <2-3 bullets del roadmap>
2. ...
```

Ordenar por camino crítico. Máximo ~8 propuestas por ejecución.

## Paso 6 — Crear las aprobadas

Preguntar: *"¿Cuáles creo? (números separados por coma, 'todas' o 'ninguna')"*.

Para cada una aprobada, seguir el skill **`create-story`** con los datos ya llenos (título, labels, milestone, dependencias, criterios, plan técnico). Crear en orden de dependencias para poder referenciar los números reales en `Depende de:`.

## Notas

- Nunca crear issues sin confirmación explícita.
- No duplicar: si un issue existente cubre parcialmente el hito, proponer solo el resto y referenciarlo.
- Si `gh` falla por red: mostrar el análisis local (pasos 1, 2, 4) y avisar que no se pudo cruzar con los issues.
