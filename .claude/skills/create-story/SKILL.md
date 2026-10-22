---
name: create-story
description: Plantilla y convenciones para crear GitHub Issues (stories) de ditto con gh — título, labels, milestone, dependencias y body estándar para features y spikes. Usar cuando el usuario quiere crear una story/issue, o cuando generate-stories crea las propuestas aprobadas.
argument-hint: "[descripción breve o hito, ej. H1.2]"
---

# Create Story

Crea una story como GitHub Issue en el repo de ditto siguiendo las convenciones de este documento. Toda interacción con GitHub se hace con **`gh`** (no el MCP de GitHub).

## Paso 0 — Configuración

1. Leer `.claude/project.config.json`: `project.repo`, `project.board`, `milestones`, `labels`, `paths.storyTemplates`.
2. `gh auth status`. Si falla, detener.

## Convenciones

### Título

```
[H<fase>.<n>] <área>: <resultado en imperativo>
```

- Ejemplos: `[H1.2] platform: detectar OS, arch, libc, glibc y AVX2` · `[H0.1] spike: validar mise aislado en .ditto/`.
- Sin hito (bug, docs sueltos): `[—] <área>: <resultado>`.
- Si un hito se divide: mismo prefijo, títulos distintos (`[H1.6] env: generar wrappers…`, `[H1.6] launcher: subshell zsh…`).

### Labels (exactamente uno de cada grupo, salvo `status`)

| Grupo | Valores | Regla |
|---|---|---|
| `type:*` | spike, feature, chore, docs, bug | Fase 0 o incógnitas → `spike` |
| `area:*` | platform, manifest, setup, resolve, installer, config, env, launcher, cli, release, docs | Paquete principal de arch.md §5 |
| `priority:*` | alta, media, baja | `alta` = camino crítico o desbloquea otras |
| `size:*` | XS, S, M, L | > L → dividir |
| `status:*` | blocked (opcional al crear) | Si depende de una decisión pendiente |
| `manual-only` | (opcional) | Solo puede hacerlo una persona: servidores reales, credenciales, hardware no disponible, root o GUI. Ningún agente lo desarrolla y `develop-batch` lo excluye. El body lista cada verificación con su comando exacto y dónde anotar el resultado |

### Milestone

La fase del hito, usando `milestones` del config (`Fase 1 — MVP`, …). Sin hito → sin milestone.

### Dependencias (obligatorias)

Toda story tiene la sección *Dependencias*: `develop-batch` la usa para decidir qué corre en paralelo y qué en serie. Una línea por dependencia **directa**, con este formato exacto (los skills la parsean):

```
Depende de: #12
Depende de: #15
```

Sin dependencias: `Depende de: ninguna` (explícito, nunca vacío).

Una story depende de otra si necesita su código (tipos, paquetes), su decisión (un spike) o si el roadmap la ordena antes. Que compartan área no basta: eso es un posible conflicto de merge que `develop-batch` gestiona aparte.

### Body

Usar la plantilla según el tipo:

- `type:spike` → `templates/spike.md`
- resto → `templates/story.md`

Reglas del contenido:

- **Criterios de aceptación verificables** (comando, test o comportamiento observable). Partir de los del roadmap y concretarlos. Nada de "funciona bien".
- **Contexto con enlaces** a las secciones de `arch.md` y al hito de `roadmap.md` que lo justifican. No copiar la arquitectura, enlazarla.
- **Plan técnico** con paquetes y archivos esperados según arch.md §5/§16. Es orientativo: `develop-story` puede ajustarlo.
- **Tests**: qué se prueba y cómo (tabla, fixtures en `testdata/`, binarios falsos en `PATH`, sin red).
- **Plataformas**: indicar si requiere verificación manual en Linux y/o macOS (Definición de hecho del roadmap).
- **Documentación**: qué secciones de arch.md/roadmap.md hay que actualizar al cerrar.
- Español, saltos de línea reales, sin secretos.

## Paso 1 — Recopilar datos

Si vienen pre-llenados (desde `generate-stories`), solo confirmar. Si no, preguntar lo que falte, en este orden: hito (o ninguno), tipo, área, título, descripción/objetivo, prioridad (default `media`), tamaño (default `M`), dependencias.

Con el hito, leer su entrada en `roadmap.md` y las secciones de `arch.md` relevantes para redactar contexto y criterios.

Para el **Plan técnico**, investigar el código existente con el protocolo de `CLAUDE.md`: `graphify query "<objetivo de la story>"` y `graphify explain "<tipo o paquete>"` para nombrar los archivos y símbolos reales que se tocan o reutilizan (en lugar de suponerlos), y `graphify path` para detectar dependencias de código con otras stories. Si no hay grafo o código aún, basarse en arch.md §5/§16.

## Paso 2 — Asegurar labels y milestone

```sh
gh label list --repo <repo> --limit 200 --json name
gh api repos/<repo>/milestones --jq '.[].title'
```

- Label faltante → crearlo con el color y descripción del config: `gh label create "<name>" --repo <repo> --color <color> --description "<desc>"`.
- Milestone faltante → `gh api repos/<repo>/milestones -f title="<título>"`.
- La primera vez que haya que crear labels/milestones, mostrar la lista y pedir confirmación una sola vez.

## Paso 3 — Validar dependencias

- Si no se indicaron dependencias, proponerlas a partir del orden del roadmap y del código que la story necesita, y pedir confirmación. Si de verdad no hay, `Depende de: ninguna`.
- Para cada `#N`: `gh issue view N --repo <repo> --json number,title,state,body`. Si no existe, avisar y pedir corrección. Informar las que ya están cerradas.
- **Ciclos**: si alguna `#N` depende (directa o transitivamente, siguiendo sus `Depende de:`) de una story que a su vez depende de esta, detener y mostrar el ciclo.

## Paso 4 — Mostrar borrador y crear

1. Mostrar título, labels, milestone y body renderizado. Pedir confirmación (salvo que venga de una aprobación explícita en `generate-stories`).
2. Escribir el body en un archivo temporal del scratchpad y crear:

```sh
gh issue create --repo <repo> \
  --title "<título>" \
  --body-file <tmp>/story.md \
  --label "type:…,area:…,priority:…,size:…" \
  --milestone "<milestone>"
```

3. Si `project.board` no es `null`: `gh project item-add <número-board> --owner <boardOwner> --url <issue-url>`. Si falla, avisar sin bloquear.

## Paso 5 — Confirmar

```
Story creada: #<N> — <título>
URL: <url>
Labels: … · Milestone: … · Depende de: …
Siguiente: /develop-story <N>
```

## Notas

- Si `gh` falla por red: mostrar el borrador final para crearlo después; no guardar archivos en el repo.
- Una story = un PR. Si no cabe en un PR revisable, dividirla.
