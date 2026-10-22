---
name: develop-batch
description: Orquesta el desarrollo de un lote de stories de ditto — construye el grafo de dependencias, avisa de dependencias externas sin terminar, propone un plan en oleadas paralelo/serie para que el usuario lo ajuste y confirme, y lo ejecuta lanzando agentes story-developer en worktrees aislados, con revisión, PR por story y reporte final. Usar cuando el usuario quiere desarrollar varias stories a la vez (ej. "develop-batch 12 13 15", "desarrolla la fase 0", "todo el hito H1.6").
argument-hint: "<#N #M …> | fase <n> | hito <Hx.y>"
---

# Develop Batch

Desarrolla un lote de stories en paralelo donde el grafo lo permite y en serie donde no. Toda interacción con GitHub con **`gh`**.

Este skill corre en la conversación principal: es el orquestador. Lanza agentes `story-developer` (uno por story, cada uno en su worktree), y él mismo ejecuta `standards-reviewer`, `platform-tester`, el push y los PRs.

## Paso 0 — Configuración y precondiciones

1. Leer `.claude/project.config.json`: `project.*`, `branchPattern`, `labels.status`, `batch`, `platforms`.
2. `gh auth status`; `git status --porcelain` limpio (si no, detener y preguntar); `git switch <defaultBranch> && git pull --ff-only`.

## Paso 1 — Armar el lote

Según `$ARGUMENTS`:

- Números → esos issues.
- `fase <n>` → issues abiertos del milestone `milestones[n]`.
- `hito <Hx.y>` → issues abiertos con ese prefijo en el título.

```sh
gh issue list --repo <repo> --state all --limit 300 --json number,title,state,labels,milestone,body
gh pr list --repo <repo> --state open --json number,headRefName,body
```

Descartar del lote (y avisar) los cerrados y los que ya tengan `status:in-progress` o `status:in-review`.

## Paso 2 — Grafo de dependencias

Por cada story, extraer las líneas `Depende de: #M` (y el título, tipo, área, tamaño y *Archivos esperados*).

- **Story sin sección de dependencias** (ni siquiera `Depende de: ninguna`): avisar. Proponer las dependencias inferidas del orden del roadmap y del área, y pedir al usuario que las confirme. Corregir el issue con `gh issue edit` tras su OK.
- **Aristas internas**: dependencias dentro del lote.
- **Dependencias externas** (fuera del lote):

  | Estado de #M | Tratamiento |
  |---|---|
  | cerrada | OK, sin arista |
  | abierta con PR abierto | ⚠️ aviso. Opción: partir de la rama de ese PR (stack) |
  | abierta sin PR | ⚠️ aviso. Opciones: añadirla al lote, sacar la story dependiente, o esperar |

- **Ciclos**: si hay, detener y mostrarlos. El usuario debe corregir los issues.
- **Conflictos probables**: dos stories sin dependencia entre sí pero con la misma área o con archivos esperados en común → avisar y proponer una arista "suave" (serializar) para evitar conflictos de merge. El usuario decide.
  Para detectarlos con evidencia y no solo por el área, usar el grafo (protocolo de `CLAUDE.md`): `graphify update .` en `defaultBranch`, `graphify explain` de los símbolos y archivos del *Plan técnico* de cada story, y `graphify path` entre los de dos stories paralelas. Si comparten archivos o una modifica algo que la otra consume, es candidato a arista suave. También sirve para descubrir **dependencias de código no declaradas**: si la story B usa un símbolo que crea la story A, proponer `Depende de: #A`.

## Paso 3 — Plan

Calcular oleadas por orden topológico (oleada 1 = sin dependencias pendientes; oleada k = todas sus dependencias en oleadas < k). Dentro de cada oleada, como máximo `batch.maxParallel` agentes simultáneos.

Base de cada rama, según `batch.strategy`:

- **`stack`** (default): una dependencia interna → parte de la rama de esa story; varias → parte de la primera y fusiona las demás (`merge`); ninguna → `defaultBranch`. El PR apunta a la rama base, de modo que cada PR muestra solo su diff.
- **`merge-gates`**: todas parten de `defaultBranch`; una oleada empieza solo cuando los PRs de la anterior están mergeados (el usuario los mergea; el orquestador espera su aviso).

Mostrar:

```
PLAN DEL LOTE — 6 stories · estrategia: stack · paralelo máx: 3

GRAFO
  #12 ──► #14 ──► #16
  #13 ──┘
  #15 (independiente)
  #17 ··► #19   (#19 depende de #19-externa abierta)

OLEADAS
| Oleada | Story | Tipo/Tamaño | Depende de | Base | Rama |
|---|---|---|---|---|---|
| 1 | #12 [H1.2] platform: … | feature/M | — | main | story/12-platform-detect |
| 1 | #13 [H1.3] installer: … | feature/M | — | main | story/13-installer-bootstrap |
| 1 | #15 [H1.8] release: … | chore/S | — | main | story/15-goreleaser |
| 2 | #14 [H1.4] manifest: … | feature/M | #12, #13 | story/12-… + merge 13 | story/14-manifest |
| 3 | #16 … | … | #14 | story/14-… | … |

AVISOS
- ⚠️ #19 depende de #18 (fuera del lote, abierta, sin PR). Opciones: añadir #18 · sacar #19 · esperar
- ⚠️ #13 y #15 comparten area:release → ¿serializar?
- ℹ️ #12 es spike: lo que requiera servidores reales quedará pendiente
```

## Paso 4 — Ajuste y confirmación del usuario

Preguntar qué hacer. El usuario puede: añadir stories (volver al Paso 1 con el lote ampliado), sacar stories, aceptar o rechazar aristas suaves, resolver cada aviso de dependencia externa, cambiar `strategy` o `maxParallel`. Recalcular y mostrar el plan tras cada cambio.

Pedir confirmación explícita del plan final. **La confirmación autoriza, para todas las stories del lote:** crear ramas y worktrees, commits, `git push` y abrir PRs. No autoriza mergear ni editar arch.md con decisiones (esas se proponen al final).

## Paso 5 — Ejecución

Mantener una cola de stories **listas**: todas sus dependencias internas terminaron en `done` (con `stack`) o están mergeadas (con `merge-gates`).

Por cada story lista, hasta `batch.maxParallel` en curso:

1. `gh issue edit <N> --repo <repo> --add-assignee @me --add-label status:in-progress`.
2. Lanzar el agente **`story-developer`** con `isolation: "worktree"` y en background, pasándole `issue`, `base`, `branch`, `merge`, `repo` y la ruta del config.
3. Al terminar, leer su `STORY_RESULT`:
   - **`done`** →
     1. lanzar **`standards-reviewer`** con `git diff <base>...<branch>` y los criterios del issue. Si hay `ERROR`, reenviarlos al mismo agente (SendMessage) para corregir; como máximo `batch.maxFixRounds` rondas, y si sigue fallando, marcar `failed`.
     2. Si el issue pide verificación Linux o es un spike con pendientes Linux, lanzar **`platform-tester`**. Los fallos se reenvían al agente igual que el punto anterior; lo que no se pueda arreglar queda en el PR como pendiente.
     3. `git push -u origin <branch>` y `gh pr create --base <base del plan> --head <branch>` con el body de develop-story (Fase 8). Con `stack`, añadir al body: `Stack: depende de #<PR de la base>; mergear después de él.`
     4. `gh issue edit <N> --remove-label status:in-progress --add-label status:in-review`.
     5. Marcar `done` y desbloquear a sus dependientes.
   - **`needs-input`** → mostrar la pregunta al usuario **en cuanto llegue** (las demás stories siguen). Reenviar la respuesta al agente con SendMessage.
   - **`failed`** → `gh issue edit <N> --remove-label status:in-progress`, comentar el error en el issue y marcar sus dependientes (transitivos) como `skipped`. Las stories independientes continúan.
4. Informar al usuario de forma breve cada vez que una story cambia de estado (`#12 ✅ PR #31 · #14 desbloqueada`).

Con `merge-gates`, al terminar una oleada: listar sus PRs y esperar a que el usuario confirme que están mergeados (verificar con `gh pr view <n> --json state`) antes de lanzar la siguiente. Antes de cada oleada, `git pull --ff-only` en `defaultBranch`.

## Paso 6 — Cierre

1. Limpiar los worktrees que ya hicieron push (`git worktree list` → `git worktree remove <ruta>`). No borrar ramas.
2. Reporte final:

```
LOTE TERMINADO — 5/6 done · 1 skipped

| Story | Estado | PR (base) | Review | Plataformas | Pendiente manual |
|---|---|---|---|---|---|
| #12 | ✅ done | #31 (main) | 0 errores, 2 warnings | ✅ 3/3 | macOS: … |
| #14 | ✅ done | #33 (story/12-…) | ✅ | — | — |
| #16 | ⏭️ skipped | — | — | — | depende de #14… |

ORDEN DE MERGE (stack): #31 → #32 → #33 → #35
DECISIONES PROPUESTAS (spikes): #12 → ejecutar /record-decision 12
FUERA DE ALCANCE DETECTADO: <lista> → /create-story
```

3. Orden de merge con `stack`: de abajo hacia arriba. Si se mergea con *squash*, después de cada merge hay que rebasar la siguiente rama sobre `defaultBranch` (`git rebase --onto <defaultBranch> <rama-base> <rama>` y `push --force-with-lease`). Ofrecer hacerlo cuando el usuario avise que mergeó.

## Reglas

- Nunca empezar una story antes de que sus dependencias estén en `done`.
- Nunca mergear PRs ni editar arch.md con decisiones de spikes: se proponen.
- No reintentar en bucle: un `failed` se reporta, no se relanza sin preguntar.
- Si `gh` deja de responder a mitad del lote: pausar el push y los PRs, dejar las ramas commiteadas y reportar qué falta.
