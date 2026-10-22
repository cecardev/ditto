---
name: record-decision
description: Registra una decisión de arquitectura de ditto en arch.md y roadmap.md de forma coherente — actualiza §2, la sección afectada, quita marcas de spike/pendiente, ajusta riesgos y el registro de decisiones, y desbloquea issues que dependían de ella. Usar al cerrar un spike o cuando una conversación cierra una decisión ("decidimos usar X", "registra esta decisión").
argument-hint: "[#issue del spike | descripción de la decisión]"
---

# Record Decision

Lleva una decisión a la documentación sin dejar contradicciones. Origen: `$ARGUMENTS`. Toda interacción con GitHub con **`gh`**.

## Paso 0 — Configuración

Leer `.claude/project.config.json` (`project.repo`, `docs.*`, `paths.spikes`, `labels.status`).

## Paso 1 — Entender la decisión

Según el origen:

- **Issue de spike** (`#N`): `gh issue view N --json title,body,comments`; leer `spikes/<carpeta>/RESULTS.md`. La decisión sale del *Criterio de decisión* aplicado a los resultados.
- **Texto o conversación**: usar lo que dijo el usuario.

Resumirla en una frase y listar alternativas descartadas y por qué. Si es ambigua o los resultados no la sostienen, preguntar antes de seguir.

## Paso 2 — Encontrar todo lo afectado

Leer `docs.architecture` y `docs.roadmap` completos y buscar:

- Marcas `*(spike H…)*`, "provisional", "Pendiente", "Decisión pendiente" relacionadas.
- Filas de la tabla de §2 *Decisiones clave*.
- Secciones que describen el comportamiento que cambia, aunque no estén marcadas (buscar por términos clave con grep).
- Riesgos de §18 que se resuelven o aparecen.
- Hitos del roadmap cuyo alcance o criterio cambia, y el checkbox del hito de origen.

## Paso 3 — Proponer los cambios

Mostrar un plan de cambios por archivo y sección (antes → después, en breve). Incluye siempre:

1. §2: fila nueva o actualizada.
2. Las secciones afectadas reescritas con la decisión (sin marca de spike).
3. §18: riesgos resueltos (quitar o marcar mitigados) y nuevos.
4. **Registro de decisiones** al final de arch.md (crear la sección si no existe):

   ```markdown
   ## Registro de decisiones

   | Fecha | Decisión | Origen | Secciones |
   |---|---|---|---|
   | 2026-10-21 | Sesión delegada en mise (opción A) | #4 · spikes/h0.1b-mise-session/RESULTS.md | §1, §2, §3, §5 |
   ```

5. roadmap.md: checkbox del hito de origen y ajustes en hitos afectados.

**Pedir confirmación** antes de editar. Son decisiones de arquitectura: el usuario puede corregir el alcance.

## Paso 4 — Aplicar y comprobar coherencia

1. Editar arch.md y roadmap.md.
2. Releer las secciones tocadas y buscar contradicciones que queden (grep de los términos de la alternativa descartada). Corregirlas o listarlas.
3. No tocar project.md (es histórico).

## Paso 5 — Issues afectados

```sh
gh issue list --repo <repo> --state open --json number,title,labels,body
```

- Issues con `status:blocked` o cuyo body menciona la decisión o el issue de origen: proponer comentario con la decisión y el enlace, y quitar `status:blocked` si ya no aplica.
- Issues cuyo alcance cambia por la decisión: proponer el comentario o la edición concreta.
- Aplicar con `gh issue comment` / `gh issue edit` **tras confirmación**.

## Paso 6 — Commit

- En una rama `story/<N>-…` (llamado desde `develop-story`): commit en esa rama, `docs(arch): <decisión> (#N)`.
- Si no: crear rama `docs/decision-<slug>`, commit, y preguntar si hacer push y abrir PR (`gh pr create`, body con la decisión y el enlace al origen).

## Resumen

Decisión registrada, secciones cambiadas, issues comentados/desbloqueados y, si aplica, URL del PR.
