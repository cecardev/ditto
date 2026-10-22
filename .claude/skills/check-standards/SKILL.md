---
name: check-standards
description: Audita código de ditto contra docs/code_standards.md y los principios de arch.md usando el agente standards-reviewer. Por defecto revisa el diff de la rama actual contra main. Usar para self-review antes de un PR o auditorías puntuales.
argument-hint: "[diff|all|area:<x>|<ruta>]"
---

# Check Standards

Revisa código con el subagente **`standards-reviewer`**. Alcance: `$ARGUMENTS`.

## Paso 0 — Configuración

Leer `.claude/project.config.json` (`project.defaultBranch`, `docs.codeStandards`, `docs.architecture`, `verify`). Si `docs.codeStandards` no existe, avisar: el revisor solo podrá buscar bugs y violaciones de arch.md.

## Paso 1 — Alcance

| Argumento | Alcance |
|---|---|
| vacío o `diff` | `git diff <defaultBranch>...HEAD` más cambios sin commitear (`git diff HEAD`) |
| `all` | `cmd/`, `internal/`, `install.sh`, `embed/` |
| `area:<x>` | `internal/<x>/` (`area:cli` → `cmd/ditto/`, `area:release` → `install.sh`, `.goreleaser.yaml`, `.github/workflows/`) |
| ruta | esa ruta |

Si el alcance está vacío (sin diff, directorio inexistente), decirlo y terminar.

## Paso 2 — Checks automáticos

Ejecutar `graphify update .` para que el revisor consulte el grafo de la rama actual (si graphify no está instalado, seguir; el revisor usará Grep). Si existe `go.mod`, ejecutar `verify.commands` y los `verify.optional` cuya herramienta esté instalada. Guardar el resultado para el reporte; no detenerse si fallan.

## Paso 3 — Revisión

Lanzar `standards-reviewer` con el alcance, la ruta de `docs.codeStandards`, la de `docs.architecture` y, si la rama es `story/<N>-…`, los criterios de aceptación de `gh issue view <N> --json body`.

## Paso 4 — Reporte

```
CHECK STANDARDS — <alcance>

Automáticos: gofmt ✅ · vet ✅ · test ❌ (2 fallos) · golangci-lint (no instalado)

<hallazgos del revisor, tal cual>

ESTADO: APROBADO | REQUIERE CAMBIOS
```

## Paso 5 — Correcciones

Si hay hallazgos, preguntar: *"¿Corrijo los ERROR? (todos / números / ninguno)"*. Aplicar solo cambios que se deriven claramente de los standards o del bug señalado, y volver a ejecutar el Paso 2. Los WARNING se corrigen solo si el usuario los elige.
