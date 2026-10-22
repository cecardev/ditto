## Pregunta

<La incógnita que este spike resuelve, en una frase.>

## Contexto

- Hito: H0.<n> — [roadmap.md](../blob/main/roadmap.md)
- Decisión afectada: [arch.md §<n> <título>](../blob/main/arch.md) *(marcada como provisional / spike)*

## Qué probar

1. <Experimento concreto>
2. <…>

## Entornos

- [ ] macOS <arch>
- [ ] Linux <distro / glibc> *(p. ej. contenedor Ubuntu 18.04 para glibc 2.27)*

## Criterio de decisión

- Si <resultado> → <decisión A>.
- Si no → <decisión B / qué evaluar>.

## Entregables

- [ ] Código descartable en `spikes/h0.<n>-<slug>/` con un `run.sh` reproducible
- [ ] `spikes/h0.<n>-<slug>/RESULTS.md`: qué se probó, en qué entorno, salida relevante, conclusión
- [ ] Decisión anotada en arch.md (§2 y la sección afectada; quitar la marca *(spike)*) y riesgos en §18
- [ ] Checkbox del hito actualizado en roadmap.md

## Fuera de alcance

- Código de producción en `internal/` o `cmd/`.

## Dependencias

Depende de: <#N o "ninguna">
