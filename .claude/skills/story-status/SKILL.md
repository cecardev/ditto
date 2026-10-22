---
name: story-status
description: Muestra el progreso de ditto por fase e hito a partir de los GitHub Issues y PRs (con gh) cruzado con roadmap.md — pendientes, en progreso, en revisión, bloqueadas y qué conviene desarrollar después. Usar cuando el usuario pregunta por el estado, el avance o qué sigue.
argument-hint: "[fase|hito|estado|area]  ej. 1, H1.3, bloqueadas, area:installer"
---

# Story Status

Estado del trabajo de ditto. Filtro opcional: `$ARGUMENTS`. Solo lectura. Toda interacción con GitHub con **`gh`**.

## Paso 0 — Configuración

Leer `.claude/project.config.json` (`project.repo`, `docs.roadmap`, `milestones`, `labels`). `gh auth status`; si falla, detener.

## Paso 1 — Datos

```sh
gh issue list --repo <repo> --state all --limit 300 \
  --json number,title,state,labels,milestone,assignees,closedAt,body
gh pr list --repo <repo> --state open \
  --json number,title,headRefName,isDraft,reviewDecision,statusCheckRollup,body
```

Leer los checkboxes y la sección *Orden y dependencias* de `docs.roadmap`.

## Paso 2 — Clasificar

Por issue:

- **Hito**: prefijo `[H…]` del título. **Fase**: milestone.
- **Estado**: `cerrada` (closed) · `en revisión` (`status:in-review` o PR abierto con `Closes #N`) · `en progreso` (`status:in-progress`) · `bloqueada` (`status:blocked` o alguna `Depende de: #M` abierta) · `pendiente` (resto).
- **CI del PR**: a partir de `statusCheckRollup` (✅ / ❌ / ⏳).

Filtro (`$ARGUMENTS`):

- `0`..`3` → solo esa fase. `H1.3` → solo ese hito.
- `pendientes`, `en-progreso`, `en-revision`, `bloqueadas`, `cerradas` → ese estado.
- `area:<x>` → esa área.

## Paso 3 — Reporte

```
ESTADO DE DITTO — <fecha>

Fase 0 — Spikes            ▓▓▓▓░░░░  3/6 hitos
  H0.1  ✅ #3 Spike: mise aislado
  H0.1b 🔍 #4 ¿Hasta dónde llega mise solo?   PR #9 (CI ✅)
  H0.2  🚧 #5 OpenCode                          @cecardev
  H0.3  ⛔ #6 Aislamiento con LazyVim           depende de #4
  H0.4  ⬜ sin issue
Fase 1 — MVP               ░░░░░░░░  0/10 hitos
  ...

BLOQUEOS
- #6 espera #4 (en revisión)

INCONSISTENCIAS
- H0.1 cerrada en GitHub pero sin [x] en roadmap.md → /record-decision o actualizar roadmap
- H1.2 marcado [x] en roadmap sin issue cerrado

SIGUIENTE RECOMENDADO
1. Revisar y mergear PR #9 (desbloquea #6)
2. /develop-story 5 (priority:alta, sin dependencias abiertas)
3. Hitos sin issue en la fase activa → /generate-stories 0
```

Leyenda: ✅ cerrada · 🔍 en revisión · 🚧 en progreso · ⛔ bloqueada · ⬜ pendiente/sin issue.

Un hito cuenta como hecho cuando todas sus stories están cerradas. **Siguiente recomendado**: primero PRs listos para mergear que desbloquean otras stories; después pendientes `priority:alta` sin dependencias abiertas, por camino crítico del roadmap.

## Notas

- No modifica issues ni archivos; para corregir inconsistencias sugiere el skill adecuado.
- Si `gh` falla por red: mostrar solo el estado según roadmap.md y avisarlo.
